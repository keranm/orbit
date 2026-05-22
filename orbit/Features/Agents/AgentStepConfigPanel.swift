import SwiftUI

struct AgentStepConfigPanel: View {
    let step: AgentStep
    let previousSteps: [AgentStep]
    let onChanged: () -> Void

    @State private var stepLabel = ""

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            configContent
        }
        .background(Color.oSurface)
        .onAppear { stepLabel = step.label }
        .onChange(of: step.id) { _, _ in stepLabel = step.label }
    }

    // MARK: - Step header

    private var stepHeader: some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: step.stepType.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                TextField("Step name", text: $stepLabel)
                    .textFieldStyle(.plain)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                    .onSubmit { commitLabel() }
                    .onChange(of: stepLabel) { old, new in
                        if new.isEmpty { stepLabel = old }
                    }
                Text(step.stepType.label)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }

            Spacer()
        }
        .padding(OSpacing.md)
    }

    // MARK: - Config content router

    @ViewBuilder
    private var configContent: some View {
        switch step.stepType {
        case .readMail:
            MailStepConfigView(step: step, onChanged: onChanged)
        case .readCalendar:
            CalendarStepConfigView(step: step, onChanged: onChanged)
        case .readReminders:
            RemindersStepConfigView(step: step, onChanged: onChanged)
        case .readFiles:
            FilesStepConfigView(step: step, onChanged: onChanged)
        case .readRSS:
            RSSStepConfigView(step: step, onChanged: onChanged)
        case .think:
            ThinkStepConfigView(step: step, previousSteps: previousSteps, onChanged: onChanged)
        case .condition:
            ConditionStepConfigView(step: step, previousSteps: previousSteps, onChanged: onChanged)
        case .output:
            OutputStepConfigView(step: step, onChanged: onChanged)
        }
    }

    // MARK: - Helpers

    private var iconColor: Color {
        switch step.stepType {
        case .readMail:      return Color.oAccent
        case .readCalendar:  return Color.oMeshTeal
        case .readReminders: return Color.oSuccessGreen
        case .readFiles:     return Color.oWarningAmber
        case .readRSS:       return Color.oAccent
        case .think:         return Color.oAccent
        case .condition:     return Color.oWarningAmber
        case .output:        return Color.oSuccessGreen
        }
    }

    private func commitLabel() {
        let trimmed = stepLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { stepLabel = step.label; return }
        step.label = trimmed
        onChanged()
    }
}

// MARK: - Empty state (no step selected)

struct AgentStepConfigEmptyPanel: View {
    var body: some View {
        VStack(spacing: OSpacing.md) {
            Image(systemName: "hand.point.left")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.oTextTertiary)
            Text("Select a step to configure it")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oSurface)
    }
}
