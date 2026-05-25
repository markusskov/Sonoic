import Foundation

enum SonoicSonosControlAPIQueueItemIDBuilder {
    static let maximumLength = 128

    static func uniqueID(
        index: Int,
        objectID: String,
        itemID: String,
        usedIDs: Set<String>
    ) -> String {
        let baseID = sanitizedID("sonoic-\(index + 1)-\(objectID)-\(itemID)")
        guard usedIDs.contains(baseID) else {
            return baseID
        }

        var suffix = index + 1
        while true {
            let candidate = suffixedID(baseID, suffix: suffix)
            if !usedIDs.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func sanitizedID(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(sanitizedScalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .sonoicTrimmed
        return String(sanitized.prefix(maximumLength))
    }

    private static func suffixedID(_ id: String, suffix: Int) -> String {
        let suffixValue = "-\(suffix)"
        let maxBaseLength = max(0, maximumLength - suffixValue.count)
        return "\(String(id.prefix(maxBaseLength)))\(suffixValue)"
    }
}
