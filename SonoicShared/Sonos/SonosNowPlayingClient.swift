import Foundation

struct SonosNowPlayingClient {
    private let transport: SonosControlTransport
    private let sourceNameResolver = SonosSourceNameResolver()

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
        let currentURI = nonEmpty(resolvedMediaInfo?.currentURI) ?? nonEmpty(resolvedPositionInfo?.trackURI)
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
            title: resolveTitle(
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
            elapsedTime: parseDuration(from: resolvedPositionInfo?.relativeTime),
            duration: parseDuration(from: resolvedPositionInfo?.trackDuration)
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
        guard let xmlString = nonEmpty(xmlString) else {
            return nil
        }

        return try? SonosDIDLMetadataParser().parse(xmlString)
    }

    private func parseDuration(from value: String?) -> TimeInterval? {
        guard let value = nonEmpty(value), value != "NOT_IMPLEMENTED" else {
            return nil
        }

        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2])
        else {
            return nil
        }

        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private func resolveTitle(
        trackMetadata: SonosDIDLMetadata?,
        sourceMetadata: SonosDIDLMetadata?,
        sourceName: String,
        playbackState: SonosNowPlayingSnapshot.PlaybackState
    ) -> String {
        if let title = nonEmpty(trackMetadata?.title) {
            return title
        }

        if let sourceTitle = nonEmpty(sourceMetadata?.title), sourceTitle != sourceName {
            return sourceTitle
        }

        if sourceName != "Sonos" {
            return sourceName
        }

        switch playbackState {
        case .playing:
            return "Audio Playing"
        case .paused:
            return "Nothing Playing"
        case .buffering:
            return "Loading Audio"
        }
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

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
