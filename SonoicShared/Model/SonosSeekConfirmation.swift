import Foundation

nonisolated enum SonosSeekConfirmation {
    static let elapsedTolerance: TimeInterval = 2.5
    static let pendingUITimeout: TimeInterval = 6

    static func isConfirmed(
        targetElapsedTime: TimeInterval,
        observedElapsedTime: TimeInterval?,
        requestedAt: Date,
        observedAt: Date,
        playbackState: SonosControlAPIPlaybackState?
    ) -> Bool {
        guard let observedElapsedTime else {
            return false
        }

        let expectedElapsedTime = expectedElapsedTime(
            targetElapsedTime: targetElapsedTime,
            requestedAt: requestedAt,
            observedAt: observedAt,
            playbackState: playbackState
        )

        return abs(observedElapsedTime - expectedElapsedTime) <= elapsedTolerance
    }

    static func expectedElapsedTime(
        targetElapsedTime: TimeInterval,
        requestedAt: Date,
        observedAt: Date,
        playbackState: SonosControlAPIPlaybackState?
    ) -> TimeInterval {
        guard playbackState == .playing else {
            return targetElapsedTime
        }

        return targetElapsedTime + max(observedAt.timeIntervalSince(requestedAt), 0)
    }
}
