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

    var peerCountOptional: Int? {
        switch self {
        case .connectedPrivate(let n), .connectedPublic(let n): return n
        default: return nil
        }
    }

    var statusLabel: String {
        switch self {
        case .disconnected:         return "Mesh: Offline"
        case .connectingPrivate,
             .connectingPublic:     return "Mesh: Connecting…"
        case .connectedPrivate,
             .connectedPublic:      return "Mesh: Connected"
        case .reconnecting:         return "Mesh: Reconnecting…"
        case .error:                return "Mesh: Error"
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

    /// Builds the argument array for launching mesh-llm.
    /// Normal startup uses `serve --headless`; joining a mesh uses root-level
    /// `--join <token>` without the `serve` subcommand, matching the CLI's own
    /// recommended syntax (`mesh-llm --join <token>`).
    func buildArguments() -> [String] {
        // When joining a mesh, --join is a root-level flag — omit `serve`.
        // When starting normally, `serve` is the confirmed entrypoint.
        var args: [String] = joinToken != nil ? ["--headless"] : ["serve", "--headless"]

        // Model ref
        if let ref = modelRef {
            args += ["--model", ref]
        }

        // Mesh join token
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
    let inviteToken: String?
    let peers: [MeshPeerEntry]?
    let servingModels: [String]?
    let availableModels: [String]?
    let hostedModels: [String]?
    let version: String?
    let routingMetrics: RoutingMetrics?
    let inflightRequests: Int?
    let gpus: [GPUInfo]?
    let myHostname: String?
    let myVRAMGB: Double?
    let publicationState: String?
    let modelSizeGB: Double?

    var peerCount: Int { peers?.count ?? 0 }

    enum CodingKeys: String, CodingKey {
        case nodeId           = "node_id"
        case nodeState        = "node_state"
        case isHost           = "is_host"
        case isClient         = "is_client"
        case llamaReady       = "llama_ready"
        case inviteToken      = "token"
        case peers
        case servingModels    = "serving_models"
        case availableModels  = "available_models"
        case hostedModels     = "hosted_models"
        case version
        case routingMetrics   = "routing_metrics"
        case inflightRequests = "inflight_requests"
        case gpus
        case myHostname       = "my_hostname"
        case myVRAMGB         = "my_vram_gb"
        case publicationState = "publication_state"
        case modelSizeGB      = "model_size_gb"
    }
}

struct RoutingMetrics: Decodable {
    let requestCount: Int?
    let successfulRequests: Int?
    let successRate: Double?
    let avgAttemptMs: Double?
    let completionTokensObserved: Int?
    let throughputSamples: [Double]?
    let pressure: MetricsPressure?
    let avgQueueWaitMs: Double?
    let retryCount: Int?
    let failoverCount: Int?

    enum CodingKeys: String, CodingKey {
        case requestCount             = "request_count"
        case successfulRequests       = "successful_requests"
        case successRate              = "success_rate"
        case avgAttemptMs             = "avg_attempt_ms"
        case completionTokensObserved = "completion_tokens_observed"
        case throughputSamples        = "throughput_samples"
        case pressure
        case avgQueueWaitMs           = "avg_queue_wait_ms"
        case retryCount               = "retry_count"
        case failoverCount            = "failover_count"
    }
}

struct MetricsPressure: Decodable {
    let localServiceShare: Double?
    let remoteServiceShare: Double?

    enum CodingKeys: String, CodingKey {
        case localServiceShare  = "local_service_share"
        case remoteServiceShare = "remote_service_share"
    }
}

struct GPUInfo: Decodable {
    let name: String?
    let vramBytes: Int?
    let reservedBytes: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case vramBytes    = "vram_bytes"
        case reservedBytes = "reserved_bytes"
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

    var displayName: String { isUnnamed ? "Unnamed mesh" : name }

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
