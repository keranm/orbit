import SwiftUI
import Carbon.HIToolbox

struct ProSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pro mode toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro Mode")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Mesh Dashboard, code editor, playground, prompt library, and advanced model controls.")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.isProMode },
                    set: { appState.isProMode = $0 }
                ))
                    .toggleStyle(.switch)
                    .tint(Color.oAccent)
                    .labelsHidden()
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)

            if appState.isProMode {
                Divider().padding(.leading, OSpacing.md)

                // Keyboard shortcut row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global shortcut")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                        Text("Toggle Pro mode from anywhere")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    Spacer()
                    ProModeShortcutView()
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
            }
        }
    }
}

// MARK: - Shortcut recorder

private struct ProModeShortcutView: View {
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var conflictWarning: String?

    /// Hold a let reference so the Observation framework can track changes to
    /// the @Observable ProModeHotkeyManager singleton.
    private let hotkeyManager = ProModeHotkeyManager.shared

    var body: some View {
        VStack(spacing: OSpacing.xxs) {
            Button {
                if isRecording { stopRecording() } else { startRecording() }
            } label: {
                Text(isRecording ? "Press shortcut…" : hotkeyManager.configuration.displayString)
                    .font(.oBodyMedium)
                    .foregroundStyle(isRecording ? Color.oAccent : Color.oTextSecondary)
                    .padding(.horizontal, OSpacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.sm)
                            .fill(isRecording ? Color.oAccentSoft : Color.oSurfaceSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: ORadius.sm)
                                    .stroke(isRecording ? Color.oAccent.opacity(0.5) : Color.oDivider, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Recording shortcut — press a key combination" : "Current shortcut: \(hotkeyManager.configuration.displayString). Click to change.")

            if let warning = conflictWarning {
                HStack(spacing: OSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.oWarningAmber)
                    Text(warning)
                        .font(.oMicro)
                        .foregroundStyle(Color.oWarningAmber)
                }
                .padding(.top, OSpacing.xxs)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        conflictWarning = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let carbonMods = HotkeyConfiguration.carbonModifiers(from: event.modifierFlags)
        let keyName = HotkeyConfiguration.keyDisplayName(from: event)
        let newConfig = HotkeyConfiguration(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonMods,
            keyDisplayName: keyName
        )
        guard newConfig.isValid else {
            conflictWarning = "Add a modifier key (⌘, ⌥, ⌃, or ⇧)"
            return
        }
        if newConfig.keyCode == UInt32(kVK_Space) && carbonMods == UInt32(optionKey) {
            conflictWarning = "⌥ Space may conflict with non-breaking space in text editors"
        } else {
            conflictWarning = nil
        }
        hotkeyManager.updateHotkey(newConfig)
        stopRecording()
    }
}
