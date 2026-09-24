import Foundation

/// A pure-Swift SentencePiece **Unigram** tokenizer that preserves exact
/// character offsets — the offset-aware backend the neural pipeline needs.
///
/// It reproduces the `masker-mini` tokenizer (`tokenizer.json`):
/// - **Metaspace** pre-tokenisation: a `▁` is prepended and every space becomes
///   `▁`, splitting the text into word segments.
/// - **Unigram** segmentation: a Viterbi search over the vocabulary maximises the
///   summed piece log-probabilities.
/// - **Unknowns**: a scalar no piece covers becomes `[UNK]` (consecutive ones
///   fuse into a single token), or its UTF-8 `<0xHH>` bytes when the tokenizer
///   enables `byte_fallback`.
///
/// Normalisation mirrors the tokenizer's normaliser: NFKC (SentencePiece's
/// `nmt_nfkc` charsmap), invisible separators to spaces, C0 controls dropped,
/// and every whitespace run collapsed to one boundary. It is applied one
/// grapheme at a time, so each normalised scalar keeps its original
/// character's range and `text[token.range!]` is exactly the surface piece.
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
    /// Whether unknown scalars become bytes (`byte_fallback`) or `[UNK]`.
    private let byteFallback: Bool
    private let unknownTokenID: Int
    private let maxPieceScalars: Int
    /// Cost charged for an unknown-scalar step; below any real path so it is
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
        self.byteFallback = model["byte_fallback"] as? Bool ?? false
        self.unknownTokenID = model["unk_id"] as? Int ?? allID["[UNK]"] ?? 3
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
        var result: [EncodedToken] = []
        var segScalars: [Unicode.Scalar] = [Self.meta]
        var segRanges: [Range<String.Index>?] = [nil]

        // Whitespace runs collapse to one boundary (the tokenizer strips the
        // ends and folds " {2,}" to " "), so an empty segment emits nothing.
        func flush() {
            defer { segScalars = [Self.meta]; segRanges = [nil] }
            if segScalars.count > 1 {
                result.append(contentsOf: viterbi(segScalars, segRanges))
            }
        }

        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            let normalized = String(text[i..<next]).precomposedStringWithCompatibilityMapping
            for scalar in normalized.unicodeScalars {
                switch Self.classify(scalar) {
                case .space: flush()                   // space → start of a new ▁ segment
                case .drop: continue
                case .keep:
                    segScalars.append(scalar)
                    segRanges.append(i..<next)
                }
            }
            i = next
        }
        flush()
        return result
    }

    private enum ScalarClass { case keep, space, drop }

    /// Invisible separators the charsmap maps to a space.
    private static let spaceLike: Set<UInt32> = [
        0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, 0xFFFD,
    ]

    /// How the tokenizer's normaliser treats one (already NFKC) scalar.
    private static func classify(_ scalar: Unicode.Scalar) -> ScalarClass {
        switch scalar.value {
        case 0x09, 0x0A, 0x0C, 0x0D: return .space
        case 0x01...0x1F, 0x7F: return .drop
        case 0x85: return .keep                        // NEL survives the charsmap
        default:
            return spaceLike.contains(scalar.value) || scalar.properties.isWhitespace ? .space : .keep
        }
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
                // Ascending, so on a tie the longest final piece wins — the
                // same order the reference lattice breaks ties in.
                for j in lowest..<i where best[j] > -.greatestFiniteMagnitude {
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
            // Single-scalar unknown edge, always available.
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
        var previousUnknown = false
        for span in spans {
            defer { previousUnknown = span.id < 0 }
            let range = mergedRange(ranges[span.lower..<span.upper])
            if span.id >= 0 {
                tokens.append(EncodedToken(id: span.id, range: range))
            } else if byteFallback {
                // Byte-fallback: emit the scalar's UTF-8 bytes, all sharing its span.
                for byte in Array(String(scalars[span.lower]).utf8) {
                    tokens.append(EncodedToken(id: byteTokenID[Int(byte)], range: range))
                }
            } else if previousUnknown, let last = tokens.last {
                // Consecutive unknowns fuse into one [UNK] covering all of them.
                tokens[tokens.count - 1] = EncodedToken(
                    id: unknownTokenID, range: mergedRange([last.range, range][...]))
            } else {
                tokens.append(EncodedToken(id: unknownTokenID, range: range))
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
