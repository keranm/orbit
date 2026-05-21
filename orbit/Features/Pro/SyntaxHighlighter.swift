import Cocoa

// MARK: - Language

enum SyntaxLanguage: String {
    case swift, objc, c, cpp, python, javaScript, typeScript, java
    case html, css, scss
    case yaml, toml, json, xml, markdown
    case shell, ruby, php, rust, go, kotlin
    case unknown

    static func from(_ url: URL?) -> SyntaxLanguage {
        guard let url else { return .unknown }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        switch ext {
        case "swift": return .swift
        case "m", "mm": return .objc
        case "h", "hh", "hpp": return .cpp
        case "c": return .c
        case "cpp", "cc", "cxx": return .cpp
        case "py": return .python
        case "js", "jsx": return .javaScript
        case "ts", "tsx": return .typeScript
        case "java": return .java
        case "html", "htm": return .html
        case "css": return .css
        case "scss", "sass": return .scss
        case "yml", "yaml": return .yaml
        case "toml": return .toml
        case "json": return .json
        case "xml", "plist", "xib", "storyboard", "strings", "entitlements": return .xml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        case "rb": return .ruby
        case "php": return .php
        case "rs": return .rust
        case "go": return .go
        case "kt", "kts": return .kotlin
        default:
            if name == "Package.swift" { return .swift }
            if name == "Makefile" || name == "CMakeLists.txt" || name == "Dockerfile" || name == "Justfile" {
                return .shell
            }
            return .unknown
        }
    }
}

// MARK: - Colors

private extension NSColor {
    static let hKeyword      = NSColor.systemBlue
    static let hString       = NSColor.systemRed
    static let hComment      = NSColor.systemGreen
    static let hNumber       = NSColor.systemOrange
    static let hType         = NSColor.systemPurple
    static let hAttribute    = NSColor.systemPink
    static let hPreprocessor = NSColor.systemBrown
    static let hConstant     = NSColor.systemTeal
}

// MARK: - Rule

private struct HighlightRule {
    let pattern: NSRegularExpression
    let color: NSColor
    let extraAttributes: [NSAttributedString.Key: Any]
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    /// Apply syntax highlighting to a text storage.
    /// Called from the text view delegate after edits.
    static func apply(to textStorage: NSTextStorage, language: SyntaxLanguage, baseFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        // Always set default color and font so text is visible
        textStorage.addAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: fullRange)

        guard language != .unknown else { return }

        // Collect string ranges so comments can skip them
        let stringRanges_ = stringRanges(in: textStorage)

        let rules = rulesForLanguage(language)
        var contentRules: [HighlightRule] = []
        var commentRules: [HighlightRule] = []
        var stringRules: [HighlightRule] = []
        for rule in rules {
            if rule.color == .hComment { commentRules.append(rule) }
            else if rule.color == .hString { stringRules.append(rule) }
            else { contentRules.append(rule) }
        }

        let str = textStorage.string

        for rule in contentRules {
            rule.pattern.enumerateMatches(in: str, range: fullRange) { m, _, _ in
                guard let m else { return }
                textStorage.addAttributes([.foregroundColor: rule.color], range: m.range)
            }
        }

