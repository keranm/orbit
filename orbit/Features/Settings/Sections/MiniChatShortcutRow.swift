import SwiftUI
import Carbon.HIToolbox

/// Settings row for configuring the Mini-Chat global hotkey.
/// Embeds a shortcut recorder that captures the next keypress when active.
struct MiniChatShortcutRow: View {
    @State private var isRecording = false
    @State private var config = HotkeyConfiguration.load()
    @State private var isEnabled = UserDefaults.standard.object(forKey: "miniChatHotkeyEnabled") as? Bool ?? true
    @State private var monitor: Any?
    @State private var conflictWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global shortcut")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                    Text("Open Mini-Chat from anywhere on your Mac")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .tint(Color.oAccent)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, enabled in
                        MiniChatHotkeyManager.shared.setEnabled(enabled)
                    }
            }
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)

            if isEnabled {
                Divider().padding(.leading, OSpacing.md)

                HStack {
                    Text("Shortcut")
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                    Spacer()
                    shortcutButton
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)

                if let warning = conflictWarning {
                    HStack(spacing: OSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.oWarningAmber)
                        Text(warning)
                            .font(.oMicro)
                            .foregroundStyle(Color.oWarningAmber)
                    }
                    .padding(.horizontal, OSpacing.md)
                    .padding(.bottom, OSpacing.xs)
                }
            }
        }
    }

    // MARK: - Shortcut button

    private var shortcutButton: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Text(isRecording ? "Press shortcut…" : config.displayString)
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
        .accessibilityLabel(isRecording ? "Recording shortcut — press a key combination" : "Current shortcut: \(config.displayString). Click to change.")
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        conflictWarning = nil
        // Monitor all keydowns globally while recording
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil  // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels recording without changing the shortcut
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

        // Require at least one modifier
        guard newConfig.isValid else {
            conflictWarning = "Add a modifier key (⌘, ⌥, ⌃, or ⇧)"
            return
        }

        // Warn if ⌥ Space (produces non-breaking space in text fields)
        if newConfig.keyCode == UInt32(kVK_Space) && carbonMods == UInt32(optionKey) {
            conflictWarning = "⌥ Space may conflict with non-breaking space in text editors"
        } else {
            conflictWarning = nil
        }

        config = newConfig
        MiniChatHotkeyManager.shared.updateHotkey(newConfig)
        stopRecording()
    }
}
