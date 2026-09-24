import Foundation
import Testing
@testable import Masker

/// Pins the Swift tokenizer to the reference (Hugging Face `tokenizers`) ids for
/// the bundled `tokenizer.json`. The model only ever saw the reference
/// tokenization, so any drift here is silent accuracy loss on device.
///
/// The expected ids belong to the bundled vocabulary: regenerate them whenever
/// the model is updated, with
/// `AutoTokenizer.from_pretrained("divergentlabs/masker-mini")(text, add_special_tokens=False)`.
@Suite("SentencePiece tokenizer — parity with the reference tokenizer")
struct TokenizerParityTests {

    private let tokenizer: SentencePieceTokenizer

    init() throws {
        tokenizer = try SentencePieceTokenizer.bundled()
    }

    @Test("Ids match the reference tokenizer", arguments: [
        // plain Dutch
        ("Sanne de Groot woont in Utrecht.", [1333, 397, 270, 12319, 1169, 20063, 271, 282, 260, 30442, 261]),
        // NFKC: non-breaking hyphen, ordinal indicator
        ("follow\u{2011}up on 25\u{00BA} marzo", [6329, 8260, 1425, 348, 783, 269, 260, 7911]),
        // NFKC: ligature, circled digit
        ("\u{FB01}nance \u{2460}", [17558, 332]),
        // newline runs collapse to one boundary
        ("Hej Anna,\n\nJag heter Erik.", [24890, 4544, 262, 3498, 44009, 12375, 261]),
        // NBSP, zero-width space and tab are spaces
        ("a\u{00A0}b\u{200B}c\td", [260, 263, 329, 316, 330]),
        // C0 controls are dropped
        ("x\u{0B}y", [260, 328, 277]),
        // unknown scalars fuse into one [UNK]
        ("Ђорђе ћћ😀 x", [27541, 2907, 15013, 260, 3, 260, 328]),
        // equal-score ties keep the longest final piece
        ("Name: __________", [5562, 268, 260, 1382, 22679]),
    ])
    func referenceIDs(text: String, expected: [Int]) {
        #expect(tokenizer.encode(text).map(\.id) == expected)
    }

    @Test("A fused [UNK] spans every unknown scalar it replaces")
    func fusedUnknownRange() throws {
        let text = "ћћ😀 x"
        let unknown = try #require(tokenizer.encode(text).first { $0.id == 3 })
        #expect(unknown.range.map { String(text[$0]) } == "ћћ😀")
    }
}
