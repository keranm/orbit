import SwiftUI

@MainActor
@Observable
final class ExploreViewModel {
    let chatService: ChatService

    var rootURL: URL?
    var treeItems: [ExploreTreeItem] = []
    var selectedFileURL: URL?
    var fileContent: String = "" {
        didSet { updateSavedContentIfNeeded() }
    }
    var selectedText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    private var savedContent: String = ""
    private var hasLoadedContent = false
    var isModified: Bool { hasLoadedContent && fileContent != savedContent }

    var isQuickLookFile: Bool {
        guard let url = selectedFileURL else { return false }
        return !isTextFile(url)
    }

    private func updateSavedContentIfNeeded() {
        if !hasLoadedContent {
            savedContent = fileContent
        }
    }

    // AI Assistant
    var assistantMessages: [AssistantMessage] = []
    var assistantInput: String = ""
    var assistantIsStreaming: Bool = false

    init(chatService: ChatService? = nil) {
        self.chatService = chatService ?? ChatService()
    }

    // MARK: - Folder

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        rootURL = url
        selectedFileURL = nil
        fileContent = ""
        selectedText = ""
        assistantMessages.removeAll()
        isLoading = true
        errorMessage = nil

        Task {
            let tree = await buildExploreTree(from: url)
            treeItems = tree
            isLoading = false
        }
    }

    // MARK: - File selection

    func selectFile(_ url: URL) {
        selectedFileURL = url
        selectedText = ""
        isLoading = true
        errorMessage = nil
        hasLoadedContent = false

        guard isTextFile(url) else {
            isLoading = false
            return
        }

        Task {
            do {
                let data = try Data(contentsOf: url)
                let content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii)
                    ?? "Unable to read file (not a text file)"
                fileContent = content
                hasLoadedContent = true
            } catch {
                errorMessage = error.localizedDescription
                fileContent = ""
                hasLoadedContent = false
            }
            isLoading = false
        }
    }

    func saveFile() {
        guard let url = selectedFileURL, isModified else { return }
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            savedContent = fileContent
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func toggleFolder(_ item: ExploreTreeItem) {
        item.isExpanded.toggle()
    }

    // MARK: - Assistant

    var canSendAssistantMessage: Bool {
        !assistantInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !assistantIsStreaming
    }

    var contextSummary: String {
        guard rootURL != nil || selectedFileURL != nil else { return "No project context" }
        var parts: [String] = []
        if let root = rootURL { parts.append("Project: \(root.lastPathComponent)") }
        if let file = selectedFileURL { parts.append("File: \(file.lastPathComponent)") }
        if !selectedText.isEmpty {
            let lines = selectedText.components(separatedBy: .newlines).count
            parts.append("Selection: \(lines) lines")
        }
        return parts.joined(separator: " · ")
    }

    func sendAssistantMessage(modelRef: String) {
        let text = assistantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !assistantIsStreaming else { return }

        assistantMessages.append(AssistantMessage(role: "user", content: text))
        assistantInput = ""
        assistantIsStreaming = true

        let projectContext = buildProjectContext()
        let fileContext = buildFileContext()
        let selectionSnippet = selectedText.isEmpty ? "" : "\n\nSelected text from the open file:\n```\n\(selectedText)\n```"

        let systemPrompt = """
You are an AI assistant integrated into Orbit's file explorer. \
You have access to the user's project context and the currently open file. \
Answer concisely and provide helpful information about the code, content, or files the user is viewing.

\(projectContext)\(fileContext)\(selectionSnippet)
"""

        let userMessage = ChatRequestMessage(role: "user", content: text)
        let stream = chatService.streamCompletion(
            messages: [userMessage],
            model: modelRef,
            systemPrompt: systemPrompt,
            temperature: 0.3,
            topP: 0.9,
            maxTokens: 2048,
            frequencyPenalty: 0,
            presencePenalty: 0
        )

        Task {
            var fullContent = ""
            do {
                for try await event in stream {
                    switch event {
                    case .token(let t):
                        fullContent += t
                        if assistantMessages.last?.role == "assistant" {
                            assistantMessages[assistantMessages.count - 1].content = fullContent
                        } else {
                            assistantMessages.append(AssistantMessage(role: "assistant", content: fullContent))
                        }
                    case .done:
                        if assistantMessages.last?.role != "assistant" {
                            assistantMessages.append(AssistantMessage(role: "assistant", content: fullContent))
                        }
                        assistantIsStreaming = false
                    }
                }
            } catch {
                assistantMessages.append(AssistantMessage(role: "assistant", content: "Sorry, I encountered an error: \(error.localizedDescription)"))
                assistantIsStreaming = false
            }
        }
    }

    // MARK: - Context builders

    private func buildProjectContext() -> String {
        guard let rootURL else { return "No project folder open.\n" }
        let fileCount = treeItems.count
        return "Project: \(rootURL.lastPathComponent) (\(fileCount) files)\n"
    }

    private func buildFileContext() -> String {
        guard let url = selectedFileURL, !fileContent.isEmpty else {
            return "No file currently open.\n"
        }
        let name = url.lastPathComponent
        let lines = fileContent.components(separatedBy: .newlines).count
        let preview = fileContent.prefix(300)
        return "Open file: \(name) (\(lines) lines)\n```\n\(preview)\(fileContent.count > 300 ? "\n..." : "")\n```\n"
    }
}

