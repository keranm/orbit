import Foundation
import Darwin

/// Lightweight HTTP client for Mesh-LLM health endpoints.
/// All methods return false on any error — callers treat connectivity
/// issues as "not ready" rather than fatal failures.
///
/// A silent POSIX TCP probe gates every request: if nothing is listening on
/// the port, the method returns false immediately without invoking URLSession.
/// This prevents the loud NSURLErrorDomain -1004 / nw_socket console messages
/// that URLSession emits even when the error is caught in Swift.
final class MeshLLMClient: Sendable {
    let baseURL: URL
    let port: Int

    init(apiPort: Int = 9337) {
        self.port = apiPort
        self.baseURL = URL(string: "http://localhost:\(apiPort)")!
    }

    // MARK: - Liveness  (GET /health)

    /// Returns true when the HTTP server is up. Does NOT confirm a model is loaded.
    func checkLiveness() async -> Bool {
        await get("/health")
    }

    // MARK: - Readiness  (GET /readyz)

    /// Returns true only when a model is loaded and ready to serve.
    /// Returns false on 504 (backend timeout / model still loading) and all errors.
    func checkReadiness() async -> Bool {
        await get("/readyz")
    }

    // MARK: - Private

    private func get(_ path: String) async -> Bool {
        // POSIX probe: skip URLSession entirely when nothing is listening.
        // connect() on localhost returns ECONNREFUSED instantly — no blocking.
        // POSIX produces no console output on failure, unlike URLSession.
        guard await tcpListening() else { return false }

        guard let url = URL(string: path, relativeTo: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Silent TCP reachability check via raw POSIX socket.
    /// Runs on a detached task so it never touches the main actor.
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
