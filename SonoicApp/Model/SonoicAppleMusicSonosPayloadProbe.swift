import Foundation

struct SonoicAppleMusicGeneratedPayloadCandidate: Identifiable, Equatable {
    enum Strategy: String, Equatable {
        case catalogHLS
        case catalogPlaylistContainer
        case libraryTrack

        var title: String {
            switch self {
            case .catalogHLS:
                "Catalog HLS"
            case .catalogPlaylistContainer:
                "Catalog Playlist"
            case .libraryTrack:
                "Library Track"
            }
        }
    }

    var strategy: Strategy
    var uri: String
    var metadataXML: String
    var serialNumber: String

    var id: String {
        "\(strategy.rawValue)-\(serialNumber)-\(uri)"
    }

    var isUserPlayable: Bool {
        strategy == .catalogHLS || strategy == .catalogPlaylistContainer
    }

    func playbackPayload(for item: SonoicSourceItem) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: item.title,
            subtitle: item.subtitle,
            artworkURL: item.artworkURL,
            service: .appleMusic,
            uri: uri,
            metadataXML: metadataXML,
            kind: strategy == .catalogPlaylistContainer ? .collection : .item,
            duration: item.duration
        )
    }

    func preparedPlaybackPayload(for item: SonoicSourceItem) throws -> SonosPlayablePayload {
        try SonosPlayablePayloadPreparer().prepare(playbackPayload(for: item))
    }
}

struct SonoicAppleMusicSonosPayloadProbe {
    private let appleMusicServiceID = "204"

    func candidates(
        for item: SonoicSourceItem,
        playbackHint: SonosMusicServicePlaybackHint?
    ) -> [SonoicAppleMusicGeneratedPayloadCandidate] {
        guard item.service.kind == .appleMusic,
              let playbackHint,
              let identity = item.sourceReference
        else {
            return []
        }

        var candidates: [SonoicAppleMusicGeneratedPayloadCandidate] = []
        let metadataBuilder = SonoicAppleMusicSonosCandidateMetadataBuilder()

        if item.kind == .song,
           let catalogID = identity.catalogID.sonoicNonEmptyTrimmed,
           let launchSerial = playbackHint.preferredLaunchSerial?.sonoicNonEmptyTrimmed,
           let encodedCatalogID = sonosPayloadID(catalogID) {
            let uri = "x-sonosapi-hls:song%3a\(encodedCatalogID)?sid=\(appleMusicServiceID)&sn=\(launchSerial)"
            candidates.append(
                SonoicAppleMusicGeneratedPayloadCandidate(
                    strategy: .catalogHLS,
                    uri: uri,
                    metadataXML: metadataBuilder.metadataXML(
                        for: item,
                        itemID: "song:\(catalogID)",
                        serviceID: appleMusicServiceID,
                        resourceURI: uri
                    ),
                    serialNumber: launchSerial
                )
            )
        }

        if item.kind == .playlist,
           let catalogID = identity.catalogID.sonoicNonEmptyTrimmed,
           let launchSerial = playbackHint.preferredLaunchSerial?.sonoicNonEmptyTrimmed,
           let encodedCatalogID = sonosPayloadID(catalogID) {
            let uri = "x-rincon-cpcontainer:1006206cplaylist%3a\(encodedCatalogID)?sid=\(appleMusicServiceID)&flags=8300&sn=\(launchSerial)"
            candidates.append(
                SonoicAppleMusicGeneratedPayloadCandidate(
                    strategy: .catalogPlaylistContainer,
                    uri: uri,
                    metadataXML: metadataBuilder.metadataXML(
                        for: item,
                        itemID: "playlist:\(catalogID)",
                        serviceID: appleMusicServiceID,
                        resourceURI: uri
                    ),
                    serialNumber: launchSerial
                )
            )
        }

        if item.kind == .song,
           let libraryID = identity.libraryID.sonoicNonEmptyTrimmed,
           let trackSerial = playbackHint.trackSerials.first?.sonoicNonEmptyTrimmed,
           let encodedLibraryID = sonosPayloadID(libraryID) {
            let uri = "x-sonos-http:librarytrack%3a\(encodedLibraryID).m4p?sid=\(appleMusicServiceID)&flags=8232&sn=\(trackSerial)"
            candidates.append(
                SonoicAppleMusicGeneratedPayloadCandidate(
                    strategy: .libraryTrack,
                    uri: uri,
                    metadataXML: metadataBuilder.metadataXML(
                        for: item,
                        itemID: "librarytrack:\(libraryID)",
                        serviceID: appleMusicServiceID,
                        resourceURI: uri
                    ),
                    serialNumber: trackSerial
                )
            )
        }

        return candidates
    }

