import SwiftUI
import SwiftData

struct AgentRunnerView: View {
    let agent: Agent
    let modelRef: String
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var state: RunnerState = .preRun
    @State private var userInput = ""
    @State private var stepStates: [Int: StepRunState] = [:]
    @State private var streamingText = ""
    @State private var runTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            runnerHeader
            Divider()

            switch state {
            case .preRun:
                preRunBody
            case .running:
                runningBody
            case .completed(let output):
                AgentRunResultView(agent: agent, output: output, stepStates: stepStates, onDismiss: onDismiss)
            case .failed(let message, _):
                failedBody(message: message)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Color.oBackground)
        .onDisappear { runTask?.cancel() }
    }

    // MARK: - Header

    private var runnerHeader: some View {
        HStack {
            Image(systemName: agent.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.oAccent)
            Text(agent.name)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
            Spacer()
            Button {
                runTask?.cancel()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.oTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    // MARK: - Pre-run

    private var preRunBody: some View {
        VStack(spacing: OSpacing.lg) {
            agentStepSummary

            if agentNeedsUserInput {
                userInputSection
            }

            Spacer()

            Button { startRun() } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Run agent")
                        .font(.oBodyMedium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OSpacing.sm)
                .background(Color.oAccent)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(OSpacing.lg)
    }

    private var agentStepSummary: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text("Steps")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
            ForEach(agent.sortedSteps, id: \.id) { step in
                HStack(spacing: OSpacing.sm) {
                    Image(systemName: step.stepType.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.oTextTertiary)
                        .frame(width: 16)
                    Text(step.label)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OSpacing.md)
        .background(Color.oSurface)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
        .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
    }

    private var userInputSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text("Your input")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
            TextEditor(text: $userInput)
                .font(.oBody)
                .frame(minHeight: 80, maxHeight: 140)
                .padding(OSpacing.xs)
                .background(Color.oSurface)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
            Text("This agent uses {user_input} — paste the text you want it to process.")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    // MARK: - Running

    private var runningBody: some View {
        VStack(spacing: 0) {
            stepProgressList
            Divider()
            streamingArea
        }
    }

    private var stepProgressList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                ForEach(agent.sortedSteps, id: \.id) { step in
                    stepRow(step: step)
                }
            }
            .padding(OSpacing.md)
        }
        .frame(maxHeight: 220)
    }

    private func stepRow(step: AgentStep) -> some View {
        let runState = stepStates[step.order] ?? .pending
        return HStack(spacing: OSpacing.sm) {
            stepIcon(for: runState)
                .frame(width: 20)

            Text(step.label)
                .font(.oCaption)
                .foregroundStyle(runState == .pending ? Color.oTextTertiary : Color.oTextPrimary)

            Spacer()

            if case .completed(let dur) = runState {
                Text(String(format: "%.1fs", dur))
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func stepIcon(for state: StepRunState) -> some View {
        switch state {
        case .pending:
            Circle()
                .fill(Color.oDivider)
                .frame(width: 8, height: 8)
                .frame(width: 20)
        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.oSuccessGreen)
        case .skipped:
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 14))
                .foregroundStyle(Color.oTextTertiary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.oErrorRed)
        }
    }

    private var streamingArea: some View {
        ScrollView {
            Text(streamingText.isEmpty ? " " : streamingText)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OSpacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Failed

    private func failedBody(message: String) -> some View {
        VStack(spacing: OSpacing.lg) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.oErrorRed)

            VStack(spacing: OSpacing.xs) {
                Text("Something went wrong")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text(message)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Close", action: onDismiss)
                .buttonStyle(.bordered)
                .tint(Color.oAccent)
        }
        .padding(OSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Run execution

    private func startRun() {
        state = .running
        stepStates = Dictionary(uniqueKeysWithValues: agent.sortedSteps.map { ($0.order, .pending) })
        streamingText = ""
        appState.novaState = .thinking

        runTask = Task {
            var startTimes: [Int: Date] = [:]
            let service = SDKChatService(appState.runtimeManager)
            do {
                for try await event in AgentExecutionService.run(
                    agent: agent,
                    userInput: userInput,
                    modelRef: modelRef,
                    modelContext: modelContext,
                    service: service
                ) {
                    await MainActor.run {
                        switch event {
                        case .stepStarted(let order, _):
                            stepStates[order] = .running
                            startTimes[order] = Date()
                            streamingText = ""

                        case .stepCompleted(let order, _):
                            let duration = startTimes[order].map { Date().timeIntervalSince($0) } ?? 0
                            stepStates[order] = .completed(duration)

                        case .stepSkipped(let order):
                            stepStates[order] = .skipped

                        case .llmToken(let token):
                            streamingText += token

                        case .done(let output):
                            state = .completed(output)
                            appState.novaState = .success
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                await MainActor.run { appState.novaState = .idle }
                            }

                        case .failed(let msg, let order):
                            if let o = order { stepStates[o] = .failed(msg) }
                            state = .failed(msg, order)
                            appState.novaState = .error
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    state = .failed(error.localizedDescription, nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private var agentNeedsUserInput: Bool {
        agent.steps.contains { step in
            guard step.stepType == .think,
                  let cfg = step.decodedConfig(ThinkStepConfig.self) else { return false }
            return cfg.userPromptTemplate.contains("{user_input}") || cfg.systemPrompt.contains("{user_input}")
        }
    }
}

// MARK: - Step run state

enum StepRunState: Equatable {
    case pending
    case running
    case completed(TimeInterval)
    case skipped
    case failed(String)
}

// MARK: - Runner state

enum RunnerState {
    case preRun
    case running
    case completed(String)
    case failed(String, Int?)
}
