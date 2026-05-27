import Foundation
import SwiftUI
import MeshLLM

enum ModelOrigin: Equatable {
    case local
    case privateMesh
    case publicMesh
    case unavailable
}

@Observable
@MainActor
final class RuntimeAdapter {

    // MARK: - Published state

    private(set) var status: RuntimeStatus = .notInstalled
    var installedVersion: String?
    private(set) var installedModels: [InstalledModelEntry] = []
    func clearInstalledModels() { installedModels = [] }
    private(set) var activeModelRef: String?
    private(set) var cacheDir: String = {
        let env = ProcessInfo.processInfo.environment
        if let hfHome = env["HF_HOME"] {
            return (hfHome as NSString).appendingPathComponent("hub")
        }
        if let hfCache = env["HUGGINGFACE_HUB_CACHE"] {
            return (hfCache as NSString).expandingTildeInPath
        }
        return ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
    }()

    // MARK: - Mesh state

    private(set) var meshConnectionState: MeshConnectionState = .disconnected
    private(set) var meshModels: [MeshModelEntry] = []
    private(set) var isLoadingMeshModels: Bool = false
    var meshFallbackMessage: String?
    private(set) var localInviteToken: String? = nil

    var activeMeshModel: MeshModelEntry? {
        guard let ref = activeModelRef else { return nil }
        return meshModels.first { $0.name == ref }
    }

    // MARK: - Node / Mesh client

    private(set) var node: Node?
    private var nodeTask: Task<Void, Never>?

    /// Separate Client handle used for mesh inference.
    /// Node.inference.chat() requires a configured API base URL for remote peer
    /// routing; Client.inference.chat() (MeshClientHandle) handles this correctly.
    private(set) var meshClient: Client?

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    func detectInstall() async {
        installedVersion = "0.66.0"

        // Scan the HuggingFace cache so the onboarding "Choose Model" screen
        // can show already-downloaded models without starting the node.
        let cached = scanHuggingFaceCacheForModels()
        installedModels = cached

        // Restore the last-used model ref if it's still on disk.
        if let stored = UserDefaults.standard.string(forKey: "orbit.lastActiveModelRef"),
           cached.contains(where: { $0.ref == stored || $0.name == stored }) {
            activeModelRef = stored
        } else {
            activeModelRef = cached.first.map { $0.ref ?? $0.name }
        }

        status = activeModelRef != nil ? .noModelConfigured : .noModelConfigured
    }

    func ensureRunning() async {
        guard status == .noModelConfigured || status == .offline else { return }
        await start()
    }

    func start(modelRef: String? = nil) async {
        guard node == nil else { return }

        status = .starting

        let keypair = generateOwnerKeypairHex()
        let token = InviteToken("local-device")
        self.localInviteToken = token.value

        do {
            // Node() init is a synchronous blocking FFI call — run it off the main actor
            // to avoid blocking the UI thread.
            let (tokenValue, keypairValue, cacheDirValue) = (token.value, keypair, cacheDir)
            let node = try await Task.detached(priority: .userInitiated) {
                try Node(inviteToken: InviteToken(tokenValue), ownerKeypairBytesHex: keypairValue, cacheDir: cacheDirValue)
            }.value
            self.node = node

            try await node.start()

            // Auto-discover which model to load:
            // explicit arg → last-used (if still on disk) → first installed
            let cachedEntries = scanHuggingFaceCacheForModels()
            let cachedRefs = Set(cachedEntries.map { $0.ref ?? $0.name })
            let storedRef = UserDefaults.standard.string(forKey: "orbit.lastActiveModelRef")
            let refToLoad = modelRef
                ?? storedRef.flatMap { cachedRefs.contains($0) ? $0 : nil }
                ?? cachedEntries.first.map { $0.ref ?? $0.name }

            if let ref = refToLoad,
               let served = try? await node.serving.load(ref, options: LoadModelOptions(devicePolicy: .auto)) {
                activeModelRef = served.modelId
                UserDefaults.standard.set(served.modelId, forKey: "orbit.lastActiveModelRef")
            }

            status = activeModelRef != nil ? .ready : .noModelConfigured
            meshConnectionState = .disconnected

            startMonitoring()
        } catch {
            status = .error(error.localizedDescription)
            self.node = nil
        }
    }

