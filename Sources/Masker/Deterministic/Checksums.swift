import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Checksum / structural validators for the deterministic PII layer.
///
/// Every function here is pure and side-effect free. They take an already
/// extracted candidate and answer a single question: *is this a well-formed X?*
/// The regex layer proposes; these validators dispose — a 16-digit number that
/// fails Luhn, or a mistyped IBAN that fails mod-97, is rejected here so the
/// deterministic layer stays high-precision.
public enum Checksums {

    // MARK: - Digit helpers

    /// Extracts the decimal digits from a string, dropping spaces, dashes, dots.
    static func digits(_ s: some StringProtocol) -> [Int] {
        s.compactMap { $0.wholeNumberValue.flatMap { (0...9).contains($0) ? $0 : nil } }
    }

    // MARK: - Luhn (credit cards)

    /// The Luhn (mod-10) checksum used by payment card numbers (ISO/IEC 7812).
    ///
    /// - Parameter candidate: a string that may contain spaces/dashes.
    /// - Returns: `true` iff the 12–19 digit number passes Luhn.
    public static func luhn(_ candidate: some StringProtocol) -> Bool {
        let ds = digits(candidate)
        guard (12...19).contains(ds.count) else { return false }
        var sum = 0
        // Double every second digit from the right.
        for (offsetFromRight, digit) in ds.reversed().enumerated() {
            if offsetFromRight % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    // MARK: - ISO 7064 mod-97 (IBAN)

    /// Minimum/maximum total IBAN length by country (subset; others fall back to
    /// a generic 15–34 length window). Values are the full IBAN length.
    static let ibanLengthByCountry: [String: Int] = [
        "NL": 18, "DE": 22, "FR": 27, "GB": 22, "BE": 16, "ES": 24,
        "IT": 27, "CH": 21, "AT": 20, "IE": 22, "PT": 25, "LU": 20,
        "FI": 18, "DK": 18, "NO": 15, "SE": 24, "PL": 28,
    ]

    /// Validates an IBAN via the ISO 7064 mod-97-10 check plus a country length
    /// check where the country is known.
    ///
    /// - Parameter candidate: an IBAN that may contain spaces (e.g. printed in
    ///   groups of four).
    public static func iban(_ candidate: some StringProtocol) -> Bool {
        let compact = String(candidate.filter { !$0.isWhitespace }).uppercased()
        // Structure: 2 letters (country) + 2 digits (check) + BBAN.
        guard (15...34).contains(compact.count) else { return false }
        let chars = Array(compact)
        guard chars[0].isLetter, chars[1].isLetter,
              chars[2].isNumber, chars[3].isNumber,
              chars.dropFirst(4).allSatisfy({ $0.isLetter || $0.isNumber })
        else { return false }

        let country = String(chars[0...1])
        if let expected = ibanLengthByCountry[country], compact.count != expected {
            return false
        }

        // Move the first four characters to the end, then map letters to numbers
        // (A=10 … Z=35) and reduce mod 97; a valid IBAN yields 1.
        let rearranged = chars.dropFirst(4) + chars.prefix(4)
        var remainder = 0
        for ch in rearranged {
            let piece: Int
            if let d = ch.wholeNumberValue, ch.isNumber {
                piece = d
            } else if let scalar = ch.unicodeScalars.first, ("A"..."Z").contains(ch) {
                piece = Int(scalar.value - Unicode.Scalar("A").value) + 10
            } else {
                return false
            }
            // A letter contributes two decimal digits; fold each in turn.
            if piece >= 10 {
                remainder = (remainder * 100 + piece) % 97
            } else {
                remainder = (remainder * 10 + piece) % 97
            }
        }
        return remainder == 1
    }

    // MARK: - Elfproef (Dutch mod-11)

    /// The Dutch "11-proef" over an explicit weight vector.
    /// Valid when the weighted digit sum is divisible by 11 (and non-zero).
    static func elevenTest(_ ds: [Int], weights: [Int]) -> Bool {
        guard ds.count == weights.count else { return false }
        let sum = zip(ds, weights).reduce(0) { $0 + $1.0 * $1.1 }
        return sum != 0 && sum % 11 == 0
    }

    /// Validates a Dutch **BSN** or **RSIN** (both 9-digit, same rule):
    /// weights 9,8,7,6,5,4,3,2 and −1 for the final digit.
    public static func bsn(_ candidate: some StringProtocol) -> Bool {
        var ds = digits(candidate)
        // An 8-digit BSN is a 9-digit one with a leading zero.
        if ds.count == 8 { ds.insert(0, at: 0) }
        guard ds.count == 9 else { return false }
        return elevenTest(ds, weights: [9, 8, 7, 6, 5, 4, 3, 2, -1])
    }

    /// Validates a legacy (pre-IBAN) Dutch bank account number of 9 or 10
    /// digits via the descending-weight 11-proef.
    public static func dutchBankAccount(_ candidate: some StringProtocol) -> Bool {
        let ds = digits(candidate)
        guard ds.count == 9 || ds.count == 10 else { return false }
        let weights = Array(stride(from: ds.count, through: 1, by: -1))
        return elevenTest(ds, weights: weights)
    }

    /// Any Dutch government/bank identifier the elfproef covers (BSN, RSIN, or a
    /// legacy 9/10-digit bank account).
    public static func dutchGovernmentID(_ candidate: some StringProtocol) -> Bool {
        bsn(candidate) || dutchBankAccount(candidate)
    }

    // MARK: - IP addresses

    /// Validates a textual IPv4 address (four octets 0–255, no leading zeros).
    public static func ipv4(_ candidate: some StringProtocol) -> Bool {
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy(\.isNumber) else { return false }
            if part.count > 1 && part.first == "0" { return false }   // reject leading zeros
            guard let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }

    /// Validates a textual IPv6 address using the system resolver (`inet_pton`).
    /// A zone identifier (e.g. `%en0`) is permitted and stripped before checking.
    public static func ipv6(_ candidate: some StringProtocol) -> Bool {
        let full = String(candidate)
        let bare = full.split(separator: Character("%"), maxSplits: 1).first.map(String.init) ?? full
        guard bare.contains(":") else { return false }
        #if canImport(Darwin)
        var buffer = in6_addr()
        return bare.withCString { inet_pton(AF_INET6, $0, &buffer) == 1 }
        #else
        return false
        #endif
    }

    // MARK: - Email

    /// A pragmatic structural check for an email address. Not full RFC 5322 —
    /// deliberately conservative so obvious non-addresses are rejected.
    public static func email(_ candidate: some StringProtocol) -> Bool {
        let s = String(candidate)
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let (local, domain) = (parts[0], parts[1])

        guard (1...64).contains(local.count) else { return false }
        guard !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else { return false }
        let localOK = local.allSatisfy { ch in
            ch.isLetter || ch.isNumber || "!#$%&'*+/=?^_`{|}~.-".contains(ch)
        }
        guard localOK else { return false }

        guard !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains("..") else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        }
        // The TLD must be at least two letters.
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        return true
    }
}
