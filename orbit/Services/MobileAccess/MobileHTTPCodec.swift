import Foundation

// MARK: - Request

struct MobileHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let remoteHost: String?

    var bearerToken: String? {
        guard let auth = headers["authorization"] else { return nil }
        let parts = auth.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return String(parts[1])
    }
}

// MARK: - Response

struct MobileHTTPResponse {
    let status: Int
    let body: String
    var contentType: String = "application/json"

    var wireData: Data {
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
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status) \(statusText)\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(bodyData)
        return out
    }

    static func json(_ status: Int, _ body: String) -> MobileHTTPResponse {
        MobileHTTPResponse(status: status, body: body)
    }
}

// MARK: - Parser

enum MobileHTTPParser {
    enum ParseError: Error {
        case badRequest
        case incompleteBody(expected: Int, got: Int)
    }

    static func parse(from data: Data) throws -> MobileHTTPRequest {
        guard let requestStr = String(data: data, encoding: .utf8) else {
            throw ParseError.badRequest
        }

        let lines = requestStr.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ParseError.badRequest }

        let requestParts = lines[0].components(separatedBy: " ")
        guard requestParts.count >= 2 else { throw ParseError.badRequest }
        let method = requestParts[0]
        let path = requestParts[1]

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

        let headerEnd = lines.prefix(headerIndex + 1).joined(separator: "\r\n")
        let headerLength = headerEnd.utf8.count + 2
        let bodyStartIndex = data.startIndex + headerLength
        let body = bodyStartIndex < data.endIndex ? Data(data[bodyStartIndex...]) : Data()

        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr) {
            guard body.count >= contentLength else {
                throw ParseError.incompleteBody(expected: contentLength, got: body.count)
            }
        }

        return MobileHTTPRequest(method: method, path: path, headers: headers, body: body, remoteHost: nil)
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    static func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
