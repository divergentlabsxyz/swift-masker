import Foundation

/// How a detected entity is rendered when redacting or masking text.
public enum RedactionStyle: Sendable {
    /// Replace with the bracketed type label, e.g. `[EMAIL]`.
    case label

    /// Replace with a bracketed, indexed label that is **stable per distinct
    /// value**, e.g. `[EMAIL_1]`, `[EMAIL_2]`. The same underlying value reuses
    /// its placeholder so downstream consumers (like an LLM) keep coreference.
    /// This is the default for reversible masking.
    case labeledIndex

    /// Replace every character of the match with `mask`, preserving length,
    /// e.g. `••••••••`. `mask` should be a single grapheme.
    case character(String)

    /// Fully custom replacement. The closure receives the entity and its
    /// occurrence index (0-based, in document order) and returns the string to
    /// substitute.
    case custom(@Sendable (PIIEntity, _ index: Int) -> String)
}

extension RedactionStyle {
    /// Produces the replacement string for `entity`, where `placeholder` is the
    /// stable indexed token assigned by the redaction engine (used by
    /// `.labeledIndex`), and `index` is the document-order occurrence index.
    func replacement(for entity: PIIEntity, placeholder: String, index: Int) -> String {
        switch self {
        case .label:
            return "[\(entity.type.rawValue)]"
        case .labeledIndex:
            return placeholder
        case .character(let mask):
            let unit = mask.isEmpty ? "•" : mask
            return String(repeating: unit, count: max(1, entity.text.count))
        case .custom(let make):
            return make(entity, index)
        }
    }
}
