import Foundation
import SwiftUI

/// Manages the Mesh-LLM process lifecycle and exposes real runtime state to the rest of Orbit.
///
/// # Confirmed behaviour (tested against mesh-llm 0.65.1+skippy):
/// - Invocation: `mesh-llm serve [--model <ref>] [--headless]`  ("serve" is the preferred entrypoint)
/// - Exits immediately (exit 0) when no model is configured and no --model flag is supplied
/// - Binary paths checked in priority order: ~/.local/bin, ~/.cargo/bin, /usr/local/bin
/// - Health:  GET http://localhost:9337/health  → {"status":"ok"}      (liveness only)
/// - Readiness: GET http://localhost:9337/readyz → {"status":"ready"}  (model loaded)
/// - Shutdown: `mesh-llm stop` (canonical); SIGTERM fallback
@Observable
@MainActor
final class RuntimeManager {

    // MARK: - Published state

    private(set) var status: RuntimeStatus = .notInstalled
    private(set) var binaryPath: URL?
    private(set) var installedVersion: String?
    private(set) var installedModels: [InstalledModelEntry] = []
    private(set) var cacheDir: String = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
    private(set) var recommendedModels: [CatalogModel] = []
    /// The model ref currently loaded in the runtime, used by ChatService requests.
    private(set) var activeModelRef: String?

    // MARK: - Mesh state

    private(set) var meshConnectionState: MeshConnectionState = .disconnected
    private(set) var meshModels: [MeshModelEntry] = []
    /// The invite token for this node (from /api/status). Nil when management API is unavailable.
    private(set) var localInviteToken: String?
    /// The launch configuration used for the currently-running process.
    private(set) var currentLaunchConfig: RuntimeLaunchConfiguration = .localOnly

    // MARK: - Configuration

    let apiPort: Int = 9337
    let managementPort: Int = 3131

    var apiBaseURL: URL { URL(string: "http://localhost:\(apiPort)")! }

    // MARK: - Private

    private var serveProcess: Process?
    private var keepaliveTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let client = MeshLLMClient()
    private let managementClient = MeshManagementClient()

    /// Candidate binary paths checked in priority order.
    static let candidatePaths: [String] = [
        ("~/.local/bin/mesh-llm" as NSString).expandingTildeInPath,
        ("~/.cargo/bin/mesh-llm" as NSString).expandingTildeInPath,
        "/usr/local/bin/mesh-llm",
    ]

    // MARK: - Init

    init() {}

    /// Forces the runtime into a `.ready` state for UI testing.
    /// Called when the app is launched with `--mock-runtime`.
    func enterMockReadyState() {
        binaryPath = URL(fileURLWithPath: "/usr/bin/mock-mesh-llm")
        installedVersion = "mock"
        activeModelRef = "mock-model"
        status = .ready
    }

    // MARK: - Install Detection