    func loadModel(_ ref: String) async {
        guard let node else { return }
        status = .starting
        do {
            if let current = activeModelRef {
                try? await node.serving.unloadModel(current, options: UnloadModelOptions(drainTimeoutMs: 0, force: true))
            }
            let served = try await node.serving.load(ref, options: LoadModelOptions(devicePolicy: .auto))
            activeModelRef = served.modelId
            UserDefaults.standard.set(served.modelId, forKey: "orbit.lastActiveModelRef")
            status = .ready
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func stop() async {
        nodeTask?.cancel()
        nodeTask = nil
        try? await node?.stop()
        node = nil
        status = .offline
        activeModelRef = nil
    }

    func switchActiveModel(to ref: String) {
        activeModelRef = ref
    }

    // MARK: - Model queries

    func fetchInstalledModels() async throws -> InstalledModelsResponse {
        guard let node else {
            return InstalledModelsResponse(cacheDir: cacheDir, results: [])
        }
        let installed = try await node.models.installed()
        var entries = installed.map { model in
            InstalledModelEntry(
                name: model.modelRef,
                ref: model.modelRef,
                size: model.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                type: "gguf",
                path: model.path
            )
        }
        // SDK scanner skips symlinks (HuggingFace hub cache uses symlinks in snapshots/
        // pointing to content-addressed blobs). Fall back to our own scanner when empty.
        if entries.isEmpty {
            entries = scanHuggingFaceCacheForModels()
        }
        installedModels = entries
        return InstalledModelsResponse(cacheDir: cacheDir, results: entries)
    }

    func fetchRecommendedModels() async throws -> [CatalogModel] {
        guard let node else { return [] }
        let recommended = try await node.models.recommended()
        return recommended.map { summary in
            CatalogModel(
                name: summary.name,
                ref: summary.id,
                description: summary.description,
                size: summary.sizeLabel,
                type: "gguf"
            )
        }
    }

    // MARK: - Model management

    func downloadModel(ref: String) async throws {
        guard let node else { throw RuntimeError.binaryNotFound }
        _ = try await node.models.download(ref)
    }

    func deleteModel(ref: String) async throws {
        guard let node else { throw RuntimeError.binaryNotFound }
        let options = DeleteModelOptions(force: true)
        _ = try await node.models.delete(ref, options: options)
        installedModels.removeAll { $0.ref == ref || $0.name == ref }
    }

    func modelOrigin(for ref: String) -> ModelOrigin {
        guard node != nil else { return .unavailable }
        if activeModelRef == ref {
            switch meshConnectionState {
            case .connectedPrivate: return .privateMesh
            case .connectedPublic:  return .publicMesh
            default:                return .local
            }
        }
        return .unavailable
    }

    // MARK: - Mesh

    func joinPrivateMesh(inviteToken: String) async {
        meshConnectionState = .connectingPrivate
        do {
            let newToken = InviteToken(inviteToken)
            let keypair = generateOwnerKeypairHex()
            let newNode = try Node(
                inviteToken: newToken,
                ownerKeypairBytesHex: keypair,
                cacheDir: cacheDir
            )
            try await newNode.start()
            try await node?.stop()
            node = newNode

            // Client for consuming mesh inference — Node.inference.chat() requires
            // a configured API base URL for remote peer routing; Client handles it.
            let client = try Client(inviteToken: newToken, ownerKeypairBytesHex: keypair)
            try await client.start()
            meshClient = client

            meshConnectionState = .connectedPrivate(peerCount: 0)
            Task { await refreshMeshModels() }
        } catch {
            meshConnectionState = .error(error.localizedDescription)
        }
    }

    func joinPublicMesh(inviteToken: String, seedModelNames: [String] = []) async {
        meshConnectionState = .connectingPublic
        do {
            let query = PublicMeshQuery(
                model: nil, minVramGb: nil, region: nil,
                targetName: nil, relays: []
            )
            let newNode = try await Node.connectPublic(
                ownerKeypairBytesHex: generateOwnerKeypairHex(),
                query: query
            )
            try await node?.stop()
            node = newNode

            let client = try await Client.connectPublic(
                ownerKeypairBytesHex: generateOwnerKeypairHex(),
                query: query
            )
            meshClient = client

            meshConnectionState = .connectedPublic(peerCount: 0)

            // Pre-populate from discovery data so Models tab shows something immediately,
            // even if the SDK's listModels() hasn't synced yet after a fresh join.
            if !seedModelNames.isEmpty {
                meshModels = seedModelNames.map { name in
                    MeshModelEntry(name: name, displayName: nil, nodeCount: nil, activeNodes: nil,
                                   status: nil, fitLabel: nil, sizeGB: nil, meshVRAMGB: nil,
                                   audio: nil, vision: nil, reasoning: nil, toolUse: nil)
                }
            }

            // Background refresh — fills in full details once the mesh propagates them.
            // refreshMeshModels() only overwrites meshModels if it gets a non-empty result,
            // so the seeded list persists if the SDK still returns empty.
            Task { await refreshMeshModels() }
        } catch {
            meshConnectionState = .error(error.localizedDescription)
        }
    }

    func leaveMesh() async {
        await meshClient?.stop()
        meshClient = nil
        await stop()
        status = .noModelConfigured
        meshConnectionState = .disconnected
        meshModels = []
    }

    func selectMeshModel(_ model: MeshModelEntry) {
        activeModelRef = model.name
    }

    func clearMeshFallbackMessage() {
        meshFallbackMessage = nil
    }

    func refreshMeshStatus() async {
        guard let node else { return }
        let status = await node.status()
        if status.connected {
            if case .connectedPublic = meshConnectionState {
                meshConnectionState = .connectedPublic(peerCount: status.peerCount)
            } else {
                meshConnectionState = .connectedPrivate(peerCount: status.peerCount)
            }
        }
    }

    func refreshMeshModels() async {
        guard let node, !isLoadingMeshModels else { return }
        isLoadingMeshModels = true
        defer { isLoadingMeshModels = false }

        // The mesh may not have pushed its model list yet right after connect.
        // Retry up to 5 times with increasing delays.
        let delays: [UInt64] = [0, 1_000_000_000, 2_000_000_000, 3_000_000_000, 4_000_000_000]
        for delay in delays {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            let models = try? await node.inference.listModels()
            let entries = (models ?? []).map { m in
                MeshModelEntry(name: m.id, displayName: m.name, nodeCount: nil, activeNodes: nil, status: nil, fitLabel: nil, sizeGB: nil, meshVRAMGB: nil, audio: nil, vision: nil, reasoning: nil, toolUse: nil)
            }
            if !entries.isEmpty {
                meshModels = entries
                return
            }
        }
        // All retries exhausted — leave meshModels empty so UI shows empty state.
    }

    func discoverPublicMeshes() async throws -> [DiscoveredMesh] {
        let query = PublicMeshQuery(
            model: nil, minVramGb: nil, region: nil,
            targetName: nil, relays: []
        )
        let meshes = try await Node.discoverPublicMeshes(query)
        return meshes.enumerated().map { i, m in
            DiscoveredMesh(
                id: "\(i)",
                name: m.name ?? "(unnamed)",
                inviteToken: m.inviteToken,
                modelNames: m.serving,
                nodeCount: Int(m.nodeCount),
                clientCount: Int(m.clientCount),
                totalVRAMGB: Int(m.totalVramBytes / 1_000_000_000)
            )
        }
    }

    func ensureModelConfigured(_ modelRef: String) throws {}

    func configTomlHasModels() -> Bool { true }

    func restoreMeshConfigIfNeeded() async {}

    // MARK: - Health

    func checkLiveness() async -> Bool {
        guard let node else { return false }
        let s = await node.status()
        return s.connected
    }

    func checkReadiness() async -> Bool {
        guard let node else { return false }
        let s = try? await node.serving.status()
        return s != nil
    }

    // MARK: - Mock

    func enterMockReadyState() {
        status = .ready
        installedVersion = "0.66.0"
    }

    // MARK: - Private

    // Fallback for SDK bug: HuggingFace hub cache stores GGUF files as symlinks
    // in snapshots/ dirs, but the Rust scanner uses is_file() which returns false
    // for symlinks. We replicate the ref format and follow symlinks ourselves.
    private func scanHuggingFaceCacheForModels() -> [InstalledModelEntry] {
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
    private func hfModelRef(repoId: String, fileName: String) -> String {
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

    private func startMonitoring() {
        nodeTask?.cancel()
        nodeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let node else { break }
                let s = await node.status()
                if s.connected {
                    self.status = .ready
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

// MARK: - RuntimeError

enum RuntimeError: LocalizedError {
    case binaryNotFound
    case cliError(String)
    case catalogNetworkUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Mesh-LLM runtime not found. Complete Orbit setup to install it."
        case .cliError(let msg):
            return msg.isEmpty ? "CLI command failed." : msg
        case .catalogNetworkUnavailable:
            return "The model library couldn't be reached from this runtime build."
        }
    }
}
