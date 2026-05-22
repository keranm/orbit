import Foundation

@Observable
@MainActor
final class DeviceTrustStore {
    private(set) var devices: [TrustedMobileDevice] = []

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadDevices()
    }

    // MARK: - Public API

    func add(_ device: TrustedMobileDevice, accessToken: String) throws {
        guard !devices.contains(where: { $0.publicDeviceId == device.publicDeviceId }) else {
            throw DeviceTrustError.alreadyPaired
        }
        var stored = device
        stored.accessToken = accessToken
        devices.append(stored)
        try saveDevices()
    }

    func rename(_ deviceId: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !trimmed.isEmpty, let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].displayName = trimmed
        try? saveDevices()
    }

    func updateLastSeen(_ deviceId: UUID) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[i].lastSeenAt = Date()
        try? saveDevices()
    }

    func revoke(_ deviceId: UUID) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices.remove(at: i)
        try? saveDevices()
    }

    func isTokenValid(publicDeviceId: String, token: String) -> Bool {
        guard let device = devices.first(where: { $0.publicDeviceId == publicDeviceId }),
              !device.accessToken.isEmpty else { return false }
        return device.accessToken == token
    }

    // MARK: - File persistence

    private func loadDevices() {
        guard let data = try? Data(contentsOf: devicesFileURL),
              let decoded = try? decoder.decode([TrustedMobileDevice].self, from: data)
        else { return }
        devices = decoded
    }

    private func saveDevices() throws {
        let data = try encoder.encode(devices)
        try fileManager.createDirectory(at: devicesFileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try data.write(to: devicesFileURL, options: .atomic)
    }

    private var devicesFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.orbit/mobileDevices.json")
    }
}

enum DeviceTrustError: LocalizedError {
    case alreadyPaired
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .alreadyPaired:
            return "This device is already paired."
        case .saveFailed:
            return "Failed to save device record."
        }
    }
}
