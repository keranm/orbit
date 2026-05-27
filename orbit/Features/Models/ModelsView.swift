import SwiftUI

struct ModelsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ModelsViewModel()
    @State private var selectedTab: ModelTab = .local

    enum ModelTab: String, CaseIterable {
        case local = "Local"
        case mesh  = "Mesh Network"
    }

    var body: some View {
        HStack(spacing: 0) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Detail panel — slides in when a model is selected
            if let selected = viewModel.selectedModel {
                Divider()
                ModelDetailPanel(
                    model: selected,
                    isActiveModel: isActiveModel(selected),
                    onSetActive: {
                        Task {
                            await viewModel.setActiveModel(selected, rm: appState.runtimeManager)
                        }
                    },
                    onRemove: {
                        Task {
                            await viewModel.removeModel(selected, rm: appState.runtimeManager)
                        }
                    },
                    onClose: { viewModel.clearSelection() }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.oBackground)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedModel?.id)
        .sheet(isPresented: $viewModel.showCatalog) {
            ModelCatalogSheet(viewModel: viewModel)
                .environment(appState)
        }
        .alert(
            "Model downloaded",
            isPresented: Binding(
                get: { viewModel.completedDownloadRef != nil },
                set: { if !$0 { viewModel.dismissCompletedDownload() } }
            )
        ) {
            Button("Use now") {
                if let ref = viewModel.completedDownloadRef,
                   let model = viewModel.installedModels.first(where: { ($0.ref ?? $0.name) == ref }) {
                    Task { await viewModel.setActiveModel(model, rm: appState.runtimeManager) }
                }
                viewModel.dismissCompletedDownload()
            }
            Button("Later", role: .cancel) {
                viewModel.dismissCompletedDownload()
            }
        } message: {
            if let name = viewModel.completedDownloadName {
                Text("\"\(name)\" is ready to use.")
            } else {
                Text("Your model is ready to use.")
            }
        }
        .task {
            await viewModel.loadInstalled(rm: appState.runtimeManager)
        }
        .onChange(of: appState.runtimeManager.status) { _, newStatus in
            if case .ready = newStatus {
                Task { await viewModel.loadInstalled(rm: appState.runtimeManager) }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .mesh && appState.runtimeManager.meshModels.isEmpty {
                Task { await appState.runtimeManager.refreshMeshModels() }
            }
        }
        .accessibilityIdentifier("models_view")
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Models")
                    .font(.oTitle1)
                    .foregroundStyle(Color.oTextPrimary)
                    .accessibilityIdentifier("models_title")

                Spacer()

                Button {
                    viewModel.showCatalog = true
                } label: {
                    Label("Add model", systemImage: "plus")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add_model_button")
            }
            .padding(.horizontal, OSpacing.xl)
            .padding(.top, OSpacing.xl)
            .padding(.bottom, OSpacing.xs)

            Text("Manage the models available to Orbit.")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .padding(.horizontal, OSpacing.xl)
                .padding(.bottom, OSpacing.lg)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ModelTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .padding(.horizontal, OSpacing.xl)

            Divider()

            // Tab content
            switch selectedTab {
            case .local:
                localTabContent
            case .mesh:
                meshTabContent
            }

            Spacer()
        }
    }

    // MARK: - Tab bar

    private func tabButton(_ tab: ModelTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: OSpacing.xs) {
                Text(tab.rawValue)
                    .font(.oBodyMedium)
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextSecondary)
                Rectangle()
                    .fill(isSelected ? Color.oAccent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, OSpacing.lg)
        .accessibilityIdentifier("tab_\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    // MARK: - Local tab

    @ViewBuilder
    private var localTabContent: some View {
        if viewModel.isLoadingInstalled && viewModel.installedModels.isEmpty {
            loadingView
        } else if let error = viewModel.installedLoadError {
            errorStateView(message: error) {
                Task { await viewModel.loadInstalled(rm: appState.runtimeManager) }
            }
        } else if viewModel.installedModels.isEmpty {
            emptyLocalState
        } else {
            installedModelsList
        }
    }

    private var installedModelsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Installed on this Mac")
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                    if viewModel.isLoadingInstalled {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, OSpacing.xl)
                .padding(.top, OSpacing.lg)
                .padding(.bottom, OSpacing.sm)

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.installedModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: viewModel.selectedModel?.id == model.id,
                            downloadPhase: nil,
                            isActiveModel: isActiveModel(model),
                            onSelect: { viewModel.select(model) },
                            onSetActive: {
                                Task {
                                    await viewModel.setActiveModel(model, rm: appState.runtimeManager)
                                }
                            },
                            onRemove: {
                                Task {
                                    await viewModel.removeModel(model, rm: appState.runtimeManager)
                                }
                            }
                        )
                        .padding(.horizontal, OSpacing.md)
                    }
                }
                .padding(.bottom, OSpacing.lg)

                if let err = viewModel.removeError {
                    Text(err)
                        .font(.oCaption)
                        .foregroundStyle(Color.oWarningAmber)
                        .padding(.horizontal, OSpacing.xl)
                        .padding(.bottom, OSpacing.sm)
                }
            }
        }
        .accessibilityIdentifier("installed_models_list")
    }

    private var emptyLocalState: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)

            Text("No models installed")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)

            Text("Download a model to start chatting privately on your Mac.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                viewModel.showCatalog = true
            } label: {
                Text("Browse models")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, OSpacing.xs)
            .accessibilityIdentifier("browse_models_button")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OSpacing.xxl)
    }

    // MARK: - Mesh tab

    @ViewBuilder
    private var meshTabContent: some View {
        let meshState = appState.runtimeManager.meshConnectionState
        let meshModels = appState.runtimeManager.meshModels

        if !meshState.isConnected {
            meshDisconnectedState
        } else if appState.runtimeManager.isLoadingMeshModels {
            VStack(spacing: OSpacing.sm) {
                ProgressView()
                Text("Loading mesh models…")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                Button("Refresh") {
                    Task { await appState.runtimeManager.refreshMeshModels() }
                }
                .buttonStyle(.plain)
                .font(.oCaption)
                .foregroundStyle(Color.oAccent)
                .padding(.top, OSpacing.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OSpacing.xxl)
        } else if meshModels.isEmpty {
            VStack(spacing: OSpacing.sm) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundStyle(Color.oTextTertiary)
                Text("No models on this mesh")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                Text("The connected mesh isn't serving any models right now.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await appState.runtimeManager.refreshMeshModels() }
                }
                .buttonStyle(.plain)
                .font(.oCaption)
                .foregroundStyle(Color.oAccent)
                .padding(.top, OSpacing.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OSpacing.xxl)
        } else {
            meshModelsList(meshModels: meshModels, isPublic: meshState.isPublic)
        }
    }

    private var meshDisconnectedState: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "network.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)

            Text("Mesh isn't connected")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)

            Text("You can still use all your local models.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)

            Button("Connect in Settings") {
                appState.route = .settings
            }
            .buttonStyle(.plain)
            .font(.oBodyMedium)
            .foregroundStyle(Color.oAccent)
            .padding(.top, OSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OSpacing.xxl)
    }

    private func meshModelsList(meshModels: [MeshModelEntry], isPublic: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isPublic {
                    VStack(spacing: OSpacing.sm) {
                        HStack(spacing: OSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.oWarningAmber)
                            Text("These models run on shared computers. Your conversations may be processed by other participants.")
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                                .lineSpacing(2)
                        }
                        .padding(OSpacing.sm)
                        .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oWarningAmber.opacity(0.08)))

                        HStack(spacing: OSpacing.sm) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.oAccent)
                            Text("Responses are generated on other people's computers over the internet. Speed depends on network conditions and how busy the mesh is — some replies feel instant, others may take a moment longer.")
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                                .lineSpacing(2)
                        }
                        .padding(OSpacing.sm)
                        .background(RoundedRectangle(cornerRadius: ORadius.md).fill(Color.oAccent.opacity(0.08)))
                    }
                    .padding(.horizontal, OSpacing.xl)
                    .padding(.top, OSpacing.lg)
                }

                Text(isPublic ? "Available on Shared Mesh" : "Available on Your Mesh")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextTertiary)
                    .padding(.horizontal, OSpacing.xl)
                    .padding(.top, OSpacing.lg)
                    .padding(.bottom, OSpacing.sm)

                LazyVStack(spacing: 0) {
                    ForEach(meshModels) { model in
                        meshModelRow(model: model, isPublic: isPublic)
                            .padding(.horizontal, OSpacing.md)
                    }
                }
            }
        }
    }

    private func meshModelRow(model: MeshModelEntry, isPublic: Bool) -> some View {
        MeshModelRow(
            model: model,
            isPublic: isPublic,
            isActive: model.name == appState.activeModelRef,
            onUse: { viewModel.selectMeshModel(model, rm: appState.runtimeManager) }
        )
    }

    // MARK: - Shared states

    private var loadingView: some View {
        VStack(spacing: OSpacing.sm) {
            ProgressView()
            Text("Loading models…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OSpacing.xxl)
    }

    private func errorStateView(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)
            Text(message)
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(action: retry) {
                Text("Try again")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OSpacing.xxl)
    }

    // MARK: - Helpers

    private func isActiveModel(_ model: InstalledModelEntry) -> Bool {
        guard let activeRef = appState.activeModelRef else { return false }
        return (model.ref ?? model.name) == activeRef
    }
}

