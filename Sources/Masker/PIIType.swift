import Foundation

/// A category of personally identifiable information the SDK can detect.
///
/// The first twelve cases correspond one-to-one to the labels emitted by the
/// `masker-mini` neural model. The final two (``ipAddress`` and ``iban``) are
/// produced only by the deterministic rules layer, which validates them with a
/// checksum before emitting — the neural model has no label for them.
public enum PIIType: String, Codable, Sendable, Hashable, CaseIterable {
    // MARK: Model-emitted types (masker-mini's 12 BIOES entity types)
    case date          = "DATE"
    case email         = "EMAIL"
    case creditCard    = "CREDIT_CARD"
    case phone         = "PHONE"
    case governmentID  = "GOVERNMENT_ID"
    case zipCode       = "ZIP_CODE"
    case age           = "AGE"
    case buildingNumber = "BUILDING_NUMBER"
    case city          = "CITY"
    case streetName    = "STREET_NAME"
    case givenName     = "GIVEN_NAME"
    case surname       = "SURNAME"

    // MARK: Deterministic-only structured types (no neural label)
    case ipAddress     = "IP_ADDRESS"
    case iban          = "IBAN"

    /// The types the neural model can emit.
    public static let modelTypes: Set<PIIType> = [
        .date, .email, .creditCard, .phone, .governmentID, .zipCode,
        .age, .buildingNumber, .city, .streetName, .givenName, .surname,
    ]

    /// The types the deterministic (regex + checksum) layer can emit.
    public static let deterministicTypes: Set<PIIType> = [
        .email, .ipAddress, .iban, .creditCard, .governmentID,
    ]
}
