import Masker

// End-to-end demonstration of the full hybrid detector (bundled Core ML model +
// deterministic rules layer).
//
//   swift run masker-demo                       # runs the built-in sample
//   swift run masker-demo "your own text here"  # runs your text instead

let defaultSample = """
Hi, I'm Ada Lovelace from Amsterdam. Email me at ada.lovelace@example.com or \
call about invoice NL91 ABNA 0417 1643 00. Card on file 4111 1111 1111 1111, \
BSN 123456782, server 192.168.1.1.
"""

// Any extra command-line arguments become the input (joined with spaces so an
// unquoted phrase still works).
let customText = CommandLine.arguments.dropFirst().joined(separator: " ")
let usingCustomText = !customText.isEmpty
let sample = usingCustomText ? customText : defaultSample

let masker = try await Masker()   // loads the bundled model

print("── INPUT ──────────────────────────────────────────")
print(sample)

let entities = try await masker.detect(sample)
print("\n── DETECTED (\(entities.count)) ────────────────────────────────")
for e in entities {
    let conf = String(format: "%.2f", e.confidence)
    print("  \(e.type.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0))  \(conf)  [\(e.source.rawValue)]  \"\(e.text)\"")
}

print("\n── REDACTED (.label) ──────────────────────────────")
print(try await masker.redact(sample, style: .label))

print("\n── MASKED (reversible, safe to send to an LLM) ────")
let masked = try await masker.mask(sample)
print(masked.text)

print("\n── VAULT (stays on-device) ────────────────────────")
for (placeholder, original) in masked.session.map.sorted(by: { $0.key < $1.key }) {
    print("  \(placeholder)  →  \(original)")
}

// Simulate an LLM reply that used the placeholders, then restore on-device.
let pretendLLMReply = "I'll email [EMAIL_1] and charge [CREDIT_CARD_1]."
let restored = masker.unmask(pretendLLMReply, with: masked.session)
print("\n── UNMASK an LLM reply ────────────────────────────")
print("  reply:    \(pretendLLMReply)")
print("  restored: \(restored)")

// Verify the round-trip is lossless.
let roundTrip = masker.unmask(masked.text, with: masked.session)
print("\nRound-trip lossless: \(roundTrip == sample ? "✅ yes" : "❌ no")")

// With the built-in sample, also show a Dutch example (the model's flagship
// language). Skipped when the user supplied their own text.
if !usingCustomText {
    print("\n── DUTCH ──────────────────────────────────────────")
    let dutch = "Ik ben Jan de Vries uit Utrecht; mijn collega heet José García."
    for e in try await masker.detect(dutch) {
        print("  \(e.type.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0))  [\(e.source.rawValue)]  \"\(e.text)\"")
    }
}
