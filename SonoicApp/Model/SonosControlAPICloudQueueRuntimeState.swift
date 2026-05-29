import Foundation

struct SonosControlAPICloudQueueRuntimeState: Equatable {
    static let empty = SonosControlAPICloudQueueRuntimeState()

    struct PlaybackTarget: Equatable {
        var sessionID: String
        var itemID: String
        var queueVersion: String?
        var track: SonosControlAPITrack?
    }

    struct ContextMismatch: Equatable {
        var storedGroupID: String?
        var currentGroupID: String?
        var storedQueueVersion: String?
        var currentQueueVersion: String?
    }

    struct VersionMismatch: Equatable {
        var source: String
        var groupID: String?
        var storedVersion: String
        var currentVersion: String
        var logKey: String
    }

    struct RestoreResult: Equatable {
        var didRestore = false
        var restoredStoredContext: SonosControlAPICloudQueueSessionContext?
        var clearedMemoryGroupMismatch: ContextMismatch?
        var skippedStoredGroupMismatch: ContextMismatch?
        var versionMismatch: VersionMismatch?
        var shouldClearStoredContext = false
    }

    var sessionID: String?
    var groupID: String?
    var queueVersion: String?
    var itemIDs: [String]?
    var tracks: [SonosControlAPITrack]?
    var versionMismatchLogKey: String?

    init(
        sessionID: String? = nil,
        groupID: String? = nil,
        queueVersion: String? = nil,
        itemIDs: [String]? = nil,
        tracks: [SonosControlAPITrack]? = nil,
        versionMismatchLogKey: String? = nil
    ) {
        self.sessionID = sessionID
        self.groupID = groupID
        self.queueVersion = queueVersion
        self.itemIDs = itemIDs
        self.tracks = tracks
        self.versionMismatchLogKey = versionMismatchLogKey
    }

    var isUsable: Bool {
        sessionID?.sonoicNonEmptyTrimmed != nil
            && itemIDs?.isEmpty == false
    }

    var itemCount: Int {
        itemIDs?.count ?? 0
    }

    var hasSessionContext: Bool {
        isUsable
    }

    mutating func clear() {
        self = .empty
    }

    func storedContext(
        groupID overrideGroupID: String? = nil,
        updatedAt: Date = Date()
    ) -> SonosControlAPICloudQueueSessionContext? {
        guard let sessionID = sessionID?.sonoicNonEmptyTrimmed,
              let itemIDs,
              !itemIDs.isEmpty
        else {
            return nil
        }

        let context = SonosControlAPICloudQueueSessionContext(
            sessionID: sessionID,
            groupID: overrideGroupID?.sonoicNonEmptyTrimmed ?? groupID?.sonoicNonEmptyTrimmed,
            queueVersion: queueVersion?.sonoicNonEmptyTrimmed,
            itemIDs: itemIDs,
            tracks: tracks ?? [],
            updatedAt: updatedAt
        )

        return context.isUsable ? context : nil
    }

    mutating func restoreIfNeeded(
        groupID currentGroupID: String?,
        queueVersion currentQueueVersion: String?,
        storedContext: SonosControlAPICloudQueueSessionContext?
    ) -> RestoreResult {
        let normalizedGroupID = currentGroupID?.sonoicNonEmptyTrimmed
        let normalizedQueueVersion = currentQueueVersion?.sonoicNonEmptyTrimmed
        var result = RestoreResult()

        if isUsable {
            let inMemoryGroupID = groupID?.sonoicNonEmptyTrimmed
            let inMemoryQueueVersion = queueVersion?.sonoicNonEmptyTrimmed
            let groupMatches = normalizedGroupID.map { inMemoryGroupID == $0 } ?? true

            if groupMatches {
                result.didRestore = true
                result.versionMismatch = updateVersionMismatchLogKey(
                    source: "keepingMemory",
                    groupID: inMemoryGroupID,
                    storedVersion: inMemoryQueueVersion,
                    currentVersion: normalizedQueueVersion
                )
                return result
            }

            result.clearedMemoryGroupMismatch = ContextMismatch(
                storedGroupID: inMemoryGroupID,
                currentGroupID: normalizedGroupID,
                storedQueueVersion: inMemoryQueueVersion,
                currentQueueVersion: normalizedQueueVersion
            )
            result.shouldClearStoredContext = true
            clear()
            return result
        }

        guard let storedContext,
              storedContext.isUsable,
              storedContext.isFresh
        else {
            return result
        }

        if let storedGroupID = storedContext.groupID?.sonoicNonEmptyTrimmed,
           let normalizedGroupID,
           storedGroupID != normalizedGroupID
        {
            result.skippedStoredGroupMismatch = ContextMismatch(
                storedGroupID: storedGroupID,
                currentGroupID: normalizedGroupID,
                storedQueueVersion: storedContext.queueVersion?.sonoicNonEmptyTrimmed,
                currentQueueVersion: normalizedQueueVersion
            )
            result.shouldClearStoredContext = true
            clear()
            return result
        }

        let previousLogKey = versionMismatchLogKey
        let storedQueueVersion = storedContext.queueVersion?.sonoicNonEmptyTrimmed
        let versionMismatch = Self.versionMismatch(
            source: "keepingStored",
            groupID: storedContext.groupID?.sonoicNonEmptyTrimmed,
            storedVersion: storedQueueVersion,
            currentVersion: normalizedQueueVersion,
            previousLogKey: previousLogKey
        )
        self = SonosControlAPICloudQueueRuntimeState(
            sessionID: storedContext.sessionID,
            groupID: storedContext.groupID,
            queueVersion: storedContext.queueVersion,
            itemIDs: storedContext.itemIDs,
            tracks: storedContext.tracks,
            versionMismatchLogKey: versionMismatch.currentLogKey
        )
        result.didRestore = true
        result.restoredStoredContext = storedContext
        result.versionMismatch = versionMismatch.event
        return result
    }

