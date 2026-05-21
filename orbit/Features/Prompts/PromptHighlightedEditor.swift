import SwiftUI
import AppKit

/// An NSTextView wrapper with live syntax highlighting for section headers
/// (ALL_CAPS:) and template variables ({{variable}}).
struct PromptHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.font = font
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.allowsUndo = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        applyHighlighting(textView)
    }

    private func applyHighlighting(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.removeAttribute(.font, range: fullRange)

        let bodyFont = font
        storage.addAttribute(.font, value: bodyFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        // Highlight ALL_CAPS: section headers
        let headerPattern = try! NSRegularExpression(pattern: "^([A-Z_]{2,}:)", options: [.anchorsMatchLines])
        for match in headerPattern.matches(in: textView.string, options: [], range: fullRange) {
            guard match.range.location != NSNotFound else { continue }
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range(at: 1))
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: match.range(at: 1))
        }

        // Highlight {{variable}} tokens
        let varPattern = try! NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}")
        for match in varPattern.matches(in: textView.string, options: [], range: fullRange) {
            guard match.range.location != NSNotFound else { continue }
            let tokenRange = match.range(at: 0)
            let keyRange = match.range(at: 1)

            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: tokenRange)
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .medium), range: tokenRange)

            if keyRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: keyRange)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
