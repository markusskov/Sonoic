import SwiftUI

struct PlayerProgressSection: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let observedAt: Date
    let isEnabled: Bool
    let seek: (TimeInterval) -> Void

    @State private var isScrubbing = false
    @State private var scrubElapsedSeconds = 0.0

    var body: some View {
        TimelineView(.periodic(from: observedAt, by: 1)) { context in
            if let durationSeconds {
                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: {
                                isScrubbing ? scrubElapsedSeconds : displayedElapsedSeconds(at: context.date)
                            },
                            set: { newValue in
                                scrubElapsedSeconds = newValue
                                isScrubbing = true
                            }
                        ),
                        in: 0 ... durationSeconds,
                        onEditingChanged: handleEditingChanged
                    )
                    .disabled(!isEnabled)

                    HStack {
                        Text(elapsedLabelText(at: context.date))
                        Spacer()
                        Text(formatTime(durationSeconds))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: observedAt, initial: false) { _, _ in
            resetScrubbingState()
        }
        .onChange(of: nowPlaying.title, initial: false) { _, _ in
            resetScrubbingState()
        }
        .onChange(of: nowPlaying.playbackState, initial: false) { _, _ in
            resetScrubbingState()
        }
    }

    private var baseElapsedSeconds: Double {
        max(nowPlaying.elapsedTime ?? 0, 0)
    }

    private var durationSeconds: Double? {
        guard let duration = nowPlaying.duration, duration > 0 else {
            return nil
        }

        return duration
    }

    private func elapsedLabelText(at date: Date) -> String {
        formatTime(isScrubbing ? scrubElapsedSeconds : displayedElapsedSeconds(at: date))
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        guard !isEditing else {
            scrubElapsedSeconds = displayedElapsedSeconds(at: .now)
            isScrubbing = true
            return
        }

        let targetElapsedSeconds = scrubElapsedSeconds
        resetScrubbingState()
        seek(targetElapsedSeconds)
    }

    private func displayedElapsedSeconds(at date: Date) -> Double {
        guard nowPlaying.playbackState == .playing else {
            return baseElapsedSeconds
        }

        let elapsedSinceObservation = max(date.timeIntervalSince(observedAt), 0)
        let nextElapsed = baseElapsedSeconds + elapsedSinceObservation

        if let durationSeconds {
            return min(nextElapsed, durationSeconds)
        }

        return nextElapsed
    }

    private func resetScrubbingState() {
        isScrubbing = false
        scrubElapsedSeconds = baseElapsedSeconds
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    PlayerProgressSection(
        nowPlaying: SonosNowPlayingSnapshot(
            title: "Unwritten",
            artistName: "Natasha Bedingfield",
            albumTitle: "Unwritten",
            sourceName: "Apple Music",
            playbackState: .playing,
            elapsedTime: 52,
            duration: 201
        ),
        observedAt: .now,
        isEnabled: true,
        seek: { _ in }
    )
    .padding()
}
