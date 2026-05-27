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
