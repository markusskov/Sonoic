import SwiftUI

struct AppleMusicBrowseDestinationView: View {
    let destination: SonoicAppleMusicBrowseDestination

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    currentStateCard
                    nextStepsCard
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(destination.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text(destination.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentStateCard: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Catalog Metadata")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("This lane is ready for Apple Music API results. Starts stay disabled until Sonoic has a Sonos-native playback payload.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var nextStepsCard: some View {
        RoomSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                AppleMusicBrowseStatusRow(
                    title: "Show Apple Music items",
                    subtitle: "Use the matching catalog or personalized endpoint for this lane.",
                    systemImage: "checklist"
                )
                Divider()
                    .padding(.leading, 46)
                AppleMusicBrowseStatusRow(
                    title: "Resolve Sonos playback",
                    subtitle: "Map selected results to Sonos-native service payloads before enabling Play.",
                    systemImage: "speaker.wave.2"
                )
            }
        }
    }
}

private struct AppleMusicBrowseStatusRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppleMusicBrowseDestinationView(destination: .popularRecommendations)
    }
}
