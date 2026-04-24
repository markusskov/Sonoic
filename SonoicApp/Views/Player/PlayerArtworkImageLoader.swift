import UIKit

enum PlayerArtworkImageLoader {
    static func loadArtworkImage(
        artworkIdentifier: String?,
        maxPixelDimension: CGFloat
    ) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let artworkIdentifier,
                  let artworkStore = try? SonoicSharedArtworkStore(),
                  let data = artworkStore.loadArtworkData(named: artworkIdentifier)
            else {
                return nil
            }

            return SonoicNowPlayableArtworkProvider.downsampledArtworkImage(
                from: data,
                maxDimension: max(maxPixelDimension, 1)
            )
        }.value
    }
}
