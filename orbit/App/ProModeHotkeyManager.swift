import Foundation
import Carbon.HIToolbox

/// Registers and manages the system-wide global hotkey for toggling Pro mode
/// using the Carbon `RegisterEventHotKey` API — the same pattern as MiniChatHotkeyManager.
@Observable
@MainActor
final class ProModeHotkeyManager {

    static let shared = ProModeHotkeyManager()

    static let defaultConfig = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey),
        keyDisplayName: "⌘⇧P"
    )

    private static let storageKey = "proModeHotkey"

    private(set) var configuration: HotkeyConfiguration = {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return defaultConfig
        }
        return decoded
    }()

    // MARK: - Private

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let hotkeySignature: OSType = 0x4F524450  // 'ORDP' — Orbit Pro

    private init() {}

    // MARK: - Lifecycle

    func start() {
        installEventHandler()
        registerHotkey()
    }

    func stop() {
        unregisterHotkey()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    // MARK: - Reconfigure

    func updateHotkey(_ newConfig: HotkeyConfiguration) {
        unregisterHotkey()
        configuration = newConfig
        // Persist using a dedicated key (save() is hardcoded to miniChatHotkeyConfiguration).
        if let data = try? JSONEncoder().encode(newConfig) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        registerHotkey()
    }

    // MARK: - Private — Carbon registration

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerProcPtr = { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            guard hotkeyID.signature == 0x4F524450 else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<ProModeHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.handleHotKeyPressed() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1, &spec,
            selfPtr,
            &handlerRef
        )
    }

    private func registerHotkey() {
        guard hotkeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: UInt32(1)
        )
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        if status != noErr {
            hotkeyRef = nil
        }
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    // MARK: - Hotkey action

    func handleHotKeyPressed() {
        // Find AppState through the static reference
        AppState.current?.toggleProMode()
    }
}


