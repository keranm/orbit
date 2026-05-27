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
        let expectedBytes = parseSizeToBytes(recommendedModels.first { $0.ref == ref }?.size)
        let cacheDir = rm.cacheDir

        downloadTasks[ref] = Task {
            defer { downloadTasks[ref] = nil }
            do {
                downloadQueue[ref] = .downloading(0)
                // Poll the HuggingFace blob directory for real file-size progress
                let progressTask: Task<Void, Never>? = expectedBytes.map { bytes in
                    Task { [weak self] in
                        await self?.pollDownloadProgress(ref: ref, expectedBytes: bytes, cacheDir: cacheDir)
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

    // MARK: - Download progress polling

    private func parseSizeToBytes(_ sizeLabel: String?) -> Int64? {
        guard let s = sizeLabel?.trimmingCharacters(in: .whitespaces).uppercased() else { return nil }
        if s.hasSuffix("GB"), let v = Double(s.dropLast(2)) { return Int64(v * 1_000_000_000) }
        if s.hasSuffix("MB"), let v = Double(s.dropLast(2)) { return Int64(v * 1_000_000) }
        return nil
    }

    private func repoDirName(from ref: String) -> String? {
        let repoPath = ref.contains(":") ? String(ref.split(separator: ":")[0]) : ref
        let parts = repoPath.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return "models--\(parts[0])--\(parts[1])"
    }

    private func pollDownloadProgress(ref: String, expectedBytes: Int64, cacheDir: String) async {
        let fm = FileManager.default
        let blobsURL: URL = {
            if let dir = repoDirName(from: ref) {
                return URL(fileURLWithPath: cacheDir).appendingPathComponent(dir).appendingPathComponent("blobs")
            }
            return URL(fileURLWithPath: cacheDir)
        }()
        var prevSizes: [String: Int64] = [:]

        while !Task.isCancelled {
            var maxBytes: Int64 = 0
            var curSizes: [String: Int64] = [:]

            if let enumerator = fm.enumerator(
                at: blobsURL,
                includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    // Skip symlinks — we want actual blobs, not the snapshot symlinks
                    guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }
                    guard let size = (try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]))?.fileSize else { continue }
                    let fileBytes = Int64(size)
                    let key = url.lastPathComponent
                    curSizes[key] = fileBytes

                    if key.hasSuffix(".incomplete") {
                        // Standard hf-hub naming for in-progress blobs
                        maxBytes = max(maxBytes, fileBytes)
                    } else if fileBytes > 1_000_000, fileBytes < expectedBytes {
                        // Fallback: any large file that grew since last poll is likely an in-progress blob
                        if fileBytes > (prevSizes[key] ?? 0) {
                            maxBytes = max(maxBytes, fileBytes)
                        }
                    }
                }
            }
            prevSizes = curSizes

            if maxBytes > 0 {
                let progress = min(Double(maxBytes) / Double(expectedBytes), 0.99)
                downloadQueue[ref] = .downloading(progress)
            }
            try? await Task.sleep(for: .milliseconds(500))
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
