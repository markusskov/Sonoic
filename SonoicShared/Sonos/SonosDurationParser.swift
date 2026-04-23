import Foundation

enum SonosDurationParser {
    nonisolated static func parseTimeInterval(from value: String?) -> TimeInterval? {
        guard let value = value.sonoicNonEmptyTrimmed, value != "NOT_IMPLEMENTED" else {
            return nil
        }

        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = TimeInterval(components[2])
        else {
            return nil
        }

        return TimeInterval(hours * 3600 + minutes * 60) + seconds
    }
}
