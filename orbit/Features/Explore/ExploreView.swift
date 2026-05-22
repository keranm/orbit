import SwiftUI

struct ExploreView: View {
    @Environment(AppState.self) private var appState

    private var viewModel: ExploreViewModel { appState.exploreViewModel }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()
            HSplitView {
                fileExplorer
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
                previewPanel
                    .frame(minWidth: 320)
                aiAssistantPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.oBackground)
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(spacing: OSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Explore")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Browse, preview, and ask about your files.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button { viewModel.openFolder() } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "folder").font(.system(size: 12))
                    Text(viewModel.rootURL == nil ? "Open Folder" : "Change Folder")
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
                        Text("No files found")
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
    private func treeView(items: [ExploreTreeItem]) -> some View {
        ForEach(items) { item in
            if item.isFolder {
                folderRow(item)
            } else {
                fileRow(item)
            }
        }
    }

    private func folderRow(_ item: ExploreTreeItem) -> some View {
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

    private func fileRow(_ item: ExploreTreeItem) -> some View {
        let selected = viewModel.selectedFileURL == item.url
        let isText = isTextFile(item.url)
        return HStack(spacing: OSpacing.xs) {
            Image(systemName: isText ? "doc.text" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.oAccent : Color.oTextTertiary)
            Text(item.name)
                .font(.oCaption)
                .foregroundStyle(selected ? Color.oAccent : Color.oTextPrimary)
                .lineLimit(1)
            Spacer()
            if !isText {
                Image(systemName: "eye")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.oTextTertiary.opacity(0.5))
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, OSpacing.sm + CGFloat(item.depth) * 12)
        .padding(.trailing, OSpacing.sm)
        .background(selected ? Color.oSidebarSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectFile(item.url)
        }
    }

    // MARK: - Preview Panel

    @ViewBuilder
    private var previewPanel: some View {
        if let url = viewModel.selectedFileURL {
            if viewModel.isLoading {
                loadingEditor
            } else if let error = viewModel.errorMessage {
                errorEditor(error)
            } else if viewModel.isQuickLookFile {
                quickLookPreview(url: url)
            } else {
                textEditor
            }
        } else {
            emptyEditor
        }
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

    private func quickLookPreview(url: URL) -> some View {
        QuickLookPreview(fileURL: url)
            .background(Color.oSurface)
    }

    private var textEditor: some View {
        VStack(spacing: 0) {
            editorTabBar
            Divider()
            ExploreTextView(
                text: Binding(get: { viewModel.fileContent }, set: { viewModel.fileContent = $0 }),
                selectedText: Binding(get: { viewModel.selectedText }, set: { viewModel.selectedText = $0 }),
                fileURL: viewModel.selectedFileURL,
                onSave: { viewModel.saveFile() }
            )
            .background(Color.oSurface)
            Divider()
            editorStatusBar
        }
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
        VStack(alignment: .leading, spacing: 2) {
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
            Text("Ask about your files")
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
            TextField("Ask about your files…", text: Binding(get: { viewModel.assistantInput }, set: { viewModel.assistantInput = $0 }))
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

// MARK: - Text Editor View

struct ExploreTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    let fileURL: URL?
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ExploreNSTextView()
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

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ExploreNSTextView else { return }

        context.coordinator.currentLanguage = SyntaxLanguage.from(fileURL)

        if textView.string != text {
            textView.string = text
            if let ts = textView.textStorage {
                SyntaxHighlighter.apply(to: ts, language: context.coordinator.currentLanguage)
            }
        }
        textView.onSave = onSave
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExploreTextView
        weak var textView: ExploreNSTextView?
        var currentLanguage: SyntaxLanguage = .unknown

        init(_ parent: ExploreTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
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
    }
}

// MARK: - NSTextView subclass

final class ExploreNSTextView: NSTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
