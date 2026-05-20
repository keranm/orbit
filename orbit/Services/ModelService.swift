import Foundation

/// Handles model download and removal operations against the local Mesh-LLM binary.
struct ModelService: Sendable {

    enum DownloadPhase: Equatable, Sendable {
        case starting
        case downloading(Double)
        case verifying
        case done
        case failed(String)
    }

    // MARK: - Download

    /// Downloads a model ref and streams animated progress.
    ///
    /// Command used: mesh-llm models download --json <ref>
    ///
    /// The CLI output uses ANSI spinners and is not parseable for percentage (confirmed 2026-05-19).
    /// The --json flag emits a final JSON result on success; stderr carries the spinner animation.
    /// Progress is animated independently (0→90%) while the process runs; snaps to done on exit 0.
    /// Completion is confirmed when the JSON stdout contains a "path" key.
    func download(binaryPath: URL, ref: String) -> AsyncThrowingStream<DownloadPhase, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                await self.runDownload(binaryPath: binaryPath, ref: ref, continuation: continuation)
            }
        }
    }

    private func runDownload(
        binaryPath: URL,
        ref: String,
        continuation: AsyncThrowingStream<DownloadPhase, Error>.Continuation
    ) async {
        continuation.yield(.starting)

        let process = Process()
        process.executableURL = binaryPath
        // --json gives a clean JSON result on stdout; ANSI progress goes to stderr.
        process.arguments = ["models", "download", "--json", ref]

        // Strip the inherited environment. Any env var set by the previously-running
        // mesh-llm server process (or inherited from it) could trigger the Tokio
        // nested-runtime panic (exit 101) in the download subprocess. Minimal env
        // is safe here because the server has been killed before this runs.
        let parentEnv = ProcessInfo.processInfo.environment
        var minimalEnv: [String: String] = [:]
        for key in ["PATH", "HOME", "USER", "TMPDIR", "HF_HOME", "HF_ENDPOINT", "LANG", "LC_ALL"] {
            if let val = parentEnv[key] { minimalEnv[key] = val }
        }
        process.environment = minimalEnv

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            continuation.yield(.failed("Couldn't start the download. Check your connection and try again."))
            continuation.finish()
            return
        }

        // Animate progress while waiting (the CLI doesn't emit parseable progress to stdout).
        let animationTask = Task.detached {
            var progress = 0.0
            let increment = 0.004
            while !Task.isCancelled && progress < 0.90 {
                try? await Task.sleep(for: .milliseconds(150))
                progress = min(progress + increment, 0.90)
                if !Task.isCancelled {
                    continuation.yield(.downloading(progress))
                }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        animationTask.cancel()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0, outText.contains("path") {
            continuation.yield(.verifying)
            continuation.yield(.done)
            continuation.finish()
        } else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let msg = Self.userFacingError(from: errText, exitCode: process.terminationStatus)
            continuation.yield(.failed(msg))
            continuation.finish()
        }
    }

    // MARK: - Remove

    /// Removes a locally-installed model.
    /// Command: mesh-llm models delete --yes <ref>
    /// The --yes flag skips the dry-run preview and performs the actual deletion.
    /// The ref to pass is the installed model's ref field (without @branch suffix).
    func remove(binaryPath: URL, ref: String) async throws {
        let result = await runCLI(
            binary: binaryPath,
            arguments: ["models", "delete", "--yes", ref]
        )
        guard result.exitCode == 0 else {
            throw ModelError.removalFailed(result.stderr)
        }
    }

    // MARK: - Progress parsing (kept for potential future use / text fallback)

    static func parseProgress(from line: String) -> Double? {
        // Pattern 1: bare percentage — "45%" or "45.2%"
        if let range = line.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
            let raw = String(line[range]).dropLast()
            if let pct = Double(raw) {
                return min(max(pct / 100.0, 0), 1)
            }
        }

        // Pattern 2: "450 MiB / 1000 MiB" or "450MB/1000MB"
        let bytesPattern = #"(\d+\.?\d*)\s*(?:GiB|MiB|KiB|GB|MB|KB)\s*/\s*(\d+\.?\d*)\s*(?:GiB|MiB|KiB|GB|MB|KB)"#
        if let rangeB = line.range(of: bytesPattern, options: .regularExpression) {
            let fragment = String(line[rangeB])
            let parts = fragment.components(separatedBy: "/")
            if parts.count == 2,
               let numerator = extractLeadingNumber(from: parts[0]),
               let denominator = extractLeadingNumber(from: parts[1]),
               denominator > 0 {
                return min(max(numerator / denominator, 0), 1)
            }
        }

        return nil
    }

    private static func extractLeadingNumber(from string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        var numStr = ""
        for ch in trimmed {
            if ch.isNumber || ch == "." { numStr.append(ch) } else { break }
        }
        return Double(numStr)
    }

    // MARK: - Error messages

    static func userFacingError(from output: String, exitCode: Int32) -> String {
        let lower = output.lowercased()
        if exitCode == 101 || lower.contains("cannot start a runtime") {
            return "Exit 101 — runtime conflict. Try again."
        }
        if lower.contains("no space") || lower.contains("disk full") {
            return "Not enough disk space. Free up space and try again."
        }
        if lower.contains("cache lock") || lower.contains("lock timed out") {
            return "Cache locked — another download may be in progress. Try again."
        }
        if lower.contains("network") || lower.contains("timeout") || lower.contains("connection") {
            return "Download stopped. Check your network connection and try again."
        }
        if lower.contains("not found") || lower.contains("not in catalog") {
            return "This model isn't available. Choose a different model."
        }
        if output.isEmpty {
            return "Download failed (exit \(exitCode)). Try again."
        }
        return "Download failed (exit \(exitCode)). Try again."
    }

    // MARK: - Private CLI helper (non-streaming, short-lived commands)

    private struct CLIResult { let stdout: String; let stderr: String; let exitCode: Int32 }

    private func runCLI(binary: URL, arguments: [String], timeout: TimeInterval = 30) async -> CLIResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            nonisolated(unsafe) var done = false

            process.terminationHandler = { proc in
                guard !done else { return }
                done = true
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: CLIResult(stdout: out, stderr: err, exitCode: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                done = true
                continuation.resume(returning: CLIResult(stdout: "", stderr: error.localizedDescription, exitCode: 1))
                return
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                guard !done else { return }
                done = true
                process.terminate()
                continuation.resume(returning: CLIResult(stdout: "", stderr: "timeout", exitCode: 1))
            }
        }
    }
}

// MARK: - ModelError

enum ModelError: LocalizedError {
    case removalFailed(String)

    var errorDescription: String? {
        switch self {
        case .removalFailed(let msg):
            return msg.isEmpty ? "Couldn't remove the model." : msg
        }
    }
}
