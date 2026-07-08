import Testing
@testable import Masker

@Suite("BIOES decoder — token predictions to character spans")
struct BIOESDecoderTests {

    private func predictions(
        _ items: [(surface: String, classIndex: Int, confidence: Double)],
        in text: String
    ) -> [BIOESDecoder.Prediction] {
        items.map { item in
            .init(token: Fixture.token(0, item.surface, in: text),
                  classIndex: item.classIndex,
                  confidence: item.confidence)
        }
    }

    @Test("Two adjacent S- tokens become two separate entities")
    func singletons() {
        let text = "Ada Byron"
        let map = LabelMap(labels: ["O", "S-GIVEN_NAME", "S-SURNAME"])
        let preds = predictions([("Ada", 1, 0.95), ("Byron", 2, 0.90)], in: text)
        let entities = BIOESDecoder.decode(preds, labelMap: map, in: text)

        #expect(entities.count == 2)
        #expect(entities[0].type == .givenName && entities[0].text == "Ada")
        #expect(entities[1].type == .surname && entities[1].text == "Byron")
        #expect(entities.allSatisfy { $0.source == .model })
    }

    @Test("B- … E- forms one multi-token entity with a merged span")
    func multiToken() {
        let text = "New York rocks"
        let map = LabelMap(labels: ["O", "B-CITY", "E-CITY"])
        let preds = predictions([("New", 1, 0.8), ("York", 2, 0.6)], in: text)
        let entities = BIOESDecoder.decode(preds, labelMap: map, in: text)

        #expect(entities.count == 1)
        #expect(entities[0].type == .city)
        #expect(entities[0].text == "New York")
        #expect(abs(entities[0].confidence - 0.7) < 1e-9)   // mean of 0.8, 0.6
    }

    @Test("A stray I- without a B- still opens a span (lenient recovery)")
    func lenientRecovery() {
        let text = "New York rocks"
        let map = LabelMap(labels: ["O", "I-CITY"])
        let preds = predictions([("New", 1, 0.7), ("York", 1, 0.7)], in: text)
        let entities = BIOESDecoder.decode(preds, labelMap: map, in: text)

        #expect(entities.count == 1)
        #expect(entities[0].text == "New York")
    }

    @Test("An O label closes the current span")
    func outsideCloses() {
        let text = "New big York"
        let map = LabelMap(labels: ["O", "B-CITY", "E-CITY"])
        // New(B) big(O) York(E) → the O breaks it into two fragments.
        let preds = predictions([("New", 1, 0.9), ("big", 0, 0.9), ("York", 2, 0.9)], in: text)
        let entities = BIOESDecoder.decode(preds, labelMap: map, in: text)

        // "New" opened but never ended, then O flushes it; "York" opens on E and flushes.
        #expect(entities.count == 2)
        #expect(entities[0].text == "New")
        #expect(entities[1].text == "York")
    }
}
