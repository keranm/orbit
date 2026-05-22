import SwiftUI
import SwiftData

struct ResetSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showClearConfirm = false
    @State private var showResetConfirm = false
    @State private var clearComplete = false
    @State private var showRemoveMeshLLM = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingGroup {
                destructiveRow(
                    title: "Clear all conversations",
                    subtitle: "Permanently deletes your chat history. This cannot be undone.",
                    label: "Clear",
                    confirmMessage: "This will permanently delete all your conversations.",
                    showConfirm: $showClearConfirm,
                    action: clearAllChats
                )

                Divider().padding(.leading, OSpacing.md)

                destructiveRow(
                    title: "Reset to first run",
                    subtitle: "Clears conversations and returns to the setup screen.",
                    label: "Reset",
                    confirmMessage: "This will clear all conversations and reset the app.",
                    showConfirm: $showResetConfirm,
                    action: resetToFirstRun
                )
            }

            sectionLabel("Mesh-LLM runtime")

            settingGroup {
                removeMeshLLMRow
            }

            sectionLabel("Diagnostic info")

            settingGroup {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                        if let ver = appState.runtimeManager.installedVersion {
                            Text("mesh-llm v\(ver)")
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextTertiary)
                        }
                    }
                    Spacer()
                    Button("Copy") { copyDiagnosticInfo() }
                        .buttonStyle(.plain)
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oAccent)
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
            }

            if clearComplete {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.oSuccessGreen)
                    Text("All conversations cleared.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                .padding(.top, OSpacing.sm)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showRemoveMeshLLM) {
            RemoveMeshLLMSheet(appState: appState)
        }
    }

    // MARK: - Remove Mesh-LLM row

    private var removeMeshLLMRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remove Mesh-LLM and Models")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text("Uninstall the runtime, downloaded models, and config before deleting Orbit.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }
            Spacer()
            Button("Remove…") {
                showRemoveMeshLLM = true
            }
            .buttonStyle(.plain)
            .font(.oCaptionMed)
            .foregroundStyle(Color.oErrorRed)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    // MARK: - Actions

    private func clearAllChats() {
        do {
            let chats = try modelContext.fetch(FetchDescriptor<Chat>())
            for chat in chats { modelContext.delete(chat) }
            try modelContext.save()
            withAnimation { clearComplete = true }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { clearComplete = false }
            }
        } catch { }
    }

    private func resetToFirstRun() {
        clearAllChats()
        UserDefaults.standard.removeObject(forKey: "systemPrompt")
        appState.showOnboardingRequest = true
    }

    private func copyDiagnosticInfo() {
        var lines = ["Orbit Diagnostic Info"]
        if let ver = appState.runtimeManager.installedVersion {
            lines.append("mesh-llm: v\(ver)")
        }
        lines.append("Binary: \(appState.runtimeManager.binaryPath?.path ?? "not found")")
        lines.append("Models: \(appState.runtimeManager.installedModels.count) installed")
        lines.append("Status: \(String(describing: appState.runtimeStatus))")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.oMicroMed)
            .foregroundStyle(Color.oTextTertiary)
            .padding(.horizontal, OSpacing.md)
            .padding(.top, OSpacing.lg)
            .padding(.bottom, OSpacing.xs)
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 0.5))
    }

    private func destructiveRow(
        title: String,
        subtitle: String,
        label: String,
        confirmMessage: String,
        showConfirm: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text(subtitle)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }
            Spacer()
            Button(label) { showConfirm.wrappedValue = true }
                .buttonStyle(.plain)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oErrorRed)
                .confirmationDialog(confirmMessage, isPresented: showConfirm, titleVisibility: .visible) {
                    Button(label, role: .destructive, action: action)
                    Button("Cancel", role: .cancel) {}
                }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }
}

// MARK: - Remove Mesh-LLM Sheet

