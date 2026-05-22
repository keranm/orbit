import SwiftUI

struct CalendarStepConfigView: View {
    let step: AgentStep
    let onChanged: () -> Void

    @State private var rangeType: CalendarStepConfig.RangeType = .today
    @State private var rangeDays = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                configRow("Time range") {
                    Picker("", selection: $rangeType) {
                        Text("Today").tag(CalendarStepConfig.RangeType.today)
                        Text("This week").tag(CalendarStepConfig.RangeType.thisWeek)
                        Text("Next N days").tag(CalendarStepConfig.RangeType.nextNDays)
                        Text("Last N days").tag(CalendarStepConfig.RangeType.lastNDays)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: rangeType) { _, _ in save() }
                }

                if rangeType == .nextNDays || rangeType == .lastNDays {
                    configRow("Number of days") {
                        HStack {
                            Stepper("\(rangeDays) days", value: $rangeDays, in: 1...90)
                                .onChange(of: rangeDays) { _, _ in save() }
                            Spacer()
                        }
                    }
                }

                privacyNote
            }
            .padding(OSpacing.md)
        }
        .onAppear { load() }
    }

    private func load() {
        let cfg = step.decodedConfig(CalendarStepConfig.self) ?? CalendarStepConfig()
        rangeType = cfg.rangeType
        rangeDays = cfg.rangeDays
    }

    private func save() {
        var cfg = CalendarStepConfig()
        cfg.rangeType = rangeType
        cfg.rangeDays = rangeDays
        step.encodeConfig(cfg)
        onChanged()
    }
}
