import Foundation

/// Turns detected entities into redacted / masked output and, for reversible
/// flows, the placeholder ↔ original vault.
enum RedactionEngine {

    /// Renders `text` with each entity replaced per `style`.
    ///
    /// Placeholders are **stable per distinct value**: the same underlying
    /// string reuses its `[TYPE_n]` token, so an LLM keeps coreference and the
    /// restore step is unambiguous. The returned session maps each emitted
    /// replacement token back to its original value.
    ///
    /// - Parameter entities: must be sorted in document order and non-overlapping
    ///   (as produced by ``EntityMerger``).
    static func render(
        text: String,
        entities: [PIIEntity],
        style: RedactionStyle
    ) -> (output: String, session: MaskingSession) {
        var output = ""
        var session = MaskingSession()
        var cursor = text.startIndex

        var counters: [PIIType: Int] = [:]
        var placeholderForValue: [String: String] = [:]

        for (index, entity) in entities.enumerated() {
            output += text[cursor..<entity.range.lowerBound]

            let value = String(entity.text)
            let valueKey = "\(entity.type.rawValue)\u{1}\(value)"
            let placeholder: String
            if let existing = placeholderForValue[valueKey] {
                placeholder = existing
            } else {
                let n = (counters[entity.type] ?? 0) + 1
                counters[entity.type] = n
                placeholder = "[\(entity.type.rawValue)_\(n)]"
                placeholderForValue[valueKey] = placeholder
            }

            let replacement = style.replacement(for: entity, placeholder: placeholder, index: index)
            output += replacement
            // Record the token that actually appears in the output so unmask can
            // find it. (Reversible only when replacements are unique per value —
            // guaranteed by `.labeledIndex`.)
            session.record(placeholder: replacement, original: value)

            cursor = entity.range.upperBound
        }
        output += text[cursor...]
        return (output, session)
    }

    /// Restores originals in `text` using `session`. Longer placeholders are
    /// substituted first so `[EMAIL_1]` cannot clobber `[EMAIL_10]`.
    static func unmask(_ text: String, with session: MaskingSession) -> String {
        var result = text
        for (placeholder, original) in session.map.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: placeholder, with: original)
        }
        return result
    }
}
