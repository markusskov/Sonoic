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

    nonisolated var title: String {
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

struct SonoicAppleMusicServiceDetails: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var status: Status = .idle
    var storefrontCountryCode: String?
    var canPlayCatalogContent: Bool?
    var canBecomeSubscriber: Bool?
    var hasCloudLibraryEnabled: Bool?

    static let idle = SonoicAppleMusicServiceDetails()

    static func loaded(
        storefrontCountryCode: String,
        canPlayCatalogContent: Bool,
        canBecomeSubscriber: Bool,
        hasCloudLibraryEnabled: Bool
    ) -> SonoicAppleMusicServiceDetails {
        SonoicAppleMusicServiceDetails(
            status: .loaded,
            storefrontCountryCode: storefrontCountryCode,
            canPlayCatalogContent: canPlayCatalogContent,
            canBecomeSubscriber: canBecomeSubscriber,
            hasCloudLibraryEnabled: hasCloudLibraryEnabled
        )
    }

    static func failed(_ detail: String) -> SonoicAppleMusicServiceDetails {
        SonoicAppleMusicServiceDetails(status: .failed(detail))
    }

    var isLoading: Bool {
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }
}

enum SonoicAppleMusicEndpointFamily: String, Equatable, Sendable {
    case serviceDetails
    case search
    case recentlyAdded
    case library
    case browse
    case itemDetail

    nonisolated var title: String {
        switch self {
        case .serviceDetails:
            "Apple Music Details"
        case .search:
            "Catalog Search"
        case .recentlyAdded:
            "Recently Added"
        case .library:
            "Library"
        case .browse:
            "Browse"
        case .itemDetail:
            "Item Detail"
        }
    }
}

enum SonoicAppleMusicRequestFailureKind: String, Equatable, Sendable {
    case missingDeveloperTokenSetup
    case unauthorized
    case networkUnavailable
    case storefrontUnavailable
    case rateLimited
    case unknown

    nonisolated var title: String {
        switch self {
        case .missingDeveloperTokenSetup:
            "MusicKit Service Missing"
        case .unauthorized:
            "Apple Music Not Authorized"
        case .networkUnavailable:
            "Network Unavailable"
        case .storefrontUnavailable:
            "Storefront Unavailable"
        case .rateLimited:
            "Apple Music Rate Limited"
        case .unknown:
            "Apple Music Request Failed"
        }
    }

    nonisolated var recoveryDetail: String {
        switch self {
        case .missingDeveloperTokenSetup:
            "Confirm the MusicKit App Service is enabled for this bundle ID in Apple Developer, then rebuild after the App ID has propagated."
        case .unauthorized:
            "Authorize Apple Music before using catalog or library metadata."
        case .networkUnavailable:
            "Check the device connection and try again."
        case .storefrontUnavailable:
            "Apple Music could not resolve a storefront for this account right now."
        case .rateLimited:
            "Apple Music is throttling requests. Wait a moment, then refresh again."
        case .unknown:
            "Try again. If this repeats, the raw error below is useful for debugging."
        }
    }
}

struct SonoicAppleMusicRequestFailure: Equatable, Sendable {
    var kind: SonoicAppleMusicRequestFailureKind
    var endpointFamily: SonoicAppleMusicEndpointFamily
    var occurredAt: Date
    var rawDetail: String

    init(
        kind: SonoicAppleMusicRequestFailureKind,
        endpointFamily: SonoicAppleMusicEndpointFamily,
        occurredAt: Date = .now,
        rawDetail: String
    ) {
        self.kind = kind
        self.endpointFamily = endpointFamily
        self.occurredAt = occurredAt
        self.rawDetail = rawDetail
    }

    nonisolated var title: String {
        kind.title
    }

    nonisolated var displayDetail: String {
        "\(kind.recoveryDetail)\n\n\(endpointFamily.title): \(rawDetail)"
    }
}

struct SonoicAppleMusicRequestReadiness: Equatable {
    enum Status: Equatable {
        case idle
        case ready
        case failed
    }

    var status: Status = .idle
    var lastFailure: SonoicAppleMusicRequestFailure?

    static let idle = SonoicAppleMusicRequestReadiness()

    static func ready(preserving previous: SonoicAppleMusicRequestReadiness) -> SonoicAppleMusicRequestReadiness {
        SonoicAppleMusicRequestReadiness(status: .ready, lastFailure: previous.lastFailure)
    }

    static func failed(_ failure: SonoicAppleMusicRequestFailure) -> SonoicAppleMusicRequestReadiness {
        SonoicAppleMusicRequestReadiness(status: .failed, lastFailure: failure)
    }

    var title: String {
        switch status {
        case .idle:
            "Not Probed"
        case .ready:
            "Ready"
        case .failed:
            lastFailure?.title ?? "Request Failed"
        }
    }

    var detail: String {
        switch status {
        case .idle:
            "Sonoic has not made a MusicKit metadata request in this session."
        case .ready:
            "The latest MusicKit metadata request completed successfully."
        case .failed:
            lastFailure?.displayDetail ?? "The latest MusicKit request failed."
        }
    }
}

struct SonoicMusicKitDiagnostics: Equatable {
    var bundleIdentifier: String
    var hasUsageDescription: Bool
    var usesAutomaticDeveloperTokenGeneration: Bool

    static var current: SonoicMusicKitDiagnostics {
        SonoicMusicKitDiagnostics(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown",
            hasUsageDescription: Bundle.main.object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") != nil,
            usesAutomaticDeveloperTokenGeneration: true
        )
    }
}
