import Foundation

/// Centralises all version and build metadata for Orbit.
///
/// Sources (in priority order):
///   1. `CFBundleShortVersionString` / `CFBundleVersion` from Bundle at runtime
///   2. `GIT_COMMIT_HASH` key injected into Info.plist at build time (optional)
///   3. Runtime `git rev-parse --short HEAD` — works in dev, returns "–" in distribution
///
/// For distribution builds, add a Run Script build phase that injects the hash:
///   `GIT_COMMIT_HASH=$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null || echo "")`
///   Then reference `$(GIT_COMMIT_HASH)` in Info.plist.
struct AppVersion {

    // MARK: - Bundle values

    /// Marketing version string, e.g. "0.1.0-alpha.1"
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number, e.g. "1"
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: - Git hash

    /// Short git commit hash at build time.
    /// Returns "–" when not available (distribution builds without build-phase injection).
    static var gitHash: String {
        // 1. Build-time injected via Info.plist key
        if let injected = Bundle.main.infoDictionary?["GIT_COMMIT_HASH"] as? String,
           !injected.isEmpty, injected != "$(GIT_COMMIT_HASH)" {
            return injected
        }
        // 2. Runtime fallback for development builds (requires git CLI)
        return gitHashFromProcess() ?? "–"
    }

    // MARK: - Display strings

    /// "0.1.0-alpha.1 (1)"
    static var displayVersion: String {
        "\(marketing) (\(build))"
    }

    /// "0.1.0-alpha.1 (1) · abc1234" — or without hash when unavailable
    static var fullVersion: String {
        let hash = gitHash
        return hash == "–" ? displayVersion : "\(marketing) (\(build)) · \(hash)"
    }

    /// True when the version string contains a pre-release label (alpha/beta/rc).
    static var isPreRelease: Bool {
        let v = marketing.lowercased()
        return v.contains("alpha") || v.contains("beta") || v.contains("rc")
    }

    /// User-visible pre-release label, e.g. "Alpha". Empty for stable releases.
    static var preReleaseLabel: String {
        let v = marketing.lowercased()
        if v.contains("alpha") { return "Alpha" }
        if v.contains("beta")  { return "Beta" }
        if v.contains("rc")    { return "Release Candidate" }
        return ""
    }

    // MARK: - Private

    private static func gitHashFromProcess() -> String? {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: gitPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["rev-parse", "--short", "HEAD"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let hash = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.flatMap { $0.isEmpty ? nil : $0 }
    }
}
