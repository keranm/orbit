import SwiftUI
import SwiftData

struct ProCodeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var prompts: [PromptTemplate] = []

    private var viewModel: CodeViewModel { appState.codeViewModel }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()
            HSplitView {
                fileExplorer
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
                codeEditor
                    .frame(minWidth: 320)
                aiAssistantPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ProStatusBar()
        }
        .background(Color.oBackground)
        .task {
            try? await appState.runtimeManager.fetchInstalledModels()
            let descriptor = FetchDescriptor<PromptTemplate>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            prompts = (try? modelContext.fetch(descriptor)) ?? []
            consumePendingPrompt()
        }
    }

    private func consumePendingPrompt() {
        guard let prompt = appState.pendingPromptForCode else { return }
        appState.pendingPromptForCode = nil
        viewModel.assistantInput = prompt
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(spacing: OSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Code")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Build and iterate with AI on your side.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button { viewModel.openFolder() } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "folder").font(.system(size: 12))
                    Text(viewModel.rootURL == nil ? "Open Project" : "Change Project")
                        .font(.oBodyMedium)
                }
                .foregroundStyle(Color.oTextPrimary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    // MARK: - File Explorer

    private var fileExplorer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FILES")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                if viewModel.rootURL != nil {
                    Button { viewModel.openFolder() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)

            Divider()

            if viewModel.rootURL == nil {
                emptyExplorer
            } else if viewModel.treeItems.isEmpty {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: OSpacing.sm) {
                        Spacer()
                        Text("No text files found")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        treeView(items: viewModel.treeItems)
                    }
                    .padding(.vertical, OSpacing.xs)
                }
            }
        }
        .background(Color.oSurface)
    }

    private var emptyExplorer: some View {
        VStack(spacing: OSpacing.sm) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 24))
                .foregroundStyle(Color.oTextTertiary)
            Text("No folder opened")
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
            Button("Open Folder") { viewModel.openFolder() }
                .buttonStyle(.plain)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func treeView(items: [CodeTreeItem]) -> some View {
        ForEach(items) { item in
            if item.isFolder {
                folderRow(item)
            } else {
                fileRow(item)
            }
        }
    }

    private func folderRow(_ item: CodeTreeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.oTextTertiary)
                Image(systemName: item.isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextTertiary)
                Text(item.name)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, OSpacing.sm + CGFloat(item.depth) * 12)
            .padding(.trailing, OSpacing.sm)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.toggleFolder(item) }

            if item.isExpanded {
                            AnyView(treeView(items: item.children))
        }
    }
}

// MARK: - Model Picker

private struct ModelPickerView: View {
    let models: [InstalledModelEntry]
    let activeRef: String?
    let onSelect: (String) -> Void

    private var label: String {
        guard let ref = activeRef else { return "No model" }
        if let match = models.first(where: { ($0.ref ?? $0.name) == ref }) {
            return match.displayName
        }
        return ref
    }

