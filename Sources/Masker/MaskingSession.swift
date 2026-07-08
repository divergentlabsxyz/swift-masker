import Foundation

/// The reversible mapping between placeholders and the original PII values they
/// stand in for — the "vault" for the mask → external service → unmask flow.
///
/// A session is `Codable` so callers may persist it if they choose, but by
/// design it is meant to stay on-device: the whole point of masking is that the
/// raw values in `map` never leave the device. Hold a session in memory across
/// the round-trip, then hand it to ``Masker/unmask(_:with:)`` to restore.
public struct MaskingSession: Codable, Sendable, Hashable {
    /// Placeholder token → original value, e.g. `"[EMAIL_1]" : "ada@x.com"`.
    public private(set) var map: [String: String]

    public init(map: [String: String] = [:]) {
        self.map = map
    }

    /// The original value a placeholder stands for, if known.
    public func original(for placeholder: String) -> String? {
        map[placeholder]
    }

    /// Records a placeholder ↔ original association.
    mutating func record(placeholder: String, original: String) {
        map[placeholder] = original
    }
}

/// The result of a reversible masking pass.
public struct MaskedText: Sendable {
    /// The placeholdered text — safe to hand to an external service.
    public let text: String
    /// The vault needed to restore originals. Keep on-device.
    public let session: MaskingSession
    /// The entities that were masked, in document order.
    public let entities: [PIIEntity]

    public init(text: String, session: MaskingSession, entities: [PIIEntity]) {
        self.text = text
        self.session = session
        self.entities = entities
    }
}
