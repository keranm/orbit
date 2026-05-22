import AppKit

// MARK: - Language detection

enum SyntaxLanguage: Equatable {
    case swift, objc, cpp, c, python, java, kotlin, rust, go
    case javaScript, typeScript, jsx, tsx
    case html, css, scss
    case json, yaml, toml, xml, markdown
    case shell, ruby, php, sql
    case unknown

    static func from(_ url: URL?) -> SyntaxLanguage {
        guard let url else { return .unknown }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        switch ext {
        case "swift":           return .swift
        case "m", "mm":         return .objc
        case "h", "hh", "hpp":  return name.hasPrefix("C") || name.hasPrefix("c") ? .cpp : .objc
        case "c", "cc", "cpp", "cxx", "c++": return .cpp
        case "py":              return .python
        case "java":            return .java
        case "kt", "kts":       return .kotlin
        case "rs":              return .rust
        case "go":              return .go
        case "js", "mjs":       return .javaScript
        case "ts":              return .typeScript
        case "jsx":             return .jsx
        case "tsx":             return .tsx
        case "html", "htm":     return .html
        case "css":             return .css
        case "scss", "sass":    return .scss
        case "json":            return .json
        case "yaml", "yml":     return .yaml
        case "toml":            return .toml
        case "xml", "plist":    return .xml
        case "md", "markdown":  return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        case "rb":              return .ruby
        case "php":             return .php
        case "sql":             return .sql
        default:
            if name == "Makefile" || name == "Dockerfile" || name == "Podfile" || name == "Package.swift" || name == "CMakeLists.txt" {
                return .shell
            }
            return .unknown
        }
    }
}

// MARK: - Highlighter

struct SyntaxHighlighter {
    private static let keywordColor = NSColor(red: 0.76, green: 0.22, blue: 0.56, alpha: 1)
    private static let stringColor = NSColor(red: 0.80, green: 0.26, blue: 0.15, alpha: 1)
    private static let commentColor = NSColor(red: 0.27, green: 0.55, blue: 0.14, alpha: 1)
    private static let numberColor = NSColor(red: 0.11, green: 0.40, blue: 0.71, alpha: 1)
    private static let typeColor = NSColor(red: 0.30, green: 0.40, blue: 0.60, alpha: 1)