    /// Resolves the binary path, records the installed version, and updates `status`.
    /// If the runtime is already serving (responds to /readyz), transitions directly to
    /// `.ready` and starts the keepalive — avoids the "AI paused" false state on relaunch.
    func detectInstall() async {
        let resolved = Self.resolveBinary()
        binaryPath = resolved

        guard let binary = resolved else {
            status = .notInstalled
            return
        }

        // Query version (best-effort — don't block on failure)
        installedVersion = await queryVersion(binary: binary)

        // Extract active model ref from config.toml if present
        let configHasModels = configTomlHasModels()
        if configHasModels {
            activeModelRef = readModelRefFromConfig()
        }

        // Check whether the runtime is already serving before defaulting to .offline.
        // Also handles the case where a previous process is still starting (liveness true,
        // readiness false) — wait up to 30s rather than firing auto-start and hitting a
        // port conflict.
        if await client.checkLiveness(), !(await client.checkReadiness()) {
            status = .starting
            var waited = 0
            while waited < 30 {
                try? await Task.sleep(for: .seconds(2))
                waited += 2
                if await client.checkReadiness() { break }
            }
        }

        if await client.checkReadiness() {
            // Runtime is already up — the live model is authoritative.
            // config.toml may be stale (e.g. written for a model that was never downloaded),
            // so we sync activeModelRef from /v1/models rather than trusting the file.
            // Retry once: /v1/models may be slow to answer right at startup.
            var liveRef = await fetchLiveModelRef()
            if liveRef == nil {
                try? await Task.sleep(for: .milliseconds(600))
                liveRef = await fetchLiveModelRef()
            }
            if let ref = liveRef {
                activeModelRef = ref
            }
            // Only show .ready when we have a usable model identifier.
            // If we still have no ref after retries, keep whatever config.toml gave us;
            // the UI will gate chat via activeModelRef != nil.
            status = .ready
            // Runtime is already running — CLI catalog calls will fail with exit 101.
            // Populate the catalog from the HF dataset cache so Add Model works immediately.
            let hfModels = scanCatalogFromHFCache()
            if !hfModels.isEmpty {
                recommendedModels = hfModels
            } else {
                let cached = loadPersistedCatalog()
                if !cached.isEmpty { recommendedModels = cached }
            }
            startKeepalive()
            return
        }

        status = configHasModels ? .offline : .noModelConfigured

        // Runtime is not running — the CLI can execute freely.
        // Pre-fetch the catalog in the background so it's cached before the
        // user starts the runtime and the CLI becomes unavailable.
        Task.detached(priority: .background) { [weak self] in
            _ = try? await self?.fetchRecommendedModels()
        }
    }

    /// Returns the version string from `mesh-llm --version`, or nil.
    func queryVersion(binary: URL? = nil) async -> String? {
        guard let bin = binary ?? binaryPath else { return nil }
        let result = await run(binary: bin, arguments: ["--version"])
        let line = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        // "mesh-llm 0.65.1+skippy.20260504.kv.2" → strip prefix
        return line.hasPrefix("mesh-llm ") ? String(line.dropFirst("mesh-llm ".count)) : line
    }

    // MARK: - Model Queries

    /// Runs `mesh-llm models installed --json` and decodes the response.
    /// Falls back to scanning the HuggingFace cache directory directly when the CLI
    /// panics with exit 101 (Tokio nested-runtime guard fires while Mesh is running).
    func fetchInstalledModels() async throws -> InstalledModelsResponse {
        guard let bin = binaryPath else {
            throw RuntimeError.binaryNotFound
        }
        let result = await run(binary: bin, arguments: ["models", "installed", "--json"])

        if result.exitCode == 101 || result.stderr.contains("Cannot start a runtime") {
            let scanned = scanInstalledModelsFromCache()
            await MainActor.run { self.installedModels = scanned }
            return InstalledModelsResponse(cacheDir: cacheDir, results: scanned)
        }

        guard result.exitCode == 0, !result.stdout.isEmpty,
              let data = result.stdout.data(using: .utf8) else {
            throw RuntimeError.cliError(result.stderr)
        }
        let response = try JSONDecoder().decode(InstalledModelsResponse.self, from: data)
        await MainActor.run {
            self.installedModels = response.results
            self.cacheDir = response.cacheDir
        }
        return response
    }

