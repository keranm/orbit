import SwiftUI
import SwiftData

// New Chat home screen.
// Stage 4: live composer, SwiftData persistence, routing to ChatView on send.
struct NewChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Chat.updatedAt, order: .reverse) private var allChats: [Chat]

    @State private var composerText = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            chatHomeContent

            if !allChats.isEmpty {
                Divider()
                ChatHistoryPanel()
            }
        }
    }

    // MARK: - Chat home (always shown, composer disabled when runtime isn't ready)

    private var chatHomeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Greeting
            VStack(spacing: OSpacing.xs) {
                Text(greeting)
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)

                Text("How can I help you today?")
                    .font(.oBodyLarge)
                    .foregroundStyle(Color.oTextSecondary)
            }
            .padding(.bottom, OSpacing.xl)

            // Live composer
            ComposerView(
                text: $composerText,
                isStreaming: false,
                canSend: canSendNewChat,
                onSend: startNewChat,
                onCancel: {}
            )
            .padding(.horizontal, OSpacing.xxxl)
            .padding(.bottom, OSpacing.lg)

            // Quick-action cards
            quickActionGrid
                .padding(.horizontal, OSpacing.xxxl)

            Spacer()

            // Model + context footer
            modelContextBar
                .padding(.horizontal, OSpacing.xxxl)
                .padding(.bottom, OSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }

    private var canSendNewChat: Bool {
        let s = appState.runtimeStatus
        guard s == .ready || s == .starting else { return false }
        return !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startNewChat() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""

        appState.novaState = .listening

        // Use the live model ref if available; ChatViewModel will resolve it once
        // the runtime finishes starting if it's still nil at this point.
        let chat = Chat(modelRef: appState.activeModelRef ?? "")
        let capped = String(text.prefix(42))
        chat.title = capped.count < text.count ? "\(capped)…" : capped

        let userMsg = Message(role: "user", content: text)
        chat.messages.append(userMsg)

        modelContext.insert(chat)
        try? modelContext.save()

        appState.route = .chat(id: chat.id)
    }

    // MARK: - Quick-action cards

    private struct QuickAction {
        let icon: String
        let title: String
        let subtitle: String
        let prompt: String
    }

    private let quickActions: [QuickAction] = [
        QuickAction(icon: "doc.text",
                    title: "Write a summary",
                    subtitle: "Summarise anything",
                    prompt: "Please summarise this for me:\n\n"),
        QuickAction(icon: "lightbulb",
                    title: "Explain a concept",
                    subtitle: "Simply, like Feynman",
                    prompt: "Explain this concept simply:\n\n"),
        QuickAction(icon: "sparkles",
                    title: "Generate ideas",
                    subtitle: "Brainstorm a project",
                    prompt: "Help me brainstorm ideas for:\n\n"),
        QuickAction(icon: "chevron.left.slash.chevron.right",
                    title: "Help me code",
                    subtitle: "Debug, review, fix",
                    prompt: "Help me with this code:\n\n"),
    ]

    private var quickActionGrid: some View {
        HStack(spacing: OSpacing.sm) {
            ForEach(quickActions, id: \.title) { action in
                quickActionCard(action)
            }
        }
    }

    private func quickActionCard(_ action: QuickAction) -> some View {
        Button {
            composerText = action.prompt
        } label: {
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Image(systemName: action.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.oAccent)

                Text(action.title)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                    .lineLimit(1)

                Text(action.subtitle)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OSpacing.md)
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .stroke(Color.oDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }

    // MARK: - Model origin badge

    private var modelOriginBadge: some View {
        let origin = appState.runtimeManager.modelOrigin(
            for: appState.activeModelRef ?? ""
        )
        let label: String
        let color: Color
        switch origin {
        case .local:
            label = "Running on this Mac"
            color = Color.oSuccessGreen
        case .privateMesh:
            label = "Running on your mesh"
            color = Color.oMeshTeal
        case .publicMesh:
            label = "Running on shared mesh"
            color = Color.oWarningAmber
        case .unavailable:
            label = "Unavailable"
            color = Color.oTextTertiary
        }
        return HStack(spacing: OSpacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
        }
        .padding(.horizontal, OSpacing.sm)
        .padding(.vertical, OSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ORadius.sm)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ORadius.sm)
                .stroke(Color.oDivider, lineWidth: 1)
        )
    }

    // MARK: - Model / context bar

    private var activeModelName: String {
        let rm = appState.runtimeManager
        if let ref = appState.activeModelRef {
            // Check local installed models first (exact then prefix match for short IDs).
            let installed = rm.installedModels
            if let exact = installed.first(where: { ($0.ref ?? $0.name) == ref }) {
                return exact.displayName
            }
            if let prefix = installed.first(where: { entry in
                let entryRef = entry.ref ?? entry.name
                return entryRef.hasPrefix(ref + "/") || entryRef.hasPrefix(ref + "@")
                    || entryRef.hasPrefix(ref + ":")
            }) {
                return prefix.displayName
            }
            // Check mesh models.
            if let meshModel = rm.meshModels.first(where: { $0.name == ref }) {
                return meshModel.displayName ?? meshModel.shortName
            }
            // Unknown ref — show the last path component as a fallback.
            return ref.components(separatedBy: "/").last ?? ref
        }
        return rm.installedModels.first?.displayName ?? "No model selected"
    }

    private var modelContextBar: some View {
        HStack(spacing: OSpacing.md) {
            // Model picker — real name when available, placeholder otherwise
            Button {
                appState.route = .models
            } label: {
                HStack(spacing: OSpacing.xs) {
                    Text("Model")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)

                    Text(activeModelName)
                        .font(.oCaption)
                        .foregroundStyle(
                            appState.runtimeManager.installedModels.isEmpty
                                ? Color.oTextTertiary
                                : Color.oTextSecondary
                        )
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.oTextTertiary)
                }
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.sm)
                        .fill(Color.oSurface)
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ORadius.sm)
                        .stroke(Color.oDivider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Model origin indicator
            modelOriginBadge

            Spacer()
        }
    }
}

#Preview {
    NewChatView()
        .environment(AppState())
        .frame(width: 860, height: 600)
}
