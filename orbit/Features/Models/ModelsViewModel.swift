import SwiftUI

/// State for the Models screen.
/// Drives the installed model list, catalog browser, download queue, and detail panel.
@Observable
@MainActor
final class ModelsViewModel {

    // MARK: - Model lists

    private(set) var installedModels: [InstalledModelEntry] = []
    private(set) var recommendedModels: [CatalogModel] = []
    private(set) var selectedModel: InstalledModelEntry?

    // MARK: - Loading states

    private(set) var isLoadingInstalled = false
    private(set) var isLoadingCatalog = false

    // MARK: - Download queue: ref → current phase

    private(set) var downloadQueue: [String: ModelService.DownloadPhase] = [:]

    // MARK: - Errors (inline, not modal)

    private(set) var installedLoadError: String?
    private(set) var catalogLoadError: String?
    /// Richer context surfaced from the last catalog failure, shown in the diagnostics panel.
    private(set) var catalogErrorDetail: CatalogErrorDetail?
    private(set) var removeError: String?

    struct CatalogErrorDetail {
        let technicalMessage: String
        let isNetworkError: Bool
    }

    // MARK: - Sheet / panel state

    var showCatalog = false

    // MARK: - Private

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private let service = ModelService()

    // MARK: - Load installed models

    func loadInstalled(rm: RuntimeManager) async {
        guard !isLoadingInstalled else { return }

        // If no binary is installed or the path doesn't exist, show empty state — not an error.
        guard let bin = rm.binaryPath,
              FileManager.default.isExecutableFile(atPath: bin.path) else {
            installedModels = []
            isLoadingInstalled = false
            return
        }

        isLoadingInstalled = true
        installedLoadError = nil

        do {
            let response = try await rm.fetchInstalledModels()
            installedModels = response.results
            if let sel = selectedModel, !installedModels.contains(sel) {
                selectedModel = nil
            }
        } catch {
            installedLoadError = "Couldn't load your models. Try refreshing."
        }
        isLoadingInstalled = false
    }

    // MARK: - Load recommended catalog

    func loadRecommended(rm: RuntimeManager) async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogLoadError = nil
        catalogErrorDetail = nil

