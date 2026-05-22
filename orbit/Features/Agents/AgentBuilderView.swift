import SwiftUI
import SwiftData

// MARK: - Route entry point (fetches agent by ID)

struct AgentBuilderView: View {
    let agentID: UUID

    @Query private var agents: [Agent]

    init(agentID: UUID) {
        self.agentID = agentID
        _agents = Query(filter: #Predicate<Agent> { $0.id == agentID })
    }

    var body: some View {
        if let agent = agents.first {
            AgentBuilderContent(agent: agent)
        } else {
            ContentUnavailableView("Agent not found", systemImage: "exclamationmark.circle")
                .background(Color.oBackground)
        }
    }
}

// MARK: - Builder content (owns ViewModel)

private struct AgentBuilderContent: View {
    @State private var viewModel: AgentBuilderViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    init(agent: Agent) {
        _viewModel = State(initialValue: AgentBuilderViewModel(agent: agent))
    }

    var body: some View {
        VStack(spacing: 0) {
            builderHeader
            Divider()
            tabBody
        }
        .background(Color.oBackground)
        .sheet(isPresented: $viewModel.showTestRunSheet) {
            AgentRunnerView(
                agent: viewModel.agent,
                modelRef: appState.runtimeManager.activeModelRef ?? "",
                onDismiss: { viewModel.showTestRunSheet = false }
            )
            .environment(appState)
        }
    }

    // MARK: - Header

