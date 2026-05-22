import Foundation

@MainActor
final class BonjourDiscoveryService: NSObject {
    private var netService: NetService?

    // MARK: - Lifecycle

    func startAdvertising(port: UInt16, displayName: String, pairingAvailable: Bool, runtimeReady: Bool) {
        stopAdvertising()

        let service = NetService(
            domain: "local.",
            type: "_orbit-mobile._tcp.",
            name: displayName,
            port: Int32(port)
        )
        service.delegate = self
        service.includesPeerToPeer = false

        let txt = buildTXTRecord(pairingAvailable: pairingAvailable, runtimeReady: runtimeReady)
        service.setTXTRecord(txt)

        service.publish()
        netService = service
    }

    func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    func updateTXTRecord(pairingAvailable: Bool, runtimeReady: Bool) {
        guard let service = netService else { return }
        let txt = buildTXTRecord(pairingAvailable: pairingAvailable, runtimeReady: runtimeReady)
        service.setTXTRecord(txt)
    }

    // MARK: - TXT Record

    private func buildTXTRecord(pairingAvailable: Bool, runtimeReady: Bool) -> Data {
        let dict: [String: Data] = [
            "app": Data("Orbit".utf8),
            "role": Data("mac".utf8),
            "version": Data("1".utf8),
            "protocol": Data("mobile-v1".utf8),
            "pairing": Data((pairingAvailable ? "available" : "unavailable").utf8),
            "runtime": Data((runtimeReady ? "ready" : "not-ready").utf8),
        ]
        return NetService.data(fromTXTRecord: dict)
    }
}

extension BonjourDiscoveryService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    }
}
