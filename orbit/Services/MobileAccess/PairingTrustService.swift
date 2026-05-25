import Foundation

@MainActor
final class PairingTrustService {
    private(set) var activeSession: PairingSession?
    private let trustStore: DeviceTrustStore

    private static let codeLifetime: TimeInterval = 180
    private static let maxAttempts = 5

    init(trustStore: DeviceTrustStore) {
        self.trustStore = trustStore
    }

    // MARK: - Session management

    func generateSession(macDisplayName: String) -> PairingSession {
        let sessionId = UUID()
        let rawCode = String(Int.random(in: 100_000...999_999))
        let displayCode = String(rawCode.prefix(3)) + " " + String(rawCode.suffix(3))
        let expiresAt = Date().addingTimeInterval(Self.codeLifetime)
        let encodedName = macDisplayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? macDisplayName
        let qrPayload = "orbit://pair?session=\(sessionId.uuidString)&code=\(rawCode)&name=\(encodedName)"

        let session = PairingSession(
            sessionId: sessionId,
            code: displayCode,
            expiresAt: expiresAt,
            qrPayload: qrPayload
        )
        activeSession = session
        return session
    }

    func validateCode(sessionId: UUID, code: String) -> PairingValidationResult {
        guard let session = activeSession, session.sessionId == sessionId else {
            return .noActiveSession
        }

        if session.expiresAt < Date() {
            return .expired
        }

        if session.attemptCount >= Self.maxAttempts {
            return .tooManyAttempts
        }

        let cleanInput = code.replacingOccurrences(of: " ", with: "")
        let cleanExpected = session.code.replacingOccurrences(of: " ", with: "")

        guard cleanInput == cleanExpected else {
            activeSession?.attemptCount += 1
            return .invalidCode
        }

        return .valid
    }

    func completePairing(sessionId: UUID, deviceInfo: PairingDeviceInfo) throws -> (TrustedMobileDevice, String) {
        guard let session = activeSession, session.sessionId == sessionId else {
            throw PairingError.noActiveSession
        }

        let validation = validateCode(sessionId: sessionId, code: deviceInfo.code)
        switch validation {
        case .valid:
            break
        case .expired:
            throw PairingError.expired
        case .invalidCode:
            throw PairingError.invalidCode
        case .tooManyAttempts:
            throw PairingError.tooManyAttempts
        case .noActiveSession:
            throw PairingError.noActiveSession
        }

        // Consume the session (one-time use)
        activeSession = nil

        let deviceId = UUID()
        let accessToken = UUID().uuidString + UUID().uuidString
        let device = TrustedMobileDevice(
            id: deviceId,
            displayName: deviceInfo.deviceName,
            deviceType: deviceInfo.deviceType,
            publicDeviceId: deviceInfo.publicDeviceId,
            pairedAt: Date(),
            lastSeenAt: Date(),
            isConnected: false
        )

        try trustStore.add(device, accessToken: accessToken)
        return (device, accessToken)
    }

    func cancelSession() {
        activeSession = nil
    }

    // MARK: - Cleanup

    func clearExpiredSessions() {
        guard let session = activeSession, session.expiresAt < Date() else { return }
        activeSession = nil
    }
}

enum PairingError: LocalizedError {
    case noActiveSession
    case expired
    case invalidCode
    case tooManyAttempts
    case deviceAlreadyPaired

    var errorDescription: String? {
        switch self {
        case .noActiveSession:    return "No pairing session is active."
        case .expired:            return "The pairing code expired."
        case .invalidCode:        return "The pairing code is incorrect."
        case .tooManyAttempts:    return "Too many incorrect attempts."
        case .deviceAlreadyPaired: return "This device is already paired."
        }
    }
}
