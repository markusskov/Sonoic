import Foundation

struct SonosNowPlayingClient {
    private let transport: SonosControlTransport
    private let sourceNameResolver = SonosSourceNameResolver()
    private let titleResolver = SonosNowPlayingTitleResolver()

    private struct PositionInfo {
        var trackMetadata: String?
        var trackURI: String?
        var trackDuration: String?
        var relativeTime: String?
    }

    private struct MediaInfo {
        var currentURIMetadata: String?
        var currentURI: String?
    }

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchSnapshot(
        host: String,
        playbackState: SonosNowPlayingSnapshot.PlaybackState,
        fallback: SonosNowPlayingSnapshot
    ) async -> SonosNowPlayingSnapshot {
        async let positionInfo = fetchPositionInfo(host: host)
        async let mediaInfo = fetchMediaInfo(host: host)

        let resolvedPositionInfo = try? await positionInfo
        let resolvedMediaInfo = try? await mediaInfo
        let trackMetadata = parseMetadata(from: resolvedPositionInfo?.trackMetadata)
        let sourceMetadata = parseMetadata(from: resolvedMediaInfo?.currentURIMetadata)
        let currentURI = resolvedMediaInfo?.currentURI.sonoicNonEmptyTrimmed
            ?? resolvedPositionInfo?.trackURI.sonoicNonEmptyTrimmed
        let hasRealMetadataContext = trackMetadata?.isEmpty == false
            || sourceMetadata?.isEmpty == false
            || currentURI != nil

        guard hasRealMetadataContext else {
            return SonosNowPlayingSnapshot(
                title: fallback.title,
                artistName: fallback.artistName,
                albumTitle: fallback.albumTitle,
                sourceName: fallback.sourceName,
                playbackState: playbackState,
                artworkURL: fallback.artworkURL,
                artworkIdentifier: fallback.artworkIdentifier,
                elapsedTime: fallback.elapsedTime,
                duration: fallback.duration
            )
        }

        let sourceName = resolveSourceName(
            sourceMetadataTitle: sourceMetadata?.title,
            trackTitle: trackMetadata?.title,
            currentURI: resolvedMediaInfo?.currentURI,
            trackURI: resolvedPositionInfo?.trackURI
        )

        return SonosNowPlayingSnapshot(
            title: titleResolver.resolveTitle(
                trackMetadata: trackMetadata,
                sourceMetadata: sourceMetadata,
                sourceName: sourceName,
                playbackState: playbackState
            ),
            artistName: trackMetadata?.artistName,
            albumTitle: trackMetadata?.albumTitle,
            sourceName: sourceName,
            playbackState: playbackState,
            artworkURL: trackMetadata?.albumArtURI ?? sourceMetadata?.albumArtURI,
            artworkIdentifier: fallback.artworkIdentifier,
            elapsedTime: SonosDurationParser.parseTimeInterval(from: resolvedPositionInfo?.relativeTime),
            duration: SonosDurationParser.parseTimeInterval(from: resolvedPositionInfo?.trackDuration)
        )
    }

    private func fetchPositionInfo(host: String) async throws -> PositionInfo {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetPositionInfo",
            body: """
            <u:GetPositionInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
            """,
            host: host
        )

        return PositionInfo(
            trackMetadata: extractOptionalSOAPValue(named: "TrackMetaData", from: data),
            trackURI: extractOptionalSOAPValue(named: "TrackURI", from: data),
            trackDuration: extractOptionalSOAPValue(named: "TrackDuration", from: data),
            relativeTime: extractOptionalSOAPValue(named: "RelTime", from: data)
        )
    }

    private func fetchMediaInfo(host: String) async throws -> MediaInfo {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetMediaInfo",
            body: """
            <u:GetMediaInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetMediaInfo>
            """,
            host: host
        )

        return MediaInfo(
            currentURIMetadata: extractOptionalSOAPValue(named: "CurrentURIMetaData", from: data),
            currentURI: extractOptionalSOAPValue(named: "CurrentURI", from: data)
        )
    }

    private func extractOptionalSOAPValue(named elementName: String, from data: Data) -> String? {
        try? SonosSOAPValueParser(expectedElement: elementName).parse(data)
    }

    private func parseMetadata(from xmlString: String?) -> SonosDIDLMetadata? {
        guard let xmlString = xmlString.sonoicNonEmptyTrimmed else {
            return nil
        }

        return try? SonosDIDLMetadataParser().parse(xmlString)
    }

    private func resolveSourceName(
        sourceMetadataTitle: String?,
        trackTitle: String?,
        currentURI: String?,
        trackURI: String?
    ) -> String {
        sourceNameResolver.resolve(
            sourceMetadataTitle: sourceMetadataTitle,
            trackTitle: trackTitle,
            currentURI: currentURI,
            trackURI: trackURI
        )
    }
}
