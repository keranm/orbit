import Foundation

/// Reads emails from Mail.app via AppleScript.
struct MailDataSource {

    /// Returns a formatted string of matching emails for use in agent context.
    static func fetch(_ config: MailStepConfig) async throws -> String {
        let script = buildScript(config)
        let result = try await runAppleScript(script)
        return result.isEmpty ? "No emails found matching your criteria." : result
    }

    // MARK: - AppleScript builder

    private static func buildScript(_ config: MailStepConfig) -> String {
        let cutoff = Date().addingTimeInterval(-Double(config.dateRangeHours) * 3600)
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)

        var conditions: [String] = []
        conditions.append("date received of msg >= date \"\(cutoffStr)\"")
        if config.unreadOnly {
            conditions.append("read status of msg is false")
        }
        if !config.fromFilter.isEmpty {
            let escaped = config.fromFilter.replacingOccurrences(of: "\"", with: "\\\"")
            conditions.append("sender of msg contains \"\(escaped)\"")
        }
        if !config.subjectFilter.isEmpty {
            let escaped = config.subjectFilter.replacingOccurrences(of: "\"", with: "\\\"")
            conditions.append("subject of msg contains \"\(escaped)\"")
        }

        let whereClause = conditions.joined(separator: " and ")
        let limit = config.maxItems

        return """
tell application "Mail"
    set output to ""
    set msgCount to 0
    repeat with acct in accounts
        repeat with mbox in mailboxes of acct
            set msgs to (messages of mbox whose \(whereClause))
            repeat with msg in msgs
                if msgCount < \(limit) then
                    set msgDate to date received of msg
                    set output to output & "From: " & sender of msg & return
                    set output to output & "Subject: " & subject of msg & return
                    set output to output & "Date: " & (msgDate as string) & return
                    try
                        set bodyText to content of msg
                        if length of bodyText > 500 then
                            set bodyText to (text 1 thru 500 of bodyText) & "..."
                        end if
                        set output to output & "Preview: " & bodyText & return
                    end try
                    set output to output & "---" & return
                    set msgCount to msgCount + 1
                end if
            end repeat
        end repeat
    end repeat
    if output is "" then
        return "No emails found matching your criteria."
    end if
    return output
end tell
"""
    }

    // MARK: - AppleScript runner

    private static func runAppleScript(_ script: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let scriptObj = NSAppleScript(source: script) else {
                throw DataSourceError.scriptCompilationFailed
            }
            let result = scriptObj.executeAndReturnError(&error)
            if let err = error {
                let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
                throw DataSourceError.scriptExecutionFailed(msg)
            }
            return result.stringValue ?? ""
        }.value
    }
}
