import Foundation

/// Owns and watchdogs the `mesh-llm serve --client --headless` background process.
///
/// The SDK's MeshClient.chat() hardcodes stream:false/max_tokens:64 — unusable for chat.
/// This sidecar provides the HTTP SSE relay at localhost:9337 that SDKChatService uses
/// for mesh inference routing.
@Observable
@MainActor
final class SidecarManager {

    private(set) var process: Process?

    // MARK: - Start

    func start(inviteToken: String? = nil, publicAuto: Bool = false) {
        stop()
        guard let binary = findBinaryPath() else { return }

        var args: [String] = ["serve", "--client", "--headless", "--port", "9337"]
        if let token = inviteToken {
            args += ["--join", token]
        } else if publicAuto {
            args += ["--auto"]
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        do {
            try p.run()
            process = p
            setenv("MESH_CLIENT_API_BASE", "http://localhost:9337", 1)
        } catch {
            process = nil
        }
    }

    // MARK: - Stop

    func stop() {
        process?.terminate()
        process = nil
        unsetenv("MESH_CLIENT_API_BASE")
    }

    // MARK: - Revive if crashed

    /// Called from the monitoring loop — restarts the sidecar if it crashed while
    /// the node is still connected to a mesh.
    func reviveIfNeeded(connectionState: MeshConnectionState, localInviteToken: String?) {
        guard process?.isRunning != true else { return }
        switch connectionState {
        case .connectedPublic:
            start(publicAuto: true)
        case .connectedPrivate:
            start(inviteToken: localInviteToken)
        default:
            break
        }
    }

    // MARK: - Private

    private func findBinaryPath() -> String? {
        let candidates = [
            ("~/.local/bin/mesh-bundle/mesh-llm" as NSString).expandingTildeInPath,
            ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath,
            ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
