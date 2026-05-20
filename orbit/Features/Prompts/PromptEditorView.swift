import SwiftUI

struct PromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PromptEditorViewModel

    init(template: PromptTemplate, service: PromptServiceProtocol) {
        _viewModel = State(initialValue: PromptEditorViewModel(template: template, service: service))
    }

    var body: some View {
        HSplitView {
            editorPanel
                .frame(minWidth: 360, idealWidth: 500)

            testPanel
                .frame(minWidth: 280, idealWidth: 340)
        }
        .frame(width: 860, height: 600)
        .background(Color.oBackground)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Text("v\(viewModel.template.version)")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextTertiary)

                if viewModel.hasUnsavedChanges {
                    Button("Revert") { revert() }
                        .font(.oBodyMedium)

                    Button("Save") {
                        viewModel.save()
                    }
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oAccent)
                }

                Button("Save as new version") {
                    Task { await viewModel.saveAsNewVersion() }
                }
                .font(.oBodyMedium)
            }
        }
    }

    // MARK: - Editor panel

    private var editorPanel: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Prompt name", text: $viewModel.editedName)
                    .textFieldStyle(.plain)
                    .font(.oTitle2)
                    .onChange(of: viewModel.editedName) { _, _ in markDirty() }

                TextField("Description", text: $viewModel.editedDescription)
                    .textFieldStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .onChange(of: viewModel.editedDescription) { _, _ in markDirty() }

                TextField("Tags (comma-separated)", text: $viewModel.editedTags)
                    .textFieldStyle(.plain)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .onChange(of: viewModel.editedTags) { _, _ in markDirty() }
            }
            .padding(OSpacing.md)

            Divider()

            // Body editor
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(Color.oSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: ORadius.md)
                            .stroke(Color.oDivider, lineWidth: 1)
                    )

                TextEditor(text: $viewModel.editedBody)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(OSpacing.sm)
                    .onChange(of: viewModel.editedBody) { _, _ in markDirty() }
            }
            .padding(OSpacing.sm)

            HStack {
                Text("\(viewModel.characterCount) chars · ~\(viewModel.tokenEstimate) tokens")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
            }
            .padding(.horizontal, OSpacing.sm)

            Spacer()
        }
    }

    // MARK: - Test panel

    private var testPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.md) {
                Text("Test")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)

                // Variables
                if !viewModel.variableValues.isEmpty {
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Variables")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)

                        ForEach(Array(viewModel.variableValues.keys.sorted()), id: \.self) { key in
                            HStack(spacing: OSpacing.xs) {
                                Text("{{\(key)}}")
                                    .font(.oCaptionMed)
                                    .foregroundStyle(Color.oAccent)
                                TextField("Value", text: Binding(
                                    get: { viewModel.variableValues[key] ?? "" },
                                    set: { viewModel.variableValues[key] = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.oCaption)
                            }
                        }
                    }
                    .padding(OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.md)
                            .fill(Color.oSurfaceSecondary)
                    )
                }

                // Run test button
                Button {
                    Task { await viewModel.runTest() }
                } label: {
                    HStack {
                        if viewModel.isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(viewModel.isTesting ? "Running…" : "Run Test")
                    }
                    .font(.oBodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OSpacing.sm)
                    .background(Color.oAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isTesting)

                // Output
                if !viewModel.testOutput.isEmpty {
                    VStack(alignment: .leading, spacing: OSpacing.xs) {
                        Text("Output")
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oTextSecondary)

                        Text(viewModel.testOutput)
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(OSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .fill(Color.oSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .stroke(Color.oDivider, lineWidth: 1)
                            )

                        Text("\(viewModel.testOutput.count) chars output")
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }

                // Metrics
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Metrics")
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextSecondary)

                    metricRow("Characters", "\(viewModel.characterCount)")
                    metricRow("Est. tokens", "~\(viewModel.tokenEstimate)")
                    metricRow("Variables", "\(viewModel.variableValues.count)")
                }
            }
            .padding(OSpacing.md)
        }
        .scrollContentBackground(.hidden)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(label)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
            Spacer()
            Text(value)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextPrimary)
        }
    }

    private func markDirty() {
        viewModel.hasUnsavedChanges = true
    }

    private func revert() {
        viewModel.editedBody = viewModel.template.body
        viewModel.editedName = viewModel.template.name
        viewModel.editedDescription = viewModel.template.templateDescription
        viewModel.editedTags = viewModel.template.tags.joined(separator: ", ")
        viewModel.hasUnsavedChanges = false
    }
}
