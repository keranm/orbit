import Foundation

enum RuntimeUpdateError: Error, LocalizedError {
    case noUpdateAvailable
    case invalidResponse
    case checksumMismatch
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noUpdateAvailable:        return "No update available"
        case .invalidResponse:          return "Invalid response from update server"
        case .checksumMismatch:         return "Downloaded file is corrupted — checksum mismatch"
        case .downloadFailed(let msg):  return "Download failed: \(msg)"
        }
    }
}

struct ReleaseInfo: Sendable, Decodable {
    let tagName: String
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
    }

    var version: String { tagName }
}

struct RuntimeUpdateService: Sendable {
    let repo = "Mesh-LLM/mesh-llm"

    /// Target directory for updates (support dir, persists across app updates).
    static var supportBinDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "Orbit/bin")
    }

    static var supportBinaryURL: URL {
        supportBinDir.appending(path: "mesh-llm")
    }

    /// Fetches the latest release from GitHub.
    func checkForUpdate(currentVersion: String) async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw RuntimeUpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        let available = release.version
        guard available.compare(currentVersion, options: .numeric) == .orderedDescending else {
            throw RuntimeUpdateError.noUpdateAvailable
        }
        return release
    }

    /// Downloads the latest binary for the current architecture.
    func downloadUpdate(version: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let archName: String = {
            #if arch(arm64)
            return "aarch64"
            #else
            return "x86_64"
            #endif
        }()
        let url = URL(string: "https://github.com/\(repo)/releases/download/\(version)/mesh-llm-\(archName)-apple-darwin.tar.gz")!

        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tarballURL = tmpDir.appending(path: "mesh-llm.tar.gz")

        // Download tarball with progress
        let (bytes, resp) = try await URLSession.shared.bytes(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw RuntimeUpdateError.downloadFailed("Server returned error")
        }

        let expectedSize = http.expectedContentLength
        var received: Int64 = 0
        guard let stream = OutputStream(url: tarballURL, append: false) else {
            throw RuntimeUpdateError.downloadFailed("Could not create temporary file")
        }
        stream.open()
        defer { stream.close() }

        try await Self.writeBytes(bytes, to: stream) { count in
            received += Int64(count)
            if expectedSize > 0 {
                progress(min(Double(received) / Double(expectedSize), 0.95))
            }
        }

        // Extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", tarballURL.path, "-C", tmpDir.path, "mesh-bundle/mesh-llm"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw RuntimeUpdateError.downloadFailed("Extraction failed")
        }

        let extracted = tmpDir.appending(path: "mesh-bundle/mesh-llm")

        // Ensure support dir exists
        try FileManager.default.createDirectory(at: Self.supportBinDir, withIntermediateDirectories: true)

        // Atomically replace
        _ = try FileManager.default.replaceItemAt(Self.supportBinaryURL, withItemAt: extracted)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.supportBinaryURL.path)

        return Self.supportBinaryURL
    }

    /// Checks whether a newer binary exists in the support directory.
    static func hasUpdateBinary() -> Bool {
        FileManager.default.fileExists(atPath: supportBinaryURL.path)
    }

    // MARK: - Private

    /// Writes an async byte stream to an output stream.
    private static func writeBytes(_ bytes: URLSession.AsyncBytes, to output: OutputStream, onBytes: (Int) -> Void) async throws {
        var buffer = [UInt8]()
        buffer.reserveCapacity(16384)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 16384 {
                let written = output.write(buffer, maxLength: buffer.count)
                guard written >= 0 else {
                    throw RuntimeUpdateError.downloadFailed(output.streamError?.localizedDescription ?? "Write failed")
                }
                onBytes(written)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            let written = output.write(buffer, maxLength: buffer.count)
            guard written >= 0 else {
                throw RuntimeUpdateError.downloadFailed(output.streamError?.localizedDescription ?? "Write failed")
            }
            onBytes(written)
        }
    }
}