// MARK: - Mesh model row

private struct MeshModelRow: View {
    let model: MeshModelEntry
    let isPublic: Bool
    let isActive: Bool
    let onUse: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: OSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .fill(isPublic ? Color.oAccent.opacity(0.12) : Color.oMeshTeal.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isPublic ? Color.oAccent : Color.oMeshTeal)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: OSpacing.xs) {
                    Text(model.displayName ?? model.shortName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                        .lineLimit(1)

                    Text(isPublic ? "Shared" : "Your Mesh")
                        .font(.oMicroMed)
                        .foregroundStyle(isPublic ? Color.oAccent : Color.oMeshTeal)
                        .padding(.horizontal, OSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isPublic ? Color.oAccent.opacity(0.10) : Color.oMeshTeal.opacity(0.10)))
                }

                HStack(spacing: OSpacing.xs) {
                    if let size = model.sizeGB {
                        Text(String(format: "%.1f GB", size))
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    if let nodes = model.nodeCount, nodes > 0 {
                        Text("·")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                        Text("\(nodes) \(nodes == 1 ? "node" : "nodes")")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    if let fit = model.fitLabel {
                        Text("·")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                        Text(fit)
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.oMicroMed)
                    .foregroundStyle(isPublic ? Color.oAccent : Color.oMeshTeal)
                    .padding(.horizontal, OSpacing.xs)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isPublic ? Color.oAccent.opacity(0.12) : Color.oMeshTeal.opacity(0.12)))
            } else if isHovered {
                Button("Use") { onUse() }
                    .buttonStyle(.plain)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
                    .padding(.horizontal, OSpacing.sm)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: ORadius.sm).fill(Color.oAccent.opacity(0.10)))
            }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(isHovered ? Color.oSurface.opacity(0.6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ORadius.md))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if !isActive { onUse() } }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

#Preview {
    ModelsView()
        .environment(AppState())
        .frame(width: 860, height: 600)
}
