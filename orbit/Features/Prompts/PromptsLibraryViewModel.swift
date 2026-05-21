import SwiftUI
import SwiftData

enum PromptsTab: String, CaseIterable {
    case all = "All Prompts"
    case tags = "Tags"
    case community = "Community"

    var isDisabled: Bool { self == .community }
    var icon: String {
        switch self {
        case .all:       return "list.bullet"
        case .tags:      return "tag"
        case .community: return "person.2"
        }
    }
}

enum PromptsSortOrder: String, CaseIterable {
    case lastUsed = "Last Used"
    case name = "Name"
    case usage = "Usage"
}

@Observable
@MainActor
final class PromptsLibraryViewModel {
    let service: PromptServiceProtocol

    private(set) var templates: [PromptTemplate] = []
    private(set) var isLoading = true
    private(set) var error: String?

    // Browse mode state
    var searchText = ""
    var selectedTab: PromptsTab = .all
    var sortOrder: PromptsSortOrder = .lastUsed
    var selectedTag: String?
    var selectedModel: String?
    var selectedTemplateID: PromptTemplate.ID?

    var selectedTemplate: PromptTemplate? {
        get { templates.first { $0.id == selectedTemplateID } }
        set { selectedTemplateID = newValue?.id }
    }

    // Edit mode state
    var isEditing = false
    var editingTemplate: PromptTemplate?

    init(service: PromptServiceProtocol) {
        self.service = service
    }

    // MARK: - Filtering & Sorting

    var allTags: [String] {
        Array(Set(templates.flatMap(\.tags))).sorted()
    }

    var allModels: [String] {
        Array(Set(templates.compactMap(\.modelAssociation))).sorted()
    }

    var filteredTemplates: [PromptTemplate] {
        var result = templates

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.templateDescription.localizedCaseInsensitiveContains(searchText)
                || $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        if let model = selectedModel {
            result = result.filter { $0.modelAssociation == model }
        }

        switch sortOrder {
        case .lastUsed: result.sort { $0.updatedAt > $1.updatedAt }
        case .name:     result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .usage:    result.sort { $0.usageCount > $1.usageCount }
        }

        return result
    }

    // MARK: - Lifecycle

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

    // MARK: - Actions

    func delete(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        if selectedTemplate?.id == template.id { selectedTemplate = nil }
        Task { try? await service.delete(template) }
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
        Task { try? await service.save(copy) }
    }

    func createNewTemplate() {
        let template = PromptTemplate(name: "New Prompt")
        templates.insert(template, at: 0)
        editingTemplate = template
        selectedTemplate = template
        isEditing = true
        Task { try? await service.save(template) }
    }

    func startEditing(_ template: PromptTemplate? = nil) {
        editingTemplate = template ?? selectedTemplate
        isEditing = true
    }

    func cancelEditing() {
        // If the template was just created and never saved properly, remove it
        if let t = editingTemplate, t.body.isEmpty, t.name == "New Prompt" {
            templates.removeAll { $0.id == t.id }
            selectedTemplate = nil
        }
        editingTemplate = nil
        isEditing = false
    }
}
