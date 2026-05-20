import Foundation
import Carbon.HIToolbox

/// Registers and manages the system-wide global hotkey for Mini-Chat using
/// the Carbon `RegisterEventHotKey` API — the standard macOS approach used by
/// Spotlight, Alfred, Raycast, and similar utilities.
///
/// This must run on the main actor since Carbon's event target runs on the main thread.
@Observable
@MainActor
final class MiniChatHotkeyManager {

    static let shared = MiniChatHotkeyManager()

    // MARK: - State

    private(set) var isEnabled: Bool = true
    private(set) var configuration: HotkeyConfiguration = .load()

    // MARK: - Private

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let hotkeySignature: OSType = 0x4F524D43  // 'ORMC' — Orbit Mini-Chat

    private init() {}

    // MARK: - Lifecycle

    /// Call once at app startup, after the main run loop is ready.
    func start() {
        installEventHandler()
        if isEnabled { registerHotkey() }
    }

    /// Clean up — call on app termination.
    func stop() {
        unregisterHotkey()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    // MARK: - Enable / disable

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "miniChatHotkeyEnabled")
        if enabled { registerHotkey() } else { unregisterHotkey() }
    }

    // MARK: - Reconfigure

    func updateHotkey(_ newConfig: HotkeyConfiguration) {
        unregisterHotkey()
        configuration = newConfig
        configuration.save()
        if isEnabled { registerHotkey() }
    }

    // MARK: - Private — Carbon registration

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // Swift requires a literal closure (not a named function) to form a C function pointer.
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
            guard hotkeyID.signature == 0x4F524D43 else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<MiniChatHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
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
            // Registration failed (e.g. shortcut already taken by another app)
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
        NovaOverlayViewController.shared.toggle()
    }
}