    var body: some View {
        Menu {
            if models.isEmpty {
                Text("No models installed")
                    .font(.oCaption)
            } else {
                Section("Installed Models") {
                    ForEach(0..<models.count, id: \.self) { i in
                        let model = models[i]
                        let ref = model.ref ?? model.name
                        Button {
                            onSelect(ref)
                        } label: {
                            HStack {
                                Text(model.displayName)
                                if ref == activeRef ?? "" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Text(label)
                .font(.oCaption).foregroundStyle(Color.oTextSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

    private func fileRow(_ item: CodeTreeItem) -> some View {
        let selected = viewModel.selectedFileURL == item.url
        return HStack(spacing: OSpacing.xs) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(item.canEdit ? (selected ? Color.oAccent : Color.oTextTertiary) : Color.oTextTertiary.opacity(0.5))
            Text(item.name)
                .font(.oCaption)
                .foregroundStyle(item.canEdit ? (selected ? Color.oAccent : Color.oTextPrimary) : Color.oTextTertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.leading, OSpacing.sm + CGFloat(item.depth) * 12)
        .padding(.trailing, OSpacing.sm)
        .background(selected && item.canEdit ? Color.oSidebarSelected : Color.clear)
        .contentShape(Rectangle())
        .opacity(item.canEdit ? 1 : 0.5)
        .onTapGesture {
            guard item.canEdit else { return }
            viewModel.selectFile(item.url)
        }
    }

    // MARK: - Code Editor

    private var codeEditor: some View {
        VStack(spacing: 0) {
            editorTabBar
            Divider()
            if viewModel.selectedFileURL == nil {
                emptyEditor
            } else if viewModel.isLoading {
                loadingEditor
            } else if let error = viewModel.errorMessage {
                errorEditor(error)
            } else {
                CodeEditorView(
                    text: Binding(get: { viewModel.fileContent }, set: { viewModel.fileContent = $0 }),
                    selectedText: Binding(get: { viewModel.selectedText }, set: { viewModel.selectedText = $0 }),
                    fileURL: viewModel.selectedFileURL,
                    onSave: { viewModel.saveFile() }
                )
                .background(Color.oSurface)
                Divider()
                editorStatusBar
            }
        }
        .background(Color.oSurface)
    }

    private var emptyEditor: some View {
        VStack(spacing: OSpacing.sm) {
            Spacer()
            Image(systemName: "text.alignleft")
                .font(.system(size: 32))
                .foregroundStyle(Color.oTextTertiary)
            Text("Select a file to preview")
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.oSurface)
    }

    private var loadingEditor: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.oSurface)
    }

    private func errorEditor(_ error: String) -> some View {
        VStack(spacing: OSpacing.sm) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Color.oWarningAmber)
            Text(error)
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.oSurface)
    }

    private var editorTabBar: some View {
        HStack(spacing: 0) {
            if let url = viewModel.selectedFileURL {
                editorTab(url.lastPathComponent, modified: viewModel.isModified, active: true)
            }
            Spacer()
        }
        .frame(height: 28)
        .background(Color.oBackground)
    }

    private func editorTab(_ name: String, modified: Bool = false, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.oCaption)
                .foregroundStyle(active ? Color.oTextPrimary : Color.oTextSecondary)
            if modified {
                Circle().fill(Color.oWarningAmber).frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, 6)
        .background(active ? Color.oSurface : Color.clear)
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Color.oAccent).frame(height: 1.5) }
        }
    }

