import SwiftUI
import UIKit

struct PlayerArtworkView: View {
    @Environment(\.displayScale) private var displayScale

    let artworkIdentifier: String?
    let reloadKey: String
    let cornerRadius: CGFloat
    let maximumDisplayDimension: CGFloat

    @State private var artworkImage: UIImage?

    var body: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                SonoicArtworkPlaceholderView(cornerRadius: cornerRadius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .task(id: reloadKey) {
            artworkImage = await loadArtworkImage(
                maxPixelDimension: max(maximumDisplayDimension * displayScale, 1)
            )
        }
    }

    private func loadArtworkImage(maxPixelDimension: CGFloat) async -> UIImage? {
        await PlayerArtworkImageLoader.loadArtworkImage(
            artworkIdentifier: artworkIdentifier,
            maxPixelDimension: maxPixelDimension
        )
    }
}

#Preview {
    PlayerArtworkView(
        artworkIdentifier: nil,
        reloadKey: "preview",
        cornerRadius: 24,
        maximumDisplayDimension: 180
    )
        .frame(width: 180, height: 180)
        .padding()
}
