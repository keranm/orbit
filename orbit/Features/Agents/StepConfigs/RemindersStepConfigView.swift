import SwiftUI

struct RemindersStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var listName = ""
    @State private var incompleteOnly = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("List name") {
                    TextField("All lists", text: $listName)
                        .textFieldStyle(.plain)
                        .font(.oBody)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: listName) { _, _ in save() }
                }

                Toggle("Incomplete items only", isOn: $incompleteOnly)
                    .font(.oBody)
                    .onChange(of: incompleteOnly) { _, _ in save() }
                    .tint(Color.oAccent)

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(RemindersStepConfig.self) ?? RemindersStepConfig()
        listName = cfg.listName
        incompleteOnly = cfg.incompleteOnly
    }

    private func save() {
        var cfg = RemindersStepConfig()
        cfg.listName = listName
        cfg.incompleteOnly = incompleteOnly
        step.encodeConfig(cfg)
        onChanged()
    }
}
