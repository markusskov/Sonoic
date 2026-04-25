import Foundation

struct SonoicAppleMusicAuthorizationState: Equatable {
    enum Status: String, Equatable {
        case notDetermined
        case requesting
        case authorized
        case denied
        case restricted
        case unavailable
    }

    var status: Status

    static let unknown = SonoicAppleMusicAuthorizationState(status: .notDetermined)

    var allowsCatalogSearch: Bool {
        status == .authorized
    }

    var canRequestAuthorization: Bool {
        status == .notDetermined
    }

    var isRequestingAuthorization: Bool {
        status == .requesting
    }

    var title: String {
        switch status {
        case .notDetermined:
            "Not Connected"
        case .requesting:
            "Requesting Access"
        case .authorized:
            "Authorized"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .unavailable:
            "Unavailable"
        }
    }

    var detail: String {
        switch status {
        case .notDetermined:
            "Authorize Apple Music before searching the catalog."
        case .requesting:
            "Waiting for Apple Music permission."
        case .authorized:
            "Catalog metadata search is available. Playback still stays on Sonos."
        case .denied:
            "Enable Apple Music access in iOS Settings to search catalog metadata."
        case .restricted:
            "This device does not allow Apple Music access."
        case .unavailable:
            "Apple Music authorization is not available right now."
        }
    }

    var systemImage: String {
        switch status {
        case .authorized:
            "checkmark.circle.fill"
        case .requesting:
            "clock"
        case .denied, .restricted, .unavailable:
            "exclamationmark.triangle.fill"
        case .notDetermined:
            "music.note"
        }
    }
}
