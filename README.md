# Masker

On-device PII detection, redaction, and **reversible masking** for iOS & macOS,
built around the [`divergentlabs/masker-mini`](https://huggingface.co/divergentlabs/masker-mini)
classifier model (v2 bundled).

| Layer                          | Handles                                                | How                                                               |
| ------------------------------ | ------------------------------------------------------ | ----------------------------------------------------------------- |
| **Deterministic** (pure Swift) | emails, IP v4/v6, IBAN, credit cards, gov-IDs          | regex + **checksum** validation (Luhn, ISO 7064 mod-97, elfproef) |
| **Neural** (Core ML)           | names, cities, streets, dates, ages, phones, zip codes | `masker-mini`, 256-token BIOES token classifier                   |

The deterministic layer is exact (a match must pass its checksum) and needs no
model, so it runs anywhere — including CI. The neural layer adds the fuzzy,
contextual entities. Their results are merged into one non-overlapping, exact-span
set where **`text[entity.range] == entity.text`** always holds.

> Everything runs on-device. In the LLM round-trip, only placeholders leave the
> device; the vault mapping placeholders back to originals never does.

## Install

```swift
.package(url: "https://github.com/divergentlabsxyz/swift-masker.git", from: "0.2.0")
```

Platforms: **iOS 18+, macOS 15+** (Swift 6).

## Uses

```swift
import Masker

let masker = try await Masker()                // full hybrid; the model is bundled
// let masker = Masker.deterministicOnly()      // rules layer only, skips loading the model
```

The Core ML model and tokenizer ship **inside the package** — no download, no
setup. `Masker()` loads them; `deterministicOnly()` skips the model when you only
need structured PII.

The bundled model is **masker-mini v2** (4-bit Core ML, 18 MB). Compared with
v1 it finds person names on real-world text much more reliably (names F1
0.627 → 0.774 on real court judgments and Dutch news). See the
[model card](https://huggingface.co/divergentlabs/masker-mini) for evaluation
and limitations.

### Detection only

```swift
for e in try await masker.detect(text) {
    print(e.type, e.text, e.confidence, e.source)   // .email "ada@x.com" 1.0 .rules
}
```

### Redaction (non-reversible)

```swift
try await masker.redact(text, style: .label)              // "[EMAIL]"
try await masker.redact(text, style: .character("•"))     // "••••••••"
```

### Custom placeholders

```swift
try await masker.redact(text, style: .custom { entity, _ in "‹\(entity.type.rawValue)›" })
```

### Reversible masking → LLM → restore (raw PII stays on-device)

```swift
let masked = try await masker.mask(userText)        // "[EMAIL_1] lives in [CITY_1]"
let reply  = try await myLLM.complete(masked.text)  // the service sees only placeholders
let final  = masker.unmask(reply, with: masked.session)   // originals filled back in, on-device
```

Placeholders are **stable per distinct value** (the same email always maps to
`[EMAIL_1]`), so an LLM keeps coreference, and restore is unambiguous. You may
have to instruct your LLM to keep these placeholders verbatim.

## Configuration

```swift
var config = MaskerConfiguration.default
config.allowedTypes = [.email, .creditCard]     // restrict output types
config.confidenceThreshold = 0.6                // model spans only
config.enableDeterministicLayer = true
config.deterministicWinsOnOverlap = true        // checksum-certain matches win
```

## Try it

```bash
swift run masker-demo     # prints detect / redact / mask / unmask on a sample
```

## License

The `masker-mini` model is under the Offchain Studio Source License v1.0
(commercial licensing via licensing@basement.dev). This SDK wraps it; check the
model card for terms before shipping.
