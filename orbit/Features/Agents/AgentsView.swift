import SwiftUI
import SwiftData

struct AgentsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Agent.createdAt) private var agents: [Agent]

    @State private var agentToRun: Agent?

    var body: some View {
        Group {
            if agents.isEmpty {
                emptyState
            } else {
                agentList
            }
        }
        .sheet(item: $agentToRun) { agent in
            AgentRunnerView(
                agent: agent,
                modelRef: appState.runtimeManager.activeModelRef ?? "",
                onDismiss: { agentToRun = nil }
            )
            .environment(appState)
        }
    }

    // MARK: - Agent list

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: OSpacing.sm) {
                    ForEach(agents) { agent in
                        AgentHubRow(
                            agent: agent,
                            runtimeReady: runtimeReady,
                            onOpen:      { appState.route = .agentBuilder(id: agent.id) },
                            onRun:       { agentToRun = agent },
                            onDuplicate: { duplicateAgent(agent) },
                            onDelete:    { deleteAgent(agent) }
                        )
                    }
                }
                .padding(OSpacing.lg)
            }
        }
        .background(Color.oBackground)
    }

    private var runtimeReady: Bool {
        if case .ready = appState.runtimeStatus { return true }
        return false
    }

    private var pageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: OSpacing.xxs) {
                Text("Agents")
                    .font(.oTitle1)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Automated workflows that run on your Mac")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button { createNewAgent() } label: {
                Label("New Agent", systemImage: "plus")
                    .font(.oBodyMedium)
            }
            .buttonStyle(.bordered)
            .tint(Color.oAccent)
        }
        .padding(.horizontal, OSpacing.xxl)
        .padding(.top, OSpacing.xxl)
        .padding(.bottom, OSpacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: OSpacing.lg) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.oTextTertiary)
            VStack(spacing: OSpacing.xs) {
                Text("No agents yet")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Agents run automated workflows using your local AI.\nAll data stays on your Mac.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create your first agent") { createNewAgent() }
                .buttonStyle(.bordered)
                .tint(Color.oAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }

    // MARK: - Actions

    private func createNewAgent() {
        let agent = Agent(name: "New Agent", description: "")
        let defaultStep = AgentStep(order: 0, stepType: .think)
        defaultStep.agent = agent
        agent.steps = [defaultStep]
        modelContext.insert(agent)
        try? modelContext.save()
        appState.route = .agentBuilder(id: agent.id)
    }

    private func duplicateAgent(_ source: Agent) {
        let copy = Agent(name: "\(source.name) copy", description: source.agentDescription, icon: source.icon)
        copy.isTemplate = false
        let copiedSteps = source.sortedSteps.map { step -> AgentStep in
            let newStep = AgentStep(order: step.order, stepType: step.stepType, label: step.label)
            newStep.configData = step.configData
            newStep.agent = copy
            return newStep
        }
        copy.steps = copiedSteps
        modelContext.insert(copy)
        try? modelContext.save()
        appState.route = .agentBuilder(id: copy.id)
    }

    private func deleteAgent(_ agent: Agent) {
        modelContext.delete(agent)
        try? modelContext.save()
    }
}

// MARK: - Per-row view (needs its own @State for hover)

private struct AgentHubRow: View {
    let agent: Agent
    let runtimeReady: Bool
    let onOpen: () -> Void
    let onRun: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: OSpacing.md) {
            // Icon
            Image(systemName: agent.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.oAccent)
                .frame(width: 36, height: 36)
                .background(Color.oAccentSoft)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))

            // Name + description
            VStack(alignment: .leading, spacing: OSpacing.xxs) {
                Text(agent.name)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text(agent.agentDescription.isEmpty ? "\(agent.steps.count) step\(agent.steps.count == 1 ? "" : "s")" : agent.agentDescription)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Trailing content — swaps between badges and run button on hover
            if isHovered {
                hoverActions
            } else {
                badges
            }
        }
        .padding(OSpacing.md)
        .background(isHovered ? Color.oSurfaceSecondary : Color.oSurface)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
        .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: ORadius.md))
        .onHover { isHovered = $0 }
        .onTapGesture { onOpen() }
        .accessibilityLabel("\(agent.name), \(agent.steps.count) steps\(agent.lastRun.map { ", last run \(relativeDate($0.startedAt))" } ?? "")")
        .accessibilityHint("Double tap to open builder")
        .contextMenu {
            Button("Run") { onRun() }
            Button("Open in Builder") { onOpen() }
            Divider()
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    // Shown when not hovered
    private var badges: some View {
        HStack(spacing: OSpacing.sm) {
            if let lastRun = agent.lastRun {
                HStack(spacing: OSpacing.xxs) {
                    Circle()
                        .fill(lastRun.status == .success ? Color.oSuccessGreen : Color.oErrorRed)
                        .frame(width: 5, height: 5)
                    Text(relativeDate(lastRun.startedAt))
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
                .padding(.horizontal, OSpacing.xs)
                .padding(.vertical, OSpacing.xxs)
                .background(Color.oSurfaceSecondary)
                .clipShape(Capsule())
            }

            Text("\(agent.steps.count) step\(agent.steps.count == 1 ? "" : "s")")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
                .padding(.horizontal, OSpacing.xs)
                .padding(.vertical, OSpacing.xxs)
                .background(Color.oSurfaceSecondary)
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    // Shown on hover
    private var hoverActions: some View {
        HStack(spacing: OSpacing.xs) {
            // Run button — primary action
            Button(action: onRun) {
                HStack(spacing: OSpacing.xxs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Run")
                        .font(.oCaptionMed)
                }
                .foregroundStyle(runtimeReady ? Color.white : Color.oTextTertiary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(runtimeReady ? Color.oAccent : Color.oSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
            }
            .buttonStyle(.plain)
            .disabled(!runtimeReady)
            .help(runtimeReady ? "Run this agent" : "Start the AI runtime first")
            .accessibilityLabel(runtimeReady ? "Run \(agent.name)" : "AI not running")

            // Edit button — secondary
            Button(action: onOpen) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.oTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.oSurface)
                    .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)
            .help("Open in builder")
            .accessibilityLabel("Edit \(agent.name)")
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        switch elapsed {
        case ..<60:    return "just now"
        case ..<3600:  return "\(Int(elapsed / 60))m ago"
        case ..<86400: return "\(Int(elapsed / 3600))h ago"
        default:       return "\(Int(elapsed / 86400))d ago"
        }
    }
}
