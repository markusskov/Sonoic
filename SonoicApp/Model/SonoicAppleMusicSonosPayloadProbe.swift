import Foundation

struct SonoicAppleMusicGeneratedPayloadCandidate: Identifiable, Equatable {
    enum Strategy: String, Equatable {
        case catalogHLS
        case libraryTrack

        var title: String {
            switch self {
            case .catalogHLS:
                "Catalog HLS"
            case .libraryTrack:
                "Library Track"
            }
        }
    }

    var strategy: Strategy
    var uri: String
    var serialNumber: String

    var id: String {
        "\(strategy.rawValue)-\(serialNumber)-\(uri)"
    }
}

struct SonoicAppleMusicSonosPayloadProbe {
    private let appleMusicServiceID = "204"

    func candidates(
        for item: SonoicSourceItem,
        playbackHint: SonosMusicServicePlaybackHint?
    ) -> [SonoicAppleMusicGeneratedPayloadCandidate] {
        guard item.service.kind == .appleMusic,
              item.kind == .song,
              let playbackHint,
              let identity = item.appleMusicIdentity
        else {
            return []
        }

        var candidates: [SonoicAppleMusicGeneratedPayloadCandidate] = []

        if let catalogID = identity.catalogID.sonoicNonEmptyTrimmed,
           let launchSerial = playbackHint.preferredLaunchSerial?.sonoicNonEmptyTrimmed,
           let encodedCatalogID = sonosPayloadID(catalogID) {
            candidates.append(
                SonoicAppleMusicGeneratedPayloadCandidate(
                    strategy: .catalogHLS,
                    uri: "x-sonosapi-hls:song%3a\(encodedCatalogID)?sid=\(appleMusicServiceID)&sn=\(launchSerial)",
                    serialNumber: launchSerial
                )
            )
        }

        if let libraryID = identity.libraryID.sonoicNonEmptyTrimmed,
           let trackSerial = playbackHint.trackSerials.first?.sonoicNonEmptyTrimmed,
           let encodedLibraryID = sonosPayloadID(libraryID) {
            candidates.append(
                SonoicAppleMusicGeneratedPayloadCandidate(
                    strategy: .libraryTrack,
                    uri: "x-sonos-http:librarytrack%3a\(encodedLibraryID).m4p?sid=\(appleMusicServiceID)&flags=8232&sn=\(trackSerial)",
                    serialNumber: trackSerial
                )
            )
        }

        return candidates
    }

    private func sonosPayloadID(_ value: String) -> String? {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
}

extension SonoicModel {
    func appleMusicGeneratedPayloadCandidates(for item: SonoicSourceItem) -> [SonoicAppleMusicGeneratedPayloadCandidate] {
        SonoicAppleMusicSonosPayloadProbe()
            .candidates(for: item, playbackHint: appleMusicPlaybackHint)
    }

    private var appleMusicPlaybackHint: SonosMusicServicePlaybackHint? {
        sonosMusicServiceProbeState.snapshot?
            .knownServiceRows
            .first { $0.service == .appleMusic }?
            .playbackHint
    }
}
