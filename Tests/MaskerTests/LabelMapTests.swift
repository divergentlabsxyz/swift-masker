import Foundation
import Testing
@testable import Masker

@Suite("LabelMap — the 49-class BIOES mapping from config.json")
struct LabelMapTests {

    @Test("The bundled config yields exactly 49 classes")
    func bundledCount() throws {
        let map = try LabelMap.bundled()
        #expect(map.classCount == 49)
        #expect(map.outsideIndex == 0)
    }

    @Test("Known indices decode to the right prefix and type")
    func decodeKnownIndices() throws {
        let map = try LabelMap.bundled()
        #expect(map.decode(0) == nil)                                   // O
        let email = try #require(map.decode(21))
        #expect(email.type == .email && email.prefix == .begin)         // B-EMAIL
        let emailSingle = try #require(map.decode(24))
        #expect(emailSingle.type == .email && emailSingle.prefix == .single) // S-EMAIL
        let govBegin = try #require(map.decode(29))
        #expect(govBegin.type == .governmentID && govBegin.prefix == .begin)
        let zipSingle = try #require(map.decode(48))
        #expect(zipSingle.type == .zipCode && zipSingle.prefix == .single)
    }

    @Test("Every model type is representable")
    func allTypesPresent() throws {
        let map = try LabelMap.bundled()
        let decodedTypes = Set((0..<map.classCount).compactMap { map.decode($0)?.type })
        #expect(decodedTypes == PIIType.modelTypes)
    }

    @Test("Malformed config throws")
    func malformed() {
        #expect(throws: MaskerError.self) {
            _ = try LabelMap(configJSON: Data("{}".utf8))
        }
    }

    @Test("Out-of-range indices decode to nil")
    func outOfRange() throws {
        let map = try LabelMap.bundled()
        #expect(map.decode(-1) == nil)
        #expect(map.decode(999) == nil)
    }
}
