import Foundation
import Darwin

/// HTTP client for the Mesh-LLM management API on port 3131.
///
/// Verified endpoints (mesh-llm 0.65.1+skippy):
///   GET /api/status  — runtime state, peer count, serving models, invite token
///   GET /api/models  — mesh_models list with per-model capabilities and fit info
///
/// Unimplemented endpoints (404 confirmed): /api/mesh, /api/peers, /api/nodes
/// Do not add methods for those.
final class MeshManagementClient: Sendable {

    let port: Int
    private let baseURL: URL

    init(managementPort: Int = 3131) {
        self.port = managementPort
        self.baseURL = URL(string: "http://localhost:\(managementPort)")!
    }

    // MARK: - /api/status

    /// Fetches runtime and mesh state from the management API.
    /// Returns nil on any error — callers treat nil as "management API unavailable".
    func fetchStatus() async -> MeshAPIStatus? {
        await getJSON("/api/status")
    }

    // MARK: - /api/models

    /// Fetches available mesh models from the management API.
    /// Returns empty array on any error.
    func fetchModels() async -> [MeshModelEntry] {
        let response: MeshAPIModels? = await getJSON("/api/models")
        return response?.meshModels ?? []
    }

    // MARK: - Reachability

    /// Returns true when port 3131 is listening.
    func isReachable() async -> Bool { await tcpListening() }

    // MARK: - Private

    private func getJSON<T: Decodable>(_ path: String) async -> T? {
        guard await tcpListening() else { return nil }
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            return try? decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func tcpListening() async -> Bool {
        let p = port
        return await Task.detached {
            let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return false }
            defer { Darwin.close(sock) }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(p).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            } == 0
        }.value
    }
}
