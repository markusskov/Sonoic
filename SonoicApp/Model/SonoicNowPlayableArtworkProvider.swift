import ImageIO
import MediaPlayer
import UIKit

enum SonoicNowPlayableArtworkProvider {
    static func artwork(for identifier: String?) -> MPMediaItemArtwork? {
        guard let identifier,
              let artworkStore = try? SonoicSharedArtworkStore(),
              let data = artworkStore.loadArtworkData(named: identifier)
        else {
            return nil
        }

        let previewSize = downsampledArtworkImage(from: data)?.size ?? CGSize(width: 512, height: 512)
        let artworkSize = CGSize(
            width: max(previewSize.width, 1),
            height: max(previewSize.height, 1)
        )

        return MPMediaItemArtwork(boundsSize: artworkSize) { @Sendable requestedSize in
            let requestedMaxDimension = max(requestedSize.width, requestedSize.height, 1)
            return downsampledArtworkImage(from: data, maxDimension: requestedMaxDimension) ?? UIImage()
        }
    }

    nonisolated static func downsampledArtworkImage(
        from data: Data,
        maxDimension: CGFloat = 512
    ) -> UIImage? {
        let options: CFDictionary = [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
