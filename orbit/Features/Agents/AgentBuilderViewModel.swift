import SwiftUI
import SwiftData
import Foundation

enum BuilderTab: String, CaseIterable {
    case builder  = "Builder"
    case runs     = "Runs"
    case settings = "Settings"
}

@Observable
@MainActor
final class AgentBuilderViewModel {
    let agent: Agent
    var selectedStepID: UUID?
    var isDirty = false
    var agentName: String
    var showTestRunSheet = false
    var selectedTab: BuilderTab = .builder
    var schedule: AgentSchedule

    init(agent: Agent) {
        self.agent = agent
        self.agentName = agent.name
        self.schedule = agent.schedule
        selectedStepID = agent.sortedSteps.first?.id
    }

    var sortedSteps: [AgentStep] {
        agent.sortedSteps
    }

    var selectedStep: AgentStep? {
        guard let id = selectedStepID else { return nil }
        return agent.steps.first { $0.id == id }
    }

    func addStep(_ type: StepType, after step: AgentStep? = nil) {
        let insertAfterOrder = step?.order ?? (sortedSteps.last?.order ?? -1)
        for s in agent.steps where s.order > insertAfterOrder {
            s.order += 1
        }
        let newStep = AgentStep(order: insertAfterOrder + 1, stepType: type)
        newStep.agent = agent
        agent.steps.append(newStep)
        selectedStepID = newStep.id
        markDirty()
    }

    func removeStep(_ step: AgentStep) {
        let wasSelected = selectedStepID == step.id
        agent.steps.removeAll { $0.id == step.id }
        renumber()
        if wasSelected {
            selectedStepID = sortedSteps.last?.id
        }
        markDirty()
    }

    func moveSteps(from source: IndexSet, to destination: Int) {
        var steps = sortedSteps
        steps.move(fromOffsets: source, toOffset: destination)
        for (i, s) in steps.enumerated() {
            s.order = i
        }
        markDirty()
    }

    /// Inserts a new step of `type` at `targetOrder`, shifting existing steps down.
    func insertStep(type: StepType, at targetOrder: Int) {
        for s in agent.steps where s.order >= targetOrder {
            s.order += 1
        }
        let newStep = AgentStep(order: targetOrder, stepType: type)
        newStep.agent = agent
        agent.steps.append(newStep)
        selectedStepID = newStep.id
        markDirty()
    }

    /// Moves the step with `id` to `targetOrder` using Array.move semantics.
    func moveStep(id: UUID, toOrder targetOrder: Int) {
        var steps = sortedSteps
        guard let fromIndex = steps.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(targetOrder, steps.count)
        steps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
        for (i, s) in steps.enumerated() { s.order = i }
        markDirty()
    }

    func markDirty() {
        isDirty = true
    }

    func save(context: ModelContext) {
        agent.name = agentName
        agent.schedule = schedule
        agent.updatedAt = .now
        try? context.save()
        isDirty = false
    }

    func previousSteps(before step: AgentStep) -> [AgentStep] {
        sortedSteps.filter { $0.order < step.order }
    }

    private func renumber() {
        for (i, s) in sortedSteps.enumerated() {
            s.order = i
        }
    }
}
