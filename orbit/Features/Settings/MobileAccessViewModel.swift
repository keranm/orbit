import Foundation
import AppKit

@Observable
@MainActor
final class MobileAccessViewModel {

    // MARK: - Types

    enum ToggleState: Equatable {
        case off, turningOn, on, turningOff
        case error(String)
    }

    enum NetworkStatus: Equatable {
        case checking
        case connected(String)
        case disconnected
    }

    struct PairedDevice: Identifiable, Equatable {
        var id: UUID
        var displayName: String
        let systemName: String
        let lastSeenLabel: String
        var isConnected: Bool
    }

    // MARK: - Coordinator reference (set by MobileAccessSection via .task)

    var coordinator: MobileAccessCoordinator?

    // MARK: - Computed state

    var toggleState: ToggleState {
        guard let coord = coordinator else { return .off }
        switch coord.state {
        case .disabled:              return .off
        case .starting:              return .turningOn
        case .enabled:               return .on
        case .stopping:              return .turningOff
        case .unavailable(let r):    return .error(unavailableMessage(r))
        case .error(let msg):        return .error(msg)
        }
    }

    var networkStatus: NetworkStatus {
        guard let name = coordinator?.networkName else { return .disconnected }
        return .connected(name)
    }

    var macDisplayName: String {
        get { coordinator?.settingsStore.settings.macDisplayName ?? Host.current().localizedName ?? "My Mac" }
        set { coordinator?.setMacDisplayName(newValue) }
    }

    var pairedDevices: [PairedDevice] {
        guard let coordinator else { return [] }
        let activeIds = coordinator.apiServer.activeDeviceIds
        return coordinator.pairedDevices.map { device in
            PairedDevice(
                id: device.id,
                displayName: device.displayName,
                systemName: sfSymbol(for: device.deviceType),
                lastSeenLabel: relativeLabel(for: device.lastSeenAt),
                isConnected: activeIds.contains(device.publicDeviceId)
            )
        }
    }

    var pairingCode: String {
        coordinator?.currentPairingSession?.code ?? ""
    }

    var pairingCodeExpiresAt: Date? {
        coordinator?.currentPairingSession?.expiresAt
    }

    var qrPayload: String {
        coordinator?.currentPairingSession?.qrPayload ?? ""
    }

    // MARK: - Computed helpers

    var isEnabled: Bool {
        if case .on = toggleState { return true }
        return false
    }

    var isTransitioning: Bool {
        toggleState == .turningOn || toggleState == .turningOff
    }

    var networkLabel: String {
        switch networkStatus {
        case .checking:            return "Checking network…"
        case .connected(let name): return "Connected to \(name)"
        case .disconnected:        return "Not connected to Wi‑Fi"
        }
    }

    var networkIsHealthy: Bool {
        if case .connected = networkStatus { return true }
        return false
    }

    var statusLabel: String {
        switch toggleState {
        case .off, .turningOff: return "Mobile Access is off"
        case .turningOn:        return "Turning on…"
        case .on:
            if case .disconnected = networkStatus { return "Waiting for Wi‑Fi" }
            return "Discoverable and ready to pair"
        case .error:            return "Mobile Access needs attention"
        }
    }

    var isPairingCodeExpired: Bool {
        guard let exp = pairingCodeExpiresAt else { return true }
        return Date() > exp
    }

    // MARK: - Actions

    func setEnabled(_ on: Bool) async {
        if on { await coordinator?.enable() }
        else  { await coordinator?.disable() }
    }

    func refreshNetworkStatus() async {
        await coordinator?.refreshStatus()
    }

    func generatePairingCode() {
        coordinator?.startPairingSession()
    }

    func copyPairingCodeToClipboard() {
        guard isEnabled else { return }
        if pairingCode.isEmpty || isPairingCodeExpired { generatePairingCode() }
        let clean = pairingCode.replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clean, forType: .string)
    }

    func forgetDevice(_ device: PairedDevice) {
        coordinator?.forgetDevice(device.id)
    }

    func disconnectDevice(_ device: PairedDevice) {
        coordinator?.disconnectDevice(device.id)
    }

    func renameDevice(_ device: PairedDevice, to name: String) {
        coordinator?.renameDevice(device.id, to: name)
    }

    // MARK: - Mapping helpers

    @discardableResult
    func startPairingSession() -> PairingSession? {
        coordinator?.startPairingSession()
    }

    private func unavailableMessage(_ reason: MobileAccessUnavailableReason) -> String {
        switch reason {
        case .runtimeNotReady:
            return "Orbit needs to be running before Mobile Access can be used."
        case .noWifi:
            return "Connect this Mac to Wi‑Fi so Orbit Mobile can find it."
        case .apiServerFailed:
            return "Mobile Access couldn't start. Try again."
        case .localNetworkPermissionMissing:
            return "Allow Orbit to communicate on your local network so your iPhone can find this Mac."
        }
    }

    private func sfSymbol(for deviceType: String) -> String {
        switch deviceType.lowercased() {
        case "ipad": return "ipad"
        default:     return "iphone"
        }
    }

    private func relativeLabel(for date: Date?) -> String {
        guard let date else { return "Never connected" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last seen " + formatter.localizedString(for: date, relativeTo: Date())
    }
}
