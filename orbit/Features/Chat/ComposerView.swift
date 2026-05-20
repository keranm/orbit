import SwiftUI

/// Text input bar shared by ChatView and NewChatView.
/// Keyboard behaviour:
///   Return       → send (if canSend)
///   Shift+Return → insert line break
struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: OSpacing.sm) {
            TextField("Ask anything…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .lineLimit(1...8)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    // Shift+Return → let the system insert a newline
                    if press.modifiers.contains(.shift) { return .ignored }
                    handleSend()
                    return .handled
                }
                .accessibilityLabel("Message input")

            if isStreaming {
                cancelButton
            } else {
                sendButton
            }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.md)
        .background(Color.oSurface)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.xl))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.xl)
                .stroke(canSend ? Color.oAccentMid : Color.oDivider, lineWidth: 1)
        )
        .onAppear { focused = true }
    }

    // MARK: - Buttons

    private var sendButton: some View {
        Button(action: handleSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(canSend ? Color.oAccent : Color.oTextTertiary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send")
        .accessibilityHint("Send message (Return)")
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.oWarningAmber)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityHint("Stop streaming response")
    }

    // MARK: - Actions

    private func handleSend() {
        guard canSend else { return }
        onSend()
    }
}
