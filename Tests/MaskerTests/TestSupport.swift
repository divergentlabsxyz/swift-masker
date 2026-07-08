import Foundation
@testable import Masker

/// A stand-in neural backend so the hybrid pipeline can be exercised without the
/// Core ML model. It simply replays a fixed set of entities (respecting the
/// confidence threshold).
struct MockNeuralDetector: NeuralDetector {
    let entities: [PIIEntity]
    func detect(in text: String, threshold: Double) throws -> [PIIEntity] {
        entities.filter { $0.confidence >= threshold }
    }
}

enum Fixture {
    /// Builds a ``PIIEntity`` over the first occurrence of `substring` in `text`.
    static func entity(
        _ type: PIIType,
        _ substring: String,
        in text: String,
        source: DetectionSource,
        confidence: Double = 1.0
    ) -> PIIEntity {
        guard let range = text.range(of: substring) else {
            fatalError("substring \(substring) not found in fixture text")
        }
        return PIIEntity(type: type, range: range, text: text[range], confidence: confidence, source: source)
    }

    /// A content token spanning the first occurrence of `surface` in `text`.
    static func token(_ id: Int, _ surface: String, in text: String) -> EncodedToken {
        guard let range = text.range(of: surface) else {
            fatalError("surface \(surface) not found in fixture text")
        }
        return EncodedToken(id: id, range: range)
    }
}
