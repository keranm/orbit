import Foundation

/// Fetches and parses RSS feeds.
struct RSSDataSource {

    static func fetch(_ config: RSSStepConfig) async throws -> String {
        guard !config.feedURLs.isEmpty else {
            throw DataSourceError.missingConfiguration("No RSS feeds configured. Add feed URLs in the step settings.")
        }

        var sections: [String] = []
        for urlString in config.feedURLs {
            guard let url = URL(string: urlString) else { continue }
            do {
                let items = try await fetchFeed(url: url, maxItems: config.maxItemsPerFeed, includeContent: config.includeContent)
                if !items.isEmpty {
                    let feedName = url.host ?? urlString
                    sections.append("## \(feedName)\n" + items.joined(separator: "\n\n"))
                }
            } catch {
                sections.append("## \(urlString)\n[Could not load feed: \(error.localizedDescription)]")
            }
        }

        return sections.isEmpty ? "No feed items found." : sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Feed fetching

    private static func fetchFeed(url: URL, maxItems: Int, includeContent: Bool) async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = RSSParser(data: data, maxItems: maxItems, includeContent: includeContent)
        return try parser.parse()
    }
}

// MARK: - XML parser

private final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let maxItems: Int
    private let includeContent: Bool

    private var items: [String] = []
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentContent = ""
    private var currentElement = ""
    private var insideItem = false
    private var parseError: Error?

    init(data: Data, maxItems: Int, includeContent: Bool) {
        self.data = data
        self.maxItems = maxItems
        self.includeContent = includeContent
    }

    func parse() throws -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error = parseError { throw error }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentContent = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "description", "summary": currentDescription += string
        case "pubDate", "published":   currentPubDate += string
        case "content", "content:encoded": currentContent += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard insideItem, (elementName == "item" || elementName == "entry") else { return }
        guard items.count < maxItems else { parser.abortParsing(); return }

        var parts: [String] = []
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append("**\(title)**") }
        if !currentPubDate.isEmpty { parts.append("Published: \(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))") }

        let body = includeContent && !currentContent.isEmpty ? currentContent : currentDescription
        let cleaned = stripHTML(body).trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            let preview = String(cleaned.prefix(300))
            parts.append(preview + (cleaned.count > 300 ? "…" : ""))
        }

        if !parts.isEmpty { items.append(parts.joined(separator: "\n")) }
        insideItem = false
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        // Simple tag stripping — avoids NSAttributedString on background threads
        var result = html
        while let open = result.range(of: "<"), let close = result.range(of: ">", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound...close.upperBound)
        }
        _ = data
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
