import SwiftUI
import UIKit

struct PlayerFullscreenArtworkBackground: View {
    let artworkImage: UIImage?
    let size: CGSize

    var body: some View {
        ZStack {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
                    .blur(radius: 56)
                    .saturation(1.25)
                    .scaleEffect(1.18)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.16, blue: 0.15),
                        Color(red: 0.05, green: 0.06, blue: 0.05),
                        .black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.08),
                    .black.opacity(0.58),
                    .black.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

struct PlayerFullscreenHeroArtwork: View {
    let artworkImage: UIImage?
    let size: CGSize

    var body: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height, alignment: .top)
            } else {
                LinearGradient(
                    colors: [.orange.opacity(0.75), .pink.opacity(0.72), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.68),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
        }
    }
}
