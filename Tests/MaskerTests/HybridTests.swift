import Testing
@testable import Masker

@Suite("Hybrid pipeline — neural + deterministic together")
struct HybridTests {

    @Test("Model and rules entities are both surfaced with correct sources")
    func bothLayers() async throws {
        let text = "Ada emailed ada@x.io yesterday"
        let modelHit = Fixture.entity(.givenName, "Ada", in: text, source: .model, confidence: 0.95)
        let masker = Masker(configuration: .default, neural: MockNeuralDetector(entities: [modelHit]))

        let entities = try await masker.detect(text)
        let byType = Dictionary(grouping: entities, by: \.type)
        #expect(byType[.givenName]?.first?.source == .model)
        #expect(byType[.email]?.first?.source == .rules)
        #expect(entities.count == 2)
    }

    @Test("On an email both layers find, the rules (checksum-certain) match wins")
    func rulesWinConflict() async throws {
        let text = "Contact ada@x.io"
        // The model also (fuzzily) tags the email span.
        let modelHit = Fixture.entity(.email, "ada@x.io", in: text, source: .model, confidence: 0.99)
        let masker = Masker(configuration: .default, neural: MockNeuralDetector(entities: [modelHit]))

        let entities = try await masker.detect(text)
        #expect(entities.count == 1)
        #expect(entities[0].source == .rules)
    }

    @Test("The confidence threshold drops weak model spans")
    func thresholdFiltersModel() async throws {
        let text = "Maybe Ada"
        let weak = Fixture.entity(.givenName, "Ada", in: text, source: .model, confidence: 0.20)
        var config = MaskerConfiguration.default
        config.confidenceThreshold = 0.5
        let masker = Masker(configuration: config, neural: MockNeuralDetector(entities: [weak]))
        #expect(try await masker.detect(text).isEmpty)
    }

    @Test("Disabling the deterministic layer leaves only model output")
    func deterministicOff() async throws {
        let text = "Ada at ada@x.io"
        let modelHit = Fixture.entity(.givenName, "Ada", in: text, source: .model, confidence: 0.9)
        var config = MaskerConfiguration.default
        config.enableDeterministicLayer = false
        let masker = Masker(configuration: config, neural: MockNeuralDetector(entities: [modelHit]))

        let entities = try await masker.detect(text)
        #expect(entities.count == 1)
        #expect(entities[0].type == .givenName)
    }

    @Test("The bundled model loads and drives the full hybrid detector")
    func bundledModelLoads() async throws {
        let masker = try await Masker()
        let entities = try await masker.detect("Ada Lovelace lives in Amsterdam.")
        // Names/city come from the model; every span must be exact.
        for e in entities { #expect(String("Ada Lovelace lives in Amsterdam."[e.range]) == String(e.text)) }
        let byType = Dictionary(grouping: entities, by: \.type).mapValues { $0.map { String($0.text) } }
        #expect(byType[.givenName]?.contains("Ada") == true)
        #expect(byType[.surname]?.contains("Lovelace") == true)
        #expect(byType[.city]?.contains("Amsterdam") == true)
    }
}
