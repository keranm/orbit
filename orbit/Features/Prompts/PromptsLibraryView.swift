import SwiftUI

struct PromptsLibraryView: View {
    @State private var viewModel: PromptsLibraryViewModel

    init(service: PromptServiceProtocol) {
        _viewModel = State(initialValue: PromptsLibraryViewModel(service: service))
    }

    var body: some View {
        HSplitView {
            listPanel
                .frame(minWidth: 280, idealWidth: 340)

            detailPanel
                .frame(minWidth: 300, idealWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
        .task { await viewModel.onAppear() }
        .sheet(isPresented: $viewModel.showEditor) {
            if let template = viewModel.selectedTemplate {
                PromptEditorView(
                    template: template,
                    service: viewModel.service
                )
            }
        }
    }

    // MARK: - List panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.oTextTertiary)
                TextField("Search prompts…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.oBody)
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(Color.oSurfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ORadius.md)
                    .stroke(Color.oDivider, lineWidth: 1)
            )
            .padding(OSpacing.sm)

            // Tag filter
            if !viewModel.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OSpacing.xs) {
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Button {
                                viewModel.selectedTag = viewModel.selectedTag == tag ? nil : tag
                            } label: {
                                Text(tag)
                                    .font(.oCaptionMed)
                                    .padding(.horizontal, OSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(viewModel.selectedTag == tag ? Color.oAccentSoft : Color.oSurfaceSecondary)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(viewModel.selectedTag == tag ? Color.oAccent : Color.oDivider, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, OSpacing.sm)
                }
                .padding(.bottom, OSpacing.xs)
            }

            // Template list
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if viewModel.filteredTemplates.isEmpty {
                emptyState
            } else {
                List(selection: $viewModel.selectedTemplate) {
                    ForEach(viewModel.filteredTemplates) { template in
                        templateRow(template)
                            .tag(template)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.delete(viewModel.filteredTemplates[index])
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.searchText.isEmpty && viewModel.selectedTag == nil {
            VStack(spacing: OSpacing.md) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.oTextTertiary)
                Text("No prompts yet")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Create your first prompt template to get started.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
                Button {
                    viewModel.selectedTemplate = PromptTemplate(name: "New Prompt")
                    viewModel.showEditor = true
                } label: {
                    Text("New Prompt")
                        .font(.oBodyMedium)
                        .padding(.horizontal, OSpacing.lg)
                        .padding(.vertical, OSpacing.sm)
                        .background(Color.oAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(OSpacing.xl)
        } else {
            VStack(spacing: OSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.oTextTertiary)
                Text("No prompts match your search.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
            }
            .padding(OSpacing.xl)
        }
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .lineLimit(1)

            if !template.templateDescription.isEmpty {
                Text(template.templateDescription)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: OSpacing.xs) {
                if !template.tags.isEmpty {
                    Text(template.tags.joined(separator: ", "))
                        .font(.oMicro)
                        .foregroundStyle(Color.oAccent)
                }
                Spacer()
                Text("v\(template.version)")
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextTertiary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Duplicate") { viewModel.duplicate(template) }
            Button("Delete", role: .destructive) { viewModel.delete(template) }
        }
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        Group {
            if let template = viewModel.selectedTemplate {
                detailContent(template)
            } else {
                VStack(spacing: OSpacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.oTextTertiary)
                    Text("Select a prompt")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailContent(_ template: PromptTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OSpacing.lg) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: OSpacing.xxs) {
                        Text(template.name)
                            .font(.oTitle2)
                            .foregroundStyle(Color.oTextPrimary)

                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(.oBody)
                                .foregroundStyle(Color.oTextSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.showEditor = true
                    } label: {
                        Text("Edit")
                            .font(.oBodyMedium)
                            .padding(.horizontal, OSpacing.md)
                            .padding(.vertical, OSpacing.xs)
                            .background(Color.oAccent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
                    }
                    .buttonStyle(.plain)
                }

                // Tags
                if !template.tags.isEmpty {
                    HStack(spacing: OSpacing.xs) {
                        ForEach(template.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.oCaptionMed)
                                .foregroundStyle(Color.oAccent)
                                .padding(.horizontal, OSpacing.sm)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.oAccentSoft)
                                )
                        }
                    }
                }

                Divider()

                // Body preview
                Text(template.body)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                    .lineLimit(20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Variables
                if !template.variables.isEmpty {
                    VStack(alignment: .leading, spacing: OSpacing.sm) {
                        Text("Variables")
                            .font(.oBodyMedium)
                            .foregroundStyle(Color.oTextPrimary)

                        ForEach(template.variables) { variable in
                            HStack {
                                Text("{{\(variable.name)}}")
                                    .font(.oCaptionMed)
                                    .foregroundStyle(Color.oAccent)
                                if !variable.defaultValue.isEmpty {
                                    Text("= \(variable.defaultValue)")
                                        .font(.oCaption)
                                        .foregroundStyle(Color.oTextTertiary)
                                }
                            }
                        }
                    }
                }

                // Stats
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Stats")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)

                    statRow("Version", "\(template.version)")
                    statRow("Usage", "\(template.usageCount) runs")
                    statRow("Created", template.createdAt.formatted(date: .abbreviated, time: .shortened))
                    statRow("Updated", template.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let model = template.modelAssociation {
                        statRow("Model", model)
                    }
                }
            }
            .padding(OSpacing.lg)
        }
        .scrollContentBackground(.hidden)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(label)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextPrimary)
        }
    }
}
