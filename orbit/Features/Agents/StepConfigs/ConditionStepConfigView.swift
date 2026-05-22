import SwiftUI

struct ConditionStepConfigView: View {
    let step: AgentStep
    let previousSteps: [AgentStep]
    let onChanged: () -> Void

    @State private var evaluationPrompt = ""
    @State private var inputStepOrder = 0
    @State private var skipNextIfFalse = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("Evaluate") {
                    TextField("e.g. Are there any urgent items?", text: $evaluationPrompt)
                        .textFieldStyle(.plain)
                        .font(.oBody)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: evaluationPrompt) { _, _ in save() }
                    Text("A yes/no question applied to the selected input.")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }

                if !previousSteps.isEmpty {
                    configRow("Input from") {
                        Picker("", selection: $inputStepOrder) {
                            ForEach(previousSteps, id: \.id) { s in
                                Text(s.label).tag(s.order)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: inputStepOrder) { _, _ in save() }
                    }
                }

                Toggle("Skip next step if false", isOn: $skipNextIfFalse)
                    .font(.oBody)
                    .onChange(of: skipNextIfFalse) { _, _ in save() }
                    .tint(Color.oAccent)

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(ConditionStepConfig.self) ?? ConditionStepConfig()
        evaluationPrompt = cfg.evaluationPrompt
        inputStepOrder = cfg.inputStepOrder
        skipNextIfFalse = cfg.skipNextIfFalse
    }

    private func save() {
        var cfg = ConditionStepConfig()
        cfg.evaluationPrompt = evaluationPrompt
        cfg.inputStepOrder = inputStepOrder
        cfg.skipNextIfFalse = skipNextIfFalse
        step.encodeConfig(cfg)
        onChanged()
    }
}