    private var builderHeader: some View {
        HStack(spacing: OSpacing.md) {
            // Back
            Button {
                if viewModel.isDirty { viewModel.save(context: modelContext) }
                appState.route = .agents
            } label: {
                HStack(spacing: OSpacing.xxs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Agents")
                        .font(.oCaption)
                }
                .foregroundStyle(Color.oAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Agents")

            Divider().frame(height: 16)

            // Editable agent name
            TextField("Agent name", text: $viewModel.agentName)
                .textFieldStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .onSubmit { viewModel.save(context: modelContext) }
                .accessibilityLabel("Agent name")

            Spacer()

            // Tab picker (centre-ish in the header)
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(BuilderTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityLabel("Builder section")

            Spacer()

            // Test run — disabled when runtime not ready
            Button {
                viewModel.showTestRunSheet = true
            } label: {
                HStack(spacing: OSpacing.xxs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                    Text("Test run")
                        .font(.oCaptionMed)
                }
                .foregroundStyle(runtimeReady ? Color.oTextPrimary : Color.oTextTertiary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(Color.oSurface)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)
            .disabled(!runtimeReady)
            .help(runtimeReady ? "Test this agent" : "Start the AI runtime to run agents")
            .accessibilityLabel(runtimeReady ? "Test run agent" : "Test run unavailable — AI not running")

            // Save
            Button {
                viewModel.save(context: modelContext)
            } label: {
                HStack(spacing: OSpacing.xxs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Save")
                        .font(.oCaptionMed)
                }
                .foregroundStyle(viewModel.isDirty ? Color.white : Color.oTextSecondary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(viewModel.isDirty ? Color.oAccent : Color.oSurface)
                .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(
                    viewModel.isDirty ? Color.clear : Color.oDivider
                ))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isDirty)
            .accessibilityLabel(viewModel.isDirty ? "Save unsaved changes" : "No unsaved changes")
        }
        .padding(.horizontal, OSpacing.xl)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    private var runtimeReady: Bool {
        if case .ready = appState.runtimeStatus { return true }
        return false
    }

    // MARK: - Tab body

    @ViewBuilder
    private var tabBody: some View {
        switch viewModel.selectedTab {
        case .builder:  builderBody
        case .runs:     AgentRunHistoryView(agent: viewModel.agent)
        case .settings: settingsBody
        }
    }

    // MARK: - Builder tab: 3-panel layout

    private var builderBody: some View {
        HSplitView {
            AgentStepPaletteView { type in
                viewModel.addStep(type, after: viewModel.selectedStep)
            }
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 240)

            stepFlowPanel
                .frame(minWidth: 280)

            configPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step flow panel

    private var stepFlowPanel: some View {
        VStack(spacing: 0) {
            stepFlowHeader
            Divider()
            if viewModel.sortedSteps.isEmpty {
                emptyFlowState
            } else {
                stepList
            }
        }
        .background(Color.oBackground)
    }

    private var stepFlowHeader: some View {
        HStack {
            Text("\(viewModel.sortedSteps.count) step\(viewModel.sortedSteps.count == 1 ? "" : "s")")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
            Spacer()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private var stepList: some View {
        List {
            ForEach(viewModel.sortedSteps, id: \.id) { step in
                VStack(spacing: 0) {
                    AgentStepCardView(
                        step: step,
                        stepNumber: step.order + 1,
                        isSelected: viewModel.selectedStepID == step.id,
                        onSelect: { viewModel.selectedStepID = step.id },
                        onDelete: { viewModel.removeStep(step) }
                    )
                    if step.id != viewModel.sortedSteps.last?.id {
                        stepConnector(after: step)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: OSpacing.md, bottom: 0, trailing: OSpacing.md))
            }
            .onMove { viewModel.moveSteps(from: $0, to: $1) }

            addStepRow
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: OSpacing.sm, leading: OSpacing.md, bottom: OSpacing.md, trailing: OSpacing.md))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func stepConnector(after step: AgentStep) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                Rectangle().fill(Color.oDivider).frame(width: 1, height: 8)
                Button {
                    viewModel.addStep(.think, after: step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.oTextTertiary)
                        .frame(width: 20, height: 20)
                        .background(Color.oSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.oDivider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert step after \(step.label)")
                Rectangle().fill(Color.oDivider).frame(width: 1, height: 8)
            }
            Spacer()
        }
    }

    private var addStepRow: some View {
        Button { viewModel.addStep(.think) } label: {
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.oAccent)
                Text("Add step")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OSpacing.sm)
            .background(Color.oAccentSoft)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oAccent.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a new step")
    }

    private var emptyFlowState: some View {
        VStack(spacing: OSpacing.md) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.oTextTertiary)
            Text("Add your first step")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextSecondary)
            Text("Pick a step type from the left panel.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Config panel (right of builder)

    private var configPanel: some View {
        Group {
            if let step = viewModel.selectedStep {
                AgentStepConfigPanel(
                    step: step,
                    previousSteps: viewModel.previousSteps(before: step),
                    onChanged: { viewModel.markDirty() }
                )
            } else {
                AgentStepConfigEmptyPanel()
            }
        }
    }

    // MARK: - Settings tab

    private var settingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.xl) {
                scheduleSection
                dangerSection
            }
            .padding(OSpacing.xxl)
        }
        .background(Color.oBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.md) {
            Text("When to run")
                .font(.oTitle3)
                .foregroundStyle(Color.oTextPrimary)

            VStack(alignment: .leading, spacing: OSpacing.sm) {
                Picker("Frequency", selection: $viewModel.schedule.frequency) {
                    ForEach(AgentSchedule.Frequency.allCases, id: \.self) { freq in
                        Text(freq.rawValue).tag(freq)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.schedule.frequency) { _, _ in viewModel.markDirty() }
                .accessibilityLabel("Run frequency")

                if viewModel.schedule.frequency != .manual {
                    timePicker
                }

                if viewModel.schedule.frequency == .weekly {
                    weekdayPicker
                }
            }
            .padding(OSpacing.md)
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))

            Text("Scheduled runs require the app to be running. Background execution arrives in a future update.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    private var timePicker: some View {
        HStack(spacing: OSpacing.md) {
            Text("Time")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .frame(width: 60, alignment: .leading)
            Picker("Hour", selection: $viewModel.schedule.hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)
            .onChange(of: viewModel.schedule.hour) { _, _ in viewModel.markDirty() }
            .accessibilityLabel("Hour")
            Text(":")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextSecondary)
            Picker("Minute", selection: $viewModel.schedule.minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)
            .onChange(of: viewModel.schedule.minute) { _, _ in viewModel.markDirty() }
            .accessibilityLabel("Minute")
        }
    }

    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var weekdayPicker: some View {
        HStack(spacing: OSpacing.md) {
            Text("Day")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .frame(width: 60, alignment: .leading)
            Picker("Day of week", selection: $viewModel.schedule.weekday) {
                ForEach(1...7, id: \.self) { d in
                    Text(weekdays[d - 1]).tag(d)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.schedule.weekday) { _, _ in viewModel.markDirty() }
            .accessibilityLabel("Day of week")
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.md) {
            Text("Agent")
                .font(.oTitle3)
                .foregroundStyle(Color.oTextPrimary)

            HStack {
                VStack(alignment: .leading, spacing: OSpacing.xxs) {
                    Text("Delete this agent")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Removes the agent and all its run history permanently.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    modelContext.delete(viewModel.agent)
                    try? modelContext.save()
                    appState.route = .agents
                }
                .accessibilityLabel("Delete this agent permanently")
            }
            .padding(OSpacing.md)
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
        }
    }
}
