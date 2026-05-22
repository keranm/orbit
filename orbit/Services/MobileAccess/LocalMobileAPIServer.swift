import Foundation
import Network

@Observable
@MainActor
final class LocalMobileAPIServer {
    private(set) var isRunning: Bool = false
    private(set) var assignedPort: UInt16?
    /// publicDeviceIds of devices with an active chat stream.
    private(set) var activeDeviceIds: Set<String> = []

    private var listener: NWListener?
    private var activeStreams: Set<UUID> = []
    private var connections: [UUID: NWConnection] = [:]

    private let pairingService: PairingTrustService
    private let trustStore: DeviceTrustStore
    private let chatBridge: MobileChatBridge
    private let settingsStore: MobileAccessSettingsStore
    private let runtimeManager: RuntimeManager

    init(
        pairingService: PairingTrustService,
        trustStore: DeviceTrustStore,
        chatBridge: MobileChatBridge,
        settingsStore: MobileAccessSettingsStore,
        runtimeManager: RuntimeManager
    ) {
        self.pairingService = pairingService
        self.trustStore = trustStore
        self.chatBridge = chatBridge
        self.settingsStore = settingsStore
        self.runtimeManager = runtimeManager
    }

    // MARK: - Start / Stop

    func start() async throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: 0)
        self.listener = listener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            listener.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    guard !didResume else { return }
                    switch state {
                    case .ready:
                        didResume = true
                        self.assignedPort = listener.port?.rawValue
                        self.isRunning = true
                        continuation.resume()
                    case .failed(let error):
                        didResume = true
                        self.isRunning = false
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.handleConnection(connection)
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        activeStreams.removeAll()

        isRunning = false
        assignedPort = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        let connId = UUID()
        connections[connId] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated {
                self?.connections.removeValue(forKey: connId)
                self?.activeStreams.remove(connId)
            }
        }
        connection.start(queue: .main)
        receiveRequest(on: connection, connId: connId)
    }

    private var receiveBuffers: [UUID: Data] = [:]

    private func receiveRequest(on connection: NWConnection, connId: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                if error != nil {
                    connection.cancel()
                    self.connections.removeValue(forKey: connId)
                    self.activeStreams.remove(connId)
                    return
                }

                guard let data, !data.isEmpty else {
                    if isComplete {
                        connection.cancel()
                        self.connections.removeValue(forKey: connId)
                        self.activeStreams.remove(connId)
                    } else {
                        self.receiveRequest(on: connection, connId: connId)
                    }
                    return
                }

                self.handleData(data, connection: connection, connId: connId)
            }
        }
    }

    private func handleData(_ data: Data, connection: NWConnection, connId: UUID) {
        var buffer = receiveBuffers[connId] ?? Data()
        buffer.append(data)

        guard let request = try? parseRequest(from: buffer) else {
            receiveBuffers[connId] = buffer
            receiveRequest(on: connection, connId: connId)
            return
        }

        receiveBuffers[connId] = nil
        handleParsedRequest(request, connection: connection)
    }

    // MARK: - HTTP parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
        let remoteHost: String?
    }

    private func parseRequest(from data: Data) throws -> HTTPRequest {
        guard let requestStr = String(data: data, encoding: .utf8) else {
            throw ServerError.badRequest
        }

        let lines = requestStr.components(separatedBy: "\r\n")
        guard lines.count >= 1 else { throw ServerError.badRequest }

        // Request line: METHOD /path HTTP/1.1
        let requestParts = lines[0].components(separatedBy: " ")
        guard requestParts.count >= 2 else { throw ServerError.badRequest }
        let method = requestParts[0]
        let path = requestParts[1]

        // Headers
        var headers: [String: String] = [:]
        var headerIndex = 1
        while headerIndex < lines.count {
            let line = lines[headerIndex]
            if line.isEmpty { break }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
            headerIndex += 1
        }

        // Body
        let headerEnd = lines.prefix(headerIndex + 1).joined(separator: "\r\n")
        let headerLength = headerEnd.utf8.count + 2 // +2 for trailing \r\n
        let bodyStartIndex = data.startIndex + headerLength
        let body = bodyStartIndex < data.endIndex ? data[bodyStartIndex...] : Data()

        // Check Content-Length
        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr) {
            guard body.count >= contentLength else {
                throw ServerError.incompleteBody(expected: contentLength, got: body.count)
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: Data(body),
            remoteHost: nil
        )
    }

    private func remoteHost(for connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        return "\(host)"
    }

    private func isLoopback(host: String?) -> Bool {
        guard let host else { return false }
        return host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    // MARK: - Routing

    private func handleParsedRequest(_ request: HTTPRequest, connection: NWConnection) {
        let path = request.path
        let method = request.method

        if request.method != "GET" && request.method != "POST" && request.method != "DELETE" {
            writeResponse(connection, status: 405, body: #"{"error":"method_not_allowed"}"#)
            return
        }

        // Route
        switch (method, path) {
        case ("GET", "/v1/health"):
            writeResponse(connection, status: 200, body: healthJSON())

        case ("POST", "/v1/pairing/start"):
            guard isLoopback(host: remoteHost(for: connection)) else {
                writeResponse(connection, status: 403, body: #"{"error":"internal_only"}"#)
                return
            }
            handlePairingStart(connection: connection)

        case ("POST", "/v1/pairing/complete"):
            handlePairingComplete(request: request, connection: connection)

        case ("GET", "/v1/models"):
            guard authenticateRequest(request) != nil else {
                writeResponse(connection, status: 401, body: #"{"error":"unauthorized"}"#)
                return
            }
            handleModels(connection: connection)

        case ("POST", "/v1/chat/stream"):
            guard let deviceId = authenticateRequest(request) else {
                writeResponse(connection, status: 401, body: #"{"error":"unauthorized"}"#)
                return
            }
            handleChatStream(request: request, connection: connection, deviceId: deviceId)

        case ("GET", "/v1/status"):
            guard authenticateRequest(request) != nil else {
                writeResponse(connection, status: 401, body: #"{"error":"unauthorized"}"#)
                return
            }
            writeResponse(connection, status: 200, body: statusJSON())

        case ("POST", let p) where p.hasPrefix("/v1/devices/") && p.hasSuffix("/disconnect"):
            guard isLoopback(host: remoteHost(for: connection)) else {
                writeResponse(connection, status: 403, body: #"{"error":"internal_only"}"#)
                return
            }
            handleDisconnectDevice(path: p, connection: connection)

        case ("DELETE", let p) where p.hasPrefix("/v1/devices/"):
            guard isLoopback(host: remoteHost(for: connection)) else {
                writeResponse(connection, status: 403, body: #"{"error":"internal_only"}"#)
                return
            }
            handleForgetDevice(path: p, connection: connection)

        default:
            writeResponse(connection, status: 404, body: #"{"error":"not_found"}"#)
        }
    }

    // MARK: - Authentication

    private func authenticateRequest(_ request: HTTPRequest) -> String? {
        guard let authHeader = request.headers["authorization"] else { return nil }
        let parts = authHeader.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = String(parts[1])

        // Find device by token
        for device in trustStore.devices {
            if trustStore.isTokenValid(publicDeviceId: device.publicDeviceId, token: token) {
                trustStore.updateLastSeen(device.id)
                return device.publicDeviceId
            }
        }
        return nil
    }

    // MARK: - Endpoint handlers

    private func healthJSON() -> String {
        let isRuntimeReady: Bool
        if case .ready = runtimeManager.status { isRuntimeReady = true }
        else { isRuntimeReady = false }

        return """
        {
          "app": "Orbit",
          "protocol": "mobile-v1",
          "status": "ready",
          "mobileAccess": \(settingsStore.settings.isEnabled),
          "runtimeReady": \(isRuntimeReady),
          "macDisplayName": "\(settingsStore.settings.macDisplayName)"
        }
        """
    }

    private func handlePairingStart(connection: NWConnection) {
        let session = pairingService.generateSession(
            macDisplayName: settingsStore.settings.macDisplayName
        )
        let formatter = ISO8601DateFormatter()
        let body = """
        {
          "pairingSessionId": "\(session.sessionId.uuidString)",
          "code": "\(session.code)",
          "expiresAt": "\(formatter.string(from: session.expiresAt))",
          "qrPayload": "\(session.qrPayload)"
        }
        """
        writeResponse(connection, status: 200, body: body)
    }

    private func handlePairingComplete(request: HTTPRequest, connection: NWConnection) {
        struct PairingCompleteBody: Decodable {
            let pairingSessionId: String
            let code: String
            let deviceName: String
            let deviceType: String
            let publicDeviceId: String
        }

        guard let body = try? JSONDecoder().decode(PairingCompleteBody.self, from: request.body) else {
            writeResponse(connection, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }

        guard let sessionId = UUID(uuidString: body.pairingSessionId) else {
            writeResponse(connection, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }

        let deviceInfo = PairingDeviceInfo(
            sessionId: sessionId,
            code: body.code,
            deviceName: body.deviceName,
            deviceType: body.deviceType,
            publicDeviceId: body.publicDeviceId
        )

        do {
            let (device, token) = try pairingService.completePairing(
                sessionId: sessionId,
                deviceInfo: deviceInfo
            )
            let body = """
            {
              "trustedDeviceId": "\(device.id.uuidString)",
              "accessToken": "\(token)",
              "macDisplayName": "\(settingsStore.settings.macDisplayName)"
            }
            """
            writeResponse(connection, status: 200, body: body)
        } catch PairingError.noActiveSession {
            writeResponse(connection, status: 404, body: #"{"error":"no_active_session"}"#)
        } catch PairingError.expired {
            writeResponse(connection, status: 401, body: #"{"error":"expired"}"#)
        } catch PairingError.invalidCode {
            writeResponse(connection, status: 401, body: #"{"error":"invalid_code"}"#)
        } catch PairingError.tooManyAttempts {
            writeResponse(connection, status: 429, body: #"{"error":"too_many_attempts"}"#)
        } catch {
            writeResponse(connection, status: 500, body: #"{"error":"internal_error"}"#)
        }
    }

    private func handleModels(connection: NWConnection) {
        // Fetch fresh local model data; installedModels may be empty if the Mac's
        // Models tab hasn't been opened yet this session.
        Task {
            _ = try? await runtimeManager.fetchInstalledModels()

            var allModels: [MobileModelSummary] = []

            // Local installed models.
            // activeModelRef is stored in CLI name format ("org/repo:filestem") while
            // entry.id uses the ref/file-path format ("org/repo/file.gguf").
            // Check both so isDefault is correctly set regardless of format used.
            let localModels = runtimeManager.installedModels.map { entry in
                let isActive = entry.id == runtimeManager.activeModelRef
                             || entry.name == runtimeManager.activeModelRef
                return MobileModelSummary(
                    id: entry.id,
                    name: entry.displayName,
                    sizeLabel: entry.size,
                    isDefault: isActive,
                    source: .local,
                    nodeCount: nil,
                    meshStatus: nil
                )
            }
            allModels.append(contentsOf: localModels)

            // Mesh network models — only when actively connected to a mesh
            if runtimeManager.meshConnectionState.isConnected {
                let meshModels = runtimeManager.meshModels.map { entry in
                    MobileModelSummary(
                        id: entry.id,
                        name: entry.displayName ?? entry.shortName,
                        sizeLabel: entry.sizeGB.map { String(format: "%.1f GB", $0) },
                        isDefault: entry.id == runtimeManager.activeModelRef,
                        source: .mesh,
                        nodeCount: entry.nodeCount,
                        meshStatus: entry.status
                    )
                }
                allModels.append(contentsOf: meshModels)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let wrapper = ["models": allModels]
            guard let data = try? encoder.encode(wrapper),
                  let jsonStr = String(data: data, encoding: .utf8) else {
                writeResponse(connection, status: 500, body: #"{"error":"encoding_failed"}"#)
                return
            }
            writeResponse(connection, status: 200, body: jsonStr)
        }
    }

    private func handleChatStream(request: HTTPRequest, connection: NWConnection, deviceId: String) {
        struct ChatStreamBody: Decodable {
            let modelId: String
            let messages: [ChatMessage]
            let stream: Bool?
        }

        guard let body = try? JSONDecoder().decode(ChatStreamBody.self, from: request.body) else {
            writeResponse(connection, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }

        let streamId = UUID()
        activeStreams.insert(streamId)
        activeDeviceIds.insert(deviceId)
        connections[streamId] = connection

        // Write SSE headers
        let header = """
        HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n\r\n
        """
        connection.send(content: Data(header.utf8), completion: .idempotent)

        let stream = chatBridge.streamChat(
            modelId: body.modelId,
            messages: body.messages,
            deviceId: deviceId
        )

        // Observe the stream and write SSE chunks.
        // IMPORTANT: The final event (done or error) MUST use .contentProcessed so the
        // connection is only cancelled after the data is in the OS send buffer. Using
        // .idempotent + immediate cancel() was a race: the remote end saw RST before
        // receiving the final SSE event, causing iOS to exit the bytes.lines loop silently.
        let task = Task { @MainActor [weak self] in
            // Closure that cancels the connection and cleans up after final delivery.
            let finish = { [weak self] in
                Task { @MainActor [weak self] in
                    connection.cancel()
                    self?.connections.removeValue(forKey: streamId)
                    self?.activeStreams.remove(streamId)
                    self?.activeDeviceIds.remove(deviceId)
                }
            }

            do {
                for try await token in stream {
                    let sse = "data: {\"type\":\"token\",\"content\":\"\(LocalMobileAPIServer.escapeJSON(token))\"}\n\n"
                    connection.send(content: Data(sse.utf8), completion: .idempotent)
                }
                let doneBytes = Data("data: {\"type\":\"done\"}\n\n".utf8)
                connection.send(content: doneBytes, completion: .contentProcessed { _ in finish() })
            } catch let error as MobileChatError {
                let msg = error.errorDescription ?? "Unknown error"
                let errBytes = Data("data: {\"type\":\"error\",\"message\":\"\(LocalMobileAPIServer.escapeJSON(msg))\"}\n\n".utf8)
                connection.send(content: errBytes, completion: .contentProcessed { _ in finish() })
            } catch {
                let errBytes = Data("data: {\"type\":\"error\",\"message\":\"Request failed.\"}\n\n".utf8)
                connection.send(content: errBytes, completion: .contentProcessed { _ in finish() })
            }
        }

        // Track for cancellation
        connection.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            task.cancel()
            MainActor.assumeIsolated {
                self?.connections.removeValue(forKey: streamId)
                self?.activeStreams.remove(streamId)
                self?.activeDeviceIds.remove(deviceId)
            }
        }
    }

    private func handleDisconnectDevice(path: String, connection: NWConnection) {
        guard let deviceId = extractDeviceId(from: path, suffix: "/disconnect") else {
            writeResponse(connection, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }
        if let device = trustStore.devices.first(where: { $0.id == deviceId }) {
            trustStore.rename(deviceId, to: device.displayName) // no-op to update lastSeen
        }
        writeResponse(connection, status: 200, body: "{}")
    }

    private func handleForgetDevice(path: String, connection: NWConnection) {
        guard let deviceId = extractDeviceId(from: path, suffix: "") else {
            writeResponse(connection, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }
        trustStore.revoke(deviceId)
        writeResponse(connection, status: 204, body: "")
    }

    private func statusJSON() -> String {
        let isRuntimeReady: Bool
        if case .ready = runtimeManager.status { isRuntimeReady = true }
        else { isRuntimeReady = false }

        let activeModel = runtimeManager.activeModelRef ?? ""
        return """
        {
          "connection": "local",
          "network": "\(networkName())",
          "runtimeReady": \(isRuntimeReady),
          "mobileAccess": \(settingsStore.settings.isEnabled),
          "activeModel": "\(activeModel)",
          "macDisplayName": "\(settingsStore.settings.macDisplayName)"
        }
        """
    }

    // MARK: - Helpers

    private func networkName() -> String { "Wi‑Fi" }

    private func extractDeviceId(from path: String, suffix: String) -> UUID? {
        let prefix = "/v1/devices/"
        var trimmed = String(path.dropFirst(prefix.count))
        if !suffix.isEmpty, trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count))
        }
        return UUID(uuidString: trimmed)
    }

    private static func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - Response writer

    private func writeResponse(_ connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 429: statusText = "Too Many Requests"
        case 500: statusText = "Internal Server Error"
        default:  statusText = "Unknown"
        }

        let data = Data(body.utf8)
        let response = "HTTP/1.1 \(status) \(statusText)\r\n" +
                       "Content-Type: application/json\r\n" +
                       "Content-Length: \(data.count)\r\n" +
                       "Connection: close\r\n" +
                       "\r\n"
        var sendData = Data(response.utf8)
        sendData.append(data)

        // contentProcessed fires when the data reaches the OS send buffer,
        // ensuring the response is fully queued before we close the connection.
        // Closing immediately with .idempotent was racing the TCP stack and
        // the remote end was seeing a RST before it could read the response body.
        connection.send(content: sendData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private enum ServerError: Error {
    case badRequest
    case incompleteBody(expected: Int, got: Int)
}
