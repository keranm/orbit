import Foundation

/// Handles model removal operations against the local Mesh-LLM binary.
/// Model downloads are handled by `ModelDownloadService`.
struct ModelService: Sendable {

    // MARK: - Remove

    /// Removes a locally-installed model via the CLI, then cleans the HF cache directory.
    /// Command: mesh-llm models delete --yes <ref>
    /// The --yes flag skips the dry-run preview and performs the actual deletion.
    /// The ref to pass is the installed model's ref field (without @branch suffix).
    func remove(binaryPath: URL, ref: String) async throws {
        let result = await Self.runCLI(
            binary: binaryPath,
            arguments: ["models", "delete", "--yes", ref]
        )
        guard result.exitCode == 0 else {
            throw ModelError.removalFailed(result.stderr)
        }
        Self.removeHFCacheDirectory(for: ref)
    }

    /// Removes the HuggingFace hub cache directory for a model ref.
    /// Only removes directories that start with "models--" directly inside the hub root.
    /// Safe to call on any ref — no-ops if the directory doesn't exist or is unrecognised.
    static func removeHFCacheDirectory(for ref: String) {
        let hubPath = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: hubPath) else { return }

        let stripped = ref
            .components(separatedBy: "@").first?
            .components(separatedBy: ":").first ?? ref
        let parts = stripped.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return }

        let dirName = "models--\(parts[0])--\(parts[1])"
            .replacingOccurrences(of: "_", with: "-")
        guard dirName.hasPrefix("models--") else { return }

        let fullPath = (hubPath as NSString).appendingPathComponent(dirName)
        guard URL(fileURLWithPath: fullPath).deletingLastPathComponent().path == hubPath else { return }
        try? fm.removeItem(atPath: fullPath)
    }

    /// Performs a full uninstall of the Mesh-LLM runtime.
    /// Stops the process, removes all models, deletes config and binary.
    static func uninstallAll(binaryPath: URL?, rm: RuntimeManager) async -> UninstallResult {
        var result = UninstallResult()

        // 1. Stop the runtime
        if rm.status != .notInstalled, rm.status != .stopping {
            await rm.stop()
            result.stoppedRuntime = true
        }

        // 2. Remove each installed model via the CLI
        if let bin = binaryPath {
            do {
                let installed = try await rm.fetchInstalledModels()
                for model in installed.results {
                    let ref = model.ref ?? model.name
                    let cliResult = await Self.runCLI(binary: bin, arguments: ["models", "delete", "--yes", ref])
                    if cliResult.exitCode == 0 {
                        result.removedModelRefs.append(ref)
                        removeHFCacheDirectory(for: ref)
                    } else {
                        result.errors.append("Could not remove model \"\(model.displayName)\".")
                    }
                }
            } catch {
                result.errors.append("Could not list installed models: \(error.localizedDescription)")
            }
        }

        // 3. Remove config directory
        let configDir = ("~/.mesh-llm" as NSString).expandingTildeInPath
        let fm = FileManager.default
        if fm.fileExists(atPath: configDir) {
            do {
                try fm.removeItem(atPath: configDir)
                result.removedConfigDir = true
            } catch {
                result.errors.append("Could not remove config directory: \(error.localizedDescription)")
                result.skippedPaths.append(configDir)
            }
        }

        // 4. Remove binary from known paths
        let binaryPaths = [
            ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath,
            ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath,
        ]
        for path in binaryPaths {
            if fm.fileExists(atPath: path) {
                do {
                    try fm.removeItem(atPath: path)
                    result.removedBinaryPaths.append(path)
                } catch {
                    result.errors.append("Could not remove binary at \(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)")
                    result.skippedPaths.append(path)
                }
            }
        }

        return result
    }

    /// Result of a full uninstallAll() operation.
    struct UninstallResult: Sendable, Equatable {
        var stoppedRuntime = false
        var removedModelRefs: [String] = []
        var removedBinaryPaths: [String] = []
        var removedConfigDir = false
        var skippedPaths: [String] = []
        var errors: [String] = []

        var removedModelCount: Int { removedModelRefs.count }
        var hasErrors: Bool { !errors.isEmpty }

        var summaryLines: [String] {
            var lines: [String] = []
            if stoppedRuntime         { lines.append("Stopped AI runtime") }
            if removedModelCount > 0  { lines.append("Removed \(removedModelCount) downloaded model\(removedModelCount == 1 ? "" : "s")") }
            if removedConfigDir       { lines.append("Removed configuration files") }
            if !removedBinaryPaths.isEmpty { lines.append("Removed Mesh-LLM runtime binary") }
            return lines
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

    struct CLIResult { let stdout: String; let stderr: String; let exitCode: Int32 }

    static func runCLI(binary: URL, arguments: [String], timeout: TimeInterval = 30) async -> CLIResult {
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
