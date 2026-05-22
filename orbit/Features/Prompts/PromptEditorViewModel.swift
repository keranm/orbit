import SwiftUI
import SwiftData

@Observable
@MainActor
final class PromptEditorViewModel {
    let template: PromptTemplate
    private let service: PromptServiceProtocol

    var editedBody: String
    var editedName: String
    var editedDescription: String
    var editedTags: [String]
    var editedNotes: String
    var changeDescription: String = ""
    var hasUnsavedChanges = false

    // Auto-save state
    private(set) var saveStatus: SaveStatus = .saved(nil)
    private var autoSaveTask: Task<Void, Never>?

    // Test panel state
    private(set) var testOutput: String = ""
    private(set) var isTesting = false
    var testTone: Double = 0.7
    var testCreativity: Double = 0.3
    var testConciseness: Double = 0.7
    var testTemperature: Double = 0.7
    var testMaxTokens: Int = 4096

    // Variable substitution
    var variableValues: [String: String] = [:]

    init(template: PromptTemplate, service: PromptServiceProtocol) {
        self.template = template
        self.service = service
        editedBody = template.body
        editedName = template.name
        editedDescription = template.templateDescription
        editedTags = template.tags
        editedNotes = template.notes
        for variable in template.variables {
            variableValues[variable.name] = variable.defaultValue
        }
    }

    var renderedPreview: String {
        service.render(body: editedBody, variables: variableValues)
    }

    var characterCount: Int { editedBody.count }
    var tokenEstimate: Int { editedBody.split(separator: " ").count + editedBody.count / 4 }

    var bodySectionHeaders: [(title: String, range: Range<String.Index>)] {
        var headers: [(String, Range<String.Index>)] = []
        for _ in editedBody.matches(of: try! Regex("^([A-Z_]{2,}:)").dotMatchesNewlines()) {
            // Approximate: just find lines matching ALL_CAPS: pattern
        }
        // Simple line-by-line approach
        let lines = editedBody.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var pos = editedBody.startIndex
        for line in lines {
            let lineStr = String(line)
            if let range = lineStr.range(of: "^[A-Z_]{2,}:", options: .regularExpression) {
                let start = editedBody.index(pos, offsetBy: lineStr.distance(from: lineStr.startIndex, to: range.lowerBound))
                let end = editedBody.index(pos, offsetBy: lineStr.distance(from: lineStr.startIndex, to: range.upperBound))
                headers.append((String(lineStr[range]), start..<end))
            }
            pos = editedBody.index(pos, offsetBy: lineStr.count + 1)
        }
        return headers
    }

    // MARK: - Save

    func save() {
        template.name = editedName
        template.templateDescription = editedDescription
        template.tags = editedTags
        template.body = editedBody
        template.notes = editedNotes
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

    func markDirty() {
        hasUnsavedChanges = true
        saveStatus = .unsaved
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            saveStatus = .saving
            // Persist happens on save call
            save()
            saveStatus = .saved(Date())
        }
    }

    func revert() {
        editedBody = template.body
        editedName = template.name
        editedDescription = template.templateDescription
        editedTags = template.tags
        editedNotes = template.notes
        hasUnsavedChanges = false
        saveStatus = .saved(nil)
    }

    // MARK: - Test

    func runTest(chatService: ChatServiceProtocol, modelRef: String, modelContext: ModelContext) async {
        isTesting = true
        testOutput = ""
        let message = ChatRequestMessage(role: "user", content: renderedPreview)
        let startedAt = Date()
        var fullContent = ""
        var completionTokens = 0
        do {
            for try await event in chatService.streamCompletion(
                messages: [message],
                model: modelRef,
                systemPrompt: "",
                temperature: testTemperature,
                topP: nil,
                maxTokens: testMaxTokens,
                frequencyPenalty: nil,
                presencePenalty: nil
            ) {
                switch event {
                case .token(let text):
                    fullContent += text
                    testOutput = fullContent
                case .done(_, let compTokens):
                    completionTokens = compTokens ?? 0
                }
            }
            let latency = Date().timeIntervalSince(startedAt)
            let record = PromptRunRecord(templateID: template.id)
            record.tokenCount = completionTokens
            record.latency = latency
            record.wasSuccess = true
            modelContext.insert(record)
            template.usageCount += 1
            try? modelContext.save()
        } catch {
            testOutput = "Error: \(error.localizedDescription)"
        }
        isTesting = false
    }

    // MARK: - Snippets

    func insertSnippet(_ text: String) {
        editedBody.append("\n" + text)
        markDirty()
    }
}

// MARK: - Auto-save status

enum SaveStatus: Equatable {
    case saved(Date?)
    case saving
    case unsaved

    var label: String {
        switch self {
        case .saved(let d):
            if let d { return "Saved! \(d.formatted(date: .omitted, time: .shortened))" }
            return "Saved"
        case .saving:  return "Saving…"
        case .unsaved: return "Unsaved changes"
        }
    }
}
