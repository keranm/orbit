import Foundation

/// Handles official Mesh-LLM binary installation.
/// Runs: curl --proto '=https' --tlsv1.2 -sSf https://install.mesh-llm.ai | sh
struct InstallService: Sendable {

    enum Phase: Equatable, Sendable {
        case starting
        case inProgress(Double)
        case done
        case failed(String)
    }

    // Confirmed from binary strings in 0.65.1+skippy build (2026-05-19).
    static let installerURL = "https://raw.githubusercontent.com/Mesh-LLM/mesh-llm/main/install.sh"

    func install() -> AsyncThrowingStream<Phase, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                await self.runInstall(continuation: continuation)
            }
        }
    }

    private func runInstall(continuation: AsyncThrowingStream<Phase, Error>.Continuation) async {
        continuation.yield(.starting)

        // The install script guards its main() call with:
        //   if [[ "${BASH_SOURCE[0]-}" == "$0" || ( -z "${BASH_SOURCE[0]-}" && "$0" == "bash" ) ]]
        // When piped to `| /bin/bash`, $0 is "/bin/bash" (full path) so "$0" == "bash" is FALSE
        // and main() is never called — the script exits 0 silently.
        // Fix: download to a temp file and execute it directly, so BASH_SOURCE[0] == $0 is TRUE.
        let tmpScript = FileManager.default.temporaryDirectory
            .appendingPathComponent("mesh-llm-install-\(UUID().uuidString).sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // MESH_LLM_INSTALL_PRERELEASE=1 selects the RC bundle, which contains the
        // +skippy build. The stable v0.65.1 bundle has a --draft-max argument removed
        // from its bundled llama-server, causing llama-server to crash on startup.
        process.arguments = [
            "-c",
            "curl --proto '=https' --tlsv1.2 -sSf '\(Self.installerURL)' -o '\(tmpScript.path)' && MESH_LLM_INSTALL_PRERELEASE=1 /bin/bash '\(tmpScript.path)'; rm -f '\(tmpScript.path)'"
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            continuation.yield(.failed(Self.userFacingError(from: error.localizedDescription, exitCode: 1)))
            continuation.finish()
            return
        }

        // Animate progress smoothly while the installer runs.
        // curl progress bars go to stderr which isn't easily parseable when piped;
        // staged animation is more reliable than output parsing here.
        let animationTask = Task.detached {
            var progress = 0.0
            let increment = 0.005  // ~0.5% per tick
            while !Task.isCancelled && progress < 0.90 {
                try? await Task.sleep(for: .milliseconds(100))
                progress = min(progress + increment, 0.90)
                if !Task.isCancelled {
                    continuation.yield(.inProgress(progress))
                }
            }
        }

        // Wait for process to exit
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        animationTask.cancel()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let combined = [
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
        ].filter { !$0.isEmpty }.joined(separator: "\n")

        if process.terminationStatus == 0, RuntimeManager.resolveBinary() != nil {
            continuation.yield(.inProgress(1.0))
            continuation.yield(.done)
            continuation.finish()
        } else {
            let msg = Self.userFacingError(from: combined, exitCode: process.terminationStatus)
            continuation.yield(.failed(msg))
            continuation.finish()
        }
    }

    static func userFacingError(from output: String, exitCode: Int32) -> String {
        let lower = output.lowercased()
        if lower.contains("permission denied") {
            return "Permission was denied. Try running Orbit as your regular user account."
        }
        if lower.contains("no space left") || lower.contains("disk full") {
            return "Not enough disk space. Free up space and try again."
        }
        if lower.contains("could not resolve") || lower.contains("network unreachable")
            || lower.contains("connection refused") || lower.contains("curl: (6)") {
            return "Couldn't connect to the installer. Check your network connection and try again."
        }
        if exitCode == 0 {
            return "Installation finished but Orbit couldn't find the runtime. Restart Orbit and try again."
        }
        return "Installation failed. Check your network connection and try again."
    }
}
