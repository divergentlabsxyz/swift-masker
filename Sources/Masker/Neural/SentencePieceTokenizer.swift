import Foundation

/// A pure-Swift SentencePiece **Unigram** tokenizer that preserves exact
/// character offsets — the offset-aware backend the neural pipeline needs.
///
/// It reproduces the `masker-mini` tokenizer (`tokenizer.json`):
/// - **Metaspace** pre-tokenisation: a `▁` is prepended and every space becomes
///   `▁`, splitting the text into word segments.
/// - **Unigram** segmentation: a Viterbi search over the vocabulary maximises the
///   summed piece log-probabilities.
/// - **Byte fallback**: a scalar no piece covers is emitted as its UTF-8 bytes
///   via the `<0xHH>` tokens.
///
/// Offsets are tracked directly on the original string's scalars (identity
/// normalisation, which holds for the Latin scripts the model targets), so
/// `text[token.range!]` is exactly the surface piece.
final class SentencePieceTokenizer: SubwordTokenizer, @unchecked Sendable {
    let padTokenID: Int
    let classificationTokenID: Int
    let separatorTokenID: Int

    /// Normal (non-special, non-byte) pieces → score and id. Specials and byte
    /// tokens are excluded here because they all carry score 0 and would
    /// otherwise dominate the max-sum search.
    private let pieceScore: [String: Double]
    private let pieceID: [String: Int]
    /// byte value (0–255) → `<0xHH>` token id.
    private let byteTokenID: [Int]
    /// id of the lone `▁` metaspace token, if present.
    private let metaTokenID: Int?
    private let maxPieceScalars: Int
    /// Cost charged for a byte-fallback step; below any real path so fallback is
    /// a last resort.
    private let unkPenalty: Double

    private static let meta = Unicode.Scalar(0x2581)! // ▁

    // MARK: - Loading

    init(tokenizerJSON data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = root["model"] as? [String: Any],
            let vocab = model["vocab"] as? [[Any]]
        else {
            throw MaskerError.tokenizerUnavailable
        }

        var pieceScore: [String: Double] = [:]
        var pieceID: [String: Int] = [:]
        var byteTokenID = [Int](repeating: 3, count: 256) // default → [UNK]
        var allID: [String: Int] = [:]
        var maxScalars = 1
        var minScore = 0.0

        for (id, entry) in vocab.enumerated() {
            guard let piece = entry.first as? String else { continue }
            let score = (entry.count > 1 ? (entry[1] as? NSNumber)?.doubleValue : nil) ?? 0
            allID[piece] = id

            if let byte = Self.byteValue(of: piece) {
                byteTokenID[byte] = id
                continue
            }
            // Real lattice edges are the pieces with a genuine (negative) score.
            if score != 0 {
                pieceScore[piece] = score
                pieceID[piece] = id
                maxScalars = max(maxScalars, piece.unicodeScalars.count)
                minScore = min(minScore, score)
            }
        }

        guard let cls = allID["[CLS]"], let sep = allID["[SEP]"], let pad = allID["[PAD]"] else {
            throw MaskerError.tokenizerUnavailable
        }

        self.pieceScore = pieceScore
        self.pieceID = pieceID
        self.byteTokenID = byteTokenID
        self.metaTokenID = pieceID[String(Self.meta)]
        self.maxPieceScalars = maxScalars
        self.unkPenalty = minScore - 10
        self.classificationTokenID = cls
        self.separatorTokenID = sep
        self.padTokenID = pad
    }

    /// Loads the tokenizer from the bundled `tokenizer.json`.
    static func bundled() throws -> SentencePieceTokenizer {
        guard let url = Bundle.module.url(forResource: "tokenizer", withExtension: "json") else {
            throw MaskerError.tokenizerResourceMissing
        }
        return try SentencePieceTokenizer(tokenizerJSON: try Data(contentsOf: url))
    }

