import Foundation

/// Errors thrown by ``Masker``.
public enum MaskerError: Error, Sendable, Equatable {
    /// The bundled Core ML model (`masker-mini.mlmodelc`) could not be found.
    /// Use ``Masker/deterministicOnly(configuration:)`` to run the rules layer
    /// without the model, or add the model to the package resources.
    case modelResourceMissing

    /// A required tokenizer resource (SentencePiece model) was not found.
    case tokenizerResourceMissing

    /// The bundled model label configuration was missing or malformed.
    case labelConfigurationInvalid(String)

    /// Core ML inference failed.
    case inferenceFailed(String)

    /// The tokenizer backend is not yet wired in this build.
    case tokenizerUnavailable
}
