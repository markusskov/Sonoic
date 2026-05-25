import Foundation

enum SonoicSonosControlAPIQueueCurrentIndexResolver {
    nonisolated static func currentIndex(
        itemIDs: [String],
        candidates: [String?]
    ) -> Int? {
        let normalizedCandidates = candidates.compactMap(\.?.sonoicNonEmptyTrimmed)

        for candidate in normalizedCandidates {
            if let exactIndex = itemIDs.firstIndex(of: candidate) {
                return exactIndex
            }
        }

        for candidate in normalizedCandidates {
            if let oneBasedIndex = Int(candidate),
               itemIDs.indices.contains(oneBasedIndex - 1)
            {
                return oneBasedIndex - 1
            }
        }

        return nil
    }
}
