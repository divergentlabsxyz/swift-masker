import Foundation

/// Combines the neural and deterministic entity sets into one coherent,
/// non-overlapping list.
enum EntityMerger {

    /// Merges `model` and `rules` entities.
    ///
    /// - On an overlap, the higher-priority entity wins: rules if
    ///   `deterministicWins`, otherwise whichever has greater confidence.
    /// - `allowedTypes`, when non-nil, filters the final set.
    /// - The result is sorted in document order and free of overlaps.
    static func merge(
        model: [PIIEntity],
        rules: [PIIEntity],
        deterministicWins: Bool,
        allowedTypes: Set<PIIType>?
    ) -> [PIIEntity] {
        let candidates = (model + rules).filter { allowedTypes?.contains($0.type) ?? true }

        // Higher priority sorts first: preferred source, then longer span, then
        // higher confidence, then earlier start (stable, deterministic order).
        let ordered = candidates.sorted { lhs, rhs in
            let lhsPreferred = deterministicWins && lhs.source == .rules
            let rhsPreferred = deterministicWins && rhs.source == .rules
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            if lhs.text.count != rhs.text.count { return lhs.text.count > rhs.text.count }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }

        var accepted: [PIIEntity] = []
        for entity in ordered where !accepted.contains(where: { $0.range.overlaps(entity.range) }) {
            accepted.append(entity)
        }
        return accepted.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
