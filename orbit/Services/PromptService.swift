import SwiftData
import Foundation

// MARK: - Protocol

@MainActor
protocol PromptServiceProtocol {
    func fetchAll() async throws -> [PromptTemplate]
    func fetch(id: UUID) async throws -> PromptTemplate?
    func save(_ template: PromptTemplate) async throws
    func delete(_ template: PromptTemplate) async throws
    func render(body: String, variables: [String: String]) -> String
    func createVersion(for template: PromptTemplate, body: String, changeDescription: String) async throws
}

// MARK: - Real implementation

final class PromptService: PromptServiceProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchAll() async throws -> [PromptTemplate] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PromptTemplate>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> PromptTemplate? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<PromptTemplate>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func save(_ template: PromptTemplate) async throws {
        let context = ModelContext(container)
        if template.modelContext == nil {
            context.insert(template)
        }
        try context.save()
    }

    func delete(_ template: PromptTemplate) async throws {
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<PromptTemplate>())
        guard let object = all.first(where: { $0.id == template.id }) else { return }
        context.delete(object)
        try context.save()
    }

    /// Replaces `{{variableName}}` placeholders with the provided values.
    func render(body: String, variables: [String: String]) -> String {
        var result = body
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    func createVersion(for template: PromptTemplate, body: String, changeDescription: String) async throws {
        let newVersion = PromptVersion(
            versionNumber: template.version + 1,
            body: body,
            changeDescription: changeDescription
        )
        newVersion.template = template
        template.versions.append(newVersion)
        template.version += 1
        template.body = body
        template.updatedAt = .now

        let context = ModelContext(container)
        context.insert(newVersion)
        try context.save()
    }
}

// MARK: - Mock

final class MockPromptService: PromptServiceProtocol {
    private var templates: [PromptTemplate] = []
    private let queue = DispatchQueue(label: "mock-prompt-service")

    func fetchAll() async throws -> [PromptTemplate] {
        queue.sync { templates }
    }

    func fetch(id: UUID) async throws -> PromptTemplate? {
        queue.sync { templates.first { $0.id == id } }
    }

    func save(_ template: PromptTemplate) async throws {
        queue.sync { templates.append(template) }
    }

    func delete(_ template: PromptTemplate) async throws {
        queue.sync { templates.removeAll { $0.id == template.id } }
    }

    func render(body: String, variables: [String: String]) -> String {
        var result = body
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    func createVersion(for template: PromptTemplate, body: String, changeDescription: String) async throws {
        queue.sync {
            let newVersion = PromptVersion(
                versionNumber: template.version + 1,
                body: body,
                changeDescription: changeDescription
            )
            newVersion.template = template
            template.versions.append(newVersion)
            template.version += 1
            template.body = body
            template.updatedAt = .now
        }
    }
}
