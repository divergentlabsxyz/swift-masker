import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Tunables for a ``Masker`` instance.
public struct MaskerConfiguration: Sendable {
    /// If set, only these types are reported; everything else is dropped.
    /// `nil` means "all types".
    public var allowedTypes: Set<PIIType>?

    /// Minimum confidence for a **model** span to be kept, in `[0, 1]`.
    /// Rules-layer spans are checksum-validated and ignore this threshold.
    public var confidenceThreshold: Double

    /// Tokens of overlap between adjacent 256-token windows, so entities that
    /// straddle a window boundary are still caught.
    public var chunkOverlap: Int

    /// Whether the deterministic regex + checksum layer runs.
    public var enableDeterministicLayer: Bool

    /// On an overlap between a rules match and a model match, keep the rules
    /// match (checksum-certain) rather than the model's.
    public var deterministicWinsOnOverlap: Bool

    #if canImport(CoreML)
    /// Which compute units Core ML may use. `.cpuAndNeuralEngine` forces the ANE.
    public var computeUnits: MLComputeUnits
    #endif

    public init(
        allowedTypes: Set<PIIType>? = nil,
        confidenceThreshold: Double = 0.5,
        chunkOverlap: Int = 32,
        enableDeterministicLayer: Bool = true,
        deterministicWinsOnOverlap: Bool = true
    ) {
        self.allowedTypes = allowedTypes
        self.confidenceThreshold = confidenceThreshold
        self.chunkOverlap = chunkOverlap
        self.enableDeterministicLayer = enableDeterministicLayer
        self.deterministicWinsOnOverlap = deterministicWinsOnOverlap
        #if canImport(CoreML)
        self.computeUnits = .all
        #endif
    }

    public static let `default` = MaskerConfiguration()
}
