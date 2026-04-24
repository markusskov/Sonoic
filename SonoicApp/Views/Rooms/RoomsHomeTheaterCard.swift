import SwiftUI

struct RoomsHomeTheaterCard: View {
    let roomName: String
    let sourceName: String
    let isTVAudioActive: Bool
    let hasSubwoofer: Bool
    let hasSurrounds: Bool
    let settings: SonosHomeTheaterSettings?
    let isRefreshing: Bool

    private var summaryText: String {
        if isTVAudioActive {
            return "\(roomName) is on TV Audio."
        }

        if let settings {
            return "Bass \(signedValue(settings.bass)), treble \(signedValue(settings.treble)) while \(sourceName) is active."
        }

        return "EQ, sub, speech, night sound, and TV checks for \(roomName)."
    }

    private var badges: [String] {
        var values = ["EQ"]

        if hasSubwoofer || settings?.supportsSubLevel == true {
            values.append("Sub")
        }

        if hasSurrounds {
            values.append("Surrounds")
        }

        if settings?.supportsSpeechEnhancement == true {
            values.append("Speech")
        }

        if settings?.supportsNightSound == true {
            values.append("Night")
        }

        if isTVAudioActive {
            values.append("TV")
        }

        return values
    }

    var body: some View {
        RoomSurfaceCard(isInteractive: true) {
            HStack(alignment: .top, spacing: 14) {
                RoomSurfaceIconView(systemImage: "theatermasks.fill")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Home Theater")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                trailingIcon
            }

            HStack(spacing: 8) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 6)
        } else {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }

    private func signedValue(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
