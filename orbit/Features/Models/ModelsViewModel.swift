import SwiftUI

/// State for the Models screen.
/// Drives the installed model list, catalog browser, download queue, and detail panel.
@Observable
@MainActor
final class ModelsViewModel {

    // MARK: - Model lists

    var installedModels: [InstalledModelEntry] = []
    private(set) var recommendedModels: [CatalogModel] = []
    private(set) var selectedModel: InstalledModelEntry?

    // MARK: - Loading states

    private(set) var isLoadingInstalled = false
    private(set) var isLoadingCatalog = false

    // MARK: - Download queue: ref → current phase

    private(set) var downloadQueue: [String: ModelDownloadService.Phase] = [:]

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

    func startDownload(ref: String, rm: RuntimeManager) {
        guard downloadTasks[ref] == nil else { return }
        downloadQueue[ref] = .resolving

        downloadTasks[ref] = Task {
            defer { downloadTasks[ref] = nil }

            let service = ModelDownloadService(cacheDir: rm.cacheDir)

            do {
                for try await phase in service.download(ref: ref) {
                    downloadQueue[ref] = phase
                    if case .done = phase {
                        try rm.ensureModelConfigured(ref)
                        await loadInstalled(rm: rm)
                        downloadQueue.removeValue(forKey: ref)
                        break
                    }
                    if case .failed = phase {
                        break
                    }
                }
            } catch {
                downloadQueue[ref] = .failed("Download stopped. Try again.")
            }
        }
    }

    func cancelDownload(ref: String) {
        downloadTasks[ref]?.cancel()
        downloadTasks[ref] = nil
        downloadQueue.removeValue(forKey: ref)
    }

    func retryDownload(ref: String, rm: RuntimeManager) {
        cancelDownload(ref: ref)
        startDownload(ref: ref, rm: rm)
    }

    // MARK: - Set active model

    /// Selects a mesh-served model. Does not restart the runtime.
    func selectMeshModel(_ model: MeshModelEntry, rm: RuntimeManager) {
        rm.selectMeshModel(model)
    }

    func setActiveModel(_ model: InstalledModelEntry, rm: RuntimeManager) async {
        let ref = model.ref ?? model.name

        switch rm.status {
        case .notInstalled:
            // Binary is gone — nothing to start.
            break
        case .starting, .stopping:
            // Already transitioning — wait for it to settle; don't interrupt.
            break
        case .ready:
            // Runtime is up — full restart with the new model ref.
            // rm.start(modelRef:) writes config.toml before launching.
            await rm.stop()
            await rm.start(modelRef: ref)
        case .offline, .noModelConfigured, .error:
            // Runtime is idle or had no model. Start fresh with the selected model.
            await rm.start(modelRef: ref)
        }
    }

    // MARK: - Remove model

    func removeModel(_ model: InstalledModelEntry, binaryPath: URL, rm: RuntimeManager) async {
        let ref = model.ref ?? model.name
        removeError = nil

        do {
            try await ModelService().remove(binaryPath: binaryPath, ref: ref)
            await loadInstalled(rm: rm)
            if selectedModel?.id == model.id { selectedModel = nil }
        } catch {
            removeError = "Couldn't remove \(model.displayName). Try again."
        }
    }

    // MARK: - Selection

    func select(_ model: InstalledModelEntry) {
        selectedModel = selectedModel?.id == model.id ? nil : model
    }

    func clearSelection() {
        selectedModel = nil
    }

    // MARK: - Helpers

    func downloadPhase(for ref: String) -> ModelDownloadService.Phase? {
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
