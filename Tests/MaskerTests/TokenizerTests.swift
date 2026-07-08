import Foundation
import Testing
@testable import Masker

@Suite("SentencePiece tokenizer — ids, offsets, byte fallback")
struct TokenizerTests {

    private let tokenizer: SentencePieceTokenizer

    init() throws {
        tokenizer = try SentencePieceTokenizer.bundled()
    }

    @Test("Special token ids match the model config")
    func specialIDs() {
        #expect(tokenizer.padTokenID == 0)
        #expect(tokenizer.classificationTokenID == 1)
        #expect(tokenizer.separatorTokenID == 2)
    }

    @Test("Every content token's range slices back to a substring of the source", arguments: [
        "Ada Lovelace from Amsterdam",
        "Mijn naam is José García en ik woon in Groningen.",
        "Neem contact op met Renée.",
        "Café visit by Zoë in München.",
        "plain ascii sentence with numbers 12345",
    ])
    func offsetsAreValid(text: String) {
        for token in tokenizer.encode(text) {
            if let range = token.range {
                // The range must be a valid, non-empty slice of the ORIGINAL string.
                #expect(range.lowerBound >= text.startIndex)
                #expect(range.upperBound <= text.endIndex)
                #expect(range.lowerBound < range.upperBound)
            }
        }
    }

    @Test("Token ranges are ordered and cover the non-space characters")
    func offsetsCoverContent() {
        let text = "Ada Lovelace from Amsterdam"
        let ranges = tokenizer.encode(text).compactMap(\.range)
        // Non-decreasing lower bounds (document order).
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.lowerBound <= b.lowerBound)
        }
        // The union of covered characters equals every non-space character.
        var covered = Set<String.Index>()
        for r in ranges {
            var i = r.lowerBound
            while i < r.upperBound { covered.insert(i); i = text.index(after: i) }
        }
        let nonSpace = Set(text.indices.filter { text[$0] != " " })
        #expect(covered == nonSpace)
    }

    @Test("Byte fallback keeps offsets valid for out-of-vocabulary scalars")
    func byteFallback() {
        let text = "wow 🎉 party"
        let tokens = tokenizer.encode(text)
        #expect(!tokens.isEmpty)
        for token in tokens {
            if let range = token.range { #expect(range.upperBound <= text.endIndex) }
        }
    }

    @Test("Encoding is non-empty for ordinary text")
    func nonEmpty() {
        #expect(!tokenizer.encode("hello world").isEmpty)
        #expect(tokenizer.encode("   ").allSatisfy { $0.range == nil })  // only whitespace → no content spans
    }
}
