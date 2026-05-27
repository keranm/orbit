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

    enum DownloadPhase: Equatable {
        case resolving
        case downloading(Double)
        case done
        case failed(String)
    }

    private(set) var downloadQueue: [String: DownloadPhase] = [:]

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

    // MARK: - Background download completion

    private(set) var completedDownloadRef: String?
    private(set) var completedDownloadName: String?

    func dismissCompletedDownload() {
        completedDownloadRef = nil
        completedDownloadName = nil
    }

    // MARK: - Private

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Load installed models

    func loadInstalled(rm: any ModelCataloguing) async {
        guard !isLoadingInstalled else { return }

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

    func loadRecommended(rm: any ModelCataloguing) async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogLoadError = nil
        catalogErrorDetail = nil

        do {
            let models = try await rm.fetchRecommendedModels()
            recommendedModels = models
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

    func startDownload(ref: String, rm: any ModelCataloguing) {
        guard downloadTasks[ref] == nil else { return }
        downloadQueue[ref] = .resolving
        let modelName = recommendedModels.first { $0.ref == ref }?.name
        let expectedBytes = HuggingFaceCacheScanner.parseExpectedBytes(recommendedModels.first { $0.ref == ref }?.size)
        let cacheDir = rm.cacheDir

        downloadTasks[ref] = Task {
            defer { downloadTasks[ref] = nil }
            do {
                downloadQueue[ref] = .downloading(0)
                // Poll the HuggingFace blob directory for real file-size progress
                let progressTask: Task<Void, Never>? = expectedBytes.map { bytes in
                    Task { [weak self] in
                        for await progress in HuggingFaceCacheScanner.pollBlobProgress(ref: ref, cacheDir: cacheDir, expectedBytes: bytes) {
                            await MainActor.run { self?.downloadQueue[ref] = .downloading(progress) }
                        }
                    }
                }
                defer { progressTask?.cancel() }

                try await rm.downloadModel(ref: ref)
                downloadQueue[ref] = .done
                try rm.ensureModelConfigured(ref)
                await loadInstalled(rm: rm)
                if !showCatalog {
                    completedDownloadRef = ref
                    completedDownloadName = modelName
                }
                downloadQueue.removeValue(forKey: ref)
            } catch {
                if !Task.isCancelled {
                    downloadQueue[ref] = .failed("Download stopped. Try again.")
                }
            }
        }
    }

    func cancelDownload(ref: String) {
        downloadTasks[ref]?.cancel()
        downloadTasks[ref] = nil
        downloadQueue.removeValue(forKey: ref)
    }

    func retryDownload(ref: String, rm: any ModelCataloguing) {
        cancelDownload(ref: ref)
        startDownload(ref: ref, rm: rm)
    }

    // MARK: - Set active model

    /// Selects a mesh-served model. Does not restart the runtime.
    func selectMeshModel(_ model: MeshModelEntry, rm: any ModelCataloguing) {
        rm.selectMeshModel(model)
    }

    func setActiveModel(_ model: InstalledModelEntry, rm: any ModelCataloguing) async {
        let ref = model.ref ?? model.name

        switch rm.status {
        case .notInstalled, .starting, .stopping:
            break
        case .ready:
            // Node is running — swap models without restarting the node.
            await rm.loadModel(ref)
        case .offline, .noModelConfigured, .error:
            await rm.start(modelRef: ref)
        }
    }

    // MARK: - Remove model

    func removeModel(_ model: InstalledModelEntry, rm: any ModelCataloguing) async {
        let ref = model.ref ?? model.name
        removeError = nil

        do {
            try await rm.deleteModel(ref: ref)
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

    func downloadPhase(for ref: String) -> DownloadPhase? {
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
