import SwiftUI
import SwiftData

// New Chat home screen.
// Stage 4: live composer, SwiftData persistence, routing to ChatView on send.
struct NewChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

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
        switch appState.runtimeStatus {
        case .notInstalled:
            runtimeState(
                icon: "arrow.down.circle",
                iconColor: Color.oWarningAmber,
                headline: "Orbit isn't set up yet",
                body: "The AI runtime needs to be installed before you can start a conversation.",
                primaryLabel: "Set up Orbit",
                primaryAction: {
                    appState.showOnboardingRequest = true
                }
            )
        case .noModelConfigured:
            runtimeState(
                icon: "sparkles",
                iconColor: Color.oAccent,
                headline: "No model selected",
                body: "Choose a model to start chatting with your AI.",
                primaryLabel: "Browse Models",
                primaryAction: { appState.route = .models }
            )
        case .offline:
            runtimeState(
                icon: "pause.circle",
                iconColor: Color.oWarningAmber,
                headline: "AI is paused",
                body: "Your AI runtime isn't running. Start it to continue chatting.",
                primaryLabel: "Start",
                primaryAction: { Task { await appState.runtimeManager.start() } }
            )
        case .error:
            runtimeState(
                icon: "exclamationmark.triangle",
                iconColor: Color.oWarningAmber,
                headline: "Orbit couldn't start",
                body: "Something went wrong when starting your AI. This is unusual and can usually be fixed quickly.",
                primaryLabel: "Try Again",
                primaryAction: { Task { await appState.runtimeManager.start() } }
            )
        case .ready where appState.activeModelRef == nil:
            // Runtime is up but we don't have a model identifier — guide to Models.
            runtimeState(
                icon: "cpu",
                iconColor: Color.oAccent,
                headline: "No model active",
                body: "The AI is running but no model is selected. Choose one to start chatting.",
                primaryLabel: "Choose a Model",
                primaryAction: { appState.route = .models }
            )
        default:
            // .ready (with model), .starting, .stopping — show chat home
            chatHomeContent
        }
    }

    // MARK: - Shared runtime state layout

    private func runtimeState(
        icon: String,
        iconColor: Color,
        headline: String,
        body bodyText: String,
        primaryLabel: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: OSpacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(spacing: OSpacing.xs) {
                Text(headline)
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                Text(bodyText)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(primaryLabel, action: primaryAction)
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.lg)
                .padding(.vertical, OSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(Color.oAccent)
                )
            Spacer()
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }

    // MARK: - Normal chat home (runtime ready or starting)

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
        appState.runtimeStatus == .ready
        && appState.activeModelRef != nil
        && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startNewChat() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let modelRef = appState.activeModelRef else { return }
        composerText = ""

        appState.novaState = .listening

        let chat = Chat(modelRef: modelRef)
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
        let installed = appState.runtimeManager.installedModels
        if let ref = appState.activeModelRef {
            // The live API returns a short model ID (e.g. "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF")
            // while installed entries use full path refs ("Qwen/…/file.gguf") or name:stem format.
            // Match exactly first, then fall back to prefix matching for the short-ID case.
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
        }
        return installed.first?.displayName ?? "No model selected"
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
