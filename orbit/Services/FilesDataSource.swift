import Foundation

/// Reads file contents from a local folder.
struct FilesDataSource {

    static func fetch(_ config: FilesStepConfig) async throws -> String {
        guard !config.folderPath.isEmpty else {
            throw DataSourceError.missingConfiguration("No folder selected for the Read Files step.")
        }

        let url = URL(fileURLWithPath: config.folderPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DataSourceError.missingConfiguration("Folder not found: \(config.folderPath)")
        }

        let files = try collectFiles(at: url, config: config)
        if files.isEmpty {
            return "No readable files found in \(url.lastPathComponent)."
        }

        var sections: [String] = ["Folder: \(url.lastPathComponent) (\(files.count) files)\n"]
        for fileURL in files {
            let name = fileURL.lastPathComponent
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let preview = String(content.prefix(1000))
                let suffix = content.count > 1000 ? "… (\(content.count) chars total)" : ""
                sections.append("### \(name)\n\(preview)\(suffix)")
            } else {
                sections.append("### \(name)\n[Binary file — cannot read as text]")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func collectFiles(at url: URL, config: FilesStepConfig) throws -> [URL] {
        let fm = FileManager.default
        let allowedExtensions = Set(config.fileTypes.map { $0.lowercased() })

        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !config.recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard results.count < config.maxFiles else { break }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            if !allowedExtensions.isEmpty && !allowedExtensions.contains(ext) { continue }
            if allowedExtensions.isEmpty && !isTextExtension(ext) { continue }

            results.append(fileURL)
        }
        return results
    }

    private static func isTextExtension(_ ext: String) -> Bool {
        let textExts: Set<String> = [
            "txt", "md", "markdown", "rtf", "csv", "json", "xml", "html", "htm",
            "swift", "py", "js", "ts", "css", "sh", "rb", "go", "rs", "java",
            "c", "cpp", "h", "m", "yaml", "yml", "toml", "ini", "conf", "log",
            "tex", "rst", "org"
        ]
        return textExts.contains(ext)
    }
}
