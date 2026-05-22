import Foundation
import Network

@Observable
@MainActor
final class MobileAccessCoordinator {
    // MARK: - Published state

    private(set) var state: MobileAccessState = .disabled
    private(set) var pairedDevices: [TrustedMobileDevice] = []
    private(set) var currentPairingSession: PairingSession?
    private(set) var activeConnectionCount: Int = 0
    private(set) var networkName: String?

    // MARK: - Owned services

    let settingsStore: MobileAccessSettingsStore
    let trustStore: DeviceTrustStore
    let pairingService: PairingTrustService
    let apiServer: LocalMobileAPIServer
    let bonjourService: BonjourDiscoveryService
    let chatBridge: MobileChatBridge

    // MARK: - Dependencies

    private let runtimeManager: RuntimeManager
    private var pathMonitor: NWPathMonitor?

    init(runtimeManager: RuntimeManager, chatService: ChatServiceProtocol) {
        self.runtimeManager = runtimeManager

        settingsStore = MobileAccessSettingsStore()
        trustStore = DeviceTrustStore()
        pairingService = PairingTrustService(trustStore: trustStore)
        // Use a dedicated ChatService with its own isolated URLSession so mobile
        // requests never share connection pools or caches with the Mac's chat.
        let mobileService = ChatService(
            apiPort: runtimeManager.apiPort,
            session: MobileChatBridge.mobileSession
        )
        chatBridge = MobileChatBridge(runtimeManager: runtimeManager, chatService: mobileService)
        apiServer = LocalMobileAPIServer(
            pairingService: pairingService,
            trustStore: trustStore,
            chatBridge: chatBridge,
            settingsStore: settingsStore,
            runtimeManager: runtimeManager
        )
        bonjourService = BonjourDiscoveryService()

        pairedDevices = trustStore.devices
    }

    // MARK: - Actions

    func enable() async {
        guard state != .enabled else { return }

        state = .starting

        // 1. Check runtime is ready
        guard case .ready = runtimeManager.status else {
            state = .unavailable(.runtimeNotReady)
            return
        }

        // 2. Check Wi-Fi
        if await !checkWifiAvailable() {
            state = .unavailable(.noWifi)
            return
        }

        // 3. Start API server
        do {
            try await apiServer.start()
        } catch {
            state = .unavailable(.apiServerFailed)
            return
        }

        // 4. Start Bonjour
        guard let port = apiServer.assignedPort else {
            state = .unavailable(.apiServerFailed)
            return
        }

        bonjourService.startAdvertising(
            port: port,
            displayName: settingsStore.settings.macDisplayName,
            pairingAvailable: settingsStore.settings.allowPairing,
            runtimeReady: true
        )

        // 5. Start network monitoring
        startPathMonitor()

        state = .enabled
        settingsStore.setEnabled(true)
        refreshPairedDevices()
    }

    func disable() async {
        guard state != .disabled else { return }

        state = .stopping

        bonjourService.stopAdvertising()
        apiServer.stop()
        stopPathMonitor()
        refreshPairedDevices()

        state = .disabled
        settingsStore.setEnabled(false)
    }

    func refreshStatus() async {
        networkName = currentNetworkName()
    }

    /// Called at app launch. Re-enables Mobile Access if the user had it on when the app was last closed.
    func autoStartIfPreviouslyEnabled() async {
        guard settingsStore.settings.isEnabled, state == .disabled else { return }
        await enable()
    }

    @discardableResult
    func startPairingSession() -> PairingSession? {
        guard case .enabled = state else { return nil }
        let session = pairingService.generateSession(
            macDisplayName: settingsStore.settings.macDisplayName
        )
        currentPairingSession = session

        // Update Bonjour TXT record
        bonjourService.updateTXTRecord(
            pairingAvailable: settingsStore.settings.allowPairing,
            runtimeReady: true
        )

        return session
    }

    func cancelPairingSession() {
        pairingService.cancelSession()
        currentPairingSession = nil

        bonjourService.updateTXTRecord(
            pairingAvailable: settingsStore.settings.allowPairing,
            runtimeReady: true
        )
    }

    func forgetDevice(_ deviceId: UUID) {
        trustStore.revoke(deviceId)
        refreshPairedDevices()
    }

    func disconnectDevice(_ deviceId: UUID) {
        trustStore.updateLastSeen(deviceId)
        refreshPairedDevices()
    }

    func renameDevice(_ deviceId: UUID, to name: String) {
        trustStore.rename(deviceId, to: name)
        refreshPairedDevices()
    }

    func setMacDisplayName(_ name: String) {
        settingsStore.setMacDisplayName(name)

        // Restart Bonjour with new name if enabled
        if case .enabled = state, let port = apiServer.assignedPort {
            bonjourService.stopAdvertising()
            bonjourService.startAdvertising(
                port: port,
                displayName: settingsStore.settings.macDisplayName,
                pairingAvailable: settingsStore.settings.allowPairing,
                runtimeReady: true
            )
        }
    }

    // MARK: - Internal

    private func refreshPairedDevices() {
        let activeIds = apiServer.activeDeviceIds
        pairedDevices = trustStore.devices.map { device in
            var d = device
            d.isConnected = activeIds.contains(device.publicDeviceId)
            return d
        }
    }

    private func checkWifiAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            var resumed = false
            monitor.pathUpdateHandler = { path in
                MainActor.assumeIsolated {
                    guard !resumed else { return }
                    resumed = true
                    monitor.cancel()
                    continuation.resume(returning: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.loopback))
                }
            }
            monitor.start(queue: .main)
        }
    }

    private func currentNetworkName() -> String {
        "Wi‑Fi"
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated {
                if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.loopback) {
                    self?.networkName = "Wi‑Fi"
                } else {
                    self?.networkName = nil
                    if case .enabled = self?.state {
                        self?.state = .unavailable(.noWifi)
                    }
                }
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}
