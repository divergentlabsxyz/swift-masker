import Foundation

/// Turns a window's per-token class predictions into character-accurate entity
/// spans, following the BIOES scheme with lenient recovery from malformed tag
/// sequences (a stray `I`/`E` without a `B` still opens a span).
enum BIOESDecoder {

    /// One token's prediction: the content token, its argmax class index, and
    /// the softmax probability of that class.
    struct Prediction {
        let token: EncodedToken
        let classIndex: Int
        let confidence: Double
    }

    /// Decodes predictions (in token order, content tokens only) into entities.
    static func decode(
        _ predictions: [Prediction],
        labelMap: LabelMap,
        in original: String
    ) -> [PIIEntity] {
        var result: [PIIEntity] = []
        var spanType: PIIType?
        var spanTokens: [(EncodedToken, Double)] = []

        func flush() {
            defer { spanType = nil; spanTokens = [] }
            guard let type = spanType, !spanTokens.isEmpty else { return }
            let ranges = spanTokens.compactMap { $0.0.range }
            guard
                let lower = ranges.map(\.lowerBound).min(),
                let upper = ranges.map(\.upperBound).max(),
                lower < upper
            else { return }
            let range = lower..<upper
            let confidence = spanTokens.map(\.1).reduce(0, +) / Double(spanTokens.count)
            result.append(
                PIIEntity(
                    type: type,
                    range: range,
                    text: original[range],
                    confidence: confidence,
                    source: .model
                )
            )
        }

        for prediction in predictions {
            guard let (prefix, type) = labelMap.decode(prediction.classIndex) else {
                flush()   // "O" or unknown → close any open span
                continue
            }
            let continuesCurrent = (spanType == type) && (prefix == .inside || prefix == .end)
            if continuesCurrent {
                spanTokens.append((prediction.token, prediction.confidence))
                if prefix == .end { flush() }
            } else {
                flush()
                spanType = type
                spanTokens = [(prediction.token, prediction.confidence)]
                if prefix == .single || prefix == .end { flush() }
            }
        }
        flush()
        return result
    }
}