    func queueCandidate(
        for item: SonoicSourceItem,
        playbackHint: SonosMusicServicePlaybackHint?
    ) -> SonoicAppleMusicGeneratedPayloadCandidate? {
        let candidates = candidates(for: item, playbackHint: playbackHint)
        return candidates.first { $0.strategy == .libraryTrack }
            ?? candidates.first { $0.strategy == .catalogHLS }
    }

    private func sonosPayloadID(_ value: String) -> String? {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
}

private struct SonoicAppleMusicSonosCandidateMetadataBuilder {
    func metadataXML(
        for item: SonoicSourceItem,
        itemID: String,
        serviceID: String,
        resourceURI: String
    ) -> String {
        let subtitleParts = item.subtitle?
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let creator = subtitleParts.first
        let album = subtitleParts.dropFirst().first
        let serviceType = SonosServiceDescriptor.appleMusic.sonosServiceType ?? serviceID

        let elementName = didlElementName(for: item.kind)

        return """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"><\(elementName) id="\(xmlEscaped(itemID))" parentID="" restricted="true"><dc:title>\(xmlEscaped(item.title))</dc:title>\(optionalElement("dc:creator", creator))\(optionalElement("upnp:album", album))\(optionalElement("upnp:albumArtURI", item.artworkURL))<upnp:class>\(upnpClass(for: item.kind))</upnp:class>\(resourceElement(for: item, uri: resourceURI))<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON\(serviceType)_X_#Svc\(serviceType)-0-Token</desc></\(elementName)></DIDL-Lite>
        """
    }

    private func upnpClass(for kind: SonoicSourceItem.Kind) -> String {
        switch kind {
        case .playlist:
            "object.container.playlistContainer"
        default:
            "object.item.audioItem.musicTrack"
        }
    }

    private func didlElementName(for kind: SonoicSourceItem.Kind) -> String {
        switch kind {
        case .playlist:
            "container"
        default:
            "item"
        }
    }

    private func optionalElement(_ name: String, _ value: String?) -> String {
        guard let value = value?.sonoicNonEmptyTrimmed else {
            return ""
        }

        return "<\(name)>\(xmlEscaped(value))</\(name)>"
    }

    private func resourceElement(for item: SonoicSourceItem, uri: String) -> String {
        var attributes = "protocolInfo=\"\(xmlEscaped(SonosPlayablePayloadPreparer.protocolInfo(for: uri)))\""

        if let duration = item.duration {
            attributes += " duration=\"\(formattedDuration(duration))\""
        }

        return "<res \(attributes)>\(xmlEscaped(uri))</res>"
    }
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension SonoicModel {
    func appleMusicGeneratedPayloadCandidates(for item: SonoicSourceItem) -> [SonoicAppleMusicGeneratedPayloadCandidate] {
        SonoicAppleMusicSonosPayloadProbe()
            .candidates(for: item, playbackHint: appleMusicPlaybackHint)
    }

    func appleMusicGeneratedPlaybackCandidate(for item: SonoicSourceItem) -> SonoicAppleMusicGeneratedPayloadCandidate? {
        appleMusicGeneratedPayloadCandidates(for: item)
            .first { $0.isUserPlayable }
    }

    func appleMusicGeneratedQueueCandidate(for item: SonoicSourceItem) -> SonoicAppleMusicGeneratedPayloadCandidate? {
        SonoicAppleMusicSonosPayloadProbe()
            .queueCandidate(for: item, playbackHint: appleMusicPlaybackHint)
    }

    private var appleMusicPlaybackHint: SonosMusicServicePlaybackHint? {
        sonosMusicServiceProbeState.snapshot?
            .knownServiceRows
            .first { $0.service == .appleMusic }?
            .playbackHint
    }
}