private struct RemoveMeshLLMSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmText = ""
    @State private var phase: Phase = .confirm

    private enum Phase {
        case confirm
        case removing
        case done(ModelService.UninstallResult)
        case failed(String)

        var isConfirm: Bool { if case .confirm = self { return true }; return false }
    }

    private var canRemove: Bool { confirmText == "REMOVE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Remove Mesh-LLM and Models")
                        .font(.oTitle2)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("This permanently removes the AI runtime from your Mac.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
                Spacer()
                if phase.isConfirm {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.oTextSecondary)
                            .padding(6)
                            .background(Circle().fill(Color.oSurfaceSecondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
            }
            .padding(OSpacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {
                    switch phase {
                    case .confirm:
                        confirmContent
                    case .removing:
                        removingContent
                    case .done(let result):
                        doneContent(result)
                    case .failed(let msg):
                        failedContent(msg)
                    }
                }
                .padding(OSpacing.xl)
            }
        }
        .frame(width: 480)
        .background(Color.oBackground)
    }

    // MARK: - Confirm phase

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            // What will be removed
            VStack(alignment: .leading, spacing: OSpacing.sm) {
                Text("The following will be permanently removed:")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)

                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    removalBullet(icon: "externaldrive",
                                  text: "Mesh-LLM runtime binary (~/.local/bin/mesh-llm)")
                    removalBullet(icon: "cpu",
                                  text: "All downloaded AI models")
                    removalBullet(icon: "folder",
                                  text: "Configuration files (~/.mesh-llm/)")
                    removalBullet(icon: "bubble.left.and.bubble.right",
                                  text: "Your chat history in Orbit")
                }
                .padding(OSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.lg)
                        .fill(Color.oSurfaceSecondary)
                )
            }

            // What is NOT removed
            HStack(alignment: .top, spacing: OSpacing.sm) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.oSuccessGreen)
                Text("Your other HuggingFace downloads and unrelated cache content will not be touched.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }

            // Reinstall note
            HStack(alignment: .top, spacing: OSpacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.oAccent)
                Text("You can reinstall Mesh-LLM at any time using Orbit's setup flow.")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }

            Divider()

            // Type-to-confirm field
            VStack(alignment: .leading, spacing: OSpacing.sm) {
                Text("Type **REMOVE** to confirm")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)

                TextField("", text: $confirmText)
                    .textFieldStyle(.plain)
                    .font(.oBodyMedium)
                    .foregroundStyle(canRemove ? Color.oErrorRed : Color.oTextPrimary)
                    .padding(OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.md)
                            .fill(Color.oSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: ORadius.md)
                                    .stroke(canRemove ? Color.oErrorRed.opacity(0.4) : Color.oDivider, lineWidth: 1)
                            )
                    )
                    .accessibilityLabel("Type REMOVE to confirm")
            }

            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)

                Spacer()

                Button {
                    startRemoval()
                } label: {
                    Text("Remove Everything")
                        .font(.oBodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, OSpacing.lg)
                        .padding(.vertical, OSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ORadius.pill)
                                .fill(canRemove ? Color.oErrorRed : Color.oTextTertiary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canRemove)
                .accessibilityIdentifier("remove_meshlLM_confirm_button")
            }
        }
    }

    // MARK: - Removing phase

    private var removingContent: some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            HStack(spacing: OSpacing.md) {
                ProgressView()
                    .scaleEffect(0.8)
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Removing…")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("This may take a moment.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
            }
            .padding(OSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ORadius.lg)
                    .fill(Color.oSurfaceSecondary)
            )
        }
    }

    // MARK: - Done phase

    private func doneContent(_ result: ModelService.UninstallResult) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            HStack(spacing: OSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.oSuccessGreen)
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Removal complete")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Mesh-LLM has been removed from your Mac.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                }
            }

            if !result.summaryLines.isEmpty {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    ForEach(result.summaryLines, id: \.self) { line in
                        HStack(spacing: OSpacing.xs) {
                            Circle()
                                .fill(Color.oSuccessGreen)
                                .frame(width: 5, height: 5)
                            Text(line)
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                        }
                    }
                }
                .padding(OSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .fill(Color.oSurfaceSecondary)
                )
            }

            if result.hasErrors {
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Some items could not be removed:")
                        .font(.oCaptionMed)
                        .foregroundStyle(Color.oWarningAmber)
                    ForEach(result.errors, id: \.self) { err in
                        Text("· \(err)")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                }
            }

            // Reinstall prompt
            HStack(alignment: .top, spacing: OSpacing.sm) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.oAccent)
                Text("To reinstall, go to the chat screen and tap \"Set up Orbit\".")
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.pill)
                        .fill(Color.oAccent)
                )
        }
    }

    // MARK: - Failed phase

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            HStack(spacing: OSpacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.oWarningAmber)
                VStack(alignment: .leading, spacing: OSpacing.xs) {
                    Text("Something went wrong")
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                    Text(message)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextSecondary)
                        .lineSpacing(2)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                Spacer()
                Button("Try Again") {
                    phase = .confirm
                    confirmText = ""
                }
                .buttonStyle(.plain)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oAccent)
            }
        }
    }

    // MARK: - Helpers

    private func removalBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: OSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.oTextTertiary)
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(2)
        }
    }

    private func startRemoval() {
        guard canRemove else { return }
        phase = .removing

        // Capture @MainActor values before entering the detached task.
        let binaryURL = appState.runtimeManager.binaryPath

        Task {
            let result = await ModelService.uninstallAll(
                binaryPath: binaryURL,
                rm: appState.runtimeManager
            )

            await appState.runtimeManager.detectInstall()

            withAnimation {
                phase = .done(result)
            }
        }
    }
}
