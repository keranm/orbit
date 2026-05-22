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
        self.baseURL = URL(string: "http://127.0.0.1:\(apiPort)")!
    }

    // MARK: - Liveness  (GET /health)

    /// Returns true when the HTTP server is up. Does NOT confirm a model is loaded.
    func checkLiveness() async -> Bool {
        await rawGet("/health") == 200
    }

    // MARK: - Readiness  (GET /readyz or /v1/models fallback)

    /// Returns true only when a model is loaded and ready to serve.
    /// Falls back to GET /v1/models when /readyz returns 404 (older mesh-llm
    /// builds that predate the /readyz endpoint).
    func checkReadiness() async -> Bool {
        let status = await rawGet("/readyz")
        if status == 200 { return true }
        if status == 404 {
            // Older build: /readyz doesn't exist. Use /v1/models — returns 200
            // with a non-empty data array only once a model is fully loaded.
            return await modelsEndpointReady()
        }
        return false
    }

    // MARK: - Private

    /// Raw POSIX HTTP GET — returns the HTTP status code, or 0 on failure.
    ///
    /// URLSession is intentionally avoided here. On macOS 26.5, the NECP path
    /// monitor (used internally by URLSession / NWConnection) returns error 22
    /// (EINVAL) on loopback even for 127.0.0.1, causing every request to fail
    /// before a TCP connection is ever attempted. Raw POSIX sockets bypass the
    /// Network framework entirely and always work on loopback.
    private func rawGet(_ path: String) async -> Int {
        let p = port
        return await Task.detached {
            let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return 0 }
            defer { Darwin.close(sock) }

            var tv = timeval(tv_sec: 4, tv_usec: 0)
            Darwin.setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            Darwin.setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(p).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let connected = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            } == 0
            guard connected else { return 0 }

            let req = "GET \(path) HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n"
            let sent = req.withCString { Darwin.send(sock, $0, Int(strlen($0)), 0) }
            guard sent > 0 else { return 0 }

            var buf = [UInt8](repeating: 0, count: 64)
            let n = Darwin.recv(sock, &buf, buf.count - 1, 0)
            guard n > 12 else { return 0 }

            // "HTTP/1.x NNN" — status code at bytes 9-11
            guard let str = String(bytes: buf[9..<12], encoding: .utf8),
                  let code = Int(str) else { return 0 }
            return code
        }.value
    }

    /// Checks /v1/models and returns true when at least one model is loaded.
    /// Used as a readiness fallback for mesh-llm builds that lack /readyz.
    private func modelsEndpointReady() async -> Bool {
        let p = port
        return await Task.detached {
            let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { return false }
            defer { Darwin.close(sock) }

            var tv = timeval(tv_sec: 4, tv_usec: 0)
            Darwin.setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            Darwin.setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(p).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let connected = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            } == 0
            guard connected else { return false }

            let req = "GET /v1/models HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n"
            let sent = req.withCString { Darwin.send(sock, $0, Int(strlen($0)), 0) }
            guard sent > 0 else { return false }

            // Read enough to check status + body for a non-empty model list
            var buf = [UInt8](repeating: 0, count: 512)
            let n = Darwin.recv(sock, &buf, buf.count - 1, 0)
            guard n > 12 else { return false }

            guard let str = String(bytes: buf[9..<12], encoding: .utf8),
                  let code = Int(str), code == 200 else { return false }

            // Body must contain an "id" field — present only when models are loaded
            let body = String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
            let ready = body.contains("\"id\"")
            return ready
        }.value
    }
}
