import SwiftUI

struct ModelCatalogSheet: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ModelsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: ModelCategory? = nil

    private var filteredModels: [CatalogModel] {
        let base = viewModel.recommendedModels
        let searched: [CatalogModel] = searchText.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        guard let cat = selectedCategory else { return searched }
        return searched.filter { cat.matches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.isLoadingCatalog {
                loadingView
            } else if let error = viewModel.catalogLoadError {
                errorView(message: error)
            } else if viewModel.recommendedModels.isEmpty {
                emptyView
            } else {
                catalogContent
            }
        }
        .background(Color.oBackground)
        .frame(minWidth: 560, minHeight: 520)
        .task {
            await viewModel.loadRecommended(rm: appState.runtimeManager)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Add a model")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Download AI models that run privately on this Mac.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.oTextSecondary)
                    .padding(6)
                    .background(Circle().fill(Color.oSurfaceSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(OSpacing.xl)
    }

    // MARK: - Catalog content

    private var catalogContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: OSpacing.sm) {
                searchBar
                categoryPills
            }
            .padding(.horizontal, OSpacing.xl)
            .padding(.top, OSpacing.md)
            .padding(.bottom, OSpacing.sm)

            Divider()

            if filteredModels.isEmpty {
                emptyFilterState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredModels) { model in
                            CatalogRowView(
                                model: model,
                                isInstalled: viewModel.isInstalled(ref: model.ref),
                                downloadPhase: viewModel.downloadPhase(for: model.ref),
                                onDownload: {
                                    viewModel.startDownload(ref: model.ref, rm: appState.runtimeManager)
                                },
                                onCancel: { viewModel.cancelDownload(ref: model.ref) },
                                onRetry: {
                                    viewModel.retryDownload(ref: model.ref, rm: appState.runtimeManager)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, OSpacing.lg)
                    .padding(.vertical, OSpacing.md)
                }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.oTextTertiary)
            TextField("Search models", text: $searchText)
                .textFieldStyle(.plain)
                .font(.oBody)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurface)
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider, lineWidth: 1))
        )
    }

    // MARK: - Category pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OSpacing.xs) {
                pill(category: nil, label: "All")
                ForEach(ModelCategory.allCases, id: \.self) { cat in
                    pill(category: cat, label: cat.rawValue)
                }
            }
        }
    }

    private func pill(category: ModelCategory?, label: String) -> some View {
        let active = selectedCategory == category
        return Button { selectedCategory = category } label: {
            Text(label)
                .font(.oCaptionMed)
                .foregroundStyle(active ? .white : Color.oTextSecondary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(active ? Color.oAccent : Color.oSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: ORadius.pill)
                                .stroke(active ? Color.clear : Color.oDivider, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: active)
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: OSpacing.sm) {
            ProgressView().scaleEffect(0.8)
            Text("Loading models…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OSpacing.xxl)
    }

    @State private var showDiagnostics = false
    @State private var showAdvancedDetail = false

    private func errorView(message: String) -> some View {
        VStack(spacing: OSpacing.lg) {
            Spacer()

            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)

            VStack(spacing: OSpacing.xs) {
                Text("Couldn't load the model library.")
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                    .multilineTextAlignment(.center)
                Text("Your installed models are still available.")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: OSpacing.sm) {
                Button {
                    Task { await viewModel.loadRecommended(rm: appState.runtimeManager) }
                } label: {
                    Text("Retry")
                        .font(.oBodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, OSpacing.lg)
                        .padding(.vertical, OSpacing.sm)
                        .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oAccent))
                }
                .buttonStyle(.plain)

                Button {
                    showDiagnostics.toggle()
                    if !showDiagnostics { showAdvancedDetail = false }
                } label: {
                    Text(showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oAccent)
                        .padding(.horizontal, OSpacing.lg)
                        .padding(.vertical, OSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.pill)
                                .stroke(Color.oAccent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if showDiagnostics {
                diagnosticsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: showDiagnostics)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OSpacing.xxl)
    }

    private var diagnosticsPanel: some View {
        let summary = buildDiagnosticsSummary()
        return VStack(alignment: .leading, spacing: OSpacing.sm) {
            HStack {
                Text("Diagnostics")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(summary, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.oMicro)
                        .foregroundStyle(Color.oAccent)
                }
                .buttonStyle(.plain)
            }

            diagnosticRow(label: "Catalog command", value: "mesh-llm models recommended --json")
            diagnosticRow(label: "Runtime status", value: appState.runtimeStatus.diagnosticsLabel)
            diagnosticRow(label: "Mesh status", value: appState.runtimeManager.meshConnectionState.diagnosticsLabel)

            if let detail = viewModel.catalogErrorDetail {
                Divider().opacity(0.5)
                DisclosureGroup(isExpanded: $showAdvancedDetail) {
                    Text(detail.technicalMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.oTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .textSelection(.enabled)
                } label: {
                    Text("Error detail")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
        }
        .padding(OSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurface)
                .overlay(RoundedRectangle(cornerRadius: ORadius.md).stroke(Color.oDivider, lineWidth: 1))
        )
        .frame(maxWidth: 440)
    }

    private func buildDiagnosticsSummary() -> String {
        var lines = [
            "Catalog command: mesh-llm models recommended --json",
            "Runtime status: \(appState.runtimeStatus.diagnosticsLabel)",
            "Mesh status: \(appState.runtimeManager.meshConnectionState.diagnosticsLabel)",
        ]
        if let detail = viewModel.catalogErrorDetail {
            lines.append("Error detail: \(detail.technicalMessage)")
        }
        return lines.joined(separator: "\n")
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.oTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var emptyView: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)
            Text("No models available")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OSpacing.xxl)
    }

    private var emptyFilterState: some View {
        VStack(spacing: OSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(Color.oTextTertiary)
            Text("No models match")
                .font(.oBody)
                .foregroundStyle(Color.oTextSecondary)
            Button {
                searchText = ""
                selectedCategory = nil
            } label: {
                Text("Clear filters")
                    .font(.oCaption)
                    .foregroundStyle(Color.oAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OSpacing.xxl)
    }
}

// MARK: - Model categories

enum ModelCategory: String, CaseIterable {
    case chat = "Chat"
    case coding = "Coding"
    case fast = "Fast"
    case reasoning = "Reasoning"
    case small = "Small"

    func matches(_ model: CatalogModel) -> Bool {
        let haystack = "\(model.name) \(model.description ?? "")".lowercased()
        switch self {
        case .chat:
            return haystack.contains("chat") || haystack.contains("instruct") ||
                   haystack.contains("hermes") || haystack.contains("llama")
        case .coding:
            return haystack.contains("cod")
        case .reasoning:
            return haystack.contains("reason") || haystack.contains("r1") ||
                   haystack.contains("think") || haystack.contains("qwq") ||
                   haystack.contains("deepseek")
        case .fast:
            return sizeGB(model.size) <= 2.0
        case .small:
            return sizeGB(model.size) <= 4.0
        }
    }

    private func sizeGB(_ size: String?) -> Double {
        guard let s = size else { return 999 }
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        if t.hasSuffix("GB"), let v = Double(t.dropLast(2)) { return v }
        if t.hasSuffix("MB"), let v = Double(t.dropLast(2)) { return v / 1024 }
        return 999
    }
}

// MARK: - Catalog row

private struct CatalogRowView: View {
    let model: CatalogModel
    let isInstalled: Bool
    let downloadPhase: ModelDownloadService.Phase?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: OSpacing.md) {
            modelIcon
            info
            Spacer(minLength: OSpacing.sm)
            actionArea
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(isHovered ? Color.oSurfaceSecondary : Color.oSurface)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private var modelIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ORadius.sm)
                .fill(Color.oAccentSoft)
                .frame(width: 36, height: 36)
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.oAccent)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.name)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let desc = model.description, !desc.isEmpty {
                    Text(desc)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineLimit(1)
                }
                if let size = model.size, !size.isEmpty {
                    if model.description != nil {
                        Text("·")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    Text(size)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let phase = downloadPhase {
            switch phase {
            case .resolving:
                startingView
            case .downloading(let p):
                downloadingView(progress: p)
            case .verifying, .caching:
                installingView
            case .done:
                installedBadge
            case .failed(let msg):
                failedView(message: msg)
            }
        } else if isInstalled {
            installedBadge
        } else {
            addButton
        }
    }

    private var addButton: some View {
        Button(action: onDownload) {
            Text("Add")
                .font(.oCaptionMed)
                .foregroundStyle(.white)
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: ORadius.pill).fill(Color.oAccent))
        }
        .buttonStyle(.plain)
    }

    private var startingView: some View {
        HStack(spacing: OSpacing.xs) {
            ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
            Text("Starting…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    private func downloadingView(progress: Double) -> some View {
        HStack(spacing: OSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.oDivider, lineWidth: 2)
                    .frame(width: 20, height: 20)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.oAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)
                } else {
                    SpinnerArc()
                }
            }

            Text("\(Int(progress * 100))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.oTextSecondary)
                .frame(width: 28, alignment: .leading)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.oTextTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
    }

    private var installingView: some View {
        HStack(spacing: OSpacing.xs) {
            ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
            Text("Installing…")
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
        }
    }

    private var installedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.oSuccessGreen)
            Text("Installed")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oSuccessGreen)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button(action: onRetry) {
                Text("Retry")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oWarningAmber)
                    .padding(.horizontal, OSpacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.sm)
                            .fill(Color.oWarningAmber.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            if !message.isEmpty {
                Text(message)
                    .font(.oMicro)
                    .foregroundStyle(Color.oWarningAmber)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        }
    }
}

// MARK: - Spinner

private struct SpinnerArc: View {
    @State private var angle: Double = 0
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.oAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
