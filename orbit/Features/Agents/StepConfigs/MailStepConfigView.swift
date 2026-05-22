import SwiftUI

struct MailStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var fromFilter = ""
    @State private var subjectFilter = ""
    @State private var dateRangeHours = 24
    @State private var unreadOnly = true
    @State private var maxItems = 25

    private let dateRangeOptions: [(label: String, hours: Int)] = [
        ("Last 6 hours", 6),
        ("Last 24 hours", 24),
        ("Last 48 hours", 48),
        ("Last 7 days", 168),
        ("Last 30 days", 720)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("From") {
                    TextField("Any sender", text: $fromFilter)
                        .textFieldStyle(.plain)
                        .font(.oBody)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: fromFilter) { _, _ in save() }
                }

                configRow("Subject contains") {
                    TextField("Any subject", text: $subjectFilter)
                        .textFieldStyle(.plain)
                        .font(.oBody)
                        .padding(OSpacing.xs)
                        .background(Color.oSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                        .onChange(of: subjectFilter) { _, _ in save() }
                }

                configRow("Date range") {
                    Picker("", selection: $dateRangeHours) {
                        ForEach(dateRangeOptions, id: \.hours) { option in
                            Text(option.label).tag(option.hours)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: dateRangeHours) { _, _ in save() }
                }

                configRow("Max emails") {
                    HStack {
                        Stepper("\(maxItems)", value: $maxItems, in: 5...100, step: 5)
                            .onChange(of: maxItems) { _, _ in save() }
                        Spacer()
                    }
                }

                Toggle("Unread only", isOn: $unreadOnly)
                    .font(.oBody)
                    .onChange(of: unreadOnly) { _, _ in save() }
                    .tint(Color.oAccent)

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(MailStepConfig.self) ?? MailStepConfig()
        fromFilter = cfg.fromFilter
        subjectFilter = cfg.subjectFilter
        dateRangeHours = cfg.dateRangeHours
        maxItems = cfg.maxItems
        unreadOnly = cfg.unreadOnly
    }

    private func save() {
        var cfg = MailStepConfig()
        cfg.fromFilter = fromFilter
        cfg.subjectFilter = subjectFilter
        cfg.dateRangeHours = dateRangeHours
        cfg.maxItems = maxItems
        cfg.unreadOnly = unreadOnly
        step.encodeConfig(cfg)
        onChanged()
    }
}
