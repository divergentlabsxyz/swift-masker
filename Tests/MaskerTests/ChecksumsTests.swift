import Testing
@testable import Masker

@Suite("Checksums — the deterministic validators")
struct ChecksumsTests {

    // MARK: Luhn (credit cards)

    @Test("Valid card numbers across networks pass Luhn", arguments: [
        "4111111111111111",   // Visa
        "4012888888881881",   // Visa
        "5555555555554444",   // Mastercard
        "5105105105105100",   // Mastercard
        "378282246310005",    // Amex (15)
        "6011111111111117",   // Discover
    ])
    func luhnValid(number: String) {
        #expect(Checksums.luhn(number))
    }

    @Test("A single flipped digit fails Luhn")
    func luhnFlipped() {
        #expect(!Checksums.luhn("4111111111111112"))
        #expect(!Checksums.luhn("5555555555554445"))
    }

    @Test("Spaces and dashes are normalised before Luhn")
    func luhnFormatting() {
        #expect(Checksums.luhn("4111 1111 1111 1111"))
        #expect(Checksums.luhn("4111-1111-1111-1111"))
    }

    @Test("Out-of-range lengths are rejected")
    func luhnLength() {
        #expect(!Checksums.luhn("41111111111"))          // 11 digits
        #expect(!Checksums.luhn("41111111111111111111")) // 20 digits
    }

    // MARK: IBAN (ISO 7064 mod-97)

    @Test("Real IBANs pass mod-97", arguments: [
        "NL91ABNA0417164300",
        "DE89370400440532013000",
        "GB29NWBK60161331926819",
        "FR1420041010050500013M02606",
        "BE68539007547034",
    ])
    func ibanValid(iban: String) {
        #expect(Checksums.iban(iban))
    }

    @Test("Lowercase and grouped-by-four IBANs normalise")
    func ibanFormatting() {
        #expect(Checksums.iban("nl91 abna 0417 1643 00"))
        #expect(Checksums.iban("GB29 NWBK 6016 1331 9268 19"))
    }

    @Test("Altered check digits and wrong country length fail")
    func ibanInvalid() {
        #expect(!Checksums.iban("NL91ABNA0417164301"))    // bad check
        #expect(!Checksums.iban("NL91ABNA041716430"))     // too short for NL
        #expect(!Checksums.iban("DE89370400440532013001")) // altered
    }

    // MARK: Elfproef (Dutch mod-11)

    @Test("Valid BSN / RSIN numbers pass the 11-proef", arguments: [
        "123456782",
        "111222333",
    ])
    func bsnValid(bsn: String) {
        #expect(Checksums.bsn(bsn))
        #expect(Checksums.dutchGovernmentID(bsn))
    }

    @Test("An 8-digit BSN is padded and validated")
    func bsnEightDigits() {
        // "23456782" == "023456782" with a leading zero.
        #expect(Checksums.bsn("023456782") == Checksums.bsn("23456782"))
    }

    @Test("BSN rejects bad checksums and all-zeros")
    func bsnInvalid() {
        #expect(!Checksums.bsn("123456789"))  // fails the -1 weighted sum
        #expect(!Checksums.bsn("000000000"))  // all zeros must not pass
    }

    @Test("Legacy 9/10-digit Dutch bank accounts use descending weights")
    func legacyBank() {
        #expect(Checksums.dutchBankAccount("123456789"))     // 9-digit, mod-11 == 0
        #expect(Checksums.dutchGovernmentID("123456789"))    // reachable via bank rule
        #expect(!Checksums.dutchGovernmentID("123456780"))   // fails both rules
    }

    // MARK: IPv4

    @Test("Valid IPv4 addresses", arguments: [
        "192.168.0.1", "8.8.8.8", "255.255.255.255", "0.0.0.0", "127.0.0.1",
    ])
    func ipv4Valid(ip: String) {
        #expect(Checksums.ipv4(ip))
    }

    @Test("Invalid IPv4 addresses", arguments: [
        "256.0.0.1", "999.999.999.999", "1.2.3", "1.2.3.4.5", "01.2.3.4", "1.2.3.04", "a.b.c.d",
    ])
    func ipv4Invalid(ip: String) {
        #expect(!Checksums.ipv4(ip))
    }

    // MARK: IPv6

    @Test("Valid IPv6 addresses", arguments: [
        "2001:db8::1", "::1", "fe80::1", "::", "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
    ])
    func ipv6Valid(ip: String) {
        #expect(Checksums.ipv6(ip))
    }

    @Test("A zone identifier is permitted")
    func ipv6Zone() {
        #expect(Checksums.ipv6("fe80::1%en0"))
    }

    @Test("Invalid IPv6 addresses", arguments: [
        "2001:db8:::1", "gggg::1", "12345::1", "1.2.3.4", "not:an:address:at:all:x:y:z",
    ])
    func ipv6Invalid(ip: String) {
        #expect(!Checksums.ipv6(ip))
    }

    // MARK: Email

    @Test("Valid emails", arguments: [
        "a@b.com", "john.doe+tag@sub.example.co", "x_y@z-w.io", "USER@EXAMPLE.COM",
    ])
    func emailValid(email: String) {
        #expect(Checksums.email(email))
    }

    @Test("Invalid emails", arguments: [
        "a@", "@b.com", "a@@b.com", "a@b", "a@b.c", "a b@c.com", "a..b@c.com", "a@b..com",
    ])
    func emailInvalid(email: String) {
        #expect(!Checksums.email(email))
    }
}
