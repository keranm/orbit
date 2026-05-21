import SwiftUI

struct ProPlaygroundView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PlaygroundViewModel()
    @State private var runDetailsTab = "Run Details"

    private let runDetailsTabs = ["Run Details", "Metrics", "Logs"]

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()
            HSplitView {
                configPanel
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                chatPanel
                    .frame(minWidth: 300)
                runDetailsPanel
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ProStatusBar()
        }
        .background(Color.oBackground)
        .onAppear {
            viewModel.modelRef = appState.runtimeManager.activeModelRef ?? ""
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(spacing: OSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playground")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Experiment, test, and iterate with your models and prompts.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            HStack(spacing: OSpacing.xs) {
                Text("Default Workspace")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.oTextTertiary)
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))

            Button { } label: { Image(systemName: "ellipsis").foregroundStyle(Color.oTextSecondary) }.buttonStyle(.plain)

            Button { } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)

            Button { viewModel.send() } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "play.fill").font(.system(size: 12))
                    Text("New Run")
                }
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, OSpacing.xs)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            }
            .buttonStyle(.plain)

            Button { } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.oTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    // MARK: - Left: Config Panel

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.md) {
                sectionHeader("MODEL")
                modelCard

                sectionHeader("SYSTEM PROMPT")
                systemPromptEditor

                sectionHeader("PARAMETERS")
                parametersSection
            }
            .padding(OSpacing.md)
        }
        .background(Color.oSurface)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.oMicro)
            .foregroundStyle(Color.oTextTertiary)
    }

    private var modelCard: some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: "cpu")
                .font(.system(size: 16))
                .foregroundStyle(Color.oAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OSpacing.xs) {
                    Text(viewModel.modelRef.isEmpty ? "No model" : viewModel.modelRef)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Local")
                        .font(.oMicro)
                        .foregroundStyle(Color.oSuccessGreen)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.oSuccessGreen.opacity(0.12)))
                }
                Text(appState.runtimeStatus.diagnosticsLabel)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 11))
                .foregroundStyle(Color.oTextTertiary)
        }
        .padding(OSpacing.sm)
        .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
        .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
    }

    private var systemPromptEditor: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: $viewModel.systemPrompt)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 80)
                .padding(OSpacing.xs)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
                .overlay(alignment: .topLeading) {
                    if viewModel.systemPrompt.isEmpty {
                        Text("Use a system prompt…")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextTertiary)
                            .padding(OSpacing.sm)
                            .allowsHitTesting(false)
                    }
                }
            Text("\(viewModel.systemPrompt.count)")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    private var parametersSection: some View {
        VStack(spacing: OSpacing.md) {
            HStack {
                Spacer()
                Button("Reset") {
                    viewModel.temperature = 0.7; viewModel.topP = 0.95
                    viewModel.maxTokens = 4096; viewModel.frequencyPenalty = 0.0; viewModel.presencePenalty = 0.0
                }
                .buttonStyle(.plain)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oAccent)
            }
            paramSlider("Temperature", value: $viewModel.temperature, range: 0...2, display: String(format: "%.1f", viewModel.temperature),
                        tooltip: "Controls randomness — lower values produce more predictable responses.")
            paramSlider("Top P", value: $viewModel.topP, range: 0...1, display: String(format: "%.2f", viewModel.topP),
                        tooltip: "Nucleus sampling — only tokens within the top probability mass are considered.")
            paramSlider("Max Tokens", value: Binding(get: { Double(viewModel.maxTokens) }, set: { viewModel.maxTokens = Int($0) }), range: 1...32768, display: "\(viewModel.maxTokens)",
                        tooltip: "Maximum number of tokens the model can generate in a single response.")
            paramSlider("Frequency Penalty", value: $viewModel.frequencyPenalty, range: -2...2, display: String(format: "%.1f", viewModel.frequencyPenalty),
                        tooltip: "Reduces repetition by penalising tokens that have already appeared.")
            paramSlider("Presence Penalty", value: $viewModel.presencePenalty, range: -2...2, display: String(format: "%.1f", viewModel.presencePenalty),
                        tooltip: "Encourages the model to introduce new topics by penalising used tokens.")
        }
    }

    private func paramSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String, tooltip: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: OSpacing.xs) {
                Text(label)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Button {
                    // tooltip popover
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.oTextTertiary)
                }
                .buttonStyle(.plain)
                .help(tooltip)
                .popover(isPresented: .constant(false)) {
                    Text(tooltip)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextPrimary)
                        .padding(OSpacing.sm)
                        .frame(width: 200)
                }
                Spacer()
                Text(display)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(Color.oAccent)
        }
    }

    // MARK: - Center: Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: OSpacing.xs) {
                    Text("Untitled Chat")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Button { } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { } label: {
                    HStack(spacing: OSpacing.xs) {
                        Image(systemName: "plus")
                        Text("Add Message")
                    }
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.sm)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                }
                .buttonStyle(.plain)
            }
            .padding(OSpacing.sm)
            .background(Color.oSurface)

            Divider()

            messageList

            Divider()
            chatComposer
        }
        .background(Color.oSurface)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {
                    if viewModel.messages.isEmpty {
                        emptyChat
                    } else {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(msg)
                        }
                    }
                }
                .padding(OSpacing.md)
            }
            .background(Color.oBackground)
        }
    }

    private var emptyChat: some View {
        VStack(spacing: OSpacing.sm) {
            Spacer().frame(height: 40)
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundStyle(Color.oTextTertiary)
            Text("Send a message to start")
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func messageBubble(_ msg: PlaygroundMessage) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            HStack {
                Text(msg.role.uppercased())
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                if msg.role == "assistant" {
                    if viewModel.isStreaming, msg.id == viewModel.messages.last?.id {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(viewModel.modelRef.isEmpty ? "Model" : viewModel.modelRef)
                        }
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.oAccentSoft))
                    }
                }
            }
            Text(msg.content)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .textSelection(.enabled)

            if msg.role == "assistant", !viewModel.isStreaming, let tc = viewModel.lastTokenCount {
                HStack(spacing: OSpacing.sm) {
                    Button { } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                    Button { } label: { Image(systemName: "hand.thumbsup").font(.system(size: 11)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                    Button { } label: { Image(systemName: "hand.thumbsdown").font(.system(size: 11)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                    Button { } label: { Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                    Spacer()
                    let lat = viewModel.lastLatency.map { String(format: "%.1fs", $0) } ?? ""
                    Text("\(lat) · \(tc) tokens")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
        }
    }

    private var chatComposer: some View {
        HStack(spacing: OSpacing.sm) {
            HStack(spacing: OSpacing.sm) {
                Button { } label: { Text("@").font(.oBodyMedium).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                Button { } label: { Image(systemName: "paperclip").font(.system(size: 13)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                Button { } label: { Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
                Button { } label: { Text("{x}").font(.oCaption).foregroundStyle(Color.oTextTertiary) }.buttonStyle(.plain)
            }
            TextField("Ask anything…", text: $viewModel.currentInput)
                .textFieldStyle(.plain)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
                .onSubmit { viewModel.send() }
            Button { viewModel.send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(viewModel.isStreaming ? Color.oTextTertiary : Color.oAccent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStreaming)
        }
        .padding(OSpacing.sm)
        .background(Color.oSurface)
    }

    // MARK: - Right: Run Details Panel

    private var runDetailsPanel: some View {
        VStack(spacing: 0) {
            underlineTabBar(tabs: runDetailsTabs, selected: $runDetailsTab)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {
                    runSummarySection
                    tokenUsageSection
                    latencySection
                    throughputSection
                    meshRouteSection
                }
                .padding(OSpacing.md)
            }
        }
        .background(Color.oSurface)
    }

    private var runSummarySection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("RUN SUMMARY")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
            let rows: [(String, String)] = [
                ("Model", viewModel.modelRef.isEmpty ? "—" : viewModel.modelRef),
                ("Duration", viewModel.lastLatency.map { String(format: "%.1fs", $0) } ?? "—"),
                ("Tokens", {
                    let pt = viewModel.lastPromptTokenCount.map(String.init) ?? "?"
                    let ct = viewModel.lastTokenCount.map(String.init) ?? "?"
                    return "\(ct) (prompt \(pt) / completion \(ct))"
                }()),
            ]
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                        .frame(width: 70, alignment: .leading)
                    Text(row.1)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Spacer()
                }
            }
            HStack {
                Text("Status")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .frame(width: 70, alignment: .leading)
                HStack(spacing: 4) {
                    Circle().fill(viewModel.isStreaming ? Color.oWarningAmber : Color.oSuccessGreen).frame(width: 7, height: 7)
                    Text(viewModel.isStreaming ? "Streaming" : (viewModel.lastTokenCount != nil ? "Success" : "No runs yet"))
                        .font(.oBodyMedium)
                        .foregroundStyle(viewModel.isStreaming ? Color.oWarningAmber : Color.oSuccessGreen)
                }
            }
        }
    }

    private var tokenUsageSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("TOKEN USAGE")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
            let pt = viewModel.lastPromptTokenCount ?? 0
            let ct = viewModel.lastTokenCount ?? 0
            let total = pt + ct
            if total > 0 {
                let promptFraction = Double(pt) / Double(total)
                HStack(spacing: OSpacing.lg) {
                    tokenDonut(total: total, promptFraction: promptFraction)
                    VStack(alignment: .leading, spacing: OSpacing.xs) {
                        legendDot(Color.oAccent, "Prompt \(pt) (\(Int(promptFraction * 100))%)")
                        legendDot(Color.oSuccessGreen, "Completion \(ct) (\(Int((1 - promptFraction) * 100))%)")
                    }
                }
                let lat = viewModel.lastLatency.map { String(format: "%.1fs", $0) } ?? ""
                let tps = viewModel.lastLatency.map { String(format: "%.1f", Double(ct) / $0) } ?? ""
                Text("\(total) tokens · \(lat) · \(tps) tok/s")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
            } else {
                Text("No run data yet")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
    }

    private func tokenDonut(total: Int, promptFraction: Double) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(1 - promptFraction))
                .stroke(Color.oSuccessGreen, lineWidth: 12)
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: CGFloat(1 - promptFraction), to: 1)
                .stroke(Color.oAccent, lineWidth: 12)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(total)")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Total")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
        .frame(width: 80, height: 80)
    }

    private var latencySection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("LATENCY")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                if let lat = viewModel.lastLatency {
                    Text(String(format: "%.1fs", lat))
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oAccent)
                }
            }
            if viewModel.latencyHistory.isEmpty {
                Text("Run a request to see latency data")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .frame(height: 80)
            } else {
                let data = viewModel.latencyHistory
                let maxVal = data.max() ?? 1
                miniLineChart(data: data.map { $0 / maxVal }, maxVal: 1.0, color: Color.oAccent)
                    .frame(height: 80)
                HStack {
                    Text("Last \(data.count) run(s)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                    if let latest = data.last {
                        Text(String(format: "%.1fs", latest))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }
            }
        }
    }

    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("THROUGHPUT")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                let tps = viewModel.lastLatency.flatMap { lat -> String? in
                    guard let tc = viewModel.lastTokenCount else { return nil }
                    return String(format: "%.1f tok/s", Double(tc) / lat)
                }
                Text(tps ?? "Avg —")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }
            if viewModel.throughputHistory.isEmpty {
                Text("Run a request to see throughput data")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .frame(height: 80)
            } else {
                let data = viewModel.throughputHistory
                let maxVal = data.max() ?? 1
                miniLineChart(data: data.map { $0 / maxVal }, maxVal: 1.0, color: Color.oAccent)
                    .frame(height: 80)
                HStack {
                    Text("Last \(data.count) run(s)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                    if let latest = data.last {
                        Text(String(format: "%.1f tok/s", latest))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }
            }
        }
    }

    private func miniLineChart(data: [Double], maxVal: Double, color: Color) -> some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            let w = size.width; let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h - CGFloat(data[0] / maxVal) * h))
            for i in 1..<data.count {
                path.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(data.count - 1) * w,
                                         y: h - CGFloat(data[i] / maxVal) * h))
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }

    private var meshRouteSection: some View {
        let state = appState.runtimeManager.meshConnectionState
        let isLocal = !state.isConnected || state.peerCountOptional == 0
        let routeLabel = isLocal ? "Local Inference" : "Mesh Inference"
        let routeBadge = isLocal ? "Direct" : "Routed"
        let routeDetail = isLocal
            ? "This response was generated on your Mac."
            : "This response used the mesh (\(state.statusLabel))."

        return VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("MESH ROUTE")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
                Button("View Map") {}
                    .buttonStyle(.plain)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }
            HStack(spacing: OSpacing.xs) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oTextSecondary)
                Text(routeLabel)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Text(routeBadge)
                    .font(.oMicro)
                    .foregroundStyle(Color.oSuccessGreen)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.oSuccessGreen.opacity(0.12)))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.oSuccessGreen).frame(width: 6, height: 6)
                Text(routeDetail)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
        }
    }

    // MARK: - Shared Helpers

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary)
        }
    }

    private func underlineTabBar(tabs: [String], selected: Binding<String>, icons: [String]? = nil) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                Button { selected.wrappedValue = tab } label: {
                    HStack(spacing: OSpacing.xs) {
                        if let iconList = icons, i < iconList.count {
                            Image(systemName: iconList[i])
                                .font(.system(size: 12))
                        }
                        Text(tab)
                            .font(.oBodyMedium)
                    }
                    .foregroundStyle(selected.wrappedValue == tab ? Color.oTextPrimary : Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.md)
                    .padding(.vertical, OSpacing.sm)
                    .overlay(alignment: .bottom) {
                        if selected.wrappedValue == tab {
                            Rectangle().fill(Color.oAccent).frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(Color.oSurface)
    }
}
