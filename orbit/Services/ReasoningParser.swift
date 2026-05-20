import Foundation

/// Parses `<think>...</think>` reasoning blocks out of model responses.
///
/// Some models (e.g. Qwen3 in thinking mode) wrap internal reasoning in
/// `<think>...</think>` tags before emitting the visible answer. This parser
/// separates the two so the UI can handle them independently.
///
/// Handles partial/in-progress blocks safely for streaming use — an unclosed
/// `<think>` is reported via `isReasoningInProgress`.
struct ReasoningParser {

    struct Result {
        /// Content extracted from inside `<think>…</think>` blocks (may be partial).
        let reasoning: String
        /// Content outside all think blocks — the model's visible answer.
        let visible: String
        /// True while a `<think>` block has opened but not yet been closed.
        /// Useful during streaming to show a "thinking" indicator instead of empty content.
        let isReasoningInProgress: Bool

        var hasReasoning: Bool { !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Parses `text` into reasoning and visible parts.
    /// Case-insensitive: `<THINK>` and `<think>` are both recognised.
    static func parse(_ text: String) -> Result {
        var reasoningParts: [String] = []
        var visibleParts:   [String] = []
        var inThink = false
        var remaining = text

        while !remaining.isEmpty {
            if !inThink {
                if let range = remaining.range(of: "<think>", options: .caseInsensitive) {
                    let before = String(remaining[..<range.lowerBound])
                    if !before.isEmpty { visibleParts.append(before) }
                    remaining = String(remaining[range.upperBound...])
                    inThink = true
                } else {
                    visibleParts.append(remaining)
                    remaining = ""
                }
            } else {
                if let range = remaining.range(of: "</think>", options: .caseInsensitive) {
                    let block = String(remaining[..<range.lowerBound])
                    reasoningParts.append(block)
                    remaining = String(remaining[range.upperBound...])
                    inThink = false
                } else {
                    // Unclosed block — still in progress (streaming)
                    reasoningParts.append(remaining)
                    remaining = ""
                }
            }
        }

        return Result(
            reasoning: reasoningParts.joined().trimmingCharacters(in: .whitespacesAndNewlines),
            visible:   visibleParts.joined().trimmingCharacters(in: .whitespacesAndNewlines),
            isReasoningInProgress: inThink
        )
    }

    /// Convenience: returns only the visible (non-reasoning) content.
    /// Useful for copy-to-clipboard where reasoning should be excluded.
    static func visibleContent(_ text: String) -> String {
        parse(text).visible
    }
}
