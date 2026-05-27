import SwiftUI

struct OnboardingFlowView: View {
    var onComplete: (() -> Void)? = nil
    @Environment(AppState.self) private var appState
    @State private var viewModel = OnboardingViewModel()

    // MARK: - Sidebar step model
    // Maps the 7 internal VM steps to 5 visual sidebar landmarks.
    // Sidebar order reflects internal occurrence order so progress is always monotonic.

    enum SidebarStep: Int, CaseIterable, Equatable {
        case welcome = 0
        case howItWorks = 1
        case install = 2
        case chooseModel = 3
        case ready = 4

        var label: String {
            switch self {
            case .welcome:    return "Welcome"
            case .howItWorks: return "How Orbit Works"
            case .install:    return "Requirements Check"
            case .chooseModel: return "Choose First Model"
            case .ready:      return "Ready to Go"
            }
        }

        var number: Int { rawValue + 1 }

        static func from(_ step: OnboardingViewModel.Step) -> SidebarStep {
            switch step {
            case .welcome:                      return .welcome
            case .howItWorks:                   return .howItWorks
            case .systemCheck: return .install
            case .chooseExperience:             return .chooseModel
            case .preparing, .complete:         return .ready
            }
        }
    }

    private var currentSidebarStep: SidebarStep { .from(viewModel.step) }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            onboardingSidebar
            Divider()
            contentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
        .onAppear {
            viewModel.runtimeManager = appState.runtimeManager
            if CommandLine.arguments.contains("--mock-onboarding") {
                viewModel.skipDelays = true
            }
        }
        .onChange(of: viewModel.step, initial: true) { _, step in
            updateNovaState(for: step)
        }
        .onChange(of: viewModel.checksDone)  { _, done in if done { appState.novaState = .idle } }
        .onChange(of: viewModel.prepareDone) { _, done in if done { appState.novaState = .success } }
    }

    // MARK: - Nova state

    private func updateNovaState(for step: OnboardingViewModel.Step) {
        switch step {
        case .welcome, .howItWorks:
            appState.novaState = .idle
        case .systemCheck:
            appState.novaState = viewModel.checksDone ? .idle : .thinking
        case .chooseExperience:
            appState.novaState = viewModel.prepareDone ? .idle : .responding
        case .preparing:
            appState.novaState = viewModel.prepareDone ? .success : .responding
        case .complete:
            appState.novaState = .success
        }
    }

    // MARK: - Left sidebar

    private var onboardingSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic light clearance + logo
            Spacer().frame(height: OSpacing.xxxl)

            logoLockup
                .padding(.horizontal, OSpacing.lg)
                .padding(.bottom, OSpacing.xl)

            // Step list with connecting line
            stepList
                .padding(.horizontal, OSpacing.sm)

            Spacer()
        }
        .frame(width: 196)
        .background(Color.oSurface)
        .accessibilityElement(children: .contain)
    }

    private var logoLockup: some View {
        HStack(spacing: OSpacing.sm) {
            Image("OrbitLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))

            Text("Orbit")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SidebarStep.allCases.enumerated()), id: \.offset) { index, sidebarStep in
                sidebarRow(for: sidebarStep)

                // Connecting line between steps (not after the last)
                if index < SidebarStep.allCases.count - 1 {
                    stepConnector(completedBelow: sidebarStep.rawValue < currentSidebarStep.rawValue)
                }
            }
        }
    }

    private func sidebarRow(for sidebarStep: SidebarStep) -> some View {
        let isCurrent  = currentSidebarStep == sidebarStep
        let isComplete = sidebarStep.rawValue < currentSidebarStep.rawValue

        return HStack(alignment: .center, spacing: OSpacing.sm) {
            // Step indicator circle
            ZStack {
                if isComplete {
                    Circle()
                        .fill(Color.oAccent.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.oAccent)
                } else if isCurrent {
                    Circle()
                        .fill(Color.oAccent)
                        .frame(width: 22, height: 22)
                    Text("\(sidebarStep.number)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(Color.oDivider, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    Text("\(sidebarStep.number)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.oTextTertiary)
                }
            }

            Text(sidebarStep.label)
                .font(isCurrent ? .oBodyMedium : .oBody)
                .foregroundStyle(
                    isCurrent  ? Color.oTextPrimary  :
                    isComplete ? Color.oTextSecondary : Color.oTextTertiary
                )
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, OSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(isCurrent ? Color.oAccentSoft : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: currentSidebarStep)
    }

    /// Thin vertical connector between two step indicators.
    private func stepConnector(completedBelow: Bool) -> some View {
        HStack(spacing: 0) {
            // Align line with centre of the 22pt dots.
            // Row padding-leading = OSpacing.xs (4) + half dot (11) = 15pt from column edge.
            Spacer().frame(width: OSpacing.xs + 11 - 1)
            Rectangle()
                .fill(completedBelow ? Color.oAccent.opacity(0.18) : Color.oDivider.opacity(0.5))
                .frame(width: 1.5, height: OSpacing.md)
            Spacer()
        }
    }

    // MARK: - Right content panel

    private var contentPanel: some View {
        VStack(spacing: 0) {
            // Scrollable step content
            ScrollView {
                stepContent
                    .id(viewModel.step)
                    .transition(contentTransition)
                    .padding(.horizontal, OSpacing.xxxl)
                    .padding(.top, OSpacing.xxxl)
                    .padding(.bottom, OSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            navigationBar
                .padding(.horizontal, OSpacing.xl)
                .padding(.vertical, OSpacing.md)
        }
    }

    // MARK: - Step content router

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:          WelcomeStep(viewModel: viewModel)
        case .howItWorks:       HowItWorksStep(viewModel: viewModel)
        case .systemCheck:      SystemCheckStep(viewModel: viewModel)
        case .chooseExperience: ChooseExperienceStep(viewModel: viewModel)
        case .preparing:        PreparingStep(viewModel: viewModel)
        case .complete:         CompleteStep(viewModel: viewModel, onComplete: completeOnboarding)
        }
    }

    private var contentTransition: AnyTransition {
        if viewModel.direction == .forward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal:   .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if !viewModel.step.isFirst {
                Button("Back") { viewModel.back() }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .accessibilityIdentifier("onboarding_back")
            } else {
                Spacer().frame(width: 40)
            }

            // Inline download progress for the Choose Model step
            if viewModel.step == .chooseExperience, viewModel.downloadState == .inProgress {
                progressBar(for: viewModel.downloadProgress)
            } else {
                Spacer()
            }

            if !viewModel.step.isLast {
                continueButton
            }
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        if viewModel.step == .chooseExperience {
            chooseExperienceButton
        } else {
            defaultContinueButton
        }
    }

    @ViewBuilder
    private var chooseExperienceButton: some View {
        switch viewModel.downloadState {
        case .completed:
            Button(action: { viewModel.advance() }) {
                Text("Continue")
                    .font(.oBodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(Color.oAccent)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding_continue")

        case .inProgress:
            Button(action: {}) {
                Text("Downloading…")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextTertiary)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(Color.oSurfaceSecondary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(true)

        case .failed:
            Button(action: { viewModel.startDownload() }) {
                Text("Retry")
                    .font(.oBodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(Color.oWarningAmber)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding_retry")

        case .idle:
            Button(action: { viewModel.advance() }) {
                Text(viewModel.selectedExistingModel != nil ? "Continue" : "Download Model")
                    .font(.oBodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.pill)
                            .fill(Color.oSuccessGreen)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding_download")
        }
    }

    private var defaultContinueButton: some View {
        Button(action: { viewModel.advance() }) {
            Text(continueLabel)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.lg)
                .padding(.vertical, OSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(continueEnabled ? Color.oAccent : Color.oTextTertiary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!continueEnabled)
        .accessibilityIdentifier("onboarding_continue")
    }

    private func progressBar(for progress: Double) -> AnyView {
        AnyView(ProgressView(value: progress, total: 1.0)
            .progressViewStyle(.linear)
            .tint(Color.oAccent)
            .frame(maxWidth: .infinity, minHeight: 6)
            .padding(.trailing, OSpacing.md))
    }

    private var continueLabel: String {
        switch viewModel.step {
        case .welcome: return "Get started"
        case .complete: return "Start using Orbit"
        default: return "Continue"
        }
    }

    private var continueEnabled: Bool {
        switch viewModel.step {
        case .systemCheck:    return viewModel.checksDone
        case .chooseExperience: return viewModel.downloadState == .completed
        case .preparing:      return viewModel.prepareDone
        default:              return true
        }
    }

    // MARK: - Completion

    private func completeOnboarding() { onComplete?() }
}

#Preview {
    OnboardingFlowView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
}
