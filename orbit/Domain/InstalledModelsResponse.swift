import Foundation

/// Decoded output of `mesh-llm models installed --json`.
struct InstalledModelsResponse: Decodable {
    let cacheDir: String
    let results: [InstalledModelEntry]

    var hasModels: Bool { !results.isEmpty }

    enum CodingKeys: String, CodingKey {
        case cacheDir = "cache_dir"
        case results
    }
}

/// A single installed model entry from `mesh-llm models installed --json`.
///
/// Real JSON shape (confirmed against 0.65.1+skippy, 2026-05-19):
/// ```
/// "name": "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:qwen2.5-coder-7b-instruct-q4_k_m"
/// "ref":  "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
/// "size": "4.7GB"
/// "type": "gguf"
/// "path": "/Users/…/.cache/huggingface/hub/…/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
/// "delete": "mesh-llm models delete Qwen/…"   (command string, not just the ref)
/// ```
struct InstalledModelEntry: Decodable, Identifiable, Hashable {
    /// CLI-format name: "org/repo:filestem" e.g. "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:qwen2.5-coder-7b-instruct-q4_k_m"
    let name: String
    /// Installed ref without @branch: "org/repo/filename.gguf"
    let ref: String?
    /// Human-readable disk size, e.g. "4.7GB"
    let size: String?
    /// Artifact type, e.g. "gguf"
    let type: String?
    /// Absolute path to the file on disk
    let path: String?

    var id: String { ref ?? name }

    /// Readable label — extracts the filename stem from the colon-separated `name` field.
    /// "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:qwen2.5-coder-7b-instruct-q4_k_m" → "qwen2.5-coder-7b-instruct-q4_k_m"
    var displayName: String {
        if let colonIdx = name.firstIndex(of: ":") {
            return String(name[name.index(after: colonIdx)...])
        }
        // Fallback: strip path prefix and .gguf extension
        let base = name.hasSuffix(".gguf") ? String(name.dropLast(5)) : name
        return base.components(separatedBy: "/").last ?? base
    }

    /// Upper-case format badge, e.g. "GGUF"
    var typeBadge: String? {
        (type ?? (name.hasSuffix(".gguf") ? "gguf" : nil))?.uppercased()
    }

    init(
        name: String,
        ref: String? = nil,
        size: String? = nil,
        type: String? = nil,
        path: String? = nil
    ) {
        self.name = name
        self.ref = ref
        self.size = size
        self.type = type
        self.path = path
    }

    enum CodingKeys: String, CodingKey {
        case name
        case ref
        case size
        case type
        case path
    }
}
