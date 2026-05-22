import Foundation
import SwiftData
import AppKit

/// Orchestrates sequential step execution for an Agent, streaming AgentProgress events.
struct AgentExecutionService {

    static func run(
        agent: Agent,
        userInput: String,
        modelRef: String,
        modelContext: ModelContext
    ) -> AsyncThrowingStream<AgentProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await execute(
                    agent: agent,
                    userInput: userInput,
                    modelRef: modelRef,
                    modelContext: modelContext,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Core execution loop

    private static func execute(
        agent: Agent,
        userInput: String,
        modelRef: String,
        modelContext: ModelContext,
        continuation: AsyncThrowingStream<AgentProgress, Error>.Continuation
    ) async {
        let run = AgentRun(agentID: agent.id)
        run.agent = agent
        await MainActor.run { modelContext.insert(run) }

        var stepContext: [Int: String] = [:]
        var skippedSteps: Set<Int> = []
        var stepLogs: [StepLog] = []
        var finalOutput = ""

        let steps = agent.sortedSteps

        for step in steps {
            let startTime = Date()

            if skippedSteps.contains(step.order) {
                continuation.yield(.stepSkipped(step.order))
                stepLogs.append(StepLog(stepOrder: step.order, stepLabel: step.label, status: "skipped", output: nil, durationSeconds: 0))
                continue
            }

            continuation.yield(.stepStarted(step.order, step.label))

            do {
                let output: String

                switch step.stepType {
                case .readMail:
                    let cfg = step.decodedConfig(MailStepConfig.self) ?? MailStepConfig()
                    output = try await MailDataSource.fetch(cfg)

                case .readCalendar:
                    let cfg = step.decodedConfig(CalendarStepConfig.self) ?? CalendarStepConfig()
                    output = try await CalendarDataSource.fetch(cfg)

                case .readReminders:
                    let cfg = step.decodedConfig(RemindersStepConfig.self) ?? RemindersStepConfig()
                    output = try await RemindersDataSource.fetch(cfg)

                case .readFiles:
                    let cfg = step.decodedConfig(FilesStepConfig.self) ?? FilesStepConfig()
                    output = try await FilesDataSource.fetch(cfg)

                case .readRSS:
                    let cfg = step.decodedConfig(RSSStepConfig.self) ?? RSSStepConfig()
                    output = try await RSSDataSource.fetch(cfg)

                case .think:
                    let cfg = step.decodedConfig(ThinkStepConfig.self) ?? ThinkStepConfig()
                    output = try await runThink(cfg: cfg, stepContext: stepContext, userInput: userInput, modelRef: modelRef, continuation: continuation)

                case .condition:
                    let cfg = step.decodedConfig(ConditionStepConfig.self) ?? ConditionStepConfig()
                    let passed = try await runCondition(cfg: cfg, stepContext: stepContext, modelRef: modelRef)
                    if !passed && cfg.skipNextIfFalse {
                        skippedSteps.insert(step.order + 1)
                    }
                    output = passed ? "Condition: true — continuing" : "Condition: false — next step skipped"

                case .output:
                    let cfg = step.decodedConfig(OutputStepConfig.self) ?? OutputStepConfig()
                    output = buildOutput(cfg: cfg, stepContext: stepContext)
                    finalOutput = output
                    if cfg.copyToClipboard {
                        await MainActor.run {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        }
                    }
                }

                let duration = Date().timeIntervalSince(startTime)
                stepContext[step.order] = output
                continuation.yield(.stepCompleted(step.order, String(output.prefix(120))))
                stepLogs.append(StepLog(stepOrder: step.order, stepLabel: step.label, status: "completed", output: String(output.prefix(600)), durationSeconds: duration))

            } catch {
                let duration = Date().timeIntervalSince(startTime)
                stepLogs.append(StepLog(stepOrder: step.order, stepLabel: step.label, status: "failed", output: error.localizedDescription, durationSeconds: duration))
                await finishRun(run: run, status: .failed, output: nil, logs: stepLogs, context: modelContext)
                continuation.yield(.failed(error.localizedDescription, step.order))
                continuation.finish()
                return
            }
        }

        // If no output step captured finalOutput, use the last available context
        if finalOutput.isEmpty {
            finalOutput = stepContext.keys.sorted().reversed().compactMap { stepContext[$0] }.first
                ?? "Agent completed — no output step configured."
        }

        await finishRun(run: run, status: .success, output: finalOutput, logs: stepLogs, context: modelContext)
        continuation.yield(.done(finalOutput))
        continuation.finish()
    }

    // MARK: - Think step

    private static func runThink(
        cfg: ThinkStepConfig,
        stepContext: [Int: String],
        userInput: String,
        modelRef: String,
        continuation: AsyncThrowingStream<AgentProgress, Error>.Continuation
    ) async throws -> String {
        let resolvedPrompt = substitute(
            template: cfg.userPromptTemplate.isEmpty ? "{user_input}" : cfg.userPromptTemplate,
            stepContext: stepContext,
            userInput: userInput
        )

        let service = ChatService()
        let activeModel = cfg.modelRef.isEmpty ? modelRef : cfg.modelRef
        let messages = [ChatRequestMessage(role: "user", content: resolvedPrompt)]

        var accumulated = ""
        let stream = service.streamCompletion(
            messages: messages,
            model: activeModel,
            systemPrompt: cfg.systemPrompt,
            temperature: cfg.temperature,
            topP: nil,
            maxTokens: cfg.maxTokens,
            frequencyPenalty: nil,
            presencePenalty: nil,
            user: "agent-runner"
        )

        for try await event in stream {
            switch event {
            case .token(let token):
                accumulated += token
                continuation.yield(.llmToken(token))
            case .done:
                break
            }
        }

        return accumulated
    }

    // MARK: - Condition step

    private static func runCondition(
        cfg: ConditionStepConfig,
        stepContext: [Int: String],
        modelRef: String
    ) async throws -> Bool {
        let inputText = stepContext[cfg.inputStepOrder] ?? ""
        guard !cfg.evaluationPrompt.isEmpty else { return true }

        let prompt = """
The following text was produced by a previous step:

\(inputText)

Question: \(cfg.evaluationPrompt)

Answer with only "yes" or "no".
"""
        let service = ChatService()
        let messages = [ChatRequestMessage(role: "user", content: prompt)]
        var answer = ""

        let stream = service.streamCompletion(
            messages: messages,
            model: modelRef,
            systemPrompt: "You are a yes/no evaluator. Reply with only 'yes' or 'no'.",
            temperature: 0,
            topP: nil,
            maxTokens: 10,
            frequencyPenalty: nil,
            presencePenalty: nil,
            user: "agent-condition"
        )

        for try await event in stream {
            if case .token(let token) = event { answer += token }
        }

        return answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("yes")
    }

    // MARK: - Output step

    private static func buildOutput(cfg: OutputStepConfig, stepContext: [Int: String]) -> String {
        let rawText = stepContext.keys.sorted().reversed().compactMap { stepContext[$0] }.first ?? ""
        switch cfg.format {
        case .text:     return rawText
        case .markdown: return rawText
        case .bullets:
            return rawText
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { line -> String in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ? line : "• \(trimmed)"
                }
                .joined(separator: "\n")
        }
    }

    // MARK: - Variable substitution

    static func substitute(template: String, stepContext: [Int: String], userInput: String) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{user_input}", with: userInput)
        for (order, output) in stepContext {
            result = result.replacingOccurrences(of: "{step_\(order)_output}", with: output)
        }
        return result
    }

    // MARK: - Persist run

    private static func finishRun(
        run: AgentRun,
        status: RunStatus,
        output: String?,
        logs: [StepLog],
        context: ModelContext
    ) async {
        await MainActor.run {
            run.status = status
            run.completedAt = .now
            run.outputText = output
            run.saveStepLogs(logs)
            try? context.save()
        }
    }
}