    /// Scans `~/.cache/huggingface/hub/` directly for GGUF files.
    /// Used as a fallback when the CLI cannot run alongside a live runtime.
    private func scanInstalledModelsFromCache() -> [InstalledModelEntry] {
        let fm = FileManager.default
        let hubURL = URL(fileURLWithPath: cacheDir)

        guard let repoDirs = try? fm.contentsOfDirectory(
            at: hubURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var entries: [InstalledModelEntry] = []
        var seen = Set<String>()

        for repoDir in repoDirs {
            let dirName = repoDir.lastPathComponent
            guard dirName.hasPrefix("models--") else { continue }

            // "models--Qwen--Qwen2.5-Coder-7B-Instruct-GGUF"
            // → org = "Qwen", repo = "Qwen2.5-Coder-7B-Instruct-GGUF"
            let stripped = String(dirName.dropFirst("models--".count))
            guard let sepRange = stripped.range(of: "--") else { continue }
            let org  = String(stripped[..<sepRange.lowerBound])
            let repo = String(stripped[sepRange.upperBound...])
            guard !org.isEmpty, !repo.isEmpty else { continue }

            let snapshotsURL = repoDir.appendingPathComponent("snapshots")
            guard let snapshots = try? fm.contentsOfDirectory(
                at: snapshotsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for snapshot in snapshots {
                guard let files = try? fm.contentsOfDirectory(
                    at: snapshot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { continue }

                for file in files where file.pathExtension.lowercased() == "gguf" {
                    let filename = file.lastPathComponent
                    let filestem = String(filename.dropLast(".gguf".count))
                    let ref = "\(org)/\(repo)/\(filename)"
                    guard !seen.contains(ref) else { continue }
                    seen.insert(ref)

                    // resolvingSymlinksInPath() follows the symlink to the blob
                    let resolvedPath = file.resolvingSymlinksInPath().path
                    let sizeBytes = (try? fm.attributesOfItem(atPath: resolvedPath))?[.size] as? Int64
                    let sizeStr: String? = sizeBytes.map { bytes in
                        let gb = Double(bytes) / 1_073_741_824
                        return gb >= 1
                            ? String(format: "%.1fGB", gb)
                            : String(format: "%.0fMB", Double(bytes) / 1_048_576)
                    }

                    entries.append(InstalledModelEntry(
                        name: "\(org)/\(repo):\(filestem)",
                        ref: ref,
                        size: sizeStr,
                        type: "gguf",
                        path: file.path
                    ))
                }
            }
        }

        return entries
    }

    /// Runs `mesh-llm models recommended --json` and decodes the response.
    /// Requires network access; fails gracefully without crashing.
    func fetchRecommendedModels() async throws -> [CatalogModel] {
        guard let bin = binaryPath else {
            throw RuntimeError.binaryNotFound
        }

        var result = await run(binary: bin, arguments: ["models", "recommended", "--json"])

        // Self-heal: a stale local catalog cache can cause a JSON schema parse error
        // (exit 1, stderr contains "parse catalog entry <path>").
        // Clear the offending cache directory and retry once.
        if result.exitCode != 0, result.stderr.contains("parse catalog entry") {
            let cachePath = ("~/.cache/meshllm/catalog" as NSString).expandingTildeInPath
            try? FileManager.default.removeItem(atPath: cachePath)
            result = await run(binary: bin, arguments: ["models", "recommended", "--json"])
        }

        // Classify the failure so the UI can show a specific, calm explanation.
        guard result.exitCode == 0 else {
            if result.exitCode == 101 || result.stderr.contains("Cannot start a runtime") {
                // CLI cannot run alongside the live runtime.
                // Read the meshllm/catalog HF dataset that mesh-llm already caches on disk.
                let hfModels = scanCatalogFromHFCache()
                if !hfModels.isEmpty {
                    persistCatalog(hfModels)
                    await MainActor.run { self.recommendedModels = hfModels }
                    return hfModels
                }
                // Fall back to our own persisted snapshot.
                let cached = loadPersistedCatalog()
                if !cached.isEmpty {
                    await MainActor.run { self.recommendedModels = cached }
                    return cached
                }
                throw RuntimeError.catalogNetworkUnavailable
            }
            let detail = result.stderr.isEmpty ? "Exit code \(result.exitCode)" : result.stderr
            throw RuntimeError.cliError(detail)
        }
        guard !result.stdout.isEmpty, let data = result.stdout.data(using: .utf8) else {
            throw RuntimeError.cliError("Catalog command returned no output")
        }

        let response = try JSONDecoder().decode(CatalogModelsResponse.self, from: data)
        let models = response.results
        persistCatalog(models)
        await MainActor.run { self.recommendedModels = models }
        return models
    }

    // MARK: - Private — Catalog cache

    private var catalogCacheURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Orbit")
            .appendingPathComponent("catalog-cache.json")
    }

    private func persistCatalog(_ models: [CatalogModel]) {
        guard let url = catalogCacheURL,
              let data = try? JSONEncoder().encode(models) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func loadPersistedCatalog() -> [CatalogModel] {
        guard let url = catalogCacheURL,
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([CatalogModel].self, from: data)
        else { return [] }
        return models
    }

    // MARK: - Config

    /// Ensures `~/.mesh-llm/config.toml` has a `[[models]]` entry for `modelRef`.
    /// Creates the file if it does not exist. Overwrites any previous model entry.
    func ensureModelConfigured(_ modelRef: String) throws {
        let dir = (("~/.mesh-llm" as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        let configPath = dir + "/config.toml"
        let content = """
        version = 1

        [[models]]
        model = "\(modelRef)"
        """
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Returns true if `~/.mesh-llm/config.toml` contains a `[[models]]` section.
    func configTomlHasModels() -> Bool {
        let path = (("~/.mesh-llm/config.toml" as NSString).expandingTildeInPath)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return content.contains("[[models]]")
    }

    /// Extracts the `model = "..."` value from config.toml, or nil.
    private func readModelRefFromConfig() -> String? {
        let path = (("~/.mesh-llm/config.toml" as NSString).expandingTildeInPath)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("model =") {
                let value = trimmed
                    .dropFirst("model =".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    // MARK: - Lifecycle

    /// Starts the Mesh-LLM runtime.
    /// If `modelRef` is provided, writes config.toml first and passes `--model`.
    /// If `modelRef` is nil, starts from existing config.toml.
    func start(modelRef: String? = nil) async {
        guard let bin = binaryPath else {
            status = .notInstalled
            return
        }

        // If a runtime is already responsive, attach to it rather than launching
        // a competing process that would fail to bind port 9337 and exit immediately.
        if modelRef == nil, await client.checkReadiness() {
            var liveRef = await fetchLiveModelRef()
            if liveRef == nil {
                try? await Task.sleep(for: .milliseconds(600))
                liveRef = await fetchLiveModelRef()
            }
            if let ref = liveRef { activeModelRef = ref }
            status = .ready
            startKeepalive()
            return
        }

        // Cancel any in-flight keepalive before changing status to .starting.
        // Without this, a keepalive tick arriving after status = .starting can
        // race-set status = .offline and abort the startup sequence.
        keepaliveTask?.cancel()
        keepaliveTask = nil

        // Write config.toml and record the active model ref
        if let ref = modelRef {
            do {
                try ensureModelConfigured(ref)
                activeModelRef = ref
            } catch {
                status = .error("Could not configure model: \(error.localizedDescription)")
                return
            }
        }

        // Guard: must have a model configured
        guard configTomlHasModels() else {
            status = .noModelConfigured
            return
        }

        status = .starting
        startupTask?.cancel()
        startupTask = Task {
            await self.launchAndMonitor(binary: bin, modelRef: modelRef)
        }
    }

    /// Stops the runtime, refreshes state.
    ///
    /// Strategy:
    ///   1. `mesh-llm stop` — clean shutdown via management API
    ///   2. Wait 1 s, then probe /readyz — if still up, fall back to port-targeted kill
    ///   3. SIGTERM on owned process handle if present
    ///   4. Verify port is closed; update status
    func stop() async {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        startupTask?.cancel()
        startupTask = nil

        guard status != .notInstalled, status != .stopping else { return }
        status = .stopping

        // 1. Attempt clean shutdown
        if let bin = binaryPath {
            _ = await run(binary: bin, arguments: ["stop"], timeout: 10)
        }

        // 2. Give the process 1 s to exit, then verify it is actually gone.
        try? await Task.sleep(for: .seconds(1))

        let stillLive = await client.checkLiveness()
        let stillReady = await client.checkReadiness()
        if stillLive || stillReady {
            // Still running — fall back to killing the process that owns the API port.
            await killProcessOnAPIPort()
            try? await Task.sleep(for: .milliseconds(600))
        }

        // 3. SIGTERM/SIGKILL on any owned process handle.
        if serveProcess?.isRunning == true {
            serveProcess?.terminate()
            try? await Task.sleep(for: .seconds(2))
            if serveProcess?.isRunning == true {
                serveProcess?.interrupt()
            }
        }
        serveProcess = nil

        // 4. Refresh state so the UI reflects the real situation.
        status = .offline
    }

    /// Kills the process listening on the API port using lsof.
    /// Safe: only sends SIGTERM; never touches unrelated processes.
    private func killProcessOnAPIPort() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-ti", "tcp:\(apiPort)"]
            let pipe = Pipe()
            lsof.standardOutput = pipe
            lsof.standardError = Pipe()
            lsof.terminationHandler = { _ in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let pids = out.components(separatedBy: .newlines).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                for pid in pids {
                    kill(pid, SIGTERM)
                }
                cont.resume()
            }
            try? lsof.run()
        }
    }

    // MARK: - Mesh join / leave

    /// Joins a private mesh using a trusted invite token.
    /// Stops any running process, then restarts with `--join <token>`.
    func joinPrivateMesh(inviteToken: String) async {
        guard !inviteToken.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await stop()
        currentLaunchConfig = RuntimeLaunchConfiguration(
            modelRef: readModelRefFromConfig(),
            joinToken: inviteToken,
            meshMode: .private,
            noEnumerateHost: false
        )
        persistMeshConfig(mode: .private, token: inviteToken)
        meshConnectionState = .connectingPrivate
        await startWithConfig(currentLaunchConfig)
    }

    /// Joins a public/shared mesh using a discovered invite token.
    /// Applies `--no-enumerate-host` to reduce hardware information broadcast.
    func joinPublicMesh(inviteToken: String) async {
        guard !inviteToken.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await stop()
        currentLaunchConfig = RuntimeLaunchConfiguration(
            modelRef: readModelRefFromConfig(),
            joinToken: inviteToken,
            meshMode: .public,
            noEnumerateHost: true   // privacy default for public mesh
        )
        persistMeshConfig(mode: .public, token: inviteToken)
        meshConnectionState = .connectingPublic
        await startWithConfig(currentLaunchConfig)
    }

    /// Leaves the current mesh and returns to local-only mode.
    func leaveMesh() async {
        await stop()
        currentLaunchConfig = RuntimeLaunchConfiguration(modelRef: readModelRefFromConfig())
        clearMeshConfig()
        meshConnectionState = .disconnected
        meshModels = []
        localInviteToken = nil
        await startWithConfig(currentLaunchConfig)
    }

    /// Refreshes mesh status from the management API.
    func refreshMeshStatus() async {
        guard let statusData = await managementClient.fetchStatus() else {
            // Management API unreachable — don't change existing state
            return
        }
        let peerCount = statusData.peerCount

        // Update peer count within the current connected state.
        // Never revert from connected → connecting based on a zero peer count;
        // peers only appear in /api/status when other nodes send us requests.
        switch meshConnectionState {
        case .connectedPrivate:
            meshConnectionState = .connectedPrivate(peerCount: peerCount)
        case .connectedPublic:
            meshConnectionState = .connectedPublic(peerCount: peerCount)
        case .connectingPrivate:
            // Still waiting for runtime to be ready — stay in connecting state
            break
        case .connectingPublic:
            // Still waiting for runtime to be ready — stay in connecting state
            break
        default:
            break
        }
        localInviteToken = statusData.inviteToken
    }

    /// Refreshes the list of models available through the connected mesh.
    func refreshMeshModels() async {
        guard meshConnectionState.isConnected else {
            meshModels = []
            return
        }
        meshModels = await managementClient.fetchModels()
    }

    /// Returns the origin (local/private mesh/public mesh/unavailable) of a model ref.
    func modelOrigin(for ref: String) -> ModelOrigin {
        // Check if installed locally first
        let localMatch = installedModels.contains { entry in
            let entryRef = entry.ref ?? entry.name
            return entryRef == ref || entryRef.hasPrefix(ref + "/") || entryRef.hasPrefix(ref + "@") || entryRef.hasPrefix(ref + ":")
        }
        if localMatch { return .local }

        // Check mesh availability
        let meshMatch = meshModels.contains { $0.name == ref || $0.name.contains(ref) }
        if meshMatch {
            switch meshConnectionState {
            case .connectedPrivate: return .privateMesh
            case .connectedPublic:  return .publicMesh
            case .connectingPrivate, .connectingPublic, .reconnecting:
                return .unavailable
            default:
                return .unavailable
            }
        }

        return .local  // assume local if we can't determine (e.g. activeModelRef just synced)
    }

    // MARK: - Mesh config persistence

    private static let meshModeKey  = "meshMode"
    private static let meshTokenKey = "meshToken"

    private func persistMeshConfig(mode: MeshMode, token: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.meshModeKey)
        // Store token in UserDefaults — tokens are ephemeral (regenerated on node restart)
        // so Keychain is not required. Never logged; truncated in debug descriptions.
        UserDefaults.standard.set(token, forKey: Self.meshTokenKey)
    }

    private func clearMeshConfig() {
        UserDefaults.standard.removeObject(forKey: Self.meshModeKey)
        UserDefaults.standard.removeObject(forKey: Self.meshTokenKey)
    }

    /// Restores the last mesh mode on app launch (so state survives Orbit restarts).
    func restoreMeshConfigIfNeeded() {
        guard let rawMode = UserDefaults.standard.string(forKey: Self.meshModeKey),
              let mode = MeshMode(rawValue: rawMode),
              mode != .none,
              let token = UserDefaults.standard.string(forKey: Self.meshTokenKey),
              !token.isEmpty else { return }
        currentLaunchConfig = RuntimeLaunchConfiguration(
            modelRef: readModelRefFromConfig(),
            joinToken: token,
            meshMode: mode,
            noEnumerateHost: mode == .public
        )
        switch mode {
        case .private: meshConnectionState = .reconnecting
        case .public:  meshConnectionState = .reconnecting
        case .none: break
        }
    }

    // MARK: - Health

    /// One-shot liveness check (GET /health). Returns false if runtime is not running.
    func checkLiveness() async -> Bool {
        await client.checkLiveness()
    }

    /// One-shot readiness check (GET /readyz). Returns true only when a model is loaded.
    func checkReadiness() async -> Bool {
        await client.checkReadiness()
    }

    // MARK: - Private — Live model ref

    /// Queries GET /v1/models and returns the first model's `id` field.
    /// This is the authoritative model identifier when the runtime is already serving.
    private func fetchLiveModelRef() async -> String? {
        guard let url = URL(string: "http://localhost:\(apiPort)/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        struct ModelsResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ModelsResponse.self, from: data),
              let first = response.data.first else {
            return nil
        }
        return first.id
    }

    // MARK: - Private — Config-driven start

    /// Starts the runtime using a fully-specified launch configuration.
    /// Used for mesh join/leave; preserves existing `start(modelRef:)` for onboarding.
    private func startWithConfig(_ config: RuntimeLaunchConfiguration) async {
        guard let bin = binaryPath else { status = .notInstalled; return }
        keepaliveTask?.cancel(); keepaliveTask = nil
        status = .starting
        startupTask?.cancel()
        startupTask = Task { await self.launchAndMonitorWithConfig(binary: bin, config: config) }
    }

    private func launchAndMonitorWithConfig(binary: URL, config: RuntimeLaunchConfiguration) async {
        let process = Process()
        process.executableURL = binary
        process.arguments = config.buildArguments()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { @MainActor in
                if self.status == .stopping { return }
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                self.handleTermination(proc: proc, stderr: stderr)
                self.serveProcess = nil
                self.keepaliveTask?.cancel()
            }
        }
        do { try process.run() } catch {
            status = .error("Could not launch runtime: \(error.localizedDescription)")
            return
        }
        serveProcess = process
        await pollUntilReady(timeout: 300)
    }

    // MARK: - Private — Process launch

    private func launchAndMonitor(binary: URL, modelRef: String?) async {
        let config = RuntimeLaunchConfiguration(
            modelRef: modelRef ?? readModelRefFromConfig(),
            joinToken: currentLaunchConfig.joinToken,
            meshMode: currentLaunchConfig.meshMode,
            noEnumerateHost: currentLaunchConfig.noEnumerateHost
        )
        await launchAndMonitorWithConfig(binary: binary, config: config)
    }

    private func pollUntilReady(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)

        // Phase 1: wait for /health (HTTP server up)
        var httpUp = false
        while !httpUp && Date() < deadline {
            if await client.checkLiveness() { httpUp = true; break }
            // Only exit early if OUR process died AND nothing else is serving.
            // If another process is already on port 9337, keep polling.
            if serveProcess?.isRunning == false {
                if !(await client.checkLiveness()) { return }
            }
            try? await Task.sleep(for: .milliseconds(800))
        }

        guard httpUp else {
            status = .error("AI took too long to start. Try restarting Orbit.")
            return
        }

        // Phase 2: wait for /readyz (model loaded)
        while Date() < deadline {
            if await client.checkReadiness() {
                // Sync active model ref from the live API so chat always uses
                // the identifier the runtime actually reports, not a stale config value.
                if let liveRef = await fetchLiveModelRef() {
                    activeModelRef = liveRef
                }
                status = .ready

                // Transition mesh connection state as soon as the runtime is ready.
                // The runtime being up with a --join token means we ARE connected —
                // peer count is display metadata that updates over time via polling.
                // Do NOT gate "connected" on peerCount > 0: peers only appear in
                // /api/status when other nodes send us requests, which may take minutes.
                switch currentLaunchConfig.meshMode {
                case .private:
                    meshConnectionState = .connectedPrivate(peerCount: 0)
                case .public:
                    meshConnectionState = .connectedPublic(peerCount: 0)
                case .none:
                    break
                }

                startKeepalive()

                // Immediate management API poll to populate peer count and mesh models.
                // The keepalive will continue refreshing every 30s thereafter.
                await refreshMeshStatus()
                await refreshMeshModels()
                return
            }
            if serveProcess?.isRunning == false { return }
            try? await Task.sleep(for: .seconds(2))
        }

        status = .error("AI took too long to start. Try restarting Orbit.")
    }

    // MARK: - Private — Keepalive

    func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            var failCount = 0
            var meshPollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }

                // Liveness / readiness check (every 10s)
                let alive = await self.client.checkLiveness()
                if alive {
                    failCount = 0
                } else {
                    failCount += 1
                    if failCount >= 2 {
                        let ready = await self.client.checkReadiness()
                        if !ready {
                            guard self.status != .starting, self.status != .stopping else { return }
                            self.status = .offline
                            return
                        }
                        failCount = 0
                    }
                }

                // Mesh status polling (every 30s — management API is lower priority)
                meshPollCount += 1
                if meshPollCount >= 3 {
                    meshPollCount = 0
                    await self.refreshMeshStatus()
                    await self.refreshMeshModels()
                }
            }
        }
    }

    // MARK: - Private — Termination handler (shared)

    private func handleTermination(proc: Process, stderr: String) {
        if Self.isModelNotFoundError(stderr) {
            activeModelRef = nil
            status = .noModelConfigured
        } else if proc.terminationStatus == 0 && (stderr.isEmpty
            || stderr.contains("rotating identity")
            || stderr.contains("No models configured")) {
            status = .noModelConfigured
        } else {
            status = .offline
        }
    }

    // MARK: - Private — CLI helpers

    struct CLIResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func run(binary: URL, arguments: [String], timeout: TimeInterval = 30) async -> CLIResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Accessed from terminationHandler and timeout Task concurrently.
            // nonisolated(unsafe) opts out of data-race checking; we accept the
            // benign race: the continuation is resumed at most once in practice
            // because process termination and timeout are mutually exclusive in
            // the common case, and CheckedContinuation will trap on double-resume.
            nonisolated(unsafe) var completed = false

            process.terminationHandler = { proc in
                guard !completed else { return }
                completed = true
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: CLIResult(stdout: out, stderr: err, exitCode: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                completed = true
                continuation.resume(returning: CLIResult(stdout: "", stderr: error.localizedDescription, exitCode: 1))
                return
            }

            // Timeout watchdog
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !completed else { return }
                completed = true
                process.terminate()
                continuation.resume(returning: CLIResult(stdout: "", stderr: "timeout", exitCode: 1))
            }
        }
    }

    // MARK: - Private — HF catalog cache reader

    /// Reads the meshllm/catalog HuggingFace dataset that mesh-llm caches locally.
    /// This avoids the CLI entirely, so it works while the runtime is running.
    /// Returns an empty array when the cache doesn't exist (first install, no prior CLI run).
    private func scanCatalogFromHFCache() -> [CatalogModel] {
        let fm = FileManager.default
        let hubPath = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
        let catalogDir = URL(fileURLWithPath: hubPath)
            .appendingPathComponent("datasets--meshllm--catalog")

        let refsMain = catalogDir.appendingPathComponent("refs/main").path
        guard let commitHash = try? String(contentsOfFile: refsMain, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !commitHash.isEmpty
        else { return [] }

        let entriesURL = catalogDir
            .appendingPathComponent("snapshots")
            .appendingPathComponent(commitHash)
            .appendingPathComponent("entries")

        guard let orgDirs = try? fm.contentsOfDirectory(
            at: entriesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var models: [CatalogModel] = []
        let decoder = JSONDecoder()

        for orgDir in orgDirs {
            guard let repoFiles = try? fm.contentsOfDirectory(
                at: orgDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for repoFile in repoFiles where repoFile.pathExtension == "json" {
                let resolved = repoFile.resolvingSymlinksInPath()
                guard let data = try? Data(contentsOf: resolved),
                      let entry = try? decoder.decode(HFCatalogEntry.self, from: data)
                else { continue }

                for (_, variant) in entry.variants {
                    let ref = "\(variant.source.repo)/\(variant.source.file)"
                    let name = variant.curated?.name ?? "\(entry.sourceRepo):\(variant.source.file)"
                    models.append(CatalogModel(
                        name: name,
                        ref: ref,
                        description: variant.curated?.description,
                        size: variant.curated?.size,
                        type: "gguf",
                        capabilities: nil
                    ))
                }
            }
        }

        return models
    }

    // MARK: - Private — Error classification

    /// Returns true when the stderr output indicates the configured model doesn't exist locally.
    /// Covers: model name typo, test artifact in config.toml, model deleted from HF cache.
    static func isModelNotFoundError(_ stderr: String) -> Bool {
        let indicators = [
            "Model not found:",
            "not in the Hugging Face cache",
            "Not a local file, not in the Hugging Face cache",
            "not in catalog",
            "No such model",
            "model not found",
        ]
        return indicators.contains { stderr.localizedCaseInsensitiveContains($0) }
    }

    // MARK: - Private — Binary resolution

    static func resolveBinary() -> URL? {
        for path in candidatePaths {
            let fm = FileManager.default
            if fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

// MARK: - RuntimeError

enum RuntimeError: LocalizedError {
    case binaryNotFound
    case cliError(String)
    /// The runtime binary cannot make network calls in +skippy builds (exit 101 / async runtime panic).
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

// MARK: - HF catalog local format (private to RuntimeManager)

private struct HFCatalogEntry: Decodable {
    let sourceRepo: String
    let variants: [String: HFCatalogVariant]
    enum CodingKeys: String, CodingKey {
        case sourceRepo = "source_repo"
        case variants
    }
}

private struct HFCatalogVariant: Decodable {
    let source: HFCatalogSource
    let curated: HFCatalogCurated?
}

private struct HFCatalogSource: Decodable {
    let repo: String
    let revision: String
    let file: String
}

private struct HFCatalogCurated: Decodable {
    let name: String?
    let size: String?
    let description: String?
}
