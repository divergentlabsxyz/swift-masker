import Foundation

/// The BIOES tag prefix for a label.
enum BIOESPrefix: Equatable {
    case begin   // B- : first token of a multi-token entity
    case inside  // I- : interior token
    case end     // E- : last token of a multi-token entity
    case single  // S- : a one-token entity
}

/// Maps the model's 49 output class indices to `(prefix, type)` pairs, loaded
/// from the model's own `config.json` so the ordering can never drift from the
/// weights.
struct LabelMap: Sendable {
    /// index → raw label, e.g. `"O"`, `"B-EMAIL"`, `"S-ZIP_CODE"`.
    let labels: [String]

    var classCount: Int { labels.count }

    /// The `"O"` (outside) class index, if present.
    var outsideIndex: Int? { labels.firstIndex(of: "O") }

    /// Decodes a class index into a BIOES prefix and ``PIIType``.
    /// Returns `nil` for `"O"` or any non-entity / unrecognised label.
    func decode(_ index: Int) -> (prefix: BIOESPrefix, type: PIIType)? {
        guard labels.indices.contains(index) else { return nil }
        let label = labels[index]
        guard label != "O", let dash = label.firstIndex(of: "-") else { return nil }

        let prefixString = label[label.startIndex..<dash]
        let typeString = String(label[label.index(after: dash)...])
        guard let type = PIIType(rawValue: typeString) else { return nil }

        let prefix: BIOESPrefix
        switch prefixString {
        case "B": prefix = .begin
        case "I": prefix = .inside
        case "E": prefix = .end
        case "S": prefix = .single
        default:  return nil
        }
        return (prefix, type)
    }

    // MARK: - Loading

    /// Builds a label map from a HF `config.json` payload (reads `id2label`).
    init(configJSON data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id2label = root["id2label"] as? [String: Any]
        else {
            throw MaskerError.labelConfigurationInvalid("missing id2label")
        }

        // id2label keys are stringified indices; place each at its numeric slot.
        var pairs: [(Int, String)] = []
        for (key, value) in id2label {
            guard let index = Int(key), let label = value as? String else {
                throw MaskerError.labelConfigurationInvalid("bad entry \(key)")
            }
            pairs.append((index, label))
        }
        guard let maxIndex = pairs.map(\.0).max() else {
            throw MaskerError.labelConfigurationInvalid("empty id2label")
        }
        var ordered = [String](repeating: "O", count: maxIndex + 1)
        for (index, label) in pairs { ordered[index] = label }
        self.labels = ordered
    }

    init(labels: [String]) {
        self.labels = labels
    }

    /// Loads the label map from the bundled `config.json` resource.
    static func bundled() throws -> LabelMap {
        guard let url = Bundle.module.url(forResource: "config", withExtension: "json") else {
            throw MaskerError.labelConfigurationInvalid("config.json not in bundle")
        }
        return try LabelMap(configJSON: Data(contentsOf: url))
    }
}
