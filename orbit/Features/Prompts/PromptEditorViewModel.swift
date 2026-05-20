import SwiftUI

@Observable
@MainActor
final class PromptEditorViewModel {
    let template: PromptTemplate
    private let service: PromptServiceProtocol

    var editedBody: String
    var editedName: String
    var editedDescription: String
    var editedTags: String
    var changeDescription: String = ""
    var hasUnsavedChanges = false

    private(set) var testOutput: String = ""
    private(set) var isTesting = false

    var variableValues: [String: String] = [:]

    init(template: PromptTemplate, service: PromptServiceProtocol) {
        self.template = template
        self.service = service
        editedBody = template.body
        editedName = template.name
        editedDescription = template.templateDescription
        editedTags = template.tags.joined(separator: ", ")
        for variable in template.variables {
            variableValues[variable.name] = variable.defaultValue
        }
    }

    var renderedPreview: String {
        service.render(body: editedBody, variables: variableValues)
    }

    var characterCount: Int { editedBody.count }
    var tokenEstimate: Int { editedBody.split(separator: " ").count + editedBody.count / 4 }

    func save() {
        template.name = editedName
        template.templateDescription = editedDescription
        template.tags = editedTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        template.body = editedBody
        template.updatedAt = .now
        hasUnsavedChanges = false
        Task { try? await service.save(template) }
    }

    func saveAsNewVersion() async {
        try? await service.createVersion(
            for: template,
            body: editedBody,
            changeDescription: changeDescription
        )
        hasUnsavedChanges = false
    }

    func runTest() async {
        isTesting = true
        testOutput = renderedPreview
        // In a real implementation this would call ChatService.
        // For now, preview the rendered body.
        try? await Task.sleep(nanoseconds: 300_000_000)
        isTesting = false
    }
}
