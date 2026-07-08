import Foundation

#if canImport(CoreML)
import CoreML

/// Loads and runs the bundled `masker-mini` Core ML model.
///
/// The model takes three fixed-length `Int32` tensors (`input_ids`,
/// `attention_mask`, `token_type_ids`) of shape `[1, 256]` and returns logits of
/// shape `[1, 256, 49]`. This runner hides all of the `MLMultiArray` marshalling
/// and returns a per-position argmax with its softmax probability.
final class CoreMLRunner: @unchecked Sendable {
    private let model: MLModel
    let sequenceLength: Int

    static let inputIDsFeature = "input_ids"
    static let attentionMaskFeature = "attention_mask"
    static let tokenTypeIDsFeature = "token_type_ids"

    init(model: MLModel, sequenceLength: Int = 256) {
        self.model = model
        self.sequenceLength = sequenceLength
    }

    /// Loads the compiled model (`masker-mini.mlmodelc`) from package resources.
    static func loadBundled(computeUnits: MLComputeUnits) throws -> CoreMLRunner {
        guard let url = Bundle.module.url(forResource: "masker-mini", withExtension: "mlmodelc") else {
            throw MaskerError.modelResourceMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            let model = try MLModel(contentsOf: url, configuration: configuration)
            return CoreMLRunner(model: model)
        } catch {
            throw MaskerError.inferenceFailed(error.localizedDescription)
        }
    }

    /// The argmax class index and softmax probability for each of the
    /// `sequenceLength` positions.
    struct PositionResult {
        let classIndex: Int
        let confidence: Double
    }

    /// Runs the model over one padded window.
    ///
    /// - Parameters are `Int32` arrays of length `sequenceLength`.
    /// - Returns one ``PositionResult`` per position.
    func run(
        inputIDs: [Int32],
        attentionMask: [Int32],
        tokenTypeIDs: [Int32]
    ) throws -> [PositionResult] {
        precondition(inputIDs.count == sequenceLength)

        let features: [String: MLFeatureValue] = [
            Self.inputIDsFeature: try featureValue(inputIDs),
            Self.attentionMaskFeature: try featureValue(attentionMask),
            Self.tokenTypeIDsFeature: try featureValue(tokenTypeIDs),
        ]
        let provider = try MLDictionaryFeatureProvider(dictionary: features)

        let output: MLFeatureProvider
        do {
            output = try model.prediction(from: provider)
        } catch {
            throw MaskerError.inferenceFailed(error.localizedDescription)
        }

        // Grab the first (and only) multi-array output — the logits.
        guard
            let name = output.featureNames.first(where: {
                output.featureValue(for: $0)?.multiArrayValue != nil
            }),
            let logits = output.featureValue(for: name)?.multiArrayValue
        else {
            throw MaskerError.inferenceFailed("model produced no logits array")
        }
        return Self.argmaxPerPosition(logits, sequenceLength: sequenceLength)
    }

    // MARK: - Marshalling

    private func featureValue(_ values: [Int32]) throws -> MLFeatureValue {
        let array = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
        for (i, v) in values.enumerated() {
            array[[0, NSNumber(value: i)]] = NSNumber(value: v)
        }
        return MLFeatureValue(multiArray: array)
    }

    /// Softmax argmax over the last axis of a `[1, seqLen, C]` logits array.
    ///
    /// The model emits `logits` as **float16**, so the raw buffer is read
    /// according to the array's actual `dataType` rather than assuming float32.
    static func argmaxPerPosition(_ logits: MLMultiArray, sequenceLength: Int) -> [PositionResult] {
        // Class count is the trailing dimension.
        let classCount = logits.shape.last?.intValue ?? 0
        let strides = logits.strides.map(\.intValue)
        let posStride = strides.count >= 2 ? strides[strides.count - 2] : classCount
        let classStride = strides.last ?? 1

        // Read one scalar (as Double) regardless of the underlying storage type.
        let read: (Int) -> Double
        switch logits.dataType {
        case .float16:
            let p = logits.dataPointer.assumingMemoryBound(to: Float16.self)
            read = { Double(p[$0]) }
        case .float32:
            let p = logits.dataPointer.assumingMemoryBound(to: Float.self)
            read = { Double(p[$0]) }
        case .double:
            let p = logits.dataPointer.assumingMemoryBound(to: Double.self)
            read = { p[$0] }
        default:
            // Any other storage (e.g. int32): fall back to type-agnostic
            // subscripting. Not expected for a logits output.
            read = { logits[$0].doubleValue }
        }

        var results: [PositionResult] = []
        results.reserveCapacity(sequenceLength)

        for position in 0..<sequenceLength {
            let base = position * posStride
            var maxLogit = -Double.greatestFiniteMagnitude
            var argmax = 0
            for c in 0..<classCount {
                let value = read(base + c * classStride)
                if value > maxLogit { maxLogit = value; argmax = c }
            }
            // Softmax probability of the argmax class (numerically stable).
            var denom = 0.0
            for c in 0..<classCount {
                denom += Foundation.exp(read(base + c * classStride) - maxLogit)
            }
            let probability = denom > 0 ? 1 / denom : 0
            results.append(PositionResult(classIndex: argmax, confidence: probability))
        }
        return results
    }
}
#endif
