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
        let streamingCursor = message.isStreaming ? "▍" : ""

        return VStack(alignment: .leading, spacing: OSpacing.xs) {
            // Reasoning block (only when showReasoning = true and reasoning exists)
            if showReasoning && parsed.hasReasoning {
                ReasoningView(
                    reasoning: parsed.reasoning,
                    isInProgress: parsed.isReasoningInProgress && message.isStreaming
                )
            }

            // Visible response
            Group {
                if message.isStreaming && parsed.visible.isEmpty {
                    if parsed.isReasoningInProgress {
                        // Inside a think block — show calm indicator
                        thinkingIndicator
                    } else {
                        thinkingIndicator
                    }
                } else {
                    Text(parsed.visible + streamingCursor)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                        // textSelection uses visible content only — reasoning excluded from copy
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oSurface)
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .stroke(Color.oDivider, lineWidth: 1)
            )
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
                    Image(systemName: isInProgress ? "brain" : "brain")
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
            // Collapse long reasoning by default
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
