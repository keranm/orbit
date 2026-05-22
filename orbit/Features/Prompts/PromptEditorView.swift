import SwiftUI
import SwiftData

struct PromptEditorView: View {
    let onBack: () -> Void
    let template: PromptTemplate

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: PromptEditorViewModel?
    @State private var activeTab = "Editor"
    @State private var rightTab = "Test"
    @State private var showAdvanced = false
    @State private var noteText: String
    @State private var editedName: String
    @State private var editedBody: String
    @State private var hasUnsavedChanges = false
    @State private var showRaw = false
    @State private var newVarName = ""
    @State private var newVarDefault = ""
    @State private var showAddVariable = false
    @State private var addingTag = false
    @State private var newEditorTag = ""

    // Test inputs
    @State private var topicInput = "AI-powered meeting assistant"
    @State private var audienceInput = "Product leaders"
    @State private var contextInput = "Early stage startup with limited resources"
    @State private var constraintsInput = "Budget < $500k, 6 month runway"
    @State private var depthInput = "Standard"
    @State private var formatInput = "Report"

    private let editorTabs = ["Editor", "Variants  3", "Evaluations", "Versions  7", "Settings"]
    private let rightTabs = ["Test", "Evaluate", "History"]

    init(onBack: @escaping () -> Void, template: PromptTemplate) {
        self.onBack = onBack
        self.template = template
        _noteText = State(initialValue: template.notes)
        _editedName = State(initialValue: template.name)
        _editedBody = State(initialValue: template.body)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            tagAndStatusBar
            Divider()
            underlineTabBar
            Divider()
            HSplitView {
                leftSidebar
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
                centerEditor
                    .frame(minWidth: 360)
                rightTestPanel
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ProStatusBar()
        }
        .background(Color.oBackground)
        .onAppear {
            guard viewModel == nil else { return }
            let service = PromptService(container: OrbitApp.modelContainer)
            viewModel = PromptEditorViewModel(template: template, service: service)
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: OSpacing.sm) {
            Button {
                if hasUnsavedChanges { /* could add unsaved changes dialog here */ }
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.oTextSecondary)
            }
            .buttonStyle(.plain)

            TextField("Prompt name", text: $editedName)
                .font(.oTitle2)
                .foregroundStyle(Color.oTextPrimary)
                .textFieldStyle(.plain)
                .frame(maxWidth: 300)
                .onChange(of: editedName) { _, _ in hasUnsavedChanges = true }
            Image(systemName: "pencil")
                .font(.system(size: 12))
                .foregroundStyle(Color.oTextTertiary)

            Spacer()

            HStack(spacing: OSpacing.xs) {
                Image(systemName: "cpu")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.oAccent)
                Text(template.modelAssociation ?? "No model selected")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.oTextTertiary)
            }
            .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))

            headerBtn("Save", icon: "square.and.arrow.down") {
                template.name = editedName
                template.body = editedBody
                template.notes = noteText
                template.updatedAt = .now
                try? modelContext.save()
                hasUnsavedChanges = false
            }

            Button {  } label: {
                Image(systemName: "ellipsis").foregroundStyle(Color.oTextSecondary)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Save As New Version") {
                    guard let vm = viewModel else { return }
                    Task { await vm.saveAsNewVersion() }
                }
                Button("Show Version History") { }
            }

            Button {
                guard let vm = viewModel, let modelRef = appState.activeModelRef else { return }
                Task {
                    await vm.runTest(
                        chatService: ChatService(),
                        modelRef: modelRef,
                        modelContext: modelContext
                    )
                }
            } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "sparkle").font(.system(size: 12))
                    Text("Test Prompt").font(.oBodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.md).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            }
            .buttonStyle(.plain)
            .disabled(viewModel?.isTesting == true)
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    private func headerBtn(_ label: String, icon: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: OSpacing.xs) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.oBodyMedium)
            }
            .foregroundStyle(Color.oTextPrimary)
            .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
        }
        .buttonStyle(.plain)
    }

    private var tagAndStatusBar: some View {
        HStack(spacing: OSpacing.sm) {
            ForEach(template.tags, id: \.self) { tag in
                Text(tag).font(.oCaptionMed).foregroundStyle(Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.sm).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
            if template.tags.isEmpty {
                Text("No tags").font(.oCaptionMed).foregroundStyle(Color.oTextTertiary)
            }
            Button { addingTag = true; newEditorTag = "" } label: {
                Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(Color.oTextTertiary)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $addingTag) {
                HStack(spacing: OSpacing.xs) {
                    TextField("Tag…", text: $newEditorTag)
                        .textFieldStyle(.plain).font(.oCaption).frame(width: 100)
                    Button("Add") {
                        let tag = newEditorTag.trimmingCharacters(in: .whitespaces)
                        if !tag.isEmpty, !template.tags.contains(tag) {
                            template.tags.append(tag)
                            try? modelContext.save()
                        }
                        addingTag = false
                        newEditorTag = ""
                    }.buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oAccent)
                }
                .padding(OSpacing.sm)
            }

            Spacer()

            Text(hasUnsavedChanges ? "Unsaved changes" : "Saved")
                .font(.oCaption).foregroundStyle(hasUnsavedChanges ? Color.oWarningAmber : Color.oTextSecondary)
            Text("Version \(template.version) · \(template.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.oCaption).foregroundStyle(Color.oTextTertiary)
            HStack(spacing: 4) {
                Circle().fill(Color.oSuccessGreen).frame(width: 6, height: 6)
                Text("Synced").font(.oCaptionMed).foregroundStyle(Color.oSuccessGreen)
            }
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.xs)
        .background(Color.oSurface)
    }

    private var underlineTabBar: some View {
        HStack(spacing: 0) {
            ForEach(editorTabs, id: \.self) { tab in
                Button { activeTab = tab } label: {
                    Text(tab).font(.oBodyMedium)
                        .foregroundStyle(activeTab == tab ? Color.oAccent : Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.md).padding(.vertical, OSpacing.sm)
                        .overlay(alignment: .bottom) {
                            if activeTab == tab {
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

    // MARK: - Left sidebar

    private var leftSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                VStack(alignment: .leading, spacing: OSpacing.sm) {
                    HStack {
                        Text("VARIABLES (\(template.variables.count))").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                        Spacer()
                    }

                    if template.variables.isEmpty {
                        VStack(spacing: OSpacing.xs) {
                            Image(systemName: "curlybraces").font(.system(size: 20)).foregroundStyle(Color.oTextTertiary)
                            Text("No variables defined").font(.oCaption).foregroundStyle(Color.oTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OSpacing.md)
                    } else {
                        ForEach(template.variables, id: \.id) { variable in
                            HStack(spacing: OSpacing.sm) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.oTextTertiary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: OSpacing.xs) {
                                        Text("{\(variable.name)}").font(.oCaptionMed).foregroundStyle(Color.oTextPrimary)
                                        Text("String").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                                    }
                                    Text(variable.defaultValue.isEmpty ? "No default" : variable.defaultValue)
                                        .font(.oMicro).foregroundStyle(Color.oTextSecondary).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    Button { showAddVariable = true; newVarName = ""; newVarDefault = "" } label: {
                        HStack(spacing: OSpacing.xs) {
                            Image(systemName: "plus").font(.system(size: 11))
                            Text("Add Variable").font(.oCaption)
                        }
                        .foregroundStyle(Color.oTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OSpacing.xs)
                        .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                        .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAddVariable) {
                        VStack(alignment: .leading, spacing: OSpacing.sm) {
                            Text("Add Variable").font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
                            TextField("Variable name", text: $newVarName)
                                .textFieldStyle(.plain).font(.oCaption)
                                .padding(OSpacing.xs)
                                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                            TextField("Default value (optional)", text: $newVarDefault)
                                .textFieldStyle(.plain).font(.oCaption)
                                .padding(OSpacing.xs)
                                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                            HStack {
                                Spacer()
                                Button("Cancel") { showAddVariable = false }.buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oTextSecondary)
                                Button("Add") {
                                    let name = newVarName.trimmingCharacters(in: .whitespaces)
                                    if !name.isEmpty {
                                        let variable = PromptVariable(name: name, defaultValue: newVarDefault)
                                        variable.template = template
                                        template.variables.append(variable)
                                        modelContext.insert(variable)
                                        try? modelContext.save()
                                    }
                                    showAddVariable = false
                                }.buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oAccent)
                            }
                        }
                        .padding(OSpacing.md)
                        .frame(width: 240)
                    }
                }

            }
            .padding(OSpacing.md)
        }
        .background(Color.oSurface)
    }

    // MARK: - Center editor

    private var centerEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROMPT TEMPLATE").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                Spacer()
                if showRaw {
                    Text("RAW").font(.oMicro).foregroundStyle(Color.oAccent)
                }
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.xs)
            .background(Color.oSurface)
            Divider()

            ScrollView {
                if showRaw {
                    Text(editedBody)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.oTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.sm)
                        .textSelection(.enabled)
                } else {
                    TextEditor(text: $editedBody)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.oTextPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 400)
                        .padding(.horizontal, OSpacing.md)
                        .padding(.vertical, OSpacing.sm)
                        .onChange(of: editedBody) { _, _ in hasUnsavedChanges = true }
                        .overlay(alignment: .topLeading) {
                            if editedBody.isEmpty {
                                Text("Write your prompt template…\nUse {{variable}} for dynamic values.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Color.oTextTertiary)
                                    .padding(.horizontal, OSpacing.md)
                                    .padding(.vertical, OSpacing.sm + 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .background(Color.oSurface)

            Divider()
            HStack(spacing: OSpacing.md) {
                Text("~\(editedBody.count / 4) tokens · ~\(String(format: "%.1f", Double(editedBody.count) / 200.0))s")
                    .font(.oMicro).foregroundStyle(Color.oTextTertiary)
                Spacer()
                HStack(spacing: 3) {
                    Text("Validate").font(.oMicro).foregroundStyle(Color.oTextSecondary)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.oSuccessGreen)
                }
                HStack(spacing: 3) {
                    Text("Lint").font(.oMicro).foregroundStyle(Color.oTextSecondary)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.oSuccessGreen)
                }
                Button("</> View raw") { showRaw.toggle() }.buttonStyle(.plain).font(.oMicro).foregroundStyle(showRaw ? Color.oAccent : Color.oTextSecondary)
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, 5)
            .background(Color.oSurface)

            Divider()
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("TEMPLATE NOTES").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                    .padding(.horizontal, OSpacing.md)
                TextEditor(text: $noteText)
                    .font(.oBody).foregroundStyle(Color.oTextPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 60)
                    .padding(.horizontal, OSpacing.md)
                    .overlay(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("Add notes about this prompt...")
                                .font(.oBody).foregroundStyle(Color.oTextTertiary)
                                .padding(.horizontal, OSpacing.md)
                                .padding(.top, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.vertical, OSpacing.sm)
            .background(Color.oSurface)
        }
        .background(Color.oSurface)
    }

    // MARK: - Right test panel

    private var rightTestPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(rightTabs, id: \.self) { tab in
                    Button { rightTab = tab } label: {
                        Text(tab).font(.oBodyMedium)
                            .foregroundStyle(rightTab == tab ? Color.oAccent : Color.oTextSecondary)
                            .padding(.horizontal, OSpacing.md).padding(.vertical, OSpacing.sm)
                            .overlay(alignment: .bottom) {
                                if rightTab == tab {
                                    Rectangle().fill(Color.oAccent).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {
                    testInputsSection
                    modelSettingsSection
                    testOutputSection
                    metricsSection
                }
                .padding(OSpacing.md)
            }
        }
        .background(Color.oSurface)
    }

    private var testInputsSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("TEST INPUTS").font(.oMicro).foregroundStyle(Color.oTextTertiary)

            inputRow("topic", value: $topicInput)
            inputRow("audience", value: $audienceInput)
            inputRow("context", value: $contextInput)
            inputRow("constraints", value: $constraintsInput)

            HStack {
                Text("depth").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
                HStack(spacing: 4) {
                    Text(depthInput).font(.oCaption).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Color.oTextTertiary)
                }
                .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                .frame(maxWidth: .infinity)
            }
            HStack {
                Text("format").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
                HStack(spacing: 4) {
                    Text(formatInput).font(.oCaption).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Color.oTextTertiary)
                }
                .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func inputRow(_ label: String, value: Binding<String>) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
            TextField("", text: value)
                .textFieldStyle(.plain).font(.oCaption)
                .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
        }
    }

    private var modelSettingsSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("MODEL & SETTINGS").font(.oMicro).foregroundStyle(Color.oTextTertiary)

            HStack {
                Text("Model").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
                HStack {
                    Text(template.modelAssociation ?? "No model selected").font(.oCaption).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Color.oTextTertiary)
                }
                .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                .frame(maxWidth: .infinity)
            }

            settingSlider("Temperature", value: Binding(
                get: { viewModel?.testTemperature ?? 0.7 },
                set: { viewModel?.testTemperature = $0 }
            ), range: 0...2, display: String(format: "%.1f", viewModel?.testTemperature ?? 0.7))

            settingSlider("Max Tokens", value: Binding(
                get: { Double(viewModel?.testMaxTokens ?? 4096) },
                set: { viewModel?.testMaxTokens = Int($0) }
            ), range: 1...32768, display: "\(viewModel?.testMaxTokens ?? 4096)")
        }
    }

    private func settingSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
            Text(display).font(.oCaption).foregroundStyle(Color.oTextPrimary).frame(width: 36, alignment: .trailing).monospacedDigit()
        }
    }

    private var testOutputSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("TEST OUTPUT").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                Spacer()
                Button("Generate") {
                    guard let vm = viewModel, let modelRef = appState.activeModelRef else { return }
                    Task {
                        await vm.runTest(
                            chatService: ChatService(),
                            modelRef: modelRef,
                            modelContext: modelContext
                        )
                    }
                }.buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oAccent)
                    .disabled(viewModel?.isTesting == true)
                HStack(spacing: 3) {
                    Circle().fill(viewModel?.isTesting == true ? Color.oWarningAmber : Color.oTextTertiary).frame(width: 5, height: 5)
                    Text(viewModel?.isTesting == true ? "Running…" : "Idle").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                }
            }
            let output = viewModel?.testOutput ?? ""
            if output.isEmpty {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text(viewModel?.isTesting == true ? "Generating…" : "Press \"Test Prompt\" or \"Generate\" to start")
                        .font(.oBody).foregroundStyle(Color.oTextTertiary)
                }
                .padding(OSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            } else {
                Text(output)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                    .textSelection(.enabled)
                    .padding(OSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                    .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("METRICS (Last 7 runs)").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                Spacer()
                Button("View all") {}.buttonStyle(.plain).font(.oMicro).foregroundStyle(Color.oAccent)
            }

            HStack(spacing: OSpacing.sm) {
                metricCard("Success Rate", value: "—", sub: nil)
                metricCard("Avg. Latency", value: "—", sub: nil)
                metricCard("Avg. Tokens", value: "—", sub: nil)
                metricCard("Version", value: "v\(template.version)", sub: nil)
            }

            let emptyData: [Double] = Array(repeating: 0, count: 7)
            metricsChart(data: emptyData).frame(height: 100)
        }
    }

    private func metricCard(_ label: String, value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.oMicro).foregroundStyle(Color.oTextTertiary).lineLimit(1)
            Text(value).font(.oTitle3).foregroundStyle(Color.oTextPrimary)
            if let s = sub {
                Text(s).font(.oMicro).foregroundStyle(Color.oTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricsChart(data: [Double]) -> some View {
        Canvas { ctx, size in
            guard !data.isEmpty else { return }
            let n = data.count
            let w = size.width
            let h = size.height - 16
            let maxV = max(data.max() ?? 1, 1)

            var area = Path(); var line = Path()
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) / CGFloat(n - 1) * w,
                        y: h - CGFloat(data[i] / maxV) * h)
            }
            area.move(to: CGPoint(x: 0, y: h))
            area.addLine(to: pt(0)); line.move(to: pt(0))
            for i in 1..<n {
                area.addLine(to: pt(i)); line.addLine(to: pt(i))
            }
            area.addLine(to: CGPoint(x: w, y: h)); area.closeSubpath()
            ctx.fill(area, with: .color(Color.oAccent.opacity(0.12)))
            ctx.stroke(line, with: .color(Color.oAccent), lineWidth: 1.5)
        }
    }
}
