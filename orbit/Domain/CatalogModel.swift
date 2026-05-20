import Foundation

/// Decoded output of `mesh-llm models recommended --json`.
struct CatalogModelsResponse: Decodable {
    let results: [CatalogModel]
    let source: String?
}

/// A single entry from the Mesh-LLM recommended model catalog.
struct CatalogModel: Codable, Identifiable, Hashable {
    /// Human-readable display name, e.g. "Qwen2.5-0.5B-Instruct-Q4_K_M"
    let name: String
    /// Hugging Face reference used with `--model`, e.g. "Qwen/Qwen2.5-0.5B-Instruct-GGUF@main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    let ref: String
    /// Short human-readable description.
    let description: String?
    /// Size label, e.g. "491MB", "2.1GB"
    let size: String?
    /// Artifact type, e.g. "gguf"
    let type: String?
    let capabilities: CatalogModelCapabilities?

    var id: String { ref }
}

struct CatalogModelCapabilities: Codable, Hashable {
    let reasoning: String?
    let toolUse: String?
    let text: Bool?
    let vision: String?

    enum CodingKeys: String, CodingKey {
        case reasoning
        case toolUse = "tool_use"
        case text
        case vision
    }

    var supportsReasoning: Bool { reasoning == "likely" }
    var supportsToolUse: Bool   { toolUse == "likely" }
    var supportsVision: Bool    { vision == "likely" }
}