    static func apply(to textStorage: NSTextStorage, language: SyntaxLanguage) {
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor], range: full)

        guard language != .unknown else { return }

        let string = textStorage.string as NSString
        let stringRanges = collectStringRanges(string, language: language)

        highlightKeywords(textStorage, string: string, language: language, stringRanges: stringRanges)
        highlightStrings(textStorage, string: string, language: language, knownRanges: stringRanges)
        highlightComments(textStorage, string: string, language: language, stringRanges: stringRanges)
        highlightNumbers(textStorage, string: string, language: language, stringRanges: stringRanges)
        highlightTypes(textStorage, string: string, language: language, stringRanges: stringRanges)
    }

    // MARK: - String range collection

    private static func collectStringRanges(_ string: NSString, language: SyntaxLanguage) -> [NSRange] {
        var ranges: [NSRange] = []
        let patterns: [String]
        let singleQuote = #"(?<![a-zA-Z])'[^']*'(?![a-zA-Z])"#
        switch language {
        case .html, .jsx, .tsx:
            patterns = [#""[^"]*""#, singleQuote, #"`[^`]*`"#]
        default:
            patterns = [#""[^"]*""#, singleQuote, #"`[^`]*`"#]
        }
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                if let r = match?.range { ranges.append(r) }
            }
        }
        return ranges
    }

    private static func isInRanges(_ ranges: [NSRange], _ loc: Int) -> Bool {
        ranges.contains { $0.contains(loc) }
    }

    // MARK: - Keywords

    private static func highlightKeywords(_ storage: NSTextStorage, string: NSString, language: SyntaxLanguage, stringRanges: [NSRange]) {
        let keywords = keywordSets[language, default: []]
        for kw in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                guard let r = match?.range, !isInRanges(stringRanges, r.location) else { return }
                storage.addAttribute(.foregroundColor, value: keywordColor, range: r)
            }
        }
    }

    // MARK: - Strings

    private static func highlightStrings(_ storage: NSTextStorage, string: NSString, language: SyntaxLanguage, knownRanges: [NSRange]) {
        for r in knownRanges {
            storage.addAttribute(.foregroundColor, value: stringColor, range: r)
        }
    }

    // MARK: - Comments

    private static func highlightComments(_ storage: NSTextStorage, string: NSString, language: SyntaxLanguage, stringRanges: [NSRange]) {
        let lineComment: String?
        let blockComment: (String, String)?

        switch language {
        case .swift, .java, .kotlin, .rust, .go, .typeScript, .javaScript, .jsx, .tsx, .c, .cpp, .objc, .css, .scss:
            lineComment = "//"
            blockComment = ("/*", "*/")
        case .python, .shell, .ruby, .yaml, .toml, .sql:
            lineComment = "#"
            blockComment = nil
        case .html, .jsx, .tsx:
            lineComment = nil
            blockComment = ("<!--", "-->")
        case .php:
            lineComment = "//"
            blockComment = ("/*", "*/")
        default:
            lineComment = nil
            blockComment = nil
        }

        if let lc = lineComment {
            let pattern = NSRegularExpression.escapedPattern(for: lc)
            guard let regex = try? NSRegularExpression(pattern: "\(pattern).*") else { return }
            regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                guard let r = match?.range, !isInRanges(stringRanges, r.location) else { return }
                storage.addAttribute(.foregroundColor, value: commentColor, range: r)
            }
        }

        if let (open, close) = blockComment {
            guard let regex = try? NSRegularExpression(pattern: "\(NSRegularExpression.escapedPattern(for: open)).*?\(NSRegularExpression.escapedPattern(for: close))", options: [.dotMatchesLineSeparators]) else { return }
            regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                guard let r = match?.range else { return }
                var isInside = false
                for sr in stringRanges where r.location >= sr.location && NSMaxRange(r) <= NSMaxRange(sr) {
                    isInside = true; break
                }
                if !isInside {
                    storage.addAttribute(.foregroundColor, value: commentColor, range: r)
                }
            }
        }
    }

    // MARK: - Numbers

    private static func highlightNumbers(_ storage: NSTextStorage, string: NSString, language: SyntaxLanguage, stringRanges: [NSRange]) {
        guard let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b") else { return }
        regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
            guard let r = match?.range, !isInRanges(stringRanges, r.location) else { return }
            storage.addAttribute(.foregroundColor, value: numberColor, range: r)
        }
    }

    // MARK: - Types

    private static func highlightTypes(_ storage: NSTextStorage, string: NSString, language: SyntaxLanguage, stringRanges: [NSRange]) {
        let patterns: [String]
        switch language {
        case .swift:
            patterns = ["\\b[A-Z][A-Za-z0-9]+\\b"]
        case .java, .kotlin, .rust, .go, .cpp, .c, .objc, .typeScript, .javaScript:
            patterns = ["\\b[A-Z][A-Za-z0-9]+\\b"]
        default:
            patterns = []
        }
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            regex.enumerateMatches(in: string as String, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                guard let r = match?.range else { return }
                let word = string.substring(with: r)
                let reserved: Set<String> = ["I", "UI", "ID", "URL", "URLs", "UUID", "JSON", "XML", "HTML", "PDF", "UIView", "UIViewController"]
                if reserved.contains(word) || isInRanges(stringRanges, r.location) { return }
                storage.addAttribute(.foregroundColor, value: typeColor, range: r)
            }
        }
    }

    // MARK: - Keyword sets

    private static let keywordSets: [SyntaxLanguage: [String]] = [
        .swift:      ["import", "let", "var", "func", "class", "struct", "enum", "protocol", "extension", "return", "if", "else", "guard", "for", "in", "while", "switch", "case", "default", "break", "continue", "throw", "throws", "rethrows", "try", "catch", "do", "where", "as", "is", "self", "super", "nil", "true", "false", "init", "deinit", "lazy", "weak", "unowned", "static", "mutating", "nonmutating", "indirect", "open", "public", "internal", "fileprivate", "private", "override", "required", "convenience", "dynamic", "final", "async", "await", "actor", "nonisolated", "isolated", "macro", "package", "any", "some", "each"],
        .python:     ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "in", "while", "break", "continue", "try", "except", "finally", "raise", "with", "as", "pass", "yield", "lambda", "global", "nonlocal", "assert", "del", "and", "or", "not", "is", "None", "True", "False", "self", "async", "await", "match", "case", "type"],
        .java:       ["import", "package", "class", "interface", "enum", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "synchronized", "volatile", "transient", "native", "strictfp", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "new", "this", "super", "try", "catch", "finally", "throw", "throws", "null", "true", "false", "var", "void", "int", "long", "float", "double", "boolean", "char", "byte", "short", "instanceof", "default", "record", "sealed", "permits", "yield"],
        .kotlin:     ["fun", "val", "var", "class", "object", "interface", "enum", "sealed", "data", "open", "abstract", "override", "private", "public", "internal", "protected", "return", "if", "else", "for", "while", "do", "when", "try", "catch", "finally", "throw", "null", "true", "false", "this", "super", "import", "package", "as", "in", "is", "!is", "as?", "suspend", "inline", "infix", "operator", "tailrec", "reified", "crossinline", "noinline", "const", "lateinit", "init", "companion", "annotation", "inner", "sealed", "data", "enum class", "fun interface"],
        .rust:       ["fn", "let", "mut", "const", "static", "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate", "super", "self", "return", "if", "else", "for", "in", "while", "loop", "match", "break", "continue", "true", "false", "Some", "None", "Ok", "Err", "unwrap", "as", "ref", "move", "async", "await", "unsafe", "extern", "macro_rules", "where", "type", "dyn", "impl"],
        .go:         ["func", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "return", "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "select", "fallthrough", "package", "import", "nil", "true", "false", "make", "new", "append", "len", "cap", "close", "delete", "panic", "recover", "string", "int", "int8", "int16", "int32", "int64", "uint", "float32", "float64", "bool", "byte", "rune", "error"],
        .javaScript: ["let", "var", "const", "function", "class", "extends", "import", "export", "default", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "new", "this", "super", "try", "catch", "finally", "throw", "typeof", "instanceof", "null", "undefined", "true", "false", "async", "await", "yield", "of", "in", "from", "as", "delete", "void", "typeof", "arguments"],
        .typeScript: ["let", "var", "const", "function", "class", "extends", "implements", "import", "export", "default", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "new", "this", "super", "try", "catch", "finally", "throw", "typeof", "instanceof", "null", "undefined", "true", "false", "async", "await", "yield", "of", "in", "from", "as", "type", "interface", "enum", "namespace", "module", "declare", "readonly", "public", "private", "protected", "abstract", "static", "keyof", "infer", "satisfies", "using", "any", "never", "unknown", "void", "string", "number", "boolean", "symbol", "bigint"],
        .html:       ["html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button", "select", "option", "textarea", "h1", "h2", "h3", "h4", "h5", "h6", "meta", "link", "script", "style", "title", "header", "footer", "nav", "section", "article", "main", "aside", "figure", "figcaption", "video", "audio", "canvas"],
        .css:        ["color", "background", "background-color", "margin", "padding", "border", "font", "font-size", "font-family", "font-weight", "display", "position", "top", "left", "right", "bottom", "width", "height", "max-width", "min-width", "overflow", "text-align", "align-items", "justify-content", "flex", "grid", "opacity", "z-index", "transform", "transition", "animation", "box-shadow", "!important"],
        .json:       ["true", "false", "null"],
        .yaml:       ["true", "false", "yes", "no", "null", "on", "off"],
        .shell:      ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "return", "exit", "export", "local", "source", "echo", "printf", "read", "set", "unset", "function", "select", "time", "trap", "declare", "typeset"],
        .ruby:       ["def", "class", "module", "end", "if", "elsif", "else", "unless", "case", "when", "return", "true", "false", "nil", "self", "super", "yield", "require", "include", "extend", "attr_reader", "attr_writer", "attr_accessor", "begin", "rescue", "ensure", "raise", "throw", "catch", "new", "initialize", "lambda", "proc", "block_given?"],
        .php:        ["echo", "return", "if", "else", "elseif", "for", "foreach", "while", "switch", "case", "break", "continue", "function", "class", "interface", "trait", "namespace", "use", "require", "include", "require_once", "include_once", "public", "private", "protected", "static", "final", "abstract", "new", "this", "parent", "self", "true", "false", "null", "array", "string", "int", "float", "bool", "void", "?string", "?int", "readonly", "match", "enum", "mixed", "never", "throw", "try", "catch", "finally", "declare", "strict_types"],
        .sql:        ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS", "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK", "UNIQUE", "CASCADE", "SERIAL", "VARCHAR", "INTEGER", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP"],
    ]
}
