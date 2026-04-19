import SwiftUI
import UIKit

struct PlayerArtworkView: View {
    let artworkIdentifier: String?
    let reloadKey: String
    let cornerRadius: CGFloat

    @State private var artworkImage: UIImage?

    var body: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.8), .pink.opacity(0.7), .indigo.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .task(id: reloadKey) {
            artworkImage = await loadArtworkImage()
        }
    }

    private func loadArtworkImage() async -> UIImage? {
        let artworkIdentifier = artworkIdentifier

        return await Task.detached(priority: .utility) {
            guard let artworkIdentifier,
                  let artworkStore = try? SonoicSharedArtworkStore(),
                  let data = artworkStore.loadArtworkData(named: artworkIdentifier)
            else {
                return nil
            }

            return UIImage(data: data)
        }.value
    }
}

#Preview {
    PlayerArtworkView(artworkIdentifier: nil, reloadKey: "preview", cornerRadius: 24)
        .frame(width: 180, height: 180)
        .padding()
}
