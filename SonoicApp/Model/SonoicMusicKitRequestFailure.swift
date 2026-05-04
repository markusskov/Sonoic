import Foundation
@preconcurrency import MusicKit

struct MusicKitRequestFailure: Equatable {
    var domain: String
    var code: Int
    var message: String

    init(_ error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
    }

    nonisolated var displayDetail: String {
        "\(domain) \(code): \(message)"
    }
}

extension SonoicAppleMusicAuthorizationState.Status {
    nonisolated init(_ musicAuthorizationStatus: MusicAuthorization.Status) {
        switch musicAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unavailable
        }
    }

    nonisolated var sonoicDisplayName: String {
        switch self {
        case .notDetermined:
            "Not Determined"
        case .requesting:
            "Requesting"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .authorized:
            "Authorized"
        case .unavailable:
            "Unavailable"
        @unknown default:
            "Unavailable"
        }
    }
}