    private var editorStatusBar: some View {
        HStack(spacing: OSpacing.md) {
            let lines = viewModel.fileContent.components(separatedBy: .newlines).count
            Text("\(lines) lines")
            Text(fileExtension)
            Spacer()
            if !viewModel.selectedText.isEmpty {
                Text("\(viewModel.selectedText.components(separatedBy: .newlines).count) lines selected")
                    .foregroundStyle(Color.oAccent)
            }
            HStack(spacing: 3) {
                Circle().fill(Color.oSuccessGreen).frame(width: 5, height: 5)
                Text("Read-only")
            }
        }
        .font(.oMicro)
        .foregroundStyle(Color.oTextTertiary)
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, 4)
        .background(Color.oBackground)
    }

    private var fileExtension: String {
        guard let url = viewModel.selectedFileURL else { return "" }
        return url.pathExtension.uppercased()
    }

    // MARK: - AI Assistant

    private var modelRef: String { appState.runtimeManager.activeModelRef ?? "" }

    private var modelPicker: some View {
        let models = appState.runtimeManager.installedModels
        let activeRef = appState.runtimeManager.activeModelRef
        return HStack(spacing: OSpacing.xs) {
            Image(systemName: "cpu").font(.system(size: 11)).foregroundStyle(Color.oTextTertiary)
            ModelPickerView(
                models: models,
                activeRef: activeRef,
                onSelect: { appState.runtimeManager.switchActiveModel(to: $0) }
            )
        }
    }

    private func send() {
        guard !modelRef.isEmpty else {
            viewModel.assistantMessages.append(AssistantMessage(
                role: "assistant",
                content: "No model is configured. Go to Models to select one first."
            ))
            return
        }
        viewModel.sendAssistantMessage(modelRef: modelRef)
    }

    private var aiAssistantPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Assistant")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Spacer()
                modelPicker
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(Color.oSurface)

            contextPanel

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.md) {
                    if viewModel.assistantMessages.isEmpty {
                        emptyAssistant
                    } else {
                        ForEach(viewModel.assistantMessages) { msg in
                            assistantBubble(msg)
                        }
                        if viewModel.assistantIsStreaming {
                            streamingIndicator
                        }
                    }
                }
                .padding(OSpacing.sm)
            }

            Divider()
            assistantComposer
        }
        .background(Color.oSurface)
    }

    private var contextPanel: some View {
        HStack(spacing: OSpacing.xs) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.oTextTertiary)
            Text(viewModel.contextSummary)
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.xs)
        .background(Color.oSurfaceSecondary)
    }

    private var emptyAssistant: some View {
        VStack(spacing: OSpacing.sm) {
            Spacer().frame(height: 32)
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.oTextTertiary)
            Text("Ask about your code")
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
            if modelRef.isEmpty {
                Text("No model configured — select one in Models")
                    .font(.oCaption)
                    .foregroundStyle(Color.oWarningAmber)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func assistantBubble(_ msg: AssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text(msg.role.uppercased())
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
            Text(msg.content)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .textSelection(.enabled)
        }
        .padding(OSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(msg.role == "user" ? RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccentSoft) : nil)
    }

    private var streamingIndicator: some View {
        HStack(spacing: OSpacing.xs) {
            ProgressView().scaleEffect(0.5)
            Text("Thinking...")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .padding(.leading, OSpacing.sm)
    }

    private var assistantComposer: some View {
        HStack(spacing: OSpacing.sm) {
            Menu {
                if prompts.isEmpty {
                    Text("No prompts available")
                        .font(.oCaption)
                } else {
                    ForEach(prompts) { template in
                        Button {
                            viewModel.assistantInput = template.body
                        } label: {
                            VStack(alignment: .leading) {
                                Text(template.name)
                                Text(template.templateDescription)
                                    .font(.oCaption)
                                    .foregroundStyle(Color.oTextTertiary)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "doc.text").font(.system(size: 13)).foregroundStyle(Color.oTextTertiary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Inject a prompt")

            TextField("Ask about your code…", text: Binding(get: { viewModel.assistantInput }, set: { viewModel.assistantInput = $0 }))
                .textFieldStyle(.plain)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .onSubmit { send() }
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(viewModel.canSendAssistantMessage && !modelRef.isEmpty ? Color.oAccent : Color.oTextTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSendAssistantMessage || modelRef.isEmpty)
        }
        .padding(OSpacing.sm)
        .background(Color.oSurface)
    }
}

// MARK: - Code Editor View

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    let fileURL: URL?
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditableTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.allowsUndo = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.onSave = onSave

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditableTextView else { return }

        context.coordinator.currentLanguage = SyntaxLanguage.from(fileURL)

        if textView.string != text {
            textView.string = text
            if let ts = textView.textStorage {
                SyntaxHighlighter.apply(to: ts, language: context.coordinator.currentLanguage)
            }
            context.coordinator.rulerView?.needsDisplay = true
        }

        textView.onSave = onSave
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: EditableTextView?
        weak var rulerView: LineNumberRulerView?
        var currentLanguage: SyntaxLanguage = .unknown

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            rulerView?.needsDisplay = true
            if let ts = tv.textStorage {
                SyntaxHighlighter.apply(to: ts, language: currentLanguage)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            if range.length > 0 {
                parent.selectedText = (tv.string as NSString).substring(with: range)
            } else {
                parent.selectedText = ""
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }
            if replacement == "\n" {
                let string = textView.string as NSString
                let lineRange = string.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                let currentLine = string.substring(with: lineRange)
                let indent = String(currentLine.prefix { $0 == " " || $0 == "\t" })
                textView.insertText("\n" + indent, replacementRange: affectedCharRange)
                return false
            }
            if replacement == "\t" {
                textView.insertText("    ", replacementRange: affectedCharRange)
                return false
            }
            return true
        }
    }
}

// MARK: - Editable Text View

final class EditableTextView: NSTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Line Number Ruler

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }

        let visible = textView.enclosingScrollView?.documentVisibleRect ?? rect
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)

        var lineNumber = 1
        let string = textView.string as NSString
        let charRangeBefore = layout.characterRange(forGlyphRange: NSRange(location: 0, length: glyphRange.location), actualGlyphRange: nil)
        if charRangeBefore.length > 0 {
            let before = string.substring(with: charRangeBefore)
            lineNumber += before.filter { $0 == "\n" }.count
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        var glyphIndex = glyphRange.location
        let endGlyph = NSMaxRange(glyphRange)
        let totalGlyphs = layout.numberOfGlyphs

        while glyphIndex < endGlyph && glyphIndex < totalGlyphs {
            var lineRange = NSRange(location: NSNotFound, length: 0)
            let glyphRect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

            let label = "\(lineNumber)"
            let size = label.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 8
            let y = glyphRect.origin.y + (glyphRect.height - size.height) / 2
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            glyphIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}


