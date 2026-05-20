import Foundation

/// Wraps `mesh-llm discover` to list publicly available meshes.
///
/// There is no --json flag for discover (confirmed against 0.65.1+skippy).
/// The output is parsed with a best-effort text parser isolated in this service.
/// If the format changes, only this file needs updating.
///
/// Example output line:
///   [1] Test2  6 node(s), 768GB capacity  serving: Qwen3-8B, Qwen3-32B  (score: 265, fresh, 151 clients)
///       token: eyJpZCI6...
actor MeshDiscoveryService {

    static let shared = MeshDiscoveryService()

    private init() {}

    // MARK: - Discovery

    /// Runs `mesh-llm discover`, waits up to `timeout` seconds, then parses and returns results.
    func discoverPublicMeshes(binaryPath: URL, timeout: TimeInterval = 12) async throws -> [DiscoveredMesh] {
        let output = try await runDiscover(binaryPath: binaryPath, timeout: timeout)
        return parse(output: output)
    }

    // MARK: - Private — CLI runner

    private func runDiscover(binaryPath: URL, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binaryPath
            process.arguments = ["discover"]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            nonisolated(unsafe) var done = false

            // Kill after timeout — discover blocks indefinitely without a peer
            let timeoutTask = Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                guard !done else { return }
                done = true
                process.terminate()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: out + err)
            }

            process.terminationHandler = { _ in
                guard !done else { return }
                done = true
                timeoutTask.cancel()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: out + err)
            }

            do {
                try process.run()
            } catch {
                done = true
                timeoutTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Private — Text parser

    /// Parses the human-readable `mesh-llm discover` output into structured data.
    /// Designed to tolerate format changes — unknown lines are skipped.
    func parse(output: String) -> [DiscoveredMesh] {
        var meshes: [DiscoveredMesh] = []
        let lines = output.components(separatedBy: .newlines)

        var currentIndex: String?
        var currentName: String?
        var currentToken: String?
        var currentModels: [String] = []
        var currentNodes: Int?
        var currentClients: Int?
        var currentVRAM: Int?

        func flush() {
            guard let idx = currentIndex, let token = currentToken, !token.isEmpty else { return }
            let mesh = DiscoveredMesh(
                id: idx,
                name: currentName ?? "",
                inviteToken: token,
                modelNames: currentModels,
                nodeCount: currentNodes,
                clientCount: currentClients,
                totalVRAMGB: currentVRAM
            )
            meshes.append(mesh)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Mesh header: "  [1] Test2  6 node(s), 768GB capacity  serving: ..."
            if let headerMatch = parseMeshHeader(trimmed) {
                flush()
                currentIndex    = headerMatch.index
                currentName     = headerMatch.name
                currentModels   = headerMatch.models
                currentNodes    = headerMatch.nodeCount
                currentClients  = headerMatch.clientCount
                currentVRAM     = headerMatch.vramGB
                currentToken    = nil
                continue
            }

            // Token line: "token: eyJpZCI6..."
            if trimmed.hasPrefix("token:") {
                currentToken = trimmed.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
        }

        flush()
        return meshes
    }

    // MARK: - Private — Header parser

    private struct HeaderMatch {
        let index: String
        let name: String
        let models: [String]
        let nodeCount: Int?
        let clientCount: Int?
        let vramGB: Int?
    }

    private func parseMeshHeader(_ line: String) -> HeaderMatch? {
        // Pattern: [N] <name>  <nodeCount> node(s), <vram>GB capacity  serving: <models>  (..., <N> clients)
        guard line.hasPrefix("[") else { return nil }
        guard let closeBracket = line.firstIndex(of: "]") else { return nil }

        let index = String(line[line.index(after: line.startIndex)..<closeBracket])
        let rest = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

        // Extract name: everything before the first double-space or "node(s)"
        var name = ""
        var afterName = rest

        // Try to find where the node count starts
        if let nodeRange = rest.range(of: #"\d+ node"#, options: .regularExpression) {
            name = String(rest[..<nodeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            afterName = String(rest[nodeRange.lowerBound...])
        } else {
            // Just grab first word-group before multiple spaces
            let parts = rest.components(separatedBy: "  ").filter { !$0.isEmpty }
            name = parts.first?.trimmingCharacters(in: .whitespaces) ?? rest
        }

        // Node count
        var nodeCount: Int?
        if let m = afterName.range(of: #"(\d+) node"#, options: .regularExpression) {
            let s = String(afterName[m])
            nodeCount = Int(s.components(separatedBy: .whitespaces).first ?? "")
        }

        // VRAM
        var vramGB: Int?
        if let m = afterName.range(of: #"(\d+)GB capacity"#, options: .regularExpression) {
            let s = String(afterName[m])
            vramGB = Int(s.components(separatedBy: "GB").first?.trimmingCharacters(in: .whitespaces) ?? "")
        }

        // Client count
        var clientCount: Int?
        if let m = afterName.range(of: #"(\d+) client"#, options: .regularExpression) {
            let s = String(afterName[m])
            clientCount = Int(s.components(separatedBy: .whitespaces).first ?? "")
        }

        // Serving models (between "serving:" and "wanted:" or end of line)
        var models: [String] = []
        if let servingRange = afterName.range(of: "serving:") {
            let afterServing = String(afterName[servingRange.upperBound...])
            let servingSection: String
            if let wantedRange = afterServing.range(of: "wanted:") {
                servingSection = String(afterServing[..<wantedRange.lowerBound])
            } else if let scoreRange = afterServing.range(of: "(score:") {
                servingSection = String(afterServing[..<scoreRange.lowerBound])
            } else {
                servingSection = afterServing
            }
            models = servingSection
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        return HeaderMatch(
            index: index,
            name: name,
            models: models,
            nodeCount: nodeCount,
            clientCount: clientCount,
            vramGB: vramGB
        )
    }
}