    func currentIndex(from itemIDCandidates: [String?]) -> Int? {
        guard let itemIDs else {
            return nil
        }

        return SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: itemIDs,
            candidates: itemIDCandidates
        )
    }

    func currentIndex(
        playbackStatus: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus?,
        queueSnapshotCurrentItemIndex: Int?,
        manualPlaybackContextPayload: SonosPlayablePayload?,
        manualQueueContextPayloads: [SonosPlayablePayload]?
    ) -> Int? {
        currentIndex(
            from: [
                playbackStatus.itemId,
                metadataStatus?.currentItem?.id,
                queueSnapshotCurrentItemIndex.map { String($0 + 1) },
                manualPlaybackContextPayload.flatMap { payload in
                    manualQueueContextPayloads?.firstIndex { $0.id == payload.id }.map {
                        String($0 + 1)
                    }
                }
            ]
        )
    }

    func playbackTarget(at index: Int) -> PlaybackTarget? {
        guard index >= 0,
              let sessionID = sessionID?.sonoicNonEmptyTrimmed,
              let itemIDs,
              itemIDs.indices.contains(index),
              let itemID = itemIDs[index].sonoicNonEmptyTrimmed
        else {
            return nil
        }

        return PlaybackTarget(
            sessionID: sessionID,
            itemID: itemID,
            queueVersion: queueVersion,
            track: track(at: index)
        )
    }

    func playbackTarget(currentIndex: Int?) -> PlaybackTarget? {
        currentIndex.flatMap(playbackTarget(at:))
    }

    func track(at index: Int) -> SonosControlAPITrack? {
        tracks.flatMap { tracks in
            tracks.indices.contains(index) ? tracks[index] : nil
        }
    }

    func snapshot(
        payloads: [SonosPlayablePayload],
        currentItemIndex: Int? = nil,
        sourceURI: String? = nil
    ) -> SonosQueueSnapshot? {
        let tracks = tracks ?? []
        let itemCount = max(payloads.count, tracks.count, itemIDs?.count ?? 0)

        guard itemCount > 0 else {
            return nil
        }

        let items = (0..<itemCount).map { index in
            let payload = payloads.indices.contains(index) ? payloads[index] : nil
            let track = tracks.indices.contains(index) ? tracks[index] : nil
            let subtitleParts = payload?.subtitle?
                .components(separatedBy: "•")
                .map(\.sonoicTrimmed)
                .filter { !$0.isEmpty } ?? []
            let itemID = itemIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            return SonosQueueItem(
                id: itemID ?? payload?.id ?? "sonoic-cloud-queue-\(index + 1)",
                title: track?.name?.sonoicNonEmptyTrimmed ?? payload?.title ?? "Unknown Track",
                artistName: track?.artist?.name.sonoicNonEmptyTrimmed ?? subtitleParts.first,
                albumTitle: track?.album?.name.sonoicNonEmptyTrimmed ?? subtitleParts.dropFirst().first,
                artworkURL: track?.imageUrl?.sonoicNonEmptyTrimmed ?? payload?.artworkURL,
                duration: track?.durationMillis.map { TimeInterval($0) / 1_000 } ?? payload?.duration
            )
        }

        return SonosQueueSnapshot(
            items: items,
            currentItemIndex: currentItemIndex.flatMap { items.indices.contains($0) ? $0 : nil },
            sourceURI: sourceURI ?? "sonoic-cloud-queue"
        )
    }

    private mutating func updateVersionMismatchLogKey(
        source: String,
        groupID: String?,
        storedVersion: String?,
        currentVersion: String?
    ) -> VersionMismatch? {
        let mismatch = Self.versionMismatch(
            source: source,
            groupID: groupID,
            storedVersion: storedVersion,
            currentVersion: currentVersion,
            previousLogKey: versionMismatchLogKey
        )
        versionMismatchLogKey = mismatch.currentLogKey
        return mismatch.event
    }

    private static func versionMismatch(
        source: String,
        groupID: String?,
        storedVersion: String?,
        currentVersion: String?,
        previousLogKey: String?
    ) -> (event: VersionMismatch?, currentLogKey: String?) {
        guard let storedVersion,
              let currentVersion,
              storedVersion != currentVersion
        else {
            return (nil, nil)
        }

        let logKey = "\(source)|\(groupID ?? "any")|\(storedVersion)|\(currentVersion)"
        guard previousLogKey != logKey else {
            return (nil, logKey)
        }

        return (
            VersionMismatch(
                source: source,
                groupID: groupID,
                storedVersion: storedVersion,
                currentVersion: currentVersion,
                logKey: logKey
            ),
            logKey
        )
    }
}
