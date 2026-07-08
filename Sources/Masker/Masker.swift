import Foundation

/// On-device PII detection, redaction, and reversible masking around the
/// `masker-mini` model.
///
/// Detection is **hybrid**: a deterministic regex + checksum layer for
/// structured PII (emails, IPs, IBANs, cards, Dutch government IDs) runs
/// alongside the neural model for contextual PII (names, cities, dates, …), and
/// the two are merged into one exact-span result set.
///
/// ### Choosing a constructor
/// - ``init(configuration:)`` — full **hybrid** detection using the bundled Core
///   ML model. This is the default; the model ships inside the package.
/// - ``deterministicOnly(configuration:)`` — rules layer only. Skips loading the
///   model — fastest to spin up, and enough when you only need structured PII.
///
/// ### Reversible masking (the LLM round-trip)
/// ```swift
/// let masker = try await Masker()
/// let masked = try await masker.mask(userText)     // "[EMAIL_1] ..."
/// let reply  = try await llm.complete(masked.text) // service sees only placeholders
/// let final  = masker.unmask(reply, with: masked.session) // originals restored on-device
/// ```
public actor Masker {
    public let configuration: MaskerConfiguration
    private let deterministic: DeterministicDetector?
    private let neural: (any NeuralDetector)?

    // Designated initializer. Internal so tests can inject a mock neural backend.
    init(configuration: MaskerConfiguration, neural: (any NeuralDetector)?) {
        self.configuration = configuration
        self.deterministic = configuration.enableDeterministicLayer
            ? DeterministicDetector(allowedTypes: configuration.allowedTypes)
            : nil
        self.neural = neural
    }

    /// Creates the default hybrid detector, loading the bundled Core ML model and
    /// tokenizer. Model load is a few MB of work, hence `async`.
    ///
    /// - Throws: ``MaskerError`` if the bundled resources cannot be loaded.
    public init(configuration: MaskerConfiguration = .default) async throws {
        #if canImport(CoreML)
        let neural = try CoreMLNeuralDetector.bundled(configuration: configuration)
        self.init(configuration: configuration, neural: neural)
        #else
        throw MaskerError.modelResourceMissing
        #endif
    }

    /// Rules-layer-only detector. Always available; skips the model entirely.
    public static func deterministicOnly(configuration: MaskerConfiguration = .default) -> Masker {
        Masker(configuration: configuration, neural: nil)
    }

    /// Full hybrid detector using the bundled Core ML model — the synchronous
    /// counterpart to ``init(configuration:)``.
    public static func withBundledModel(configuration: MaskerConfiguration = .default) throws -> Masker {
        #if canImport(CoreML)
        let neural = try CoreMLNeuralDetector.bundled(configuration: configuration)
        return Masker(configuration: configuration, neural: neural)
        #else
        throw MaskerError.modelResourceMissing
        #endif
    }

    // MARK: - 1. Detection

    /// Detects all configured PII in `text`, in document order with exact spans.
    public func detect(_ text: String) throws -> [PIIEntity] {
        let ruleEntities = deterministic?.detect(in: text) ?? []
        let modelEntities = try neural?.detect(in: text, threshold: configuration.confidenceThreshold) ?? []
        return EntityMerger.merge(
            model: modelEntities,
            rules: ruleEntities,
            deterministicWins: configuration.deterministicWinsOnOverlap,
            allowedTypes: configuration.allowedTypes
        )
    }

    // MARK: - 2. Redaction (non-reversible)

    /// Replaces detected PII in `text` per `style` and returns the redacted
    /// string. Use ``mask(_:style:)`` when you need to restore the originals.
    public func redact(_ text: String, style: RedactionStyle = .label) throws -> String {
        let entities = try detect(text)
        return RedactionEngine.render(text: text, entities: entities, style: style).output
    }

    // MARK: - 3. Reversible masking

    /// Replaces detected PII with stable placeholders and returns the masked
    /// text together with the vault needed to restore it. Only the placeholdered
    /// `text` should leave the device.
    public func mask(_ text: String, style: RedactionStyle = .labeledIndex) throws -> MaskedText {
        let entities = try detect(text)
        let rendered = RedactionEngine.render(text: text, entities: entities, style: style)
        return MaskedText(text: rendered.output, session: rendered.session, entities: entities)
    }

    // MARK: - 4. Restore

    /// Restores original values in `text` using a session from ``mask(_:style:)``.
    /// Pure and model-free — safe and cheap to call on any thread.
    public nonisolated func unmask(_ text: String, with session: MaskingSession) -> String {
        RedactionEngine.unmask(text, with: session)
    }
}
