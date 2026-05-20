import Foundation

// MARK: - Mesh Connection State

/// The current state of Orbit's connection to a Mesh-LLM mesh network.
enum MeshConnectionState: Equatable {
    case disconnected                   // local-only, no mesh configured
    case connectingPrivate              // joining a private mesh
    case connectedPrivate(peerCount: Int) // joined, all peers are trusted own devices
    case connectingPublic              // joining a public/shared mesh
    case connectedPublic(peerCount: Int) // joined a public mesh (privacy implications)
    case reconnecting                  // lost connection, attempting to rejoin
    case error(String)                 // join failed

    var isConnected: Bool {
        switch self {
        case .connectedPrivate, .connectedPublic: return true
        default: return false
        }
    }

    var isPublic: Bool {
        if case .connectedPublic = self { return true }
        if case .connectingPublic = self { return true }
        return false
    }

    var peerCount: Int {
        switch self {
        case .connectedPrivate(let n): return n
        case .connectedPublic(let n):  return n
        default: return 0
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .disconnected:              return "disconnected (local only)"
        case .connectingPrivate:         return "connecting to private mesh…"
        case .connectedPrivate(let n):   return "connected (private mesh, \(n) peer\(n == 1 ? "" : "s"))"
        case .connectingPublic:          return "connecting to public mesh…"
        case .connectedPublic(let n):    return "connected (public mesh, \(n) peer\(n == 1 ? "" : "s"))"
        case .reconnecting:              return "reconnecting…"
        case .error(let msg):            return "error — \(msg)"
        }
    }
}

// MARK: - Mesh Mode

enum MeshMode: String, Codable, Equatable {
    case none      // local only
    case `private` // own-device mesh
    case `public`  // public/shared mesh
}

// MARK: - Model Origin

/// Where a model's inference will actually run.
enum ModelOrigin: Equatable {
    case local              // installed on this Mac
    case privateMesh        // available via connected private mesh
    case publicMesh         // available via public/shared mesh
    case unavailable        // known but mesh is disconnected
}

// MARK: - Runtime Launch Configuration

/// Encapsulates all arguments needed to launch mesh-llm serve.
struct RuntimeLaunchConfiguration: Equatable {
    var modelRef: String?
    var joinToken: String?
    var meshMode: MeshMode = .none
    /// Hide GPU name, hostname, VRAM from peers — recommended default for public mesh.
    var noEnumerateHost: Bool = false

    /// Builds the argument array for `mesh-llm serve`.
    func buildArguments() -> [String] {
        var args = ["serve", "--headless"]

        // Model ref
        if let ref = modelRef {
            args += ["--model", ref]
        }

        // Mesh join token (can repeat; we use single join for now)
        if let token = joinToken {
            args += ["--join", token]
        }

        // Privacy hardening for public mesh
        if noEnumerateHost {
            args.append("--no-enumerate-host")
        }

        return args
    }

    static let localOnly = RuntimeLaunchConfiguration()
}

// MARK: - Management API — /api/status

/// Decoded response from GET http://localhost:3131/api/status
struct MeshAPIStatus: Decodable {
    let nodeId: String?
    let nodeState: String?
    let isHost: Bool?
    let isClient: Bool?
    let llamaReady: Bool?
    let inviteToken: String?         // the current node's invite token (field: "token")
    let peers: [MeshPeerEntry]?
    let servingModels: [String]?
    let availableModels: [String]?
    let hostedModels: [String]?
    let version: String?

    /// Number of currently connected peers.
    var peerCount: Int { peers?.count ?? 0 }

    enum CodingKeys: String, CodingKey {
        case nodeId          = "node_id"
        case nodeState       = "node_state"
        case isHost          = "is_host"
        case isClient        = "is_client"
        case llamaReady      = "llama_ready"
        case inviteToken     = "token"
        case peers
        case servingModels   = "serving_models"
        case availableModels = "available_models"
        case hostedModels    = "hosted_models"
        case version
    }
}

struct MeshPeerEntry: Decodable {
    let nodeId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case name
    }
}

// MARK: - Management API — /api/models

/// Decoded response from GET http://localhost:3131/api/models
struct MeshAPIModels: Decodable {
    let meshModels: [MeshModelEntry]

    enum CodingKeys: String, CodingKey {
        case meshModels = "mesh_models"
    }
}

/// A single entry from /api/models mesh_models array.
struct MeshModelEntry: Decodable, Identifiable, Equatable {
    let name: String              // full model ref, e.g. "unsloth/Qwen3-8B-GGUF:Q4_K_M"
    let displayName: String?
    let nodeCount: Int?
    let activeNodes: [String]?
    let status: String?           // "warm", "cold", etc.
    let fitLabel: String?         // "Likely comfortable", "May require mesh"
    let sizeGB: Double?
    let meshVRAMGB: Double?
    let audio: Bool?
    let vision: Bool?
    let reasoning: Bool?
    let toolUse: Bool?

    var id: String { name }

    /// A human-readable short name derived from the full model ref.
    var shortName: String {
        // "unsloth/Qwen3-8B-GGUF:Q4_K_M" → "Qwen3-8B-Q4_K_M"
        if let colon = name.lastIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name.components(separatedBy: "/").last ?? name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName  = "display_name"
        case nodeCount    = "node_count"
        case activeNodes  = "active_nodes"
        case status
        case fitLabel     = "fit_label"
        case sizeGB       = "size_gb"
        case meshVRAMGB   = "mesh_vram_gb"
        case audio, vision, reasoning
        case toolUse      = "tool_use"
    }
}

// MARK: - Discovered Public Mesh

/// A public mesh found via `mesh-llm discover`.
/// Contains only user-useful fields — raw tokens and relay details are not exposed in UI.
struct DiscoveredMesh: Identifiable, Equatable {
    let id: String          // derived from order in discover output
    let name: String        // mesh name, or "(unnamed)" for unnamed meshes
    let inviteToken: String // base64 token — never displayed directly in normal UI
    let modelNames: [String]
    let nodeCount: Int?
    let clientCount: Int?
    let totalVRAMGB: Int?

    var displayName: String { name.isEmpty ? "Unnamed mesh" : name }

    var isUnnamed: Bool { name.isEmpty || name == "(unnamed)" }

    /// Brief model summary, e.g. "Qwen3-8B, Qwen3-32B +3 more"
    var modelSummary: String {
        guard !modelNames.isEmpty else { return "Unknown models" }
        let shortNames = modelNames.prefix(2).map { ref -> String in
            // Shorten "unsloth/Qwen3-8B-GGUF:Q4_K_M" to "Qwen3-8B"
            let stem: String
            if let colon = ref.lastIndex(of: ":") {
                stem = String(ref[ref.index(after: colon)...])
            } else {
                stem = ref.components(separatedBy: "/").last ?? ref
            }
            // Drop quantisation suffix like _Q4_K_M
            if let qIdx = stem.range(of: "-Q", options: .backwards) {
                return String(stem[..<qIdx.lowerBound])
            }
            return stem
        }
        let extra = modelNames.count > 2 ? " +\(modelNames.count - 2) more" : ""
        return shortNames.joined(separator: ", ") + extra
    }
}
