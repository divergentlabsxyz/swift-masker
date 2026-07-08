import Foundation

/// A backend that finds contextual PII with the neural model.
///
/// Abstracting this lets the deterministic layer, merger, and masking engine be
/// exercised end-to-end against a mock, and lets the real Core ML backend be
/// swapped in without touching the public API.
protocol NeuralDetector: Sendable {
    /// Detects model-labelled PII in `text`, keeping spans at or above
    /// `threshold` confidence.
    func detect(in text: String, threshold: Double) throws -> [PIIEntity]
}
