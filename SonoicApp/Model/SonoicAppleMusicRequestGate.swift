import Foundation
@preconcurrency import MusicKit

actor SonoicMusicKitRequestGate {
    static let artistArtworkFallbackLimit = 12
    static let playlistArtworkFallbackLimit = 12
    static let relatedTrackPageLimit = 100

    var cachedStorefrontCountryCode: String?

    func fetchServiceDetails() async throws -> AppleMusicServiceMetadata {
        let subscription = try await MusicSubscription.current
        let storefrontCountryCode = try await storefrontCountryCode()

        return AppleMusicServiceMetadata(
            storefrontCountryCode: storefrontCountryCode,
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            canBecomeSubscriber: subscription.canBecomeSubscriber,
            hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
    }
}
