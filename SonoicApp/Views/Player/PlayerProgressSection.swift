import SwiftUI

struct PlayerProgressSection: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let observedAt: Date
    let contentIdentity: String
    let isEnabled: Bool
    var showsTimeLabels = true
    var showsThumb = true
    let seek: (TimeInterval) async -> Bool

    @State private var isScrubbing = false
    @State private var scrubElapsedSeconds = 0.0
    @State private var pendingSeekTarget: PendingSeekTarget?
    @State private var pendingSeekTask: Task<Void, Never>?
    @State private var pendingSeekTimeoutTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: observedAt, by: 1)) { context in
            if let durationSeconds {
                VStack(spacing: 10) {
                    PlayerScrubber(
                        value: Binding(
                            get: {
                                if isScrubbing {
                                    scrubElapsedSeconds
                                } else if let pendingSeekTarget {
                                    pendingSeekTarget.displayedElapsedSeconds(at: context.date, duration: durationSeconds)
                                } else {
                                    displayedElapsedSeconds(at: context.date)
                                }
                            },
                            set: { newValue in
                                scrubElapsedSeconds = newValue
                                isScrubbing = true
                            }
                        ),
                        bounds: 0 ... durationSeconds,
                        isEnabled: isEnabled,
                        showsThumb: showsThumb,
                        accessibilityLabel: "Playback position",
                        onEditingChanged: handleEditingChanged
                    )

                    if showsTimeLabels {
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
        }
        .onChange(of: observedAt, initial: false) { _, _ in
            guard !isScrubbing else {
                return
            }

            if shouldKeepPendingSeek(at: .now) {
                return
            }

            resetScrubbingState()
        }
        .onChange(of: contentIdentity, initial: false) { _, _ in
            guard !isScrubbing else {
                return
            }

            resetScrubbingState()
        }
        .onChange(of: nowPlaying.playbackState, initial: false) { _, _ in
            guard !isScrubbing else {
                return
            }

            refreshPendingSeekPlaybackState(at: .now)

            if shouldKeepPendingSeek(at: .now) {
                return
            }

            resetScrubbingState()
        }
        .onDisappear {
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
        if isScrubbing {
            formatTime(scrubElapsedSeconds)
        } else if let pendingSeekTarget {
            formatTime(pendingSeekTarget.displayedElapsedSeconds(at: date, duration: durationSeconds))
        } else {
            formatTime(displayedElapsedSeconds(at: date))
        }
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        guard !isEditing else {
            scrubElapsedSeconds = displayedElapsedSeconds(at: .now)
            isScrubbing = true
            return
        }

        let targetElapsedSeconds = scrubElapsedSeconds
        scrubElapsedSeconds = targetElapsedSeconds
        pendingSeekTarget = PendingSeekTarget(
            elapsedSeconds: targetElapsedSeconds,
            requestedAt: .now,
            playbackState: nowPlaying.playbackState,
            contentIdentity: contentIdentity
        )
        schedulePendingSeekTimeout()
        isScrubbing = false
        scheduleSeek(targetElapsedSeconds, pendingTarget: pendingSeekTarget)
    }

    private func shouldKeepPendingSeek(at date: Date) -> Bool {
        guard let pendingSeekTarget else {
            return false
        }

        if pendingSeekTarget.contentIdentity != contentIdentity {
            self.pendingSeekTarget = nil
            return false
        }

        let modelElapsedSeconds = displayedElapsedSeconds(at: date)
        let targetElapsedSeconds = pendingSeekTarget.displayedElapsedSeconds(at: date, duration: durationSeconds)

        if abs(modelElapsedSeconds - targetElapsedSeconds) <= SonosSeekConfirmation.elapsedTolerance {
            self.pendingSeekTarget = nil
            return false
        }

        if date.timeIntervalSince(pendingSeekTarget.requestedAt) > SonosSeekConfirmation.pendingUITimeout {
            self.pendingSeekTarget = nil
            return false
        }

        return true
    }

    private func refreshPendingSeekPlaybackState(at date: Date) {
        guard let pendingSeekTarget,
              pendingSeekTarget.playbackState != nowPlaying.playbackState
        else {
            return
        }

        self.pendingSeekTarget = PendingSeekTarget(
            id: pendingSeekTarget.id,
            elapsedSeconds: pendingSeekTarget.displayedElapsedSeconds(at: date, duration: durationSeconds),
            requestedAt: pendingSeekTarget.requestedAt,
            playbackState: nowPlaying.playbackState,
            contentIdentity: pendingSeekTarget.contentIdentity
        )
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
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        pendingSeekTimeoutTask?.cancel()
        pendingSeekTimeoutTask = nil
        isScrubbing = false
        pendingSeekTarget = nil
        scrubElapsedSeconds = baseElapsedSeconds
    }

    private func schedulePendingSeekTimeout() {
        pendingSeekTimeoutTask?.cancel()
        pendingSeekTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(SonosSeekConfirmation.pendingUITimeout))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            if shouldKeepPendingSeek(at: .now) {
                resetScrubbingState()
            }
        }
    }

    private func scheduleSeek(_ elapsedSeconds: TimeInterval, pendingTarget: PendingSeekTarget?) {
        let pendingTargetID = pendingTarget?.id
        pendingSeekTask?.cancel()
        pendingSeekTask = Task { @MainActor in
            let didSeek = await seek(elapsedSeconds)

            guard !Task.isCancelled,
                  pendingSeekTarget?.id == pendingTargetID
            else {
                return
            }

            pendingSeekTask = nil

            if !didSeek {
                resetScrubbingState()
            }
        }
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

private struct PendingSeekTarget: Equatable {
    var id = UUID()
    var elapsedSeconds: TimeInterval
    var requestedAt: Date
    var playbackState: SonosNowPlayingSnapshot.PlaybackState
    var contentIdentity: String

    func displayedElapsedSeconds(at date: Date, duration: TimeInterval?) -> TimeInterval {
        var elapsedSeconds = elapsedSeconds

        if playbackState == .playing {
            elapsedSeconds += max(date.timeIntervalSince(requestedAt), 0)
        }

        if let duration {
            return min(max(elapsedSeconds, 0), duration)
        }

        return max(elapsedSeconds, 0)
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
        contentIdentity: "preview",
        isEnabled: true,
        seek: { _ in true }
    )
    .padding()
}
