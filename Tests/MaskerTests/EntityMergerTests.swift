import Testing
@testable import Masker

@Suite("Entity merger — combining the two layers")
struct EntityMergerTests {

    private let text = "Mail ada@x.com to Ada today"

    @Test("On overlap, the rules match wins when deterministic-wins is set")
    func rulesWinOnOverlap() {
        let rules = Fixture.entity(.email, "ada@x.com", in: text, source: .rules)
        let model = Fixture.entity(.email, "ada@x.com", in: text, source: .model, confidence: 0.99)
        let merged = EntityMerger.merge(model: [model], rules: [rules],
                                        deterministicWins: true, allowedTypes: nil)
        #expect(merged.count == 1)
        #expect(merged[0].source == .rules)
    }

    @Test("With deterministic-wins off, higher confidence wins the overlap")
    func confidenceWins() {
        let rules = Fixture.entity(.email, "ada@x.com", in: text, source: .rules, confidence: 1.0)
        let model = Fixture.entity(.email, "ada@x.com", in: text, source: .model, confidence: 0.5)
        let merged = EntityMerger.merge(model: [model], rules: [rules],
                                        deterministicWins: false, allowedTypes: nil)
        #expect(merged.count == 1)
        #expect(merged[0].source == .rules)   // 1.0 > 0.5
    }

    @Test("Non-overlapping entities from both layers are all kept, in order")
    func keepsNonOverlapping() {
        let email = Fixture.entity(.email, "ada@x.com", in: text, source: .rules)
        let name = Fixture.entity(.givenName, "Ada", in: text, source: .model, confidence: 0.9)
        let merged = EntityMerger.merge(model: [name], rules: [email],
                                        deterministicWins: true, allowedTypes: nil)
        #expect(merged.count == 2)
        #expect(merged[0].range.lowerBound < merged[1].range.lowerBound)  // document order
        #expect(merged.map(\.type) == [.email, .givenName])
    }

    @Test("allowedTypes filters the merged set")
    func filtersTypes() {
        let email = Fixture.entity(.email, "ada@x.com", in: text, source: .rules)
        let name = Fixture.entity(.givenName, "Ada", in: text, source: .model, confidence: 0.9)
        let merged = EntityMerger.merge(model: [name], rules: [email],
                                        deterministicWins: true, allowedTypes: [.email])
        #expect(merged.map(\.type) == [.email])
    }
}
