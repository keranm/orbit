import SwiftUI
import SwiftData

struct AgentRunHistoryView: View {
    let agent: Agent

    @Query private var runs: [AgentRun]
    @State private var selectedRun: AgentRun?

    init(agent: Agent) {
        self.agent = agent
        let agentID = agent.id
        _runs = Query(
            filter: #Predicate<AgentRun> { $0.agentID == agentID },
            sort: [SortDescriptor(\AgentRun.startedAt, order: .reverse)]
        )
    }

    var body: some View {
        if runs.isEmpty {
            emptyState
        } else {
            HSplitView {
                runList
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                runDetail
                    .frame(minWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Run list

    private var runList: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: OSpacing.xs) {
                    ForEach(runs) { run in
                        runRow(run)
                    }
                }
                .padding(OSpacing.sm)
            }
        }
        .background(Color.oSurface)
        .onAppear { if selectedRun == nil { selectedRun = runs.first } }
        .onChange(of: runs.count) { _, _ in
            if selectedRun == nil { selectedRun = runs.first }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("\(runs.count) run\(runs.count == 1 ? "" : "s")")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
            Spacer()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private func runRow(_ run: AgentRun) -> some View {
        let isSelected = selectedRun?.id == run.id
        return Button { selectedRun = run } label: {
            HStack(spacing: OSpacing.sm) {
                statusDot(run.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(runDateLabel(run.startedAt))
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextPrimary)
                    HStack(spacing: OSpacing.xs) {
                        Text(run.status.rawValue.capitalized)
                            .font(.oMicro)
                            .foregroundStyle(statusColor(run.status))
                        if let dur = run.durationSeconds {
                            Text("·")
                                .font(.oMicro)
                                .foregroundStyle(Color.oTextTertiary)
                            Text(String(format: "%.1fs", dur))
                                .font(.oMicro)
                                .foregroundStyle(Color.oTextTertiary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .fill(isSelected ? Color.oAccentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .stroke(isSelected ? Color.oAccent.opacity(0.3) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: ORadius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(run.status.rawValue) run, \(runDateLabel(run.startedAt))")
    }

    // MARK: - Run detail

    @ViewBuilder
    private var runDetail: some View {
        if let run = selectedRun {
            AgentRunResultView(
                agent: agent,
                output: run.outputText ?? "No output recorded.",
                stepStates: stepStatesFrom(run),
                onDismiss: {}
            )
        } else {
            Color.oBackground
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: OSpacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.oTextTertiary)
            VStack(spacing: OSpacing.xs) {
                Text("No runs yet")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Use Test run to execute this agent and\nthe history will appear here.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }

    // MARK: - Helpers

    private func statusDot(_ status: RunStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 7, height: 7)
    }

    private func statusColor(_ status: RunStatus) -> Color {
        switch status {
        case .running: return Color.oWarningAmber
        case .success: return Color.oSuccessGreen
        case .failed:  return Color.oErrorRed
        }
    }

    private func runDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            return "Today \(fmt.string(from: date))"
        }
        if cal.isDateInYesterday(date) {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            return "Yesterday \(fmt.string(from: date))"
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func stepStatesFrom(_ run: AgentRun) -> [Int: StepRunState] {
        var result: [Int: StepRunState] = [:]
        for log in run.stepLogs {
            switch log.status {
            case "completed": result[log.stepOrder] = .completed(log.durationSeconds)
            case "skipped":   result[log.stepOrder] = .skipped
            case "failed":    result[log.stepOrder] = .failed(log.output ?? "")
            default:          result[log.stepOrder] = .pending
            }
        }
        return result
    }
}