        do {
            let models = try await rm.fetchRecommendedModels()
            recommendedModels = models
        } catch let error as RuntimeError {
            switch error {
            case .catalogNetworkUnavailable:
                catalogLoadError = "unavailable"
                catalogErrorDetail = CatalogErrorDetail(
                    technicalMessage: "Runtime reported: Cannot start a runtime from within a runtime (exit 101). This is a known limitation of the current runtime build.",
                    isNetworkError: true
                )
            case .cliError(let msg):
                catalogLoadError = "cli_error"
                catalogErrorDetail = CatalogErrorDetail(
                    technicalMessage: msg.isEmpty ? "CLI exited with an error and no output." : msg,
                    isNetworkError: false
                )
            case .binaryNotFound:
                catalogLoadError = "not_installed"
                catalogErrorDetail = CatalogErrorDetail(
                    technicalMessage: "The Orbit runtime binary could not be found.",
                    isNetworkError: false
                )
            }
        } catch {
            catalogLoadError = "unknown"
            catalogErrorDetail = CatalogErrorDetail(
                technicalMessage: error.localizedDescription,
                isNetworkError: false
            )
        }
        isLoadingCatalog = false
    }

    // MARK: - Download

    func startDownload(ref: String, binaryPath: URL, rm: RuntimeManager) {
        guard downloadTasks[ref] == nil else { return }
        downloadQueue[ref] = .starting

        downloadTasks[ref] = Task {
            defer { downloadTasks[ref] = nil }

            // Stop any running runtime before spawning the download CLI.
            // The mesh-llm binary panics (exit 101) if any mesh-llm process
            // holds an active Tokio runtime — including one that is still starting.
            let shouldRestart = rm.status == .ready || rm.status == .starting
            if shouldRestart {
                await rm.stop()
                // Kill-and-verify loop: keep sending SIGKILL until pgrep confirms
                // zero mesh-llm processes remain. The download CLI panics (exit 101)
                // if ANY mesh-llm process holds a live Tokio runtime.
                for _ in 0..<8 {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        let kill = Process()
                        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                        kill.arguments = ["-KILL", "-x", "mesh-llm"]
                        kill.standardOutput = FileHandle.nullDevice
                        kill.standardError  = FileHandle.nullDevice
                        kill.terminationHandler = { _ in cont.resume() }
                        if (try? kill.run()) == nil { cont.resume() }
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    // pgrep exits 0 if processes found, 1 if none — stop killing when clear
                    let stillRunning = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                        let pg = Process()
                        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                        pg.arguments = ["-x", "mesh-llm"]
                        pg.standardOutput = FileHandle.nullDevice
                        pg.standardError  = FileHandle.nullDevice
                        pg.terminationHandler = { p in cont.resume(returning: p.terminationStatus == 0) }
                        if (try? pg.run()) == nil { cont.resume(returning: false) }
                    }
                    if !stillRunning { break }
                }
                // Final port check
                var portChecks = 0
                while await rm.checkLiveness(), portChecks < 10 {
                    try? await Task.sleep(for: .milliseconds(300))
                    portChecks += 1
                }
            }

            do {
                for try await phase in service.download(binaryPath: binaryPath, ref: ref) {
                    downloadQueue[ref] = phase
                    if case .done = phase {
                        await loadInstalled(rm: rm)
                        downloadQueue.removeValue(forKey: ref)
                        if shouldRestart { await rm.start() }
                        break
                    }
                    if case .failed = phase {
                        if shouldRestart { await rm.start() }
                        break
                    }
                }
            } catch {
                if shouldRestart { await rm.start() }
                downloadQueue[ref] = .failed("Download stopped. Try again.")
            }
        }
    }

    func cancelDownload(ref: String) {
        downloadTasks[ref]?.cancel()
        downloadTasks[ref] = nil
        downloadQueue.removeValue(forKey: ref)
    }

    func retryDownload(ref: String, binaryPath: URL, rm: RuntimeManager) {
        cancelDownload(ref: ref)
        startDownload(ref: ref, binaryPath: binaryPath, rm: rm)
    }

    // MARK: - Set active model

    func setActiveModel(_ model: InstalledModelEntry, rm: RuntimeManager) async {
        let ref = model.ref ?? model.name
        do {
            try rm.ensureModelConfigured(ref)

            switch rm.status {
            case .notInstalled:
                // Binary is gone — nothing to start. Config is written for when it returns.
                break
            case .starting, .stopping:
                // Already transitioning — wait for it to settle; don't interrupt.
                break
            case .ready:
                // Runtime is up with a different model — full restart needed.
                await rm.stop()
                await rm.start(modelRef: ref)
            case .offline, .noModelConfigured, .error:
                // Runtime is idle or had no model. Start fresh with the selected model.
                await rm.start(modelRef: ref)
            }
        } catch {
            removeError = "Couldn't activate this model. Try again."
        }
    }

    // MARK: - Remove model

    func removeModel(_ model: InstalledModelEntry, binaryPath: URL, rm: RuntimeManager) async {
        let ref = model.ref ?? model.name
        removeError = nil

        do {
            try await service.remove(binaryPath: binaryPath, ref: ref)
            // Clean up the HuggingFace cache directory so the broken-symlink
            // problem (BUG-002) doesn't cause "No such file" on next serve start.
            removeHFCacheDirectory(for: ref)
            await loadInstalled(rm: rm)
            if selectedModel?.id == model.id { selectedModel = nil }
        } catch {
            removeError = "Couldn't remove \(model.displayName). Try again."
        }
    }

    /// Removes the HuggingFace hub cache directory for a model ref.
    /// Only removes directories that start with "models--" directly inside the hub root.
    private func removeHFCacheDirectory(for ref: String) {
        let hubPath = ("~/.cache/huggingface/hub" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: hubPath) else { return }

        // Derive directory name: take org/repo from ref, convert to models--org--repo format
        let stripped = ref.components(separatedBy: "@").first?
            .components(separatedBy: ":").first ?? ref
        let parts = stripped.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return }

        let dirName = "models--\(parts[0])--\(parts[1])"
            .replacingOccurrences(of: "_", with: "-")
        guard dirName.hasPrefix("models--") else { return }

        let fullPath = (hubPath as NSString).appendingPathComponent(dirName)
        guard URL(fileURLWithPath: fullPath).deletingLastPathComponent().path == hubPath else { return }

        try? fm.removeItem(atPath: fullPath)
    }

    // MARK: - Selection

    func select(_ model: InstalledModelEntry) {
        selectedModel = selectedModel?.id == model.id ? nil : model
    }

    func clearSelection() {
        selectedModel = nil
    }

    // MARK: - Helpers

    func downloadPhase(for ref: String) -> ModelService.DownloadPhase? {
        downloadQueue[ref]
    }

    func isDownloading(ref: String) -> Bool {
        if let phase = downloadQueue[ref] {
            if case .done = phase { return false }
            if case .failed = phase { return false }
            return true
        }
        return false
    }

    func isInstalled(ref: String) -> Bool {
        installedModels.contains { ($0.ref ?? $0.name) == ref }
    }
}
