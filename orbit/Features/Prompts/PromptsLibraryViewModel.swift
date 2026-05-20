import SwiftUI
import SwiftData

@Observable
@MainActor
final class PromptsLibraryViewModel {
    let service: PromptServiceProtocol

    private(set) var templates: [PromptTemplate] = []
    private(set) var isLoading = true
    private(set) var error: String?
    var searchText = ""
    var selectedTag: String?

    var selectedTemplate: PromptTemplate?
    var showEditor = false

    init(service: PromptServiceProtocol) {
        self.service = service
    }

    var filteredTemplates: [PromptTemplate] {
        var result = templates
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.templateDescription.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        return result
    }

    var allTags: [String] {
        Array(Set(templates.flatMap(\.tags))).sorted()
    }

    func onAppear() async {
        isLoading = true
        error = nil
        do {
            templates = try await service.fetchAll()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        Task {
            try? await service.delete(template)
        }
    }

    func duplicate(_ template: PromptTemplate) {
        let copy = PromptTemplate(
            name: "\(template.name) (copy)",
            description: template.templateDescription,
            tags: template.tags,
            body: template.body,
            modelAssociation: template.modelAssociation
        )
        templates.insert(copy, at: 0)
        Task {
            try? await service.save(copy)
        }
    }
}
