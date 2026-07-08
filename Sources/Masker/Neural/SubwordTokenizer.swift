import Foundation

/// One subword token with its exact source span.
///
/// `range` is `nil` for special tokens (`[CLS]`, `[SEP]`, `[PAD]`) that don't
/// correspond to any input characters. For content tokens it is the half-open
/// character range in the original string — this is what makes precise, span-
/// accurate decoding possible.
struct EncodedToken: Equatable {
    let id: Int
    let range: Range<String.Index>?
}

/// A SentencePiece-style subword tokenizer that preserves character offsets.
///
/// The intended production backend wraps Google's `libsentencepiece`, whose
/// `ImmutableSentencePieceText` exposes per-piece byte offsets; those UTF-8 byte
/// offsets are converted to `String.Index` via the string's `utf8` view so that
/// `text[token.range!]` is exactly the surface piece.
protocol SubwordTokenizer: Sendable {
    /// The `[PAD]` token id (0 for masker-mini).
    var padTokenID: Int { get }
    /// The `[CLS]` token id (1 for masker-mini).
    var classificationTokenID: Int { get }
    /// The `[SEP]` token id (2 for masker-mini).
    var separatorTokenID: Int { get }

    /// Encodes `text` into content tokens (no special tokens), each carrying its
    /// source character range.
    func encode(_ text: String) -> [EncodedToken]
}
