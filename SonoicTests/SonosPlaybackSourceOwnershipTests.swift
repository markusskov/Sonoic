import Testing
@testable import Sonoic

@MainActor
struct SonosPlaybackSourceOwnershipTests {
    @Test(arguments: [
        ("x-rincon-queue:RINCON_123#0", SonosPlaybackSourceOwnership.sonosQueue, true),
        ("x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204", .serviceContainer, false),
        ("x-sonosapi-hls:song%3a1440845464?sid=204", .directServiceStream, false),
        ("x-sonosapi-radio:station%3aabc?sid=254", .directServiceStream, false),
        ("x-sonos-htastream:RINCON_123:spdif", .tvAudio, false),
        ("x-rincon-stream:RINCON_456", .lineIn, false),
        ("x-file-cifs://music/song.mp3", .musicLibrary, false),
        ("x-rincon:RINCON_789", .groupCoordinator, false),
        ("https://example.com/stream.mp3", .webStream, false),
        ("nota-real-sonos-uri", .unknown, false),
        ("", .unavailable, false)
    ])
    func classifiesURIPlaybackOwnership(
        uri: String,
        expectedOwnership: SonosPlaybackSourceOwnership,
        expectedQueueMutationSupport: Bool
    ) {
        let ownership = SonosPlaybackSourceOwnership(uri: uri)

        #expect(ownership == expectedOwnership)
        #expect(ownership.supportsLocalQueueMutation == expectedQueueMutationSupport)
    }

    @Test
    func queueHeuristicOnlyAcceptsTrueQueueURI() {
        #expect(SonosMetadataHeuristics.isQueueContainerURI("x-rincon-queue:RINCON_123#0"))
        #expect(!SonosMetadataHeuristics.isQueueContainerURI("x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204"))
        #expect(!SonosMetadataHeuristics.isQueueContainerURI("x-sonosapi-hls:song%3a1440845464?sid=204"))
    }

    @Test
    func sourceNameCanStillUseTrackURIForServiceContainers() {
        #expect(SonosMetadataHeuristics.isPlaybackContainerURI("x-rincon-queue:RINCON_123#0"))
        #expect(SonosMetadataHeuristics.isPlaybackContainerURI("x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204"))
        #expect(!SonosMetadataHeuristics.isPlaybackContainerURI("x-sonosapi-hls:song%3a1440845464?sid=204"))
    }

    @Test
    func diagnosticsExposeCurrentAndTrackOwnershipSeparately() {
        let diagnostics = SonosNowPlayingDiagnostics(
            currentURI: "x-rincon-queue:RINCON_123#0",
            trackURI: "x-sonosapi-hls:song%3a1440845464?sid=204",
            rawDuration: "0:03:45",
            rawElapsedTime: "0:01:02",
            hasTrackMetadata: true,
            hasSourceMetadata: true,
            usedFallbackSnapshot: false
        )

        #expect(diagnostics.currentURIOwnership == .sonosQueue)
        #expect(diagnostics.currentURIOwnership.supportsLocalQueueMutation)
        #expect(diagnostics.trackURIOwnership == .directServiceStream)
    }
}
