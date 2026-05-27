import Foundation

/// Scans the HuggingFace hub cache directory for installed GGUF model files.
///
/// The SDK's built-in scanner uses `is_file()` on the Rust side, which returns false
/// for symlinks. HuggingFace hub stores GGUF files as symlinks in snapshots/ pointing
/// to content-addressed blobs. This scanner follows symlinks explicitly.
enum HuggingFaceCacheScanner {

    static func scan(cacheDir: String) -> [InstalledModelEntry] {
        let fm = FileManager.default
        let hubURL = URL(fileURLWithPath: cacheDir)
        var entries: [InstalledModelEntry] = []
        var seenRefs = Set<String>()

        guard let repoDirs = try? fm.contentsOfDirectory(
            at: hubURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return entries }

        for repoDir in repoDirs {
            let dirName = repoDir.lastPathComponent
            guard dirName.hasPrefix("models--") else { continue }
            let repoId = String(dirName.dropFirst("models--".count))
                .replacingOccurrences(of: "--", with: "/")

            let snapshotsDir = repoDir.appendingPathComponent("snapshots")
            guard let snapshots = try? fm.contentsOfDirectory(
                at: snapshotsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for snapshot in snapshots {
                guard let files = try? fm.contentsOfDirectory(
                    at: snapshot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { continue }

                for file in files {
                    guard file.pathExtension.lowercased() == "gguf" else { continue }
                    let modelRef = hfModelRef(repoId: repoId, fileName: file.lastPathComponent)
                    guard seenRefs.insert(modelRef).inserted else { continue }

                    let resolvedPath = file.resolvingSymlinksInPath().path
                    let size = (try? fm.attributesOfItem(atPath: resolvedPath))?[.size] as? Int64
                    entries.append(InstalledModelEntry(
                        name: file.deletingPathExtension().lastPathComponent,
                        ref: modelRef,
                        size: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
                        type: "gguf",
                        path: resolvedPath
                    ))
                }
            }
        }
        return entries
    }

    // Replicates Rust's format_model_ref + quant_selector_from_gguf_file.
    // Returns e.g. "unsloth/Qwen3-4B-GGUF:Q4_K_M"
    // MARK: - Download progress polling

    /// Converts a human-readable size label ("4.7 GB", "~397 MB") to bytes.
    static func parseExpectedBytes(_ sizeLabel: String?) -> Int64? {
        guard let raw = sizeLabel else { return nil }
        // Strip leading non-numeric characters (e.g. "~")
        let s = raw.drop(while: { !$0.isNumber }).trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasSuffix("GB"), let v = Double(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
            return Int64(v * 1_000_000_000)
        }
        if s.hasSuffix("MB"), let v = Double(s.dropLast(2).trimmingCharacters(in: .whitespaces)) {
            return Int64(v * 1_000_000)
        }
        return nil
    }

    /// Derives the HuggingFace hub `models--org--repo` directory name from a model ref.
    static func repoDirName(from ref: String) -> String? {
        let repoPath = ref.contains(":") ? String(ref.split(separator: ":")[0]) : ref
        let parts = repoPath.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return "models--\(parts[0])--\(parts[1])"
    }

    /// Polls the HuggingFace blobs directory every 500 ms, yielding progress in [0, 0.99].
    /// Cancel the consuming Task when the download completes to stop polling.
    static func pollBlobProgress(
        ref: String,
        cacheDir: String,
        expectedBytes: Int64
    ) -> AsyncStream<Double> {
        let fm = FileManager.default
        let blobsURL: URL = {
            if let dir = repoDirName(from: ref) {
                return URL(fileURLWithPath: cacheDir).appendingPathComponent(dir).appendingPathComponent("blobs")
            }
            return URL(fileURLWithPath: cacheDir)
        }()

        return AsyncStream { continuation in
            Task {
                var prevSizes: [String: Int64] = [:]
                while !Task.isCancelled {
                    var maxBytes: Int64 = 0
                    var curSizes: [String: Int64] = [:]

                    if let enumerator = fm.enumerator(
                        at: blobsURL,
                        includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        // Use nextObject() — NSEnumerator.makeIterator is unavailable in async context
                        while let url = enumerator.nextObject() as? URL {
                            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }
                            guard let size = (try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]))?.fileSize else { continue }
                            let fileBytes = Int64(size)
                            let key = url.lastPathComponent
                            curSizes[key] = fileBytes

                            if key.hasSuffix(".incomplete") {
                                maxBytes = max(maxBytes, fileBytes)
                            } else if fileBytes > 1_000_000, fileBytes < expectedBytes {
                                if fileBytes > (prevSizes[key] ?? 0) {
                                    maxBytes = max(maxBytes, fileBytes)
                                }
                            }
                        }
                    }
                    prevSizes = curSizes

                    if maxBytes > 0 {
                        continuation.yield(min(Double(maxBytes) / Double(expectedBytes), 0.99))
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Model ref parsing

    static func hfModelRef(repoId: String, fileName: String) -> String {
        let stem = String(fileName.dropLast(".gguf".count))
        let stemLower = stem.lowercased()
        let markers = ["-ud-", ".ud-", "-iq", ".iq", "-q", ".q",
                       "-bf16", ".bf16", "-f16", ".f16", "-f32", ".f32"]
        for marker in markers {
            if let range = stemLower.range(of: marker, options: .backwards) {
                let offset = stemLower.distance(from: stemLower.startIndex, to: range.lowerBound) + 1
                let selectorStart = stem.index(stem.startIndex, offsetBy: offset)
                return "\(repoId):\(stem[selectorStart...])"
            }
        }
        return stem.isEmpty ? repoId : "\(repoId):\(stem)"
    }
}
