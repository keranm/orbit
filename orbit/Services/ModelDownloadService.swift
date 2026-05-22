import Foundation
import CryptoKit

/// Unified model download service that downloads GGUF files directly from Hugging Face
/// via URLSession and sets up the HF cache structure so mesh-llm can find them.
///
/// This replaces the old `mesh-llm models download` subprocess approach, which was slow
/// due to a long "Preparing download" phase before any bytes transferred.
struct ModelDownloadService {

    let cacheDir: String

    init(cacheDir: String = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath) {
        self.cacheDir = cacheDir
    }

    // MARK: - Phase

    enum Phase: Equatable {
        case resolving
        case downloading(Double)
        case verifying
        case caching
        case done
        case failed(String)
    }

    // MARK: - Download

    /// Downloads a model ref and sets up the HF cache.
    /// - Parameter ref: Hugging Face ref like `org/repo@branch:quant` (e.g. `unsloth/Qwen3-0.6B-GGUF@main:Q4_K_M`)
    /// - Returns: Async stream of download phases.
    func download(ref: String) -> AsyncThrowingStream<Phase, Error> {
        AsyncThrowingStream { continuation in
            let downloadTask = Task {
                let tempBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent("opencode-model-dl-\(UUID().uuidString)")
                let tempFile = tempBase.appendingPathComponent("model.gguf")
                var session: URLSession?

                defer {
                    session?.invalidateAndCancel()
                    try? FileManager.default.removeItem(at: tempBase)
                }

                do {
                    continuation.yield(.resolving)

                    let info = try await resolveRef(ref)
                    guard !Task.isCancelled else { continuation.finish(); return }

                    continuation.yield(.downloading(0))
                    try await downloadFile(url: info.downloadURL, to: tempFile, session: &session) { p in
                        continuation.yield(.downloading(p))
                    }
                    guard !Task.isCancelled else { continuation.finish(); return }

                    continuation.yield(.verifying)
                    let sha = try computeSHA256(of: tempFile)
                    guard !Task.isCancelled else { continuation.finish(); return }

                    continuation.yield(.caching)
                    try setupHFCache(tempFile: tempFile, info: info, sha256: sha)
                    guard !Task.isCancelled else { continuation.finish(); return }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            // Cancel the inner download task when the stream consumer stops iterating
            // (e.g. outer Task cancelled, user presses Back). Without this the URLSession
            // keeps running after the stream terminates, leaving dangling delegate callbacks.
            continuation.onTermination = { _ in downloadTask.cancel() }
        }
    }

    /// Helper: checks Task cancellation and throws CancellationError if cancelled.
    /// This avoids the `@Sendable` closure issues with `guard !Task.isCancelled`.
    private func notCancelled() throws -> Bool {
        try Task.checkCancellation()
        return true
    }

    // MARK: - Resolve ref

    /// Resolves a HF ref string to download info by querying the HF API.
    /// Does NOT download anything.
    func resolveRef(_ ref: String) async throws -> ModelDownloadInfo {
        let parsed = try Self.parseRef(ref)

        let apiURL = URL(string: "https://huggingface.co/api/models/\(parsed.org)/\(parsed.repo)")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelDownloadError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        let modelInfo = try decoder.decode(HFModelResponse.self, from: data)
        let commitHash = modelInfo.sha

        let ggufFiles = modelInfo.siblings
            .map { $0.rfilename }
            .filter { $0.hasSuffix(".gguf") }
            .sorted()

        guard !ggufFiles.isEmpty else {
            throw ModelDownloadError.noGGUFFiles
        }

        let matchingFile: String
        if let filename = parsed.catalogFilename {
            if let exact = ggufFiles.first(where: { $0 == filename }) {
                matchingFile = exact
            } else {
                let available = ggufFiles.map { String($0) }
                throw ModelDownloadError.fileNotFound(filename, available: available)
            }
        } else if let quant = parsed.quant {
            let candidates = ggufFiles.filter { file in
                let stem = String(file.dropLast(5))
                return stem.hasSuffix(quant)
            }
            guard let match = candidates.first else {
                let available = ggufFiles.map { String($0) }
                throw ModelDownloadError.quantNotFound(quant, available: available)
            }
            matchingFile = match
        } else {
            matchingFile = ggufFiles[0]
        }

        let downloadURL = URL(string: "https://huggingface.co/\(parsed.org)/\(parsed.repo)/resolve/\(parsed.branch)/\(matchingFile)")!

        var headRequest = URLRequest(url: downloadURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 15
        let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
        let expectedBytes: Int64
        if let http = headResponse as? HTTPURLResponse {
            if let linkedSizeStr = http.value(forHTTPHeaderField: "x-linked-size"),
               let linkedSize = Int64(linkedSizeStr) {
                expectedBytes = linkedSize
            } else {
                expectedBytes = http.expectedContentLength
            }
        } else {
            expectedBytes = -1
        }

        return ModelDownloadInfo(
            ref: ref,
            org: parsed.org,
            repo: parsed.repo,
            branch: parsed.branch,
            filename: matchingFile,
            downloadURL: downloadURL,
            commitHash: commitHash,
            expectedBytes: expectedBytes
        )
    }

    // MARK: - Download file (URLSessionDownloadTask delegate approach)

    /// Downloads a file using `URLSessionDownloadTask` with real byte-level progress.
    /// The delegate-based approach gives us accurate `totalBytesWritten / totalBytesExpectedToWrite`
    /// without the per-byte iteration overhead of `AsyncBytes`.
    private func downloadFile(url: URL, to dest: URL, session: inout URLSession?, progress: @escaping (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let delegate = DownloadProgressDelegate(dest: dest, progress: progress)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        let dlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        session = dlSession

        let dlTask = dlSession.downloadTask(with: url)

        // withTaskCancellationHandler ensures that if the surrounding Task is cancelled
        // while we are suspended in withCheckedThrowingContinuation, dlTask.cancel() fires
        // immediately. That triggers didCompleteWithError(URLError.cancelled), which resumes
        // the continuation and lets the Task wake up and run its defer cleanup.
        // Without this, a cancelled Task stays suspended here until the download finishes
        // naturally, leaving the URLSession and its delegate alive on the CFNetwork queue
        // and causing EXC_BAD_ACCESS when the surrounding scope has already been torn down.
        try await withTaskCancellationHandler {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                // Install completion BEFORE resume() to close the window where the download
                // could finish before the continuation is set, leaving it unresumable.
                delegate.completion = cont
                dlTask.resume()
            }
        } onCancel: {
            dlTask.cancel()
        }
    }

    // MARK: - SHA256

    private func computeSHA256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var sha = SHA256()
        while try autoreleasepool(invoking: {
            guard let data = try handle.read(upToCount: 16_777_216), !data.isEmpty else { return false }
            sha.update(data: data)
            return true
        }) {}
        let digest = sha.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - HF cache setup

    private func setupHFCache(tempFile: URL, info: ModelDownloadInfo, sha256: String) throws {
        let fm = FileManager.default
        let hubDir = URL(fileURLWithPath: cacheDir)
        let repoDirName = "models--\(info.org)--\(info.repo)".replacingOccurrences(of: "_", with: "-")
        let repoDir = hubDir.appendingPathComponent(repoDirName)

        let blobsDir = repoDir.appendingPathComponent("blobs")
        let snapshotsDir = repoDir.appendingPathComponent("snapshots")
        let commitDir = snapshotsDir.appendingPathComponent(info.commitHash)
        let refsDir = repoDir.appendingPathComponent("refs")

        try fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: commitDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: refsDir, withIntermediateDirectories: true)

        let blobPath = blobsDir.appendingPathComponent(sha256)
        if fm.fileExists(atPath: blobPath.path) {
            try fm.removeItem(at: tempFile)
        } else {
            try fm.moveItem(at: tempFile, to: blobPath)
        }

        let symlinkPath = commitDir.appendingPathComponent(info.filename)
        if !fm.fileExists(atPath: symlinkPath.path) {
            try fm.createSymbolicLink(atPath: symlinkPath.path, withDestinationPath: "../../blobs/\(sha256)")
        }

        let refsPath = refsDir.appendingPathComponent(info.branch)
        if !fm.fileExists(atPath: refsPath.path) {
            try info.commitHash.write(to: refsPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Ref parsing

    static func parseRef(_ ref: String) throws -> ParsedRef {
        let parts = ref.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ModelDownloadError.invalidRef(ref)
        }
        let org = String(parts[0])
        let rest = String(parts[1])

        var repo = rest
        var branch = "main"
        var quant: String?
        var catalogFilename: String?

        if let atIdx = rest.firstIndex(of: "@") {
            repo = String(rest[..<atIdx])
            let afterAt = String(rest[rest.index(after: atIdx)...])
            if let colonIdx = afterAt.firstIndex(of: ":") {
                branch = String(afterAt[..<colonIdx])
                quant = String(afterAt[afterAt.index(after: colonIdx)...])
            } else if let slashIdx = afterAt.firstIndex(of: "/") {
                branch = String(afterAt[..<slashIdx])
                catalogFilename = String(afterAt[afterAt.index(after: slashIdx)...])
            } else {
                branch = afterAt
            }
        } else if let colonIdx = rest.firstIndex(of: ":") {
            repo = String(rest[..<colonIdx])
            quant = String(rest[rest.index(after: colonIdx)...])
        }

        return ParsedRef(
            org: org,
            repo: repo,
            branch: branch.isEmpty ? "main" : branch,
            quant: quant?.isEmpty == true ? nil : quant,
            catalogFilename: catalogFilename?.isEmpty == true ? nil : catalogFilename
        )
    }
}

// MARK: - Download progress delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let dest: URL
    let progress: (Double) -> Void
    var completion: CheckedContinuation<URL, Error>?

    init(dest: URL, progress: @escaping (Double) -> Void) {
        self.dest = dest
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            completion?.resume(returning: dest)
            completion = nil
        } catch {
            completion?.resume(throwing: error)
            completion = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion?.resume(throwing: error)
            completion = nil
        }
    }
}

// MARK: - Supporting types

struct ParsedRef: Equatable {
    let org: String
    let repo: String
    let branch: String
    let quant: String?
    /// When the ref uses catalog format (`@branch/filename.gguf`), the filename is captured here.
    /// When nil, `resolveRef` matches by `quant` or picks the first GGUF file.
    let catalogFilename: String?
}

struct ModelDownloadInfo: Equatable {
    let ref: String
    let org: String
    let repo: String
    let branch: String
    let filename: String
    let downloadURL: URL
    let commitHash: String
    let expectedBytes: Int64
}

enum ModelDownloadError: Error, Equatable {
    case invalidRef(String)
    case apiError(statusCode: Int)
    case noGGUFFiles
    case fileNotFound(String, available: [String])
    case quantNotFound(String, available: [String])
    case cacheSetupFailed
}

extension ModelDownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRef(let ref):
            return "Invalid model reference: \(ref)"
        case .apiError(let code):
            return "Could not reach Hugging Face (HTTP \(code)). Check your connection."
        case .noGGUFFiles:
            return "No model files found in this repository."
        case .fileNotFound(let file, let available):
            if available.isEmpty {
                return "File '\(file)' not found."
            }
            let joined = available.joined(separator: ", ")
            return "File '\(file)' not found. Available: \(joined)."
        case .quantNotFound(let quant, let available):
            if available.isEmpty {
                return "Quantization '\(quant)' not found."
            }
            let joined = available.joined(separator: ", ")
            return "Couldn't find quantization '\(quant)'. Available: \(joined)."
        case .cacheSetupFailed:
            return "Couldn't set up the model cache."
        }
    }
}

// MARK: - HF API response types

private struct HFModelResponse: Decodable {
    let sha: String
    let siblings: [HFSibling]
}

private struct HFSibling: Decodable {
    let rfilename: String
}
