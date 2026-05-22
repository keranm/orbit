import Foundation

// MARK: - Access lifecycle

enum MobileAccessState: Equatable {
    case disabled
    case starting
    case enabled
    case stopping
    case unavailable(MobileAccessUnavailableReason)
    case error(String)
}

enum MobileAccessUnavailableReason: Equatable {
    case runtimeNotReady
    case noWifi
    case localNetworkPermissionMissing
    case apiServerFailed
}

// MARK: - Pairing

struct PairingSession {
    let sessionId: UUID
    let code: String
    let expiresAt: Date
    let qrPayload: String
    var attemptCount: Int = 0
}

// MARK: - Devices

struct TrustedMobileDevice: Identifiable, Codable {
    let id: UUID
    var displayName: String
    let deviceType: String
    let publicDeviceId: String
    let pairedAt: Date
    var lastSeenAt: Date?
    var isConnected: Bool = false
    /// Bearer token used to authenticate requests from this device.
    /// Stored in the device JSON file rather than the keychain to avoid
    /// per-build macOS keychain ACL prompts.
    var accessToken: String = ""
}

// MARK: - Models exposed to mobile

enum MobileModelSource: String, Codable {
    case local
    case mesh
}

struct MobileModelSummary: Identifiable, Codable {
    let id: String
    let name: String
    let sizeLabel: String?
    let isDefault: Bool
    let source: MobileModelSource
    let nodeCount: Int?     // mesh only: number of peer nodes serving this model
    let meshStatus: String? // mesh only: "warm", "cold", etc.
}

// MARK: - Settings

struct MobileAccessSettings: Codable {
    var isEnabled: Bool = false
    var macDisplayName: String
    var allowPairing: Bool = true
}

// MARK: - Chat

struct ChatMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Pairing validation

enum PairingValidationResult {
    case valid
    case expired
    case invalidCode
    case tooManyAttempts
    case noActiveSession
}

struct PairingDeviceInfo {
    let sessionId: UUID
    let code: String
    let deviceName: String
    let deviceType: String
    let publicDeviceId: String
}

// MARK: - Chat errors

enum MobileChatError: LocalizedError {
    case modelUnavailable
    case runtimeUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:  return "That model isn't available on this Mac right now."
        case .runtimeUnavailable: return "Orbit isn't running. Open Orbit to continue."
        }
    }
}
