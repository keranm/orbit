import Foundation

/// A model recommended by the catalog (will be replaced by SDK's `ModelSummary`).
struct CatalogModel: Codable, Identifiable, Hashable {
    let name: String
    let ref: String
    let description: String?
    let size: String?
    let type: String?

    var id: String { ref }
}
