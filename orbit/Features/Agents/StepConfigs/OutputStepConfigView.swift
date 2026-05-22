import SwiftUI

struct OutputStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var format: OutputStepConfig.Format = .markdown
    @State private var copyToClipboard = false
    @State private var createReminder = false
    @State private var reminderTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("Format") {
                    Picker("", selection: $format) {
                        Text("Text").tag(OutputStepConfig.Format.text)
                        Text("Markdown").tag(OutputStepConfig.Format.markdown)
                        Text("Bullet list").tag(OutputStepConfig.Format.bullets)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: format) { _, _ in save() }
                }

                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                    .font(.oBody)
                    .onChange(of: copyToClipboard) { _, _ in save() }
                    .tint(Color.oAccent)

                Toggle("Create a reminder", isOn: $createReminder)
                    .font(.oBody)
                    .onChange(of: createReminder) { _, _ in save() }
                    .tint(Color.oAccent)

                if createReminder {
                    configRow("Reminder title") {
                        TextField("e.g. Review weekly wrap", text: $reminderTitle)
                            .textFieldStyle(.plain)
                            .font(.oBody)
                            .padding(OSpacing.xs)
                            .background(Color.oSurfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                            .onChange(of: reminderTitle) { _, _ in save() }
                    }
                }

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(OutputStepConfig.self) ?? OutputStepConfig()
        format = cfg.format
        copyToClipboard = cfg.copyToClipboard
        createReminder = cfg.createReminder
        reminderTitle = cfg.reminderTitle
    }

    private func save() {
        var cfg = OutputStepConfig()
        cfg.format = format
        cfg.copyToClipboard = copyToClipboard
        cfg.createReminder = createReminder
        cfg.reminderTitle = reminderTitle
        step.encodeConfig(cfg)
        onChanged()
    }
}
