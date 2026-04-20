import Foundation

enum SonosServiceCatalog {
    static func descriptor(named name: String?) -> SonosServiceDescriptor? {
        guard let normalizedName = name.sonoicNonEmptyTrimmed?.lowercased() else {
            return nil
        }

        return switch normalizedName {
        case "apple music":
            SonosServiceDescriptor.appleMusic
        case "spotify":
            SonosServiceDescriptor.spotify
        case "sonos radio":
            SonosServiceDescriptor.sonosRadio
        case "streaming audio":
            SonosServiceDescriptor.genericStreaming
        default:
            nil
        }
    }

    static func descriptor(from uri: String?) -> SonosServiceDescriptor? {
        guard let normalizedURI = uri.sonoicNonEmptyTrimmed?.lowercased() else {
            return nil
        }

        if let serviceID = serviceID(from: normalizedURI),
           let descriptor = descriptor(forServiceID: serviceID)
        {
            return descriptor
        }

        if normalizedURI.hasPrefix("x-sonosapi-stream:")
            || normalizedURI.hasPrefix("x-sonosapi-radio:")
            || normalizedURI.hasPrefix("x-sonosapi-hls:")
            || normalizedURI.hasPrefix("x-sonosapi-http:")
            || normalizedURI.hasPrefix("x-sonosapi-static:")
            || normalizedURI.hasPrefix("x-sonos-http:")
        {
            return .genericStreaming
        }

        return nil
    }

    private static func descriptor(forServiceID serviceID: String) -> SonosServiceDescriptor? {
        return switch serviceID {
        case "9":
            SonosServiceDescriptor.spotify
        case "204":
            SonosServiceDescriptor.appleMusic
        case "236", "254":
            SonosServiceDescriptor.sonosRadio
        default:
            nil
        }
    }

    private static func serviceID(from uri: String) -> String? {
        guard let queryRange = uri.range(of: "?") else {
            return nil
        }

        let query = uri[queryRange.upperBound...]
        let queryItems = query.split(separator: "&")

        for queryItem in queryItems {
            let parts = queryItem.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == "sid" else {
                continue
            }

            return String(parts[1])
        }

        return nil
    }
}
