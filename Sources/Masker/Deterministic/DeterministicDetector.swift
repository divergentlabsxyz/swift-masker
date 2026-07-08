import Foundation

/// The deterministic PII layer: regex candidate extraction followed by checksum
/// / structural validation. Pure Swift, no model and no native dependencies.
///
/// Only candidates that pass their validator are emitted, each with an exact
/// character range, `confidence == 1.0`, and `source == .rules`.
struct DeterministicDetector {

    /// A single detection rule: pattern → validator → emitted type.
    private struct Rule {
        let type: PIIType
        let regex: Regex<AnyRegexOutput>
        let boundary: Patterns.Boundary
        let validate: @Sendable (Substring) -> Bool
    }

    private let rules: [Rule]

    /// Builds the detector, compiling only the rules for `allowedTypes`
    /// (or all rules when `nil`).
    init(allowedTypes: Set<PIIType>? = nil) {
        let all: [(PIIType, String, Patterns.Boundary, @Sendable (Substring) -> Bool)] = [
            (.email,        Patterns.email,        .emailChar,    { Checksums.email($0) }),
            (.iban,         Patterns.ibanCompact,  .alphanumeric, { Checksums.iban($0) }),
            (.iban,         Patterns.ibanGrouped,  .alphanumeric, { Checksums.iban($0) }),
            (.creditCard,   Patterns.creditCard,   .digit,        { Checksums.luhn($0) }),
            (.governmentID, Patterns.dutchID,    .digitOrDot,   { Checksums.dutchGovernmentID($0) }),
            (.ipAddress,    Patterns.ipv4,       .dottedDecimal, { Checksums.ipv4($0) }),
            (.ipAddress,    Patterns.ipv6,       .hexOrColon,   { Checksums.ipv6($0) }),
        ]
        rules = all.compactMap { type, pattern, boundary, validate in
            guard allowedTypes?.contains(type) ?? true else { return nil }
            // Patterns are authored as constants; a failure here is a programmer error.
            let regex = try! Regex(pattern)
            return Rule(type: type, regex: regex, boundary: boundary, validate: validate)
        }
    }

    /// Detects structured PII in `text`. Results are de-overlapped (longer, then
    /// earlier match wins) and returned in document order.
    func detect(in text: String) -> [PIIEntity] {
        var found: [PIIEntity] = []
        for rule in rules {
            for match in text.matches(of: rule.regex) {
                let range = match.range
                guard hasCleanBoundaries(text, range, rule.boundary) else { continue }
                let slice = text[range]
                guard rule.validate(slice) else { continue }
                found.append(
                    PIIEntity(
                        type: rule.type,
                        range: range,
                        text: slice,
                        confidence: 1.0,
                        source: .rules
                    )
                )
            }
        }
        return resolveOverlaps(found)
    }

    // MARK: - Boundaries

    /// Rejects a match whose immediate neighbours would make it part of a larger
    /// token (e.g. `4111...` inside a 20-digit string, or `1.2.3.4` inside
    /// `1.2.3.4.5`).
    private func hasCleanBoundaries(
        _ text: String,
        _ range: Range<String.Index>,
        _ boundary: Patterns.Boundary
    ) -> Bool {
        if range.lowerBound > text.startIndex {
            let beforeIndex = text.index(before: range.lowerBound)
            let before = text[beforeIndex]
            let beyond = beforeIndex > text.startIndex ? text[text.index(before: beforeIndex)] : nil
            if boundary.forbids(before, beyond: beyond) { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            let afterNext = text.index(after: range.upperBound)
            let beyond = afterNext < text.endIndex ? text[afterNext] : nil
            if boundary.forbids(after, beyond: beyond) { return false }
        }
        return true
    }

    // MARK: - Overlap resolution

    /// Keeps the strongest non-overlapping set: sort by length (desc) then start
    /// (asc), then greedily accept matches that don't overlap an accepted one.
    private func resolveOverlaps(_ entities: [PIIEntity]) -> [PIIEntity] {
        let ordered = entities.sorted { lhs, rhs in
            if lhs.text.count != rhs.text.count { return lhs.text.count > rhs.text.count }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }
        var accepted: [PIIEntity] = []
        for entity in ordered where !accepted.contains(where: { $0.range.overlaps(entity.range) }) {
            accepted.append(entity)
        }
        return accepted.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
