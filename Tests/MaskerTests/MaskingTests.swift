import Testing
@testable import Masker

@Suite("Masking, redaction, and the reversible round-trip")
struct MaskingTests {

    private let sample = "Email ada@example.com and IBAN NL91ABNA0417164300 now."

    @Test("Detection returns exact, ordered spans")
    func detect() async throws {
        let masker = Masker.deterministicOnly()
        let entities = try await masker.detect(sample)
        for e in entities { #expect(String(sample[e.range]) == String(e.text)) }
        #expect(entities.map(\.type) == [.email, .iban])   // document order
    }

    @Test("redact(.label) swaps in bracketed type labels")
    func redactLabel() async throws {
        let masker = Masker.deterministicOnly()
        let redacted = try await masker.redact(sample, style: .label)
        #expect(redacted.contains("[EMAIL]"))
        #expect(redacted.contains("[IBAN]"))
        #expect(!redacted.contains("ada@example.com"))
    }

    @Test("redact(.character) preserves length and hides content")
    func redactCharacter() async throws {
        let masker = Masker.deterministicOnly()
        let redacted = try await masker.redact(sample, style: .character("•"))
        #expect(redacted.contains(String(repeating: "•", count: "ada@example.com".count)))
        #expect(!redacted.contains("ada@example.com"))
    }

    @Test("Custom placeholders are honoured")
    func redactCustom() async throws {
        let masker = Masker.deterministicOnly()
        let redacted = try await masker.redact(sample, style: .custom { entity, _ in
            "<\(entity.type.rawValue)>"
        })
        #expect(redacted.contains("<EMAIL>"))
        #expect(redacted.contains("<IBAN>"))
    }

    // MARK: The LLM round-trip

    @Test("mask → unmask restores the original exactly")
    func roundTrip() async throws {
        let masker = Masker.deterministicOnly()
        let masked = try await masker.mask(sample)

        // Placeholdered text carries no raw PII.
        #expect(masked.text.contains("[EMAIL_1]"))
        #expect(masked.text.contains("[IBAN_1]"))
        for value in masked.session.map.values {
            #expect(!masked.text.contains(value))
        }

        // Restoring yields the original document.
        let restored = masker.unmask(masked.text, with: masked.session)
        #expect(restored == sample)
    }

    @Test("Restoration works on a reordered reply (simulating an LLM)")
    func restoreReorderedReply() async throws {
        let masker = Masker.deterministicOnly()
        let masked = try await masker.mask(sample)
        // Pretend an LLM rewrote the sentence but kept the placeholders.
        let reply = "Your IBAN \(masked.session.map.first(where: { $0.key.hasPrefix("[IBAN") })!.key) "
                  + "is linked to [EMAIL_1]."
        let restored = masker.unmask(reply, with: masked.session)
        #expect(restored.contains("ada@example.com"))
        #expect(restored.contains("NL91ABNA0417164300"))
    }

    @Test("A repeated value reuses the same placeholder")
    func stablePlaceholders() async throws {
        let text = "From ada@x.io to ada@x.io again"
        let masker = Masker.deterministicOnly()
        let masked = try await masker.mask(text)
        // One distinct value → one placeholder → appears twice.
        #expect(masked.session.map.count == 1)
        let occurrences = masked.text.components(separatedBy: "[EMAIL_1]").count - 1
        #expect(occurrences == 2)
        #expect(masker.unmask(masked.text, with: masked.session) == text)
    }

    @Test("unmask substitutes longer placeholders first ([EMAIL_10] before [EMAIL_1])")
    func longestFirst() {
        let masker = Masker.deterministicOnly()
        let session = MaskingSession(map: [
            "[EMAIL_1]": "one@x.com",
            "[EMAIL_10]": "ten@x.com",
        ])
        let restored = masker.unmask("a [EMAIL_10] b [EMAIL_1] c", with: session)
        #expect(restored == "a ten@x.com b one@x.com c")
    }
}
