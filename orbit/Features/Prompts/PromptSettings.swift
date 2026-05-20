import Foundation
import Darwin

/// Persisted prompt configuration and system message assembly.
/// All values are stored in UserDefaults under namespaced keys.
/// Read from ChatViewModel on every send — no global singleton needed.
struct PromptSettings {

    // MARK: - UserDefaults keys

    static let defaultPromptKey       = "promptSettings.defaultPrompt"
    static let userPreferencesKey     = "promptSettings.userPreferences"
    static let includeLocalContextKey = "promptSettings.includeLocalContext"

    // MARK: - Factory defaults

    static let defaultPromptText = """
    You are Orbit, a helpful, thoughtful, and privacy-first AI assistant.
    Aim to be accurate, clear, and concise.
    Ask clarifying questions when needed.
    Use plain language and practical examples.
    Respect my privacy and keep everything local.
    Adapt your answers to my context.
    """

    static let defaultPreferencesText = ""

    static let defaultIncludeLocalContext = true

    // MARK: - Persistence helpers

    static func readDefaultPrompt() -> String {
        UserDefaults.standard.string(forKey: defaultPromptKey) ?? defaultPromptText
    }

    static func readUserPreferences() -> String {
        UserDefaults.standard.string(forKey: userPreferencesKey) ?? defaultPreferencesText
    }

    static func readIncludeLocalContext() -> Bool {
        if UserDefaults.standard.object(forKey: includeLocalContextKey) == nil {
            return defaultIncludeLocalContext
        }
        return UserDefaults.standard.bool(forKey: includeLocalContextKey)
    }

    static func resetToDefaults() {
        UserDefaults.standard.set(defaultPromptText, forKey: defaultPromptKey)
        UserDefaults.standard.set(defaultPreferencesText, forKey: userPreferencesKey)
        UserDefaults.standard.set(defaultIncludeLocalContext, forKey: includeLocalContextKey)
    }

    // MARK: - System message assembly

    /// Builds the full system message injected before every conversation.
    static func buildSystemMessage() -> String {
        let prompt = readDefaultPrompt().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefs  = readUserPreferences().trimmingCharacters(in: .whitespacesAndNewlines)
        let context = readIncludeLocalContext()

        var parts: [String] = []
        if !prompt.isEmpty { parts.append(prompt) }
        if !prefs.isEmpty  { parts.append("About me:\n\(prefs)") }
        if context         { parts.append(buildContextBlock()) }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Local context

    /// Returns a formatted context block describing the user's device environment.
    static func buildContextBlock() -> String {
        var lines = ["My current context:"]
        lines.append("- Location: \(locationFromTimezone())")
        lines.append("- Timezone: \(TimeZone.current.identifier)")
        lines.append("- Date & time: \(formattedDateTime())")
        lines.append("- Device: \(deviceModel())")
        lines.append("- Language: \(languageDescription())")
        return lines.joined(separator: "\n")
    }

    // MARK: - Context item values (used by PromptsView for live preview)

    static func locationFromTimezone() -> String {
        let id = TimeZone.current.identifier         // e.g. "Australia/Adelaide"
        let parts = id.components(separatedBy: "/")
        guard parts.count >= 2,
              let city = parts.last,
              let region = parts.first else {
            return TimeZone.current.abbreviation() ?? id
        }
        let cityName = city.replacingOccurrences(of: "_", with: " ")
        return "\(cityName), \(region)"
    }

    static func formattedDateTime() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .short
        return fmt.string(from: Date())
    }

    static func deviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return ProcessInfo.processInfo.hostName }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let raw = String(cString: model)   // e.g. "MacBookPro18,3"
        return humanReadableModel(raw)
    }

    static func languageDescription() -> String {
        let locale = Locale.current
        if let langCode = locale.language.languageCode?.identifier,
           let regionCode = locale.region?.identifier {
            // e.g. "en (AU)"
            return "\(langCode.uppercased()) (\(regionCode))"
        }
        return locale.identifier
    }

    // MARK: - Private helpers

    private static func humanReadableModel(_ identifier: String) -> String {
        // Map common sysctl model identifiers to readable names.
        // Fallback to the raw identifier when unknown.
        let map: [String: String] = [
            // MacBook Air
            "MacBookAir10,1":  "MacBook Air (M1)",
            "Mac14,2":         "MacBook Air (M2)",
            "Mac15,12":        "MacBook Air (M3)",
            // MacBook Pro 13-inch
            "MacBookPro17,1":  "MacBook Pro 13‑inch (M1)",
            "MacBookPro18,1":  "MacBook Pro 16‑inch (M1 Pro)",
            "MacBookPro18,2":  "MacBook Pro 16‑inch (M1 Max)",
            "MacBookPro18,3":  "MacBook Pro 14‑inch (M1 Pro)",
            "MacBookPro18,4":  "MacBook Pro 14‑inch (M1 Max)",
            "Mac14,5":         "MacBook Pro 14‑inch (M2 Pro)",
            "Mac14,6":         "MacBook Pro 16‑inch (M2 Pro)",
            "Mac14,9":         "MacBook Pro 14‑inch (M2 Pro)",
            "Mac14,10":        "MacBook Pro 14‑inch (M2 Max)",
            "Mac15,6":         "MacBook Pro 14‑inch (M3 Pro)",
            "Mac15,7":         "MacBook Pro 14‑inch (M3 Max)",
            "Mac15,8":         "MacBook Pro 16‑inch (M3 Pro)",
            "Mac15,9":         "MacBook Pro 16‑inch (M3 Max)",
            // Mac mini
            "Mac14,3":         "Mac mini (M2)",
            "Mac14,12":        "Mac mini (M2 Pro)",
            "Mac16,10":        "Mac mini (M4)",
            // Mac Studio / Pro
            "Mac13,1":         "Mac Studio (M1 Max)",
            "Mac13,2":         "Mac Studio (M1 Ultra)",
            "Mac14,13":        "Mac Studio (M2 Max)",
            "Mac14,14":        "Mac Studio (M2 Ultra)",
            // iMac
            "Mac13,4":         "iMac 24‑inch (M1)",
            "Mac15,4":         "iMac 24‑inch (M3)",
        ]
        return map[identifier] ?? identifier
    }
}