// MARK: - Text file detection

private let textExtensions: Set<String> = [
    "swift", "m", "mm", "h", "hh", "hpp", "c", "cpp", "cc", "cxx",
    "py", "js", "jsx", "ts", "tsx",
    "html", "htm", "css", "scss", "sass", "less",
    "json", "xml", "plist", "yaml", "yml", "toml",
    "md", "txt", "rtf", "markdown",
    "strings", "entitlements", "xcconfig",
    "rb", "php", "rs", "go", "kt", "kts", "java",
    "sh", "bash", "zsh", "fish",
    "cfg", "ini", "conf", "env", "gitignore", "editorconfig",
    "cmake", "gradle", "lock", "sql",
]

private let textFilenames: Set<String> = [
    "Package.swift", "Podfile", "Makefile", "CMakeLists.txt",
    "Dockerfile", "docker-compose.yml", ".gitignore", "README.md",
    "Cartfile", "Mintfile", "Brewfile", "Vagrantfile",
    "Gemfile", "Rakefile", "Procfile",
]

func isTextFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    let name = url.lastPathComponent
    return textExtensions.contains(ext) || textFilenames.contains(name)
}

// MARK: - Tree model

final class ExploreTreeItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isFolder: Bool
    var children: [ExploreTreeItem]
    var isExpanded: Bool
    let depth: Int

    init(url: URL, name: String, isFolder: Bool, children: [ExploreTreeItem] = [], isExpanded: Bool = false, depth: Int = 0) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.children = children
        self.isExpanded = isExpanded
        self.depth = depth
    }
}

// MARK: - Tree builder

private func buildExploreTree(from root: URL) async -> [ExploreTreeItem] {
    let skipDirs: Set<String> = [".git", ".build", ".xcodeproj", "DerivedData", "node_modules", ".opencode", ".swiftpm"]

    func scan(url: URL) async -> [ExploreTreeItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return [] }

        var items: [URL: ExploreTreeItem] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDir = resourceValues?.isDirectory ?? false
            let name = fileURL.lastPathComponent

            if isDir {
                if skipDirs.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let relativePath = Array(fileURL.pathComponents.dropFirst(root.pathComponents.count))
            let comps = Array(relativePath.dropLast())
            var parent: ExploreTreeItem?

            for (i, component) in comps.enumerated() {
                if skipDirs.contains(component) { break }
                let parentURL = root.appendingPathComponent(comps[0...i].joined(separator: "/"))
                if items[parentURL] == nil {
                    let folder = ExploreTreeItem(
                        url: parentURL,
                        name: component,
                        isFolder: true,
                        depth: i
                    )
                    items[parentURL] = folder
                }
                parent = items[parentURL]
            }

            let file = ExploreTreeItem(
                url: fileURL,
                name: name,
                isFolder: false,
                depth: comps.count
            )

            if let parent {
                parent.children.append(file)
            } else {
                items[fileURL] = file
            }
        }

        for folder in items.values where folder.isFolder && folder.depth > 0 {
            let parentURL = folder.url.deletingLastPathComponent()
            if let parent = items[parentURL], parent.isFolder {
                parent.children.append(folder)
            }
        }

        for item in items.values {
            item.children = item.children.sorted { a, b in
                if a.isFolder != b.isFolder { return a.isFolder }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }

        let rootFolders = items.values.filter { $0.isFolder && $0.depth == 0 }.sorted { $0.name < $1.name }
        let rootFiles = items.values.filter { !$0.isFolder && $0.depth == 0 }.sorted { $0.name < $1.name }
        return rootFolders + rootFiles
    }

    return await scan(url: root)
}

// MARK: - Data types

struct AssistantMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
}
