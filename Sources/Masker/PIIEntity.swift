import Foundation

/// Which detection layer produced an entity.
public enum DetectionSource: String, Codable, Sendable, Hashable {
    /// The neural `masker-mini` Core ML model.
    case model
    /// The deterministic regex + checksum rules layer.
    case rules
}

/// A single span of detected PII within a source string.
///
/// `range` indexes into the **original** string the entity was detected in, so
/// `text[entity.range] == entity.text` always holds. This exactness is what
/// lets redaction and reversible masking operate on precise substrings.
public struct PIIEntity: Sendable, Hashable {
    /// The kind of PII.
    public let type: PIIType
    /// The half-open character range in the original string.
    public let range: Range<String.Index>
    /// The matched substring (equal to `original[range]`).
    public let text: Substring
    /// Confidence in `[0, 1]`. Rules-layer matches are checksum-validated and
    /// reported as `1.0`; model matches carry the mean softmax probability over
    /// the span's tokens.
    public let confidence: Double
    /// Which layer produced this entity.
    public let source: DetectionSource

    public init(
        type: PIIType,
        range: Range<String.Index>,
        text: Substring,
        confidence: Double,
        source: DetectionSource
    ) {
        self.type = type
        self.range = range
        self.text = text
        self.confidence = confidence
        self.source = source
    }
}

extension PIIEntity {
    /// The number of characters spanned, in the original string.
    var length: Int { text.count }

    /// Whether this entity's character range overlaps `other`'s.
    func overlaps(_ other: PIIEntity) -> Bool {
        range.overlaps(other.range) || range.lowerBound == other.range.lowerBound
    }
}
