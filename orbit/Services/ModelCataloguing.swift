import Foundation

/// The surface of RuntimeAdapter that ModelsViewModel and LocalMobileAPIServer
/// depend on. Defining this as a protocol means tests can inject a mock without
/// spinning up a real Node.
///
/// Two concrete adapters exist today: RuntimeAdapter (production) and a
/// future MockModelCatalogue for unit tests. One adapter = hypothetical seam;
/// two adapters = real seam.
@MainActor
protocol ModelCataloguing: AnyObject {
    // MARK: - Catalogue state
    var installedModels: [InstalledModelEntry] { get }
    var cacheDir: String { get }
    var activeModelRef: String? { get }
    var status: RuntimeStatus { get }
    var meshModels: [MeshModelEntry] { get }
    var meshConnectionState: MeshConnectionState { get }

    // MARK: - Catalogue operations
    func fetchInstalledModels() async throws -> InstalledModelsResponse
    func fetchRecommendedModels() async throws -> [CatalogModel]
    func downloadModel(ref: String) async throws
    func deleteModel(ref: String) async throws
    func ensureModelConfigured(_ ref: String) throws

    // MARK: - Runtime control (needed by ModelsViewModel.setActiveModel)
    func start(modelRef: String?) async
    func loadModel(_ ref: String) async
    func selectMeshModel(_ model: MeshModelEntry)
}

extension RuntimeAdapter: ModelCataloguing {}
