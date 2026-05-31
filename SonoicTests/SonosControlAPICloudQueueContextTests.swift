import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonosControlAPICloudQueueContextTests {
    @Test
    func cloudQueueUnauthorizedStatusExpiresSonosControlAPIAuth() throws {
        let model = try Self.makeModel()

        #expect(
            model.isSonosControlAPIAuthorizationFailure(
                SonoicCloudQueueClient.ClientError.httpStatus(401, nil)
            )
        )
        #expect(
            model.isSonosControlAPIAuthorizationFailure(
                SonoicCloudQueueClient.ClientError.httpStatus(403, "Forbidden")
            )
        )
        #expect(
            !model.isSonosControlAPIAuthorizationFailure(
                SonoicCloudQueueClient.ClientError.httpStatus(500, "Server error")
            )
        )
    }

    @Test
    func transportUnauthorizedStatusExpiresSonosControlAPIAuth() throws {
        let model = try Self.makeModel()

        #expect(
            model.isSonosControlAPIAuthorizationFailure(
                SonosControlAPITransport.TransportError.httpStatus(401, "Token expired")
            )
        )
        #expect(
            model.isSonosControlAPIAuthorizationFailure(
                SonosControlAPITransport.TransportError.httpStatus(403, "Forbidden")
            )
        )
        #expect(
            !model.isSonosControlAPIAuthorizationFailure(
                SonosControlAPITransport.TransportError.httpStatus(500, "Server error")
            )
        )
        #expect(
            !model.isSonosControlAPIAuthorizationFailure(
                SonosControlAPITransport.TransportError.invalidResponse
            )
        )
    }

    @Test
    func runtimeStateCreatesStoredContextAndPlaybackTarget() throws {
        let state = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"],
            tracks: [Self.track(id: "track-1", name: "Track 1")]
        )

        let context = try #require(state.storedContext())
        let target = try #require(state.playbackTarget(at: 0))

        #expect(context.sessionID == "session-1")
        #expect(context.groupID == "group-1")
        #expect(context.queueVersion == "queue-v1")
        #expect(context.itemIDs == ["item-1"])
        #expect(target.sessionID == "session-1")
        #expect(target.itemID == "item-1")
        #expect(target.queueVersion == "queue-v1")
        #expect(target.track?.name == "Track 1")
    }

    @Test
    func runtimeStateRejectsPlaybackTargetsForInvalidIndexes() {
        let state = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            itemIDs: ["item-1"]
        )

        #expect(state.playbackTarget(at: -1) == nil)
        #expect(state.playbackTarget(at: 1) == nil)
    }

    @Test
    func runtimeStateRejectsPlaybackTargetsWithoutSessionID() {
        let emptySessionState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "",
            itemIDs: ["item-1"]
        )
        let whitespaceSessionState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "   ",
            itemIDs: ["item-1"]
        )

        #expect(emptySessionState.playbackTarget(at: 0) == nil)
        #expect(whitespaceSessionState.playbackTarget(at: 0) == nil)
    }

    @Test
    func runtimeStateRejectsPlaybackTargetsWithoutItemID() {
        let emptyItemState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            itemIDs: [""]
        )
        let whitespaceItemState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            itemIDs: ["   "]
        )

        #expect(emptyItemState.playbackTarget(at: 0) == nil)
        #expect(whitespaceItemState.playbackTarget(at: 0) == nil)
    }

    @Test
    func runtimeStateBuildsQueueSnapshotFromRelatedState() throws {
        let state = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"],
            tracks: [Self.track(id: "track-1", name: "Track 1")]
        )
        let payload = Self.playbackPayload(id: "payload-1")

        let snapshot = try #require(
            state.snapshot(
                payloads: [payload],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:queue-1"
            )
        )

        #expect(snapshot.sourceURI == "sonoic-cloud-queue:queue-1")
        #expect(snapshot.currentItemIndex == 0)
        #expect(snapshot.items.map(\.id) == ["item-1"])
        #expect(snapshot.items.first?.title == "Track 1")
        #expect(snapshot.items.first?.artistName == "Sonoic")
        #expect(snapshot.items.first?.duration == 180)
    }

    @Test
    func runtimeStateCurrentIndexUsesControlAPIFallbackOrder() throws {
        let state = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            itemIDs: ["item-1", "item-2", "item-3", "item-4"]
        )
        let metadataStatus = SonosControlAPIMetadataStatus(
            container: nil,
            currentItem: SonosControlAPIQueueItem(id: "item-2", track: nil, deleted: nil, policies: nil),
            nextItem: nil,
            streamInfo: nil
        )
        let manualQueuePayloads = [
            Self.playbackPayload(id: "payload-1"),
            Self.playbackPayload(id: "payload-2"),
            Self.playbackPayload(id: "payload-3"),
            Self.playbackPayload(id: "payload-4")
        ]
        let manualPlaybackPayload = try #require(manualQueuePayloads.dropFirst(3).first)
        let playbackStatusWithExactItem = SonosControlAPIPlaybackStatus(
            playbackState: .playing,
            isDucking: nil,
            queueVersion: nil,
            itemId: "item-3",
            positionMillis: nil,
            previousItemId: nil,
            previousPositionMillis: nil,
            playModes: nil,
            availablePlaybackActions: nil
        )
        let playbackStatusWithoutMatch = SonosControlAPIPlaybackStatus(
            playbackState: .playing,
            isDucking: nil,
            queueVersion: nil,
            itemId: "missing-item",
            positionMillis: nil,
            previousItemId: nil,
            previousPositionMillis: nil,
            playModes: nil,
            availablePlaybackActions: nil
        )
        let metadataStatusWithoutMatch = SonosControlAPIMetadataStatus(
            container: nil,
            currentItem: SonosControlAPIQueueItem(id: "missing-metadata-item", track: nil, deleted: nil, policies: nil),
            nextItem: nil,
            streamInfo: nil
        )

        #expect(
            state.currentIndex(
                playbackStatus: playbackStatusWithExactItem,
                metadataStatus: metadataStatus,
                queueSnapshotCurrentItemIndex: 0,
                manualPlaybackContextPayload: manualPlaybackPayload,
                manualQueueContextPayloads: manualQueuePayloads
            ) == 2
        )
        #expect(
            state.currentIndex(
                playbackStatus: playbackStatusWithoutMatch,
                metadataStatus: metadataStatus,
                queueSnapshotCurrentItemIndex: 0,
                manualPlaybackContextPayload: manualPlaybackPayload,
                manualQueueContextPayloads: manualQueuePayloads
            ) == 1
        )
        #expect(
            state.currentIndex(
                playbackStatus: playbackStatusWithoutMatch,
                metadataStatus: metadataStatusWithoutMatch,
                queueSnapshotCurrentItemIndex: 0,
                manualPlaybackContextPayload: manualPlaybackPayload,
                manualQueueContextPayloads: manualQueuePayloads
            ) == 0
        )
        #expect(
            state.currentIndex(
                playbackStatus: playbackStatusWithoutMatch,
                metadataStatus: metadataStatusWithoutMatch,
                queueSnapshotCurrentItemIndex: nil,
                manualPlaybackContextPayload: manualPlaybackPayload,
                manualQueueContextPayloads: manualQueuePayloads
            ) == 3
        )
    }

    @Test
    func runtimeStateRestoresStoredContextWithoutLooseFieldCopies() {
        var state = SonosControlAPICloudQueueRuntimeState.empty
        let storedContext = SonosControlAPICloudQueueSessionContext(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"],
            tracks: [Self.track(id: "track-1", name: "Track 1")],
            updatedAt: Date()
        )

        let result = state.restoreIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v2",
            storedContext: storedContext
        )

        #expect(result.didRestore)
        #expect(result.restoredStoredContext == storedContext)
        #expect(result.versionMismatch?.source == "keepingStored")
        #expect(state.sessionID == "session-1")
        #expect(state.groupID == "group-1")
        #expect(state.queueVersion == "queue-v1")
        #expect(state.itemIDs == ["item-1"])
        #expect(state.tracks == storedContext.tracks)
        #expect(state.versionMismatchLogKey == "keepingStored|group-1|queue-v1|queue-v2")
    }

    @Test
    func runtimeStateDoesNotRestoreStaleStoredContext() {
        var state = SonosControlAPICloudQueueRuntimeState.empty
        let storedContext = SonosControlAPICloudQueueSessionContext(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"],
            tracks: [Self.track(id: "track-1", name: "Track 1")],
            updatedAt: Date(
                timeIntervalSinceNow: -SonosControlAPICloudQueueSessionContext.staleInterval - 1
            )
        )

        let result = state.restoreIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v1",
            storedContext: storedContext
        )

        #expect(!result.didRestore)
        #expect(result.restoredStoredContext == nil)
        #expect(!result.shouldClearStoredContext)
        #expect(state == .empty)
    }

    @Test
    func runtimeStateDoesNotRestoreUnusableStoredContext() {
        var blankSessionState = SonosControlAPICloudQueueRuntimeState.empty
        let blankSessionContext = SonosControlAPICloudQueueSessionContext(
            sessionID: "   ",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"],
            tracks: [],
            updatedAt: Date()
        )
        let blankSessionResult = blankSessionState.restoreIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v1",
            storedContext: blankSessionContext
        )

        var emptyItemState = SonosControlAPICloudQueueRuntimeState.empty
        let emptyItemContext = SonosControlAPICloudQueueSessionContext(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: [],
            tracks: [],
            updatedAt: Date()
        )
        let emptyItemResult = emptyItemState.restoreIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v1",
            storedContext: emptyItemContext
        )

        #expect(!blankSessionResult.didRestore)
        #expect(blankSessionResult.restoredStoredContext == nil)
        #expect(blankSessionState == .empty)
        #expect(!emptyItemResult.didRestore)
        #expect(emptyItemResult.restoredStoredContext == nil)
        #expect(emptyItemState == .empty)
    }

    @Test
    func inMemoryCloudQueueContextSurvivesQueueVersionDrift() throws {
        let model = try Self.makeModel()
        model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"]
        )

        let restored = model.restoreSonosControlAPICloudQueueContextIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v2"
        )

        #expect(restored)
        #expect(model.sonosControlAPICloudQueueRuntimeState.sessionID == "session-1")
        #expect(model.sonosControlAPICloudQueueRuntimeState.itemIDs == ["item-1"])
        #expect(
            model.sonosControlAPICloudQueueRuntimeState.versionMismatchLogKey
                == "keepingMemory|group-1|queue-v1|queue-v2"
        )
    }

    @Test
    func inMemoryCloudQueueContextClearsOnGroupMismatch() throws {
        let model = try Self.makeModel()
        model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-1",
            groupID: "group-1",
            queueVersion: "queue-v1",
            itemIDs: ["item-1"]
        )

        let restored = model.restoreSonosControlAPICloudQueueContextIfNeeded(
            groupID: "group-2",
            queueVersion: "queue-v1"
        )

        #expect(!restored)
        #expect(model.sonosControlAPICloudQueueRuntimeState == .empty)
    }

    private static func makeModel() throws -> SonoicModel {
        let suiteName = "SonosControlAPICloudQueueContextTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            startInitialSonosControlAPICloudRefresh: false
        )
    }

    private static func playbackPayload(id: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Payload Track",
            subtitle: "Payload Artist • Payload Album",
            artworkURL: "https://example.com/artwork.jpg",
            service: .appleMusic,
            uri: "x-sonos-http:song:\(id).m4p",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 181
        )
    }

    private static func track(id: String, name: String) -> SonosControlAPITrack {
        SonosControlAPITrack(
            type: "track",
            name: name,
            mediaUrl: nil,
            imageUrl: nil,
            contentType: "audio/mp4",
            album: SonosControlAPIAlbum(
                name: "Cloud",
                artist: SonosControlAPIArtist(name: "Sonoic", id: nil),
                id: nil
            ),
            artist: SonosControlAPIArtist(name: "Sonoic", id: nil),
            id: SonosControlAPIUniversalMusicObjectID(
                serviceId: "204",
                objectId: "song:\(id)",
                accountId: nil
            ),
            service: SonosControlAPIService(id: "204", name: "Apple Music", imageUrl: nil),
            durationMillis: 180_000,
            trackNumber: nil,
            quality: nil
        )
    }
}
