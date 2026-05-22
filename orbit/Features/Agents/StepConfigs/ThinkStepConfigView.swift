import SwiftUI

struct ThinkStepConfigView: View {
    let step: AgentStep
    let previousSteps: [AgentStep]
    let onChanged: () -> Void

    @State private var systemPrompt = ""
    @State private var userPromptTemplate = ""
    @State private var temperature = 0.7
    @State private var maxTokens = 1024

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                if !previousSteps.isEmpty {
                    availableVariables
                }

                configRow("System prompt") {
                    TextEditor(text: $systemPrompt)
                        .font(.oBody)
                        .frame(minHeight: 80, maxHeight: 140)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: systemPrompt) { _, _ in save() }
                }

                configRow("User prompt template") {
                    TextEditor(text: $userPromptTemplate)
                        .font(.oBody)
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: userPromptTemplate) { _, _ in save() }
                    Text("Use {step_N_output} to include output from earlier steps.")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }

                configRow("Temperature") {
                    HStack {
                        Slider(value: $temperature, in: 0...1, step: 0.1)
                            .tint(Color.oAccent)
                            .onChange(of: temperature) { _, _ in save() }
                        Text(String(format: "%.1f", temperature))
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                configRow("Max tokens") {
                    HStack {
                        Stepper("\(maxTokens)", value: $maxTokens, in: 256...8192, step: 256)
                            .onChange(of: maxTokens) { _, _ in save() }
                        Spacer()
                    }
                }

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private var availableVariables: some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text("Available variables")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)

            VStack(alignment: .leading, spacing: OSpacing.xxs) {
                ForEach(previousSteps, id: \.id) { s in
                    HStack(spacing: OSpacing.xs) {
                        Text("{step_\(s.order)_output}")
                            .font(.oMicroMed)
                            .foregroundStyle(Color.oAccent)
                            .padding(.horizontal, OSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.oAccentSoft)
                            .clipShape(Capsule())
                        Text(s.label)
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }
            }
        }
    }

    private func load() {
        let cfg = step.decodedConfig(ThinkStepConfig.self) ?? ThinkStepConfig()
        systemPrompt = cfg.systemPrompt
        userPromptTemplate = cfg.userPromptTemplate
        temperature = cfg.temperature
        maxTokens = cfg.maxTokens
    }

    private func save() {
        var cfg = ThinkStepConfig()
        cfg.systemPrompt = systemPrompt
        cfg.userPromptTemplate = userPromptTemplate
        cfg.temperature = temperature
        cfg.maxTokens = maxTokens
        step.encodeConfig(cfg)
        onChanged()
    }
}
