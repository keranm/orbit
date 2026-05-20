import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var showOnboarding: Bool

    init() {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let resetting  = CommandLine.arguments.contains("--reset-onboarding")
        _showOnboarding = State(initialValue: !completed || resetting)
    }

    var body: some View {
        if showOnboarding {
            OnboardingFlowView {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                withAnimation(.easeInOut(duration: 0.35)) {
                    showOnboarding = false
                }
            }
        } else {
            appShell
                .onChange(of: appState.showOnboardingRequest) { _, requested in
                    guard requested else { return }
                    appState.showOnboardingRequest = false
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    withAnimation(.easeInOut(duration: 0.35)) { showOnboarding = true }
                }
        }
    }

    // MARK: - Main app shell

    @ViewBuilder
    private var appShell: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack(alignment: .topTrailing) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Nova only appears on chat screens — not Models or Settings.
                if novaVisible {
                    NovaView(state: runtimeDrivenNovaState, size: 72)
                        .padding(.top, OSpacing.lg)
                        .padding(.trailing, OSpacing.xl)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: novaVisible)
            .background(Color.oBackground)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Nova is an emotional presence for chat and absent from all other screens.
    private var novaVisible: Bool {
        switch appState.route {
        case .newChat, .chat: return true
        case .prompts, .models, .settings: return false
        case .dashboard, .coding, .playground: return false
        }
    }

    /// Maps live runtime status to a Nova companion state.
    private var runtimeDrivenNovaState: NovaState {
        switch appState.runtimeStatus {
        case .ready:              return appState.novaState
        case .starting:           return .thinking
        case .noModelConfigured:  return .alert
        case .notInstalled:       return .alert
        case .stopping, .offline: return .offline
        case .error:              return .error
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.route {
        case .newChat:
            NewChatView()
        case .chat(let id):
            ChatViewLoader(chatID: id)
        case .prompts:
            PromptsView()
        case .models:
            ModelsView()
        case .settings:
            SettingsView()
        case .dashboard:
            ProPlaceholderView(title: "Mesh Dashboard", subtitle: "Mesh inference metrics and system monitoring.")
        case .coding:
            ProPlaceholderView(title: "Code", subtitle: "AI-augmented code editor.")
        case .playground:
            ProPlaceholderView(title: "Playground", subtitle: "Model testing and parameter experimentation.")
        }
    }
}

// MARK: - Placeholder

private struct ProPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.oTextTertiary)

            Text(title)
                .font(.oTitle2)
                .foregroundStyle(Color.oTextPrimary)

            Text(subtitle)
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }
}

#Preview {
    MainWindowView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
}
