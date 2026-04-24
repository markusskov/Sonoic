import SwiftUI

struct HomeTheaterTVDiagnosticsCard: View {
    let isTVAudioActive: Bool
    let nowPlaying: SonosNowPlayingSnapshot
    let nowPlayingDiagnostics: SonosNowPlayingDiagnostics
    let tvDiagnostics: SonosHomeTheaterTVDiagnostics

    var body: some View {
        RoomSurfaceCard {
            HomeTheaterDiagnosticRow(
                title: "TV Audio",
                value: isTVAudioActive ? "Active" : "Inactive",
                systemImage: isTVAudioActive ? "tv.fill" : "tv"
            )

            Divider()

            HomeTheaterDiagnosticRow(
                title: "Source",
                value: nowPlaying.sourceName,
                systemImage: "music.note.list"
            )

            HomeTheaterDiagnosticRow(
                title: "Playback",
                value: nowPlaying.playbackState.title,
                systemImage: nowPlaying.playbackState.systemImage
            )

            currentURIRow
            trackURIRow

            Divider()

            HomeTheaterDiagnosticRow(
                title: "Remote",
                value: boolText(tvDiagnostics.remoteConfigured),
                systemImage: "button.programmable"
            )

            HomeTheaterDiagnosticRow(
                title: "IR Repeater",
                value: tvDiagnostics.irRepeaterState ?? "Unavailable",
                systemImage: "dot.radiowaves.left.and.right"
            )

            HomeTheaterDiagnosticRow(
                title: "LED Feedback",
                value: tvDiagnostics.ledFeedbackState ?? "Unavailable",
                systemImage: "lightbulb"
            )
        }
    }

    @ViewBuilder
    private var currentURIRow: some View {
        if let currentURI = nowPlayingDiagnostics.currentURI {
            Divider()

            HomeTheaterDiagnosticRow(
                title: "Current URI",
                value: currentURI,
                systemImage: "link",
                isMonospaced: true
            )
        }
    }

    @ViewBuilder
    private var trackURIRow: some View {
        if let trackURI = nowPlayingDiagnostics.trackURI,
           trackURI != nowPlayingDiagnostics.currentURI
        {
            HomeTheaterDiagnosticRow(
                title: "Track URI",
                value: trackURI,
                systemImage: "link.badge.plus",
                isMonospaced: true
            )
        }
    }
}

private struct HomeTheaterDiagnosticRow: View {
    let title: String
    let value: String
    let systemImage: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(isMonospaced ? 3 : 2)
                .minimumScaleFactor(0.82)
                .textSelection(.enabled)
        }
    }
}

private func boolText(_ value: Bool?) -> String {
    guard let value else {
        return "Unavailable"
    }

    return value ? "Yes" : "No"
}
