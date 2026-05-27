import SwiftUI

struct MessageBubble: View {
    let message: Message

    /// Controlled by Settings > General — injected from AppStorage.
    @AppStorage("showModelReasoning") private var showReasoning = false

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: OSpacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: OSpacing.xxs) {
                bubbleContent
                    .fixedSize(horizontal: false, vertical: true)

                if message.isInterrupted {
                    Text("Response interrupted")
                        .font(.oMicro)
                        .foregroundStyle(Color.oWarningAmber)
                        .padding(.horizontal, OSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: OSpacing.xxl) }
        }
    }

    // MARK: - Bubble

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.oBody)
            .foregroundStyle(Color.oTextInverse)
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oAccent)
            )
            .textSelection(.enabled)
    }

    private var assistantBubble: some View {
        let parsed = ReasoningParser.parse(message.content)

        return VStack(alignment: .leading, spacing: OSpacing.xs) {
            // Reasoning block (only when showReasoning = true and reasoning exists)
            if showReasoning && parsed.hasReasoning {
                ReasoningView(
                    reasoning: parsed.reasoning,
                    isInProgress: parsed.isReasoningInProgress && message.isStreaming
                )
            }

            // Content bubble
            VStack(alignment: .leading, spacing: 0) {
                if message.isStreaming && parsed.visible.isEmpty {
                    thinkingIndicator
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.sm)
                } else if message.isStreaming {
                    StreamingBubbleText(content: parsed.visible)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.sm)
                } else {
                    // Full Markdown + code block rendering once complete
                    MarkdownContentView(content: parsed.visible)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oSurface)
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .stroke(Color.oDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: OSpacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                ThinkingDot(delay: Double(i) * 0.18)
            }
        }
        .padding(.vertical, OSpacing.xs)
    }
}

// MARK: - Streaming text with per-token fade-in

/// Renders streaming text with a subtle fade-in on each incoming token.
/// Keeps confirmed content stable while animating only the newly arrived chunk.
/// Gives slow mesh tokens a smooth reveal instead of a jarring pop.
private struct StreamingBubbleText: View {
    let content: String

    @State private var shownContent = ""
    @State private var newChunk = ""
    @State private var chunkOpacity: Double = 1.0

    var body: some View {
        (Text(shownContent).foregroundStyle(Color.oTextPrimary) +
         Text(newChunk + "▍").foregroundStyle(Color.oTextPrimary.opacity(chunkOpacity)))
            .font(.oBody)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: content) { _, new in
                let totalShown = shownContent + newChunk
                let delta: String
                if new.hasPrefix(totalShown) {
                    delta = String(new.dropFirst(totalShown.count))
                } else if new.hasPrefix(shownContent) {
                    delta = String(new.dropFirst(shownContent.count))
                } else {
                    delta = new
                }
                shownContent = totalShown
                newChunk = delta
                chunkOpacity = 0.0
                withAnimation(.easeIn(duration: 0.18)) { chunkOpacity = 1.0 }
            }
            .onAppear { shownContent = content }
    }
}

// MARK: - Markdown content

/// Renders a completed assistant message with inline Markdown formatting and code blocks.
private struct MarkdownContentView: View {
    let content: String

    private var segments: [MarkdownSegment] { parseMarkdownSegments(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    inlineMarkdown(text)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.xs)
                case .code(let language, let codeContent):
                    CodeBlockView(language: language, content: codeContent)
                        .padding(.horizontal, OSpacing.sm)
                        .padding(.vertical, OSpacing.xs)
                }
            }
        }
        .padding(.vertical, OSpacing.xs)
    }

    @ViewBuilder
    private func inlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let language: String?
    let content: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: OSpacing.xs) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.oMicroMed)
                        .foregroundStyle(Color.oTextTertiary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copied ? "Copied" : "Copy")
                            .font(.oMicroMed)
                    }
                    .foregroundStyle(copied ? Color.oSuccessGreen : Color.oTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(Color.oBackground)

            Divider()
                .overlay(Color.oDivider)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.trimmingCharacters(in: CharacterSet(charactersIn: "\n")))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.oTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OSpacing.sm)
            }
            .background(Color.oSurfaceSecondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.md)
                .stroke(Color.oDivider, lineWidth: 1)
        )
    }
}

// MARK: - Markdown segment parser

private enum MarkdownSegment {
    case text(String)
    case code(language: String?, content: String)
}

private func parseMarkdownSegments(_ input: String) -> [MarkdownSegment] {
    var segments: [MarkdownSegment] = []
    var remaining = input

    while !remaining.isEmpty {
        guard let fenceRange = remaining.range(of: "```") else {
            segments.append(.text(remaining))
            break
        }

        // Text before the opening fence
        let before = String(remaining[..<fenceRange.lowerBound])
        if !before.isEmpty { segments.append(.text(before)) }
        remaining = String(remaining[fenceRange.upperBound...])

        // Optional language identifier on the same line as the opening fence
        let language: String?
        if let newlineIdx = remaining.firstIndex(of: "\n") {
            let lang = String(remaining[..<newlineIdx]).trimmingCharacters(in: .whitespaces)
            language = lang.isEmpty ? nil : lang
            remaining = String(remaining[remaining.index(after: newlineIdx)...])
        } else {
            language = nil
        }

        // Content up to closing fence (or rest of string if unclosed)
        if let closingRange = remaining.range(of: "```") {
            let code = String(remaining[..<closingRange.lowerBound])
            segments.append(.code(language: language, content: code))
            remaining = String(remaining[closingRange.upperBound...])
            if remaining.hasPrefix("\n") { remaining = String(remaining.dropFirst()) }
        } else {
            segments.append(.code(language: language, content: remaining))
            remaining = ""
        }
    }

    // Drop empty text segments that are just whitespace between blocks
    return segments.filter {
        if case .text(let s) = $0 { return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }
}

// MARK: - Reasoning view

private struct ReasoningView: View {
    let reasoning: String
    let isInProgress: Bool

    @State private var isExpanded = false

    private var isLong: Bool { reasoning.count > 200 }
    private var displayText: String {
        if !isExpanded && isLong {
            return String(reasoning.prefix(200)) + "…"
        }
        return reasoning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.oTextTertiary)
                        .symbolEffect(.pulse, isActive: isInProgress)
                    Text(isInProgress ? "Thinking…" : "Reasoning")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                    if isLong {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content
            Text(displayText)
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, OSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurfaceSecondary)
        )
        .onAppear {
            isExpanded = !isLong
        }
    }
}

// MARK: - Thinking dot

private struct ThinkingDot: View {
    let delay: Double
    @State private var scale: CGFloat = 0.6

    var body: some View {
        Circle()
            .fill(Color.oTextTertiary)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    scale = 1.0
                }
            }
    }
}