        for rule in commentRules {
            rule.pattern.enumerateMatches(in: str, range: fullRange) { m, _, _ in
                guard let m else { return }
                guard !stringRanges_.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return }
                textStorage.addAttributes([.foregroundColor: rule.color], range: m.range)
            }
        }

        for rule in stringRules {
            rule.pattern.enumerateMatches(in: str, range: fullRange) { m, _, _ in
                guard let m else { return }
                textStorage.addAttributes([.foregroundColor: rule.color], range: m.range)
            }
        }
    }

    private static func stringRanges(in ts: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        let doubleString = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        doubleString.enumerateMatches(in: ts.string, range: NSRange(location: 0, length: ts.length)) { m, _, _ in
            guard let m else { return }; ranges.append(m.range)
        }
        let singleString = try! NSRegularExpression(pattern: #"'(?:[^'\\]|\\.)*'"#)
        singleString.enumerateMatches(in: ts.string, range: NSRange(location: 0, length: ts.length)) { m, _, _ in
            guard let m else { return }; ranges.append(m.range)
        }
        return ranges
    }

    // MARK: - Rule definitions

    private static func rulesForLanguage(_ language: SyntaxLanguage) -> [HighlightRule] {
        var rules: [HighlightRule] = []
        rules.append(contentsOf: stringRules(for: language))
        rules.append(contentsOf: commentRules(for: language))
        rules.append(contentsOf: numberRules())
        rules.append(contentsOf: keywordRules(for: language))
        rules.append(contentsOf: typeRules())
        return rules
    }

    private static func stringRules(for language: SyntaxLanguage) -> [HighlightRule] {
        let double = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        let singleQuoteLanguages: Set<SyntaxLanguage> = [
            .swift, .objc, .c, .cpp, .python, .javaScript, .typeScript,
            .java, .rust, .go, .ruby, .php, .shell, .kotlin,
            .yaml, .toml,
        ]
        var rules: [HighlightRule] = [
            HighlightRule(pattern: double, color: .hString, extraAttributes: [:]),
        ]
        if singleQuoteLanguages.contains(language) {
            let single = try! NSRegularExpression(pattern: #"'(?:[^'\\]|\\.)*'"#)
            rules.append(HighlightRule(pattern: single, color: .hString, extraAttributes: [:]))
        }
        return rules
    }

    private static func commentRules(for language: SyntaxLanguage) -> [HighlightRule] {
        let doubleSlash = try! NSRegularExpression(pattern: "//.*")
        let block = try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)
        let hash = try! NSRegularExpression(pattern: "#.*")
        let hashLanguages: Set<SyntaxLanguage> = [.python, .ruby, .shell, .yaml, .toml, .scss]
        var rules: [HighlightRule] = [
            HighlightRule(pattern: doubleSlash, color: .hComment, extraAttributes: [:]),
            HighlightRule(pattern: block, color: .hComment, extraAttributes: [:]),
        ]
        if hashLanguages.contains(language) {
            rules.append(HighlightRule(pattern: hash, color: .hComment, extraAttributes: [:]))
        }
        return rules
    }

    private static func numberRules() -> [HighlightRule] {
        let hex = try! NSRegularExpression(pattern: #"\b0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]+)?[pP][+-]?\d+|\b0[xX][0-9a-fA-F]+\b"#)
        let bin = try! NSRegularExpression(pattern: #"\b0[bB][01]+\b"#)
        let oct = try! NSRegularExpression(pattern: #"\b0[oO][0-7]+\b"#)
        let dec = try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#)
        return [
            HighlightRule(pattern: hex, color: .hNumber, extraAttributes: [:]),
            HighlightRule(pattern: bin, color: .hNumber, extraAttributes: [:]),
            HighlightRule(pattern: oct, color: .hNumber, extraAttributes: [:]),
            HighlightRule(pattern: dec, color: .hNumber, extraAttributes: [:]),
        ]
    }

    private static func typeRules() -> [HighlightRule] {
        let types = try! NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z0-9_]*(?:\.[A-Z][a-zA-Z0-9_]*)*\b"#)
        return [HighlightRule(pattern: types, color: .hType, extraAttributes: [:])]
    }

    private static func keywordRules(for language: SyntaxLanguage) -> [HighlightRule] {
        switch language {
        case .swift:
            return [HighlightRule(pattern: words(#"(?:let|var|func|class|struct|enum|protocol|extension|import|return|if|else|for|while|switch|case|default|break|continue|guard|defer|throws|rethrows|async|await|actor|nonisolated|mutating|init|self|Self|nil|true|false|in|where|as|is|try|catch|do|repeat|public|private|internal|fileprivate|open|static|final|override|lazy|weak|unowned|optional|required|convenience|dynamic|indirect|associatedtype|typealias|subscript|get|set|willSet|didSet|Any|some|any|precedencegroup|associativity|left|right|none|higherThan|lowerThan|willSet|didSet|nonmutating|infix|prefix|postfix)"#), color: .hKeyword, extraAttributes: [:])]

        case .python:
            return [HighlightRule(pattern: words(#"(?:def|class|return|if|elif|else|for|while|try|except|finally|with|as|import|from|pass|break|continue|and|or|not|is|in|None|True|False|raise|yield|lambda|self|async|await|global|nonlocal|del|assert|print|range|len|super|property|staticmethod|classmethod)"#), color: .hKeyword, extraAttributes: [:])]

        case .javaScript, .typeScript:
            return [HighlightRule(pattern: words(#"(?:function|const|let|var|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|new|this|class|extends|import|export|default|from|async|await|yield|typeof|instanceof|in|of|null|undefined|true|false|interface|type|enum|namespace|implements|abstract|public|private|protected|readonly|static|get|set|super|delete|void)"#), color: .hKeyword, extraAttributes: [:])]

        case .cpp, .c, .objc:
            let ckw = HighlightRule(pattern: words(#"(?:int|long|float|double|char|void|short|unsigned|signed|if|else|for|while|do|switch|case|break|continue|return|struct|union|enum|typedef|sizeof|const|static|extern|volatile|register|auto|inline|virtual|override|class|template|typename|namespace|using|public|private|protected|friend|this|new|delete|try|catch|throw|true|false|nullptr)"#), color: .hKeyword, extraAttributes: [:])
            let preproc = HighlightRule(pattern: try! NSRegularExpression(pattern: #"^\s*#\s*(?:include|define|undef|ifdef|ifndef|if|else|elif|endif|pragma|error|warning|line|import|once)\b"#, options: .anchorsMatchLines), color: .hPreprocessor, extraAttributes: [:])
            return [ckw, preproc]

        case .java:
            return [HighlightRule(pattern: words(#"(?:public|private|protected|static|final|class|interface|extends|implements|import|package|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|throws|new|this|super|void|int|long|float|double|char|boolean|byte|short|null|true|false|instanceof|abstract|synchronized|volatile|transient|native|strictfp|enum|assert|default|var|record|sealed|permits|yield)"#), color: .hKeyword, extraAttributes: [:])]

        case .rust:
            return [HighlightRule(pattern: words(#"(?:fn|let|mut|const|static|return|if|else|for|while|loop|match|break|continue|struct|enum|impl|trait|pub|use|mod|crate|self|super|where|as|in|ref|move|async|await|unsafe|extern|type|dyn|true|false|Some|None|Ok|Err)"#), color: .hKeyword, extraAttributes: [:])]

        case .go:
            return [HighlightRule(pattern: words(#"(?:func|return|if|else|for|range|switch|case|break|continue|go|defer|select|chan|interface|struct|map|type|var|const|import|package|true|false|nil|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|string|bool|byte|rune|error|make|new|append|len|cap)"#), color: .hKeyword, extraAttributes: [:])]

        case .ruby:
            return [HighlightRule(pattern: words(#"(?:def|class|module|return|if|elsif|else|unless|case|when|for|while|until|do|end|begin|rescue|ensure|yield|self|nil|true|false|and|or|not|in|super|defined\?|break|next|redo|retry|raise|throw|catch|attr_reader|attr_writer|attr_accessor|require|include|extend|prepend)"#), color: .hKeyword, extraAttributes: [:])]

        case .shell:
            return [HighlightRule(pattern: words(#"(?:if|then|else|elif|fi|for|while|do|done|case|esac|function|return|exit|export|local|source|echo|printf|read|set|unset|shift|trap|exec|eval|test)"#), color: .hKeyword, extraAttributes: [:])]

        case .html:
            let tag = try! NSRegularExpression(pattern: #"</?[\w-]+(?:\s[^>]*)?>"#)
            let attr = try! NSRegularExpression(pattern: #"\b(?:class|id|style|href|src|alt|title|name|type|value|placeholder|disabled|checked|selected|data-\w+|rel|target|action|method)\b"#)
            let entity = try! NSRegularExpression(pattern: #"&[\w#]+;"#)
            return [
                HighlightRule(pattern: tag, color: .hKeyword, extraAttributes: [:]),
                HighlightRule(pattern: attr, color: .hAttribute, extraAttributes: [:]),
                HighlightRule(pattern: entity, color: .hConstant, extraAttributes: [:]),
            ]

        case .css, .scss:
            let selector = try! NSRegularExpression(pattern: #"\.[\w-]+|#[\w-]+|[\w-]+(?=\s*\{)"#)
            let prop = try! NSRegularExpression(pattern: #"\b(?:color|background|margin|padding|font|border|display|position|width|height|top|left|right|bottom|flex|grid|align|justify|overflow|opacity|transform|transition|animation|box-shadow|text-shadow|z-index|content|cursor|filter|outline|resize|user-select|pointer-events)\b"#)
            let value = try! NSRegularExpression(pattern: #"\b(?:auto|inherit|initial|none|block|inline|flex|grid|absolute|relative|fixed|sticky|visible|hidden|solid|dashed|dotted|bold|normal|italic|underline|cursive|monospace|serif|sans-serif|!important)\b"#)
            return [
                HighlightRule(pattern: selector, color: .hType, extraAttributes: [:]),
                HighlightRule(pattern: prop, color: .hAttribute, extraAttributes: [:]),
                HighlightRule(pattern: value, color: .hConstant, extraAttributes: [:]),
            ]

        case .markdown:
            let heading = try! NSRegularExpression(pattern: #"^#{1,6}\s+"#, options: .anchorsMatchLines)
            let boldItalic = try! NSRegularExpression(pattern: #"\*{1,3}[^*]+\*{1,3}|_{1,3}[^_]+_{1,3}"#)
            let code = try! NSRegularExpression(pattern: #"`[^`]+`"#)
            let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#)
            return [
                HighlightRule(pattern: heading, color: .hKeyword, extraAttributes: [.font: NSFont.boldSystemFont(ofSize: 14)]),
                HighlightRule(pattern: boldItalic, color: .hConstant, extraAttributes: [:]),
                HighlightRule(pattern: code, color: .hString, extraAttributes: [:]),
                HighlightRule(pattern: link, color: .hType, extraAttributes: [:]),
            ]

        case .yaml:
            let key = try! NSRegularExpression(pattern: #"^[\w-]+(?=:)"#, options: .anchorsMatchLines)
            let anchor = try! NSRegularExpression(pattern: #"&\w+|\*\w+"#)
            return [
                HighlightRule(pattern: key, color: .hAttribute, extraAttributes: [:]),
                HighlightRule(pattern: anchor, color: .hConstant, extraAttributes: [:]),
            ]

        case .toml:
            let key = try! NSRegularExpression(pattern: #"^[\w.]+(?=\s*=)"#, options: .anchorsMatchLines)
            let section = try! NSRegularExpression(pattern: #"^\[[\w.]+\]"#, options: .anchorsMatchLines)
            return [
                HighlightRule(pattern: key, color: .hAttribute, extraAttributes: [:]),
                HighlightRule(pattern: section, color: .hType, extraAttributes: [:]),
            ]

        case .json:
            let key = try! NSRegularExpression(pattern: #""[^"]+"(?=\s*:)"#)
            let boolNull = try! NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#)
            return [
                HighlightRule(pattern: key, color: .hAttribute, extraAttributes: [:]),
                HighlightRule(pattern: boolNull, color: .hConstant, extraAttributes: [:]),
            ]

        default:
            return []
        }
    }

    private static func words(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}
