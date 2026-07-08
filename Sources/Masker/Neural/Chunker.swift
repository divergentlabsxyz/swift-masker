import Foundation

/// Splits a long token sequence into fixed-width windows so inputs longer than
/// the model's 256-token limit are fully covered.
///
/// Each window reserves two slots for `[CLS]`/`[SEP]`, so it holds up to
/// `maxLength - 2` content tokens. Adjacent windows share `overlap` tokens so an
/// entity that straddles a window boundary still appears whole in at least one
/// window; duplicate detections in the shared region are reconciled downstream.
struct Chunker {
    let maxLength: Int
    let overlap: Int

    init(maxLength: Int = 256, overlap: Int = 32) {
        self.maxLength = maxLength
        // Overlap must leave room for forward progress.
        self.overlap = max(0, min(overlap, maxLength - 3))
    }

    /// The number of content tokens per window.
    var contentCapacity: Int { maxLength - 2 }

    /// Produces windows of content tokens. A sequence that fits in one window
    /// yields a single window.
    func windows(_ tokens: [EncodedToken]) -> [[EncodedToken]] {
        guard tokens.count > contentCapacity else {
            return tokens.isEmpty ? [] : [tokens]
        }
        let stride = max(1, contentCapacity - overlap)
        var windows: [[EncodedToken]] = []
        var start = 0
        while start < tokens.count {
            let end = min(start + contentCapacity, tokens.count)
            windows.append(Array(tokens[start..<end]))
            if end == tokens.count { break }
            start += stride
        }
        return windows
    }
}
