import Foundation

/// Candidate-extraction patterns for the deterministic layer.
///
/// These regexes are intentionally *loose* — they over-match on purpose and let
/// the ``Checksums`` validators reject the false positives. Each pattern is
/// paired with a neighbour rule that rejects a match glued to a character that
/// would make it part of a larger token (e.g. a 9-digit run inside a longer
/// number). We avoid regex lookbehind for engine portability and check
/// neighbours in code instead.
enum Patterns {

    /// What kind of character must *not* sit immediately before/after a match
    /// for it to count as a standalone token.
    enum Boundary {
        case digit          // reject if neighbour is 0-9
        case digitOrDot     // reject if neighbour is 0-9 or '.'
        case alphanumeric   // reject if neighbour is a letter or digit
        case hexOrColon     // reject if neighbour is a hex digit or ':'
        case emailChar      // reject if neighbour continues an address
        case dottedDecimal  // for IPv4: reject a digit, or a dot that continues the sequence

        /// - Parameters:
        ///   - ch: the character immediately adjacent to the match.
        ///   - beyond: the next character out (used for two-char lookahead), if any.
        func forbids(_ ch: Character, beyond: Character?) -> Bool {
            switch self {
            case .digit:
                return ch.isNumber
            case .digitOrDot:
                return ch.isNumber || ch == "."
            case .alphanumeric:
                return ch.isLetter || ch.isNumber
            case .hexOrColon:
                return ch == ":" || ch.isHexDigit
            case .emailChar:
                return ch.isLetter || ch.isNumber || "._%+-@".contains(ch)
            case .dottedDecimal:
                // A digit neighbour always continues the address. A dot only
                // continues it when another digit follows (so `1.2.3.4.5` is
                // rejected but `192.168.1.1.` at a sentence end is accepted).
                if ch.isNumber { return true }
                if ch == "." { return beyond?.isNumber ?? false }
                return false
            }
        }
    }

    static let email = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
    static let ipv4 = #"(?:[0-9]{1,3}\.){3}[0-9]{1,3}"#
    static let ipv6 = #"[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?:%[A-Za-z0-9]+)?"#
    /// Compact IBAN: `NL91ABNA0417164300`.
    static let ibanCompact = #"[A-Za-z]{2}[0-9]{2}[A-Za-z0-9]{11,30}"#
    /// Grouped IBAN printed in blocks of four: `NL91 ABNA 0417 1643 00`.
    /// Interior groups are exactly four characters; only the final group may be
    /// shorter — this stops the match from swallowing a following word.
    static let ibanGrouped = #"[A-Za-z]{2}[0-9]{2}(?: [A-Za-z0-9]{4})+(?: [A-Za-z0-9]{1,3})?"#
    static let creditCard = #"[0-9](?:[ \-]?[0-9]){11,18}"#
    static let dutchID = #"[0-9]{8,10}"#
}
