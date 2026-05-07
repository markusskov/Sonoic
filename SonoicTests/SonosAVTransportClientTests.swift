import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonosAVTransportClientTests {
    @Test
    func confirmsSeekNearObservedTarget() {
        let position = SonosAVTransportClient.SeekPositionConfirmation(
            relativeTime: 61,
            trackDuration: 300
        )

        #expect(SonosAVTransportClient.didConfirmSeekTarget(position, target: 60))
    }

    @Test
    func confirmsSeekThatRolledToNextTrackAtEnd() {
        let position = SonosAVTransportClient.SeekPositionConfirmation(
            relativeTime: 1,
            trackDuration: 300
        )

        #expect(SonosAVTransportClient.didConfirmSeekTarget(position, target: 298))
    }

    @Test
    func rejectsEarlyObservedTimeForNonTerminalSeek() {
        let position = SonosAVTransportClient.SeekPositionConfirmation(
            relativeTime: 1,
            trackDuration: 300
        )

        #expect(!SonosAVTransportClient.didConfirmSeekTarget(position, target: 120))
    }
}
