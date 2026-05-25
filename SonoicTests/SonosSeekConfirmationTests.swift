import Foundation
import Testing
@testable import Sonoic

struct SonosSeekConfirmationTests {
    @Test
    func confirmsObservedPositionNearPausedTarget() {
        let requestedAt = Date(timeIntervalSinceReferenceDate: 100)
        let observedAt = requestedAt.addingTimeInterval(1)

        #expect(
            SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: 60,
                observedElapsedTime: 61,
                requestedAt: requestedAt,
                observedAt: observedAt,
                playbackState: .paused
            )
        )
    }

    @Test
    func confirmsPlayingPositionThatAdvancedAfterSeek() {
        let requestedAt = Date(timeIntervalSinceReferenceDate: 100)
        let observedAt = requestedAt.addingTimeInterval(2)

        #expect(
            SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: 60,
                observedElapsedTime: 62,
                requestedAt: requestedAt,
                observedAt: observedAt,
                playbackState: .playing
            )
        )
    }

    @Test
    func rejectsStaleObservedPosition() {
        let requestedAt = Date(timeIntervalSinceReferenceDate: 100)
        let observedAt = requestedAt.addingTimeInterval(1)

        #expect(
            !SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: 60,
                observedElapsedTime: 12,
                requestedAt: requestedAt,
                observedAt: observedAt,
                playbackState: .playing
            )
        )
    }

    @Test
    func rejectsMissingObservedPosition() {
        let requestedAt = Date(timeIntervalSinceReferenceDate: 100)

        #expect(
            !SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: 60,
                observedElapsedTime: nil,
                requestedAt: requestedAt,
                observedAt: requestedAt,
                playbackState: .playing
            )
        )
    }

    @Test
    @MainActor
    func disablesSeekWhenTransportActionsExplicitlyDoNotSupportIt() {
        let snapshot = SonosNowPlayingSnapshot(
            title: "Whiskey In the Jar",
            artistName: "Metallica",
            albumTitle: "Garage Inc.",
            sourceName: "Apple Music",
            playbackState: .playing,
            elapsedTime: 10,
            duration: 320,
            transportActions: SonosTransportActions(rawActions: ["Play", "Pause"])
        )

        #expect(!snapshot.canSeek)
    }
}
