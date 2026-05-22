import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Library

struct PromptsLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: PromptsLibraryViewModel?
    @State private var detailTab = "Overview"
    @State private var showingEditor = false
    @State private var editingTemplate: PromptTemplate?
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: PromptTemplate?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var showModelPickerFor: PromptTemplate?
    @State private var addingTagFor: PromptTemplate?
    @State private var newTagText = ""
    @AppStorage("promptsViewMode") private var viewMode: ViewMode = .list

    enum ViewMode: String { case list, grid }

    var body: some View {
        Group {
            if let vm = viewModel {
                if showingEditor, let template = editingTemplate {
                    PromptEditorView(onBack: {
                        showingEditor = false
                        editingTemplate = nil
                    }, template: template)
                } else {
                    mainContent(vm: vm)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            let service = PromptService(container: OrbitApp.modelContainer)
            viewModel = PromptsLibraryViewModel(service: service)
        }
        .task { await viewModel?.onAppear() }
        .alert("Delete Prompt", isPresented: $showDeleteConfirmation, presenting: templateToDelete) { template in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel?.delete(template)
            }
        } message: { template in
            Text("Are you sure you want to delete \"\(template.name)\"? This cannot be undone.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importPrompts(from: url)
            case .failure:
                importError = "Could not open the selected file."
            }
        }
        .alert("Import Error", isPresented: .init(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $showModelPickerFor) { template in
            modelPickerSheet(for: template)
        }
    }

    @ViewBuilder
    private func mainContent(vm: PromptsLibraryViewModel) -> some View {
        VStack(spacing: 0) {
            HSplitView {
                leftContent(vm: vm)
                    .frame(minWidth: 520)
                rightPanel(vm: vm)
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            }
            ProStatusBar()
        }
        .background(Color.oBackground)
    }

    // MARK: - Left

    private func leftContent(vm: PromptsLibraryViewModel) -> some View {
        VStack(spacing: 0) {
            pageHeader(vm: vm)
            Divider()
            tabBar
            Divider()
            filterBar(vm: vm)
            Divider()
            tableView(vm: vm)
            Divider()
            tableFooter(vm: vm)
        }
    }

    private func pageHeader(vm: PromptsLibraryViewModel) -> some View {
        HStack(spacing: OSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prompts")
                    .font(.oLargeTitle)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Organize, optimize, and run powerful prompts.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button {
                vm.createNewTemplate()
                editingTemplate = vm.editingTemplate
                if editingTemplate != nil { showingEditor = true }
            } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("New Prompt").font(.oBodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            }
            .buttonStyle(.plain)

            Button { showImporter = true } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                    Text("Import").font(.oBodyMedium)
                }
                .foregroundStyle(Color.oTextPrimary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.md)
        .background(Color.oSurface)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            Text("My Prompts")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oAccent)
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.oAccent).frame(height: 2)
                }
            Spacer()
        }
        .background(Color.oSurface)
    }

    private func filterBar(vm: PromptsLibraryViewModel) -> some View {
        HStack(spacing: OSpacing.sm) {
            Menu {
                Button("All Prompts") { vm.selectedTag = nil }
                ForEach(vm.allTags, id: \.self) { tag in
                    Button(tag) { vm.selectedTag = tag }
                }
            } label: {
                dropdownChip(vm.selectedTag ?? "All Prompts")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            HStack(spacing: OSpacing.xs) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color.oTextTertiary)
                TextField("Search prompts...", text: Binding(
                    get: { vm.searchText },
                    set: { vm.searchText = $0 }
                ))
                .textFieldStyle(.plain).font(.oBody).frame(width: 140)
                Text("⌘F").font(.oMicro).foregroundStyle(Color.oTextTertiary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.oSurfaceSecondary))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.oDivider))
            }
            .padding(.horizontal, OSpacing.sm).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
            .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))

            Spacer()

            Menu {
                Button("Last Used") { vm.sortOrder = .lastUsed }
                Button("Name") { vm.sortOrder = .name }
                Button("Usage") { vm.sortOrder = .usage }
            } label: {
                dropdownChip(vm.sortOrder.rawValue)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            HStack(spacing: 0) {
                Button { viewMode = .list } label: {
                    Image(systemName: "list.bullet").font(.system(size: 13))
                        .foregroundStyle(viewMode == .list ? Color.oAccent : Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.sm).padding(.vertical, OSpacing.xs)
                        .background(viewMode == .list ? Color.oAccentSoft : Color.clear)
                }
                .buttonStyle(.plain)
                Button { viewMode = .grid } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 13))
                        .foregroundStyle(viewMode == .grid ? Color.oAccent : Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.sm).padding(.vertical, OSpacing.xs)
                        .background(viewMode == .grid ? Color.oAccentSoft : Color.clear)
                }
                .buttonStyle(.plain)
            }
            .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurface))
            .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
            .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.xs)
        .background(Color.oSurface)
    }

    private func dropdownChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.oBody).foregroundStyle(Color.oTextPrimary)
            Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(Color.oTextTertiary)
        }
        .padding(.horizontal, OSpacing.sm).padding(.vertical, OSpacing.xs)
        .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oSurface))
        .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider))
    }

    // MARK: - Table

    private func tableView(vm: PromptsLibraryViewModel) -> some View {
        Group {
            if vm.isLoading {
                loadingSkeleton
            } else if let error = vm.error {
                errorState(error)
            } else if vm.filteredTemplates.isEmpty {
                emptyState(vm: vm)
            } else {
                VStack(spacing: 0) {
                    columnHeaders
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.filteredTemplates) { template in
                                promptRow(template, vm: vm)
                                Divider().padding(.leading, OSpacing.lg)
                            }
                        }
                    }
                }
                .background(Color.oSurface)
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Text("Name")
                Image(systemName: "chevron.up").font(.system(size: 9))
            }
            .font(.oCaption).foregroundStyle(Color.oTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, OSpacing.lg)

            Text("Tags").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 150, alignment: .leading)
            Text("Model").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 130, alignment: .leading)
            Text("Last Used").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .leading)
            Text("Usage").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 60, alignment: .center)
            Text("Actions").font(.oCaption).foregroundStyle(Color.oTextSecondary).frame(width: 80, alignment: .center)
                .padding(.trailing, OSpacing.md)
        }
        .padding(.vertical, OSpacing.xs)
        .background(Color.oSurfaceSecondary)
    }

    private func promptRow(_ template: PromptTemplate, vm: PromptsLibraryViewModel) -> some View {
        let isSelected = vm.selectedTemplate?.id == template.id
        return HStack(spacing: 0) {
            HStack(spacing: OSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: ORadius.sm).fill(iconBg(for: template))
                    Image(systemName: iconName(for: template)).font(.system(size: 14)).foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.name).font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
                    Text(template.templateDescription).font(.oCaption).foregroundStyle(Color.oTextSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, OSpacing.lg)

            HStack(spacing: OSpacing.xs) {
                ForEach(template.tags.prefix(3), id: \.self) { tag in
                    Text(tag).font(.oMicro).foregroundStyle(Color.oTextSecondary)
                        .padding(.horizontal, OSpacing.xs).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                        .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                }
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(template.modelAssociation ?? "Any Model").font(.oCaption).foregroundStyle(Color.oTextPrimary)
            }
            .frame(width: 130, alignment: .leading)

            Text(template.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.oCaption).foregroundStyle(Color.oTextSecondary)
                .frame(width: 80, alignment: .leading)
            Text("\(template.usageCount)").font(.oCaption).foregroundStyle(Color.oTextPrimary)
                .frame(width: 60, alignment: .center)

            HStack(spacing: OSpacing.sm) {
                Button {
                    editingTemplate = template
                    vm.selectedTemplate = template
                    showingEditor = true
                } label: {
                    Image(systemName: "play.circle").font(.system(size: 17)).foregroundStyle(Color.oTextSecondary)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Use in Code Assistant") {
                        appState.pendingCodePrompt = AppState.PendingCodePrompt(
                            id: template.id, name: template.name, body: template.body
                        )
                        appState.route = .coding
                    }
                    Button("Use in Chat") {
                        appState.pendingChatPrompt = template.body
                        appState.route = .newChat
                    }
                    Divider()
                    Button("Edit") {
                        vm.startEditing(template)
                        editingTemplate = template
                        showingEditor = true
                    }
                    Button("Duplicate") { vm.duplicate(template) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        templateToDelete = template
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Color.oTextSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .frame(width: 80, alignment: .center)
            .padding(.trailing, OSpacing.md)
        }
        .padding(.vertical, 10)
        .background(isSelected ? Color.oAccentSoft : Color.oSurface)
        .contentShape(Rectangle())
        .onTapGesture { vm.selectedTemplate = template }
    }

    private func tableFooter(vm: PromptsLibraryViewModel) -> some View {
        HStack {
            Text("\(vm.filteredTemplates.count) prompt\(vm.filteredTemplates.count == 1 ? "" : "s")")
                .font(.oCaption).foregroundStyle(Color.oTextSecondary)
            Spacer()
        }
        .padding(.horizontal, OSpacing.lg)
        .padding(.vertical, OSpacing.sm)
        .background(Color.oSurface)
    }

    // MARK: - Right detail panel

    private func rightPanel(vm: PromptsLibraryViewModel) -> some View {
        VStack(spacing: 0) {
            if let template = vm.selectedTemplate {
                detailPanelHeader(template, vm: vm)
                Divider()
                runPromptButton(template: template)
                Divider()
                detailTabRow
                Divider()
                ScrollView {
                    detailOverviewContent(template, vm: vm)
                }
            } else if vm.filteredTemplates.isEmpty {
                Spacer()
                VStack(spacing: OSpacing.sm) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.oTextTertiary)
                    Text("No prompts yet")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Create your first prompt to get started.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }
                Spacer()
            } else {
                Spacer()
                Text("Select a prompt")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextTertiary)
                Spacer()
            }
        }
        .background(Color.oSurface)
    }

    private func detailPanelHeader(_ template: PromptTemplate, vm: PromptsLibraryViewModel) -> some View {
        HStack(spacing: OSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: ORadius.sm).fill(iconBg(for: template))
                Image(systemName: iconName(for: template)).font(.system(size: 15)).foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.oTitle3).foregroundStyle(Color.oTextPrimary)
                HStack(spacing: OSpacing.xs) {
                    chip("Personal", color: Color.oTextSecondary, bg: Color.oSurfaceSecondary, border: Color.oDivider)
                    HStack(spacing: 3) {
                        Circle().fill(Color.oSuccessGreen).frame(width: 5, height: 5)
                        Text("Synced").font(.oMicro).foregroundStyle(Color.oSuccessGreen)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.oSuccessGreen.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.oSuccessGreen.opacity(0.3)))
                }
            }
            Spacer()
            Button {
                vm.startEditing(template)
                editingTemplate = template
                showingEditor = true
            } label: {
                Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Color.oTextSecondary)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Duplicate") { vm.duplicate(template) }
                Divider()
                Button("Delete", role: .destructive) {
                    templateToDelete = template
                    showDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Color.oTextSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private func runPromptButton(template: PromptTemplate) -> some View {
        HStack(spacing: OSpacing.xs) {
            HStack(spacing: 0) {
                Button {
                    let record = PromptRunRecord(templateID: template.id)
                    modelContext.insert(record)
                    template.usageCount += 1
                    try? modelContext.save()
                    editingTemplate = template
                    showingEditor = true
                } label: {
                    HStack(spacing: OSpacing.xs) {
                        Image(systemName: "play.fill").font(.system(size: 11))
                        Text("Run Prompt").font(.oBodyMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, OSpacing.md).padding(.vertical, OSpacing.sm)
                }
                .buttonStyle(.plain)
                Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
                Button {  } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, OSpacing.sm).padding(.vertical, OSpacing.sm)
                }
                .buttonStyle(.plain)
            }
            .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            .frame(maxWidth: .infinity)

        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private var detailTabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(["Overview", "Prompt", "Variables", "Settings", "History"], id: \.self) { tab in
                    Button { detailTab = tab } label: {
                        Text(tab).font(.oCaption)
                            .foregroundStyle(detailTab == tab ? Color.oAccent : Color.oTextSecondary)
                            .padding(.horizontal, OSpacing.sm).padding(.vertical, OSpacing.xs)
                            .overlay(alignment: .bottom) {
                                if detailTab == tab {
                                    Rectangle().fill(Color.oAccent).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detailOverviewContent(_ template: PromptTemplate, vm: PromptsLibraryViewModel) -> some View {
        let allRecords = (try? modelContext.fetch(FetchDescriptor<PromptRunRecord>(sortBy: [SortDescriptor(\.runAt, order: .reverse)]))) ?? []
        let records = allRecords.filter { $0.templateID == template.id }
        let successCount = records.filter(\.wasSuccess).count
        let successRate: String = {
            guard !records.isEmpty else { return "—" }
            return "\(Int(Double(successCount) / Double(records.count) * 100))%"
        }()
        let lastRun = records.first
        return VStack(alignment: .leading, spacing: OSpacing.lg) {
            infoSection("Description") {
                Text(template.templateDescription.isEmpty ? "No description" : template.templateDescription)
                    .font(.oBody).foregroundStyle(Color.oTextSecondary)
            }
            infoSection("Model") {
                HStack {
                    Text(template.modelAssociation ?? "No model set").font(.oBody).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Button("Change") { showModelPickerFor = template }
                        .buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oAccent)
                        .padding(.horizontal, OSpacing.sm).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurface))
                        .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                }
            }
            infoSection("Tags") {
                HStack(spacing: OSpacing.xs) {
                    ForEach(template.tags, id: \.self) { tag in
                        chip(tag, color: Color.oTextSecondary, bg: Color.oSurfaceSecondary, border: Color.oDivider)
                    }
                    if template.tags.isEmpty {
                        Text("No tags").font(.oCaption).foregroundStyle(Color.oTextTertiary)
                    }
                    Button { addingTagFor = template; newTagText = "" } label: {
                        Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(Color.oTextTertiary)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oSurfaceSecondary))
                            .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: .init(get: { addingTagFor?.id == template.id }, set: { if !$0 { addingTagFor = nil } })) {
                        HStack(spacing: OSpacing.xs) {
                            TextField("Tag name…", text: $newTagText)
                                .textFieldStyle(.plain)
                                .font(.oCaption)
                                .frame(width: 120)
                            Button("Add") {
                                let tag = newTagText.trimmingCharacters(in: .whitespaces)
                                if !tag.isEmpty, !template.tags.contains(tag) {
                                    template.tags.append(tag)
                                    try? modelContext.save()
                                }
                                addingTagFor = nil
                                newTagText = ""
                            }
                            .buttonStyle(.plain)
                            .font(.oCaptionMed)
                            .foregroundStyle(Color.oAccent)
                        }
                        .padding(OSpacing.sm)
                    }
                }
            }
            VStack(alignment: .leading, spacing: OSpacing.sm) {
                HStack {
                    Text("Variables (\(template.variables.count))").font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    Button("Manage") {}.buttonStyle(.plain).font(.oCaptionMed).foregroundStyle(Color.oAccent)
                }
                if template.variables.isEmpty {
                    Text("No variables defined").font(.oCaption).foregroundStyle(Color.oTextTertiary)
                } else {
                    ForEach(template.variables, id: \.id) { variable in
                        variableRow(variable.name, type: "String", hint: variable.defaultValue.isEmpty ? "No default" : variable.defaultValue, color: Color.oAccent)
                    }
                }
            }
            VStack(alignment: .leading, spacing: OSpacing.sm) {
                Text("Usage").font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
                HStack(spacing: OSpacing.md) {
                    statTile("Total Runs", "\(records.count)")
                    statTile("Success Rate", successRate)
                    statTile("Version", "v\(template.version)")
                }
                placeholderUsageChart(data: records.isEmpty ? Array(repeating: 0, count: 24) : records.prefix(24).map { _ in CGFloat.random(in: 0...30) })
                    .frame(height: 120)
            }
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                HStack {
                    Text("Last Run").font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    if let run = lastRun {
                        HStack(spacing: 4) {
                            Circle().fill(run.wasSuccess ? Color.oMeshTeal : Color.oWarningAmber).frame(width: 6, height: 6)
                            Text("\(run.runAt.formatted(date: .abbreviated, time: .shortened)) · \(run.latency < 1 ? "\(Int(run.latency * 1000))ms" : String(format: "%.1fs", run.latency)) · \(run.tokenCount) tokens")
                                .font(.oCaptionMed).foregroundStyle(Color.oTextTertiary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Color.oTextTertiary).frame(width: 6, height: 6)
                            Text("No runs yet").font(.oCaptionMed).foregroundStyle(Color.oTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(OSpacing.md)
    }

    // MARK: - States

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            columnHeaders
            Divider()
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: OSpacing.sm) {
                        RoundedRectangle(cornerRadius: ORadius.sm)
                            .fill(Color.oSurfaceSecondary)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.oSurfaceSecondary)
                                .frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.oSurfaceSecondary)
                                .frame(width: 200, height: 10)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, OSpacing.lg)
                    Divider()
                }
            }
        }
        .background(Color.oSurface)
    }

    private func emptyState(vm: PromptsLibraryViewModel) -> some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32))
                .foregroundStyle(Color.oTextTertiary)
            Text("Create your first prompt")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
            Text("Organize your most-used prompts and run them with one click.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
            Button {
                vm.createNewTemplate()
                editingTemplate = vm.editingTemplate
                if editingTemplate != nil { showingEditor = true }
            } label: {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("New Prompt").font(.oBodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent))
            }
            .buttonStyle(.plain)
            .padding(.top, OSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oSurface)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.oWarningAmber)
            Text("Could not load prompts")
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
            Text(error)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .lineLimit(2)
            Button("Retry") {
                Task { await viewModel?.onAppear() }
            }
            .buttonStyle(.plain)
            .font(.oBodyMedium)
            .foregroundStyle(Color.oAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oSurface)
    }

    // MARK: - Shared helpers

    private func infoSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text(title).font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
            content()
        }
    }

    private func chip(_ label: String, color: Color, bg: Color, border: Color) -> some View {
        Text(label).font(.oCaption).foregroundStyle(color)
            .padding(.horizontal, OSpacing.sm).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(border))
    }

    private func variableRow(_ name: String, type: String, hint: String, color: Color) -> some View {
        HStack(spacing: OSpacing.sm) {
            Text(name).font(.oCaption).foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(color.opacity(0.1)))
                .frame(width: 72, alignment: .leading)
            Text(type).font(.oCaption).foregroundStyle(Color.oTextTertiary).frame(width: 40)
            Text(hint).font(.oCaption).foregroundStyle(Color.oTextSecondary).lineLimit(1)
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary)
            Text(value).font(.oTitle3).foregroundStyle(Color.oTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statMini(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.oCaption).foregroundStyle(Color.oTextSecondary)
            Text(value).font(.oBodyMedium).foregroundStyle(Color.oTextPrimary)
        }
    }

    private func placeholderUsageChart(data: [CGFloat]) -> some View {
        Canvas { ctx, size in
            guard !data.isEmpty else { return }
            let n = data.count
            let w = size.width
            let h = size.height - 18
            let maxV: CGFloat = data.max() ?? 1

            var area = Path(); var line = Path()
            area.move(to: CGPoint(x: 0, y: h))
            area.addLine(to: CGPoint(x: 0, y: h - data[0] / maxV * h))
            line.move(to: CGPoint(x: 0, y: h - data[0] / maxV * h))
            for i in 1..<n {
                let x = CGFloat(i) / CGFloat(n - 1) * w
                let y = h - data[i] / maxV * h
                area.addLine(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x, y: y))
            }
            area.addLine(to: CGPoint(x: w, y: h)); area.closeSubpath()
            ctx.fill(area, with: .color(Color.oAccent.opacity(0.12)))
            ctx.stroke(line, with: .color(Color.oAccent), lineWidth: 1.5)

            let axisLabels = ["24h ago", "12h ago", "Now"]
            for (i, label) in axisLabels.enumerated() {
                let x = CGFloat(i) / CGFloat(axisLabels.count - 1) * w
                ctx.draw(Text(label).font(.system(size: 9)).foregroundStyle(Color.oTextTertiary),
                         at: CGPoint(x: x, y: h + 4), anchor: .top)
            }
        }
    }

    // MARK: - Import

    private struct ImportPrompt: Codable {
        var name: String
        var description: String?
        var body: String?
        var tags: [String]?
        var modelAssociation: String?
    }

    private func importPrompts(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let imported: [ImportPrompt]

            if let single = try? decoder.decode(ImportPrompt.self, from: data) {
                imported = [single]
            } else {
                imported = try decoder.decode([ImportPrompt].self, from: data)
            }

            for p in imported {
                let template = PromptTemplate(
                    name: p.name,
                    description: p.description ?? "",
                    tags: p.tags ?? [],
                    body: p.body ?? "",
                    modelAssociation: p.modelAssociation
                )
                modelContext.insert(template)
            }
            try modelContext.save()
            Task { await viewModel?.onAppear() }
        } catch {
            importError = "Could not import prompts: \(error.localizedDescription)"
        }
    }

    // MARK: - Model Picker

    private func modelPickerSheet(for template: PromptTemplate) -> some View {
        let models = appState.runtimeManager.installedModels
        return NavigationStack {
            List {
                Button("Any Model (use default)") {
                    template.modelAssociation = nil
                    try? modelContext.save()
                    showModelPickerFor = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(template.modelAssociation == nil ? Color.oAccent : Color.oTextPrimary)
                if template.modelAssociation == nil {
                    Image(systemName: "checkmark").foregroundStyle(Color.oAccent)
                }
                ForEach(models, id: \.name) { model in
                    HStack {
                        Button(model.displayName) {
                            template.modelAssociation = model.name
                            try? modelContext.save()
                            showModelPickerFor = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(template.modelAssociation == model.name ? Color.oAccent : Color.oTextPrimary)
                        Spacer()
                        if template.modelAssociation == model.name {
                            Image(systemName: "checkmark").foregroundStyle(Color.oAccent)
                        }
                    }
                }
            }
            .navigationTitle("Select Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showModelPickerFor = nil }
                }
            }
        }
        .frame(width: 360, height: 300)
    }

    private func iconName(for template: PromptTemplate) -> String {
        if template.tags.contains("coding") || template.tags.contains("code") { return "chevron.left.forwardslash.chevron.right" }
        if template.tags.contains("research") { return "magnifyingglass" }
        if template.tags.contains("data") || template.tags.contains("analysis") { return "chart.bar.fill" }
        if template.tags.contains("writing") || template.tags.contains("docs") { return "pencil" }
        if template.tags.contains("marketing") { return "megaphone.fill" }
        if template.tags.contains("sql") || template.tags.contains("database") { return "cylinder.split.1x2.fill" }
        if template.tags.contains("creative") || template.tags.contains("ideation") { return "lightbulb.fill" }
        return "sparkles"
    }

    private func iconBg(for template: PromptTemplate) -> Color {
        if template.tags.contains("coding") || template.tags.contains("code") { return Color(red: 0.42, green: 0.35, blue: 0.85) }
        if template.tags.contains("research") { return Color(red: 0.50, green: 0.50, blue: 0.55) }
        if template.tags.contains("data") || template.tags.contains("analysis") { return Color(red: 0.18, green: 0.70, blue: 0.42) }
        if template.tags.contains("writing") || template.tags.contains("docs") { return Color(red: 0.25, green: 0.55, blue: 0.85) }
        if template.tags.contains("marketing") { return Color(red: 0.92, green: 0.50, blue: 0.18) }
        if template.tags.contains("sql") || template.tags.contains("database") { return Color(red: 0.25, green: 0.48, blue: 0.80) }
        if template.tags.contains("creative") || template.tags.contains("ideation") { return Color(red: 0.95, green: 0.75, blue: 0.12) }
        return Color.oAccent
    }
}
