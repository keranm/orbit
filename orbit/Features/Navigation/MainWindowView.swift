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
                .sheet(isPresented: Binding(
                    get: { appState.showFeedbackRequest },
                    set: { appState.showFeedbackRequest = $0 }
                )) {
                    FeedbackView().environment(appState)
                }
        }
    }

    // MARK: - Main app shell

    private var appShell: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            contentZStack
                .ignoresSafeArea(edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await appState.runtimeManager.ensureRunning()
        }
    }

    private var contentZStack: some View {
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
        .overlay(alignment: .top) {
            if let msg = appState.runtimeManager.meshFallbackMessage {
                MeshFallbackBanner(message: msg) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.runtimeManager.clearMeshFallbackMessage()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.runtimeManager.clearMeshFallbackMessage()
                        }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: appState.runtimeManager.meshFallbackMessage != nil)
    }

    /// Nova lives inside ChatHistoryPanel for chat screens — no top-right overlay needed there.
    private var novaVisible: Bool {
        switch appState.route {
        case .newChat, .chat: return false
        case .explore, .prompts, .models, .settings: return false
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
        case .explore:
            ExploreView()
        case .prompts:
            PromptsView()
        case .models:
            ModelsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Mesh fallback banner

private struct MeshFallbackBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.oWarningAmber)
            Text(message)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.oTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurface)
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .stroke(Color.oWarningAmber.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, OSpacing.xl)
        .padding(.top, OSpacing.lg)
    }
}

#Preview {
    MainWindowView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
}