    /// Parses `<0xHH>` → 0–255, else nil.
    private static func byteValue(of piece: String) -> Int? {
        guard piece.hasPrefix("<0x"), piece.hasSuffix(">"), piece.count == 6 else { return nil }
        let hex = piece.dropFirst(3).dropLast()
        return Int(hex, radix: 16)
    }

    // MARK: - Encoding

    func encode(_ text: String) -> [EncodedToken] {
        let scalars = text.unicodeScalars
        // Strip leading/trailing whitespace (the tokenizer's Strip normaliser).
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, CharacterSet.whitespacesAndNewlines.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start,
              CharacterSet.whitespacesAndNewlines.contains(scalars[scalars.index(before: end)]) {
            end = scalars.index(before: end)
        }

        var result: [EncodedToken] = []
        var segScalars: [Unicode.Scalar] = [Self.meta]
        var segRanges: [Range<String.Index>?] = [nil]

        func flush() {
            defer { segScalars = [Self.meta]; segRanges = [nil] }
            if segScalars.count == 1 {                 // a lone metaspace (extra spacing)
                if let id = metaTokenID { result.append(EncodedToken(id: id, range: nil)) }
                return
            }
            result.append(contentsOf: viterbi(segScalars, segRanges))
        }

        var i = start
        while i < end {
            let scalar = scalars[i]
            let next = scalars.index(after: i)
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flush()                                // space → start of a new ▁ segment
            } else {
                segScalars.append(scalar)
                segRanges.append(i..<next)
            }
            i = next
        }
        flush()
        return result
    }

    // MARK: - Viterbi over one segment

    private func viterbi(
        _ scalars: [Unicode.Scalar],
        _ ranges: [Range<String.Index>?]
    ) -> [EncodedToken] {
        let n = scalars.count
        var best = [Double](repeating: -.greatestFiniteMagnitude, count: n + 1)
        var startOf = [Int](repeating: -1, count: n + 1)
        var edgeID = [Int](repeating: -1, count: n + 1)   // ≥0 real piece id, -1 byte fallback
        best[0] = 0

        for i in 1...n {
            let lowest = max(0, i - maxPieceScalars)
            if lowest < i {
                for j in stride(from: i - 1, through: lowest, by: -1) where best[j] > -.greatestFiniteMagnitude {
                    let piece = String(String.UnicodeScalarView(scalars[j..<i]))
                    if let score = pieceScore[piece] {
                        let candidate = best[j] + score
                        if candidate > best[i] {
                            best[i] = candidate
                            startOf[i] = j
                            edgeID[i] = pieceID[piece]!
                        }
                    }
                }
            }
            // Single-scalar byte-fallback edge, always available.
            let j = i - 1
            if best[j] > -.greatestFiniteMagnitude {
                let candidate = best[j] + unkPenalty
                if candidate > best[i] {
                    best[i] = candidate
                    startOf[i] = j
                    edgeID[i] = -1
                }
            }
        }

        // Reconstruct pieces back-to-front.
        var spans: [(lower: Int, upper: Int, id: Int)] = []
        var i = n
        while i > 0 {
            let j = startOf[i]
            spans.append((j, i, edgeID[i]))
            i = j
        }
        spans.reverse()

        var tokens: [EncodedToken] = []
        for span in spans {
            let range = mergedRange(ranges[span.lower..<span.upper])
            if span.id >= 0 {
                tokens.append(EncodedToken(id: span.id, range: range))
            } else {
                // Byte-fallback: emit the scalar's UTF-8 bytes, all sharing its span.
                for byte in Array(String(scalars[span.lower]).utf8) {
                    tokens.append(EncodedToken(id: byteTokenID[Int(byte)], range: range))
                }
            }
        }
        return tokens
    }

    private func mergedRange(_ slice: ArraySlice<Range<String.Index>?>) -> Range<String.Index>? {
        let present = slice.compactMap { $0 }
        guard
            let lower = present.map(\.lowerBound).min(),
            let upper = present.map(\.upperBound).max()
        else { return nil }
        return lower..<upper
    }
}
