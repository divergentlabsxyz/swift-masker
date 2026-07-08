import Testing
@testable import Masker

@Suite("Deterministic detector — extraction, spans, precision")
struct DeterministicDetectorTests {

    private let detector = DeterministicDetector()

    /// Every emitted entity must be a rules match whose range slices back to its
    /// exact text.
    private func assertSpanFidelity(_ entities: [PIIEntity], in text: String) {
        for entity in entities {
            #expect(entity.source == .rules)
            #expect(entity.confidence == 1.0)
            #expect(String(text[entity.range]) == String(entity.text))
        }
    }

    @Test("Finds a valid email with an exact span")
    func email() {
        let text = "Reach me at ada@example.com tomorrow."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        #expect(entities.contains { $0.type == .email && $0.text == "ada@example.com" })
    }

    @Test("Finds a spaced IBAN including its whitespace groups")
    func iban() {
        let text = "Pay to NL91 ABNA 0417 1643 00 please."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        let iban = entities.first { $0.type == .iban }
        #expect(iban?.text == "NL91 ABNA 0417 1643 00")
    }

    @Test("Finds a spaced credit-card number")
    func creditCard() {
        let text = "Card: 4111 1111 1111 1111 exp 05/29"
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        #expect(entities.contains { $0.type == .creditCard && $0.text == "4111 1111 1111 1111" })
    }

    @Test("Finds IPv4 and IPv6 addresses")
    func ipAddresses() {
        let text = "Hosts 192.168.1.1 and 2001:db8::1 are up."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        let ips = entities.filter { $0.type == .ipAddress }.map { String($0.text) }
        #expect(ips.contains("192.168.1.1"))
        #expect(ips.contains("2001:db8::1"))
    }

    @Test("An IPv4 at a sentence end (trailing period) is still detected")
    func ipv4TrailingPeriod() {
        let text = "The server is 192.168.1.1."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        #expect(entities.contains { $0.type == .ipAddress && $0.text == "192.168.1.1" })
    }

    @Test("A five-group dotted sequence does not yield a spurious IPv4")
    func ipv4NotInsideLongerSequence() {
        let text = "version 1.2.3.4.5 released"
        let entities = detector.detect(in: text)
        #expect(entities.allSatisfy { $0.type != .ipAddress })
    }

    @Test("Finds a checksum-valid Dutch BSN")
    func governmentID() {
        let text = "BSN 123456782 on file."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        #expect(entities.contains { $0.type == .governmentID && $0.text == "123456782" })
    }

    @Test("Detects several distinct types in one string")
    func mixed() {
        let text = "Email ada@x.io, IBAN NL91ABNA0417164300, card 5555555555554444."
        let entities = detector.detect(in: text)
        assertSpanFidelity(entities, in: text)
        let types = Set(entities.map(\.type))
        #expect(types.isSuperset(of: [.email, .iban, .creditCard]))
    }

    // MARK: Precision — the checksum is what rejects false positives

    @Test("16-digit numbers that fail Luhn are NOT reported as cards")
    func noFalseCards() {
        // All three fail Luhn (verified inline), so nothing should be emitted.
        let numbers = ["1111111111111111", "3333333333333333", "7777777777777777"]
        for n in numbers { #expect(!Checksums.luhn(n)) }
        let text = "Ledger: \(numbers.joined(separator: " ")) end."
        let entities = detector.detect(in: text)
        #expect(entities.allSatisfy { $0.type != .creditCard })
    }

    @Test("A near-IBAN with a broken check digit is dropped")
    func noFalseIBAN() {
        let text = "Ref NL91ABNA0417164301 is not a real account."
        let entities = detector.detect(in: text)
        #expect(entities.allSatisfy { $0.type != .iban })
    }

    @Test("A random 9-digit number that fails the elfproef is not a government ID")
    func noFalseGovID() {
        #expect(!Checksums.dutchGovernmentID("123456780"))
        let text = "Ticket 123456780 assigned."
        let entities = detector.detect(in: text)
        #expect(entities.allSatisfy { $0.type != .governmentID })
    }

    @Test("Overlapping matches resolve to a single entity")
    func overlapResolution() {
        // The 18-digit run inside this IBAN must not also surface as a card.
        let text = "IBAN DE89370400440532013000 here."
        let entities = detector.detect(in: text)
        let overlapping = entities.filter { a in
            entities.contains { b in a.range != b.range && a.range.overlaps(b.range) }
        }
        #expect(overlapping.isEmpty)
    }

    @Test("allowedTypes restricts which patterns run")
    func allowedTypes() {
        let text = "ada@x.io and 4111 1111 1111 1111"
        let onlyEmail = DeterministicDetector(allowedTypes: [.email]).detect(in: text)
        #expect(onlyEmail.allSatisfy { $0.type == .email })
        #expect(onlyEmail.contains { $0.type == .email })
    }
}
