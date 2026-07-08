import Foundation

#if canImport(CoreML)
import CoreML

/// The production ``NeuralDetector``: tokenize → window → Core ML infer → BIOES
/// decode → reconcile windows.
///
/// Both resources it needs — the compiled `masker-mini.mlmodelc` and the
/// SentencePiece `tokenizer.json` — are bundled with the package, so
/// ``bundled(configuration:)`` builds a working detector out of the box.
final class CoreMLNeuralDetector: NeuralDetector, @unchecked Sendable {
    private let tokenizer: SubwordTokenizer
    private let runner: CoreMLRunner
    private let labelMap: LabelMap
    private let chunker: Chunker

    init(tokenizer: SubwordTokenizer, runner: CoreMLRunner, labelMap: LabelMap, chunker: Chunker) {
        self.tokenizer = tokenizer
        self.runner = runner
        self.labelMap = labelMap
        self.chunker = chunker
    }

    /// Assembles the detector from bundled resources.
    static func bundled(configuration: MaskerConfiguration) throws -> CoreMLNeuralDetector {
        let tokenizer = try SentencePieceTokenizer.bundled()
        let runner = try CoreMLRunner.loadBundled(computeUnits: configuration.computeUnits)
        let labelMap = try LabelMap.bundled()
        let chunker = Chunker(maxLength: runner.sequenceLength, overlap: configuration.chunkOverlap)
        return CoreMLNeuralDetector(tokenizer: tokenizer, runner: runner, labelMap: labelMap, chunker: chunker)
    }

    func detect(in text: String, threshold: Double) throws -> [PIIEntity] {
        let content = tokenizer.encode(text)
        guard !content.isEmpty else { return [] }

        var perWindow: [PIIEntity] = []
        for window in chunker.windows(content) {
            perWindow.append(contentsOf: try detect(window: window, in: text))
        }

        let kept = perWindow.filter { $0.confidence >= threshold }
        // Reconcile duplicate detections in overlapping window regions.
        return EntityMerger.merge(model: kept, rules: [], deterministicWins: false, allowedTypes: nil)
    }

    // MARK: - One window

    private func detect(window: [EncodedToken], in text: String) throws -> [PIIEntity] {
        let length = runner.sequenceLength
        var ids = [Int32](repeating: Int32(tokenizer.padTokenID), count: length)
        var mask = [Int32](repeating: 0, count: length)
        let types = [Int32](repeating: 0, count: length)

        // [CLS] content… [SEP], padded to `length`.
        ids[0] = Int32(tokenizer.classificationTokenID)
        mask[0] = 1
        for (i, token) in window.enumerated() {
            ids[i + 1] = Int32(token.id)
            mask[i + 1] = 1
        }
        let sepPosition = window.count + 1
        ids[sepPosition] = Int32(tokenizer.separatorTokenID)
        mask[sepPosition] = 1

        let positions = try runner.run(inputIDs: ids, attentionMask: mask, tokenTypeIDs: types)

        // Content tokens live at positions 1...window.count.
        var predictions: [BIOESDecoder.Prediction] = []
        predictions.reserveCapacity(window.count)
        for (i, token) in window.enumerated() {
            let p = positions[i + 1]
            predictions.append(.init(token: token, classIndex: p.classIndex, confidence: p.confidence))
        }
        return BIOESDecoder.decode(predictions, labelMap: labelMap, in: text)
    }
}
#endif
