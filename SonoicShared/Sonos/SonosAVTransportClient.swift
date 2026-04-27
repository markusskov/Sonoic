import Foundation

struct SonosAVTransportClient {
    enum ClientError: LocalizedError {
        case invalidTransportState(String)
        case invalidQueueTrackNumber(String)

        var errorDescription: String? {
            switch self {
            case let .invalidTransportState(value):
                "The Sonos player returned an invalid transport state: \(value)."
            case let .invalidQueueTrackNumber(value):
                "The Sonos player returned an invalid queue track number: \(value)."
            }
        }
    }

    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchPlaybackState(host: String) async throws -> SonosNowPlayingSnapshot.PlaybackState {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetTransportInfo",
            body: """
            <u:GetTransportInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentTransportState").parse(data)

        return switch value {
        case "PLAYING":
            .playing
        case "PAUSED_PLAYBACK", "STOPPED", "NO_MEDIA_PRESENT":
            .paused
        case "TRANSITIONING":
            .buffering
        default:
            throw ClientError.invalidTransportState(value)
        }
    }

    func fetchCurrentTransportActions(host: String) async throws -> SonosTransportActions {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetCurrentTransportActions",
            body: """
            <u:GetCurrentTransportActions xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetCurrentTransportActions>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "Actions").parse(data)
        return SonosTransportActions(actionsString: value)
    }

    func setPlayMode(host: String, mode: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "SetPlayMode",
            body: """
            <u:SetPlayMode xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <NewPlayMode>\(escapedSOAPValue(mode))</NewPlayMode>
            </u:SetPlayMode>
            """,
            host: host
        )
    }

    func play(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Play",
            body: """
            <u:Play xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
            """,
            host: host
        )
    }

    func pause(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Pause",
            body: """
            <u:Pause xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Pause>
            """,
            host: host
        )
    }

    func next(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Next",
            body: """
            <u:Next xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Next>
            """,
            host: host
        )
    }

    func previous(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Previous",
            body: """
            <u:Previous xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Previous>
            """,
            host: host
        )
    }

    func seek(host: String, timeInterval: TimeInterval) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Seek",
            body: """
            <u:Seek xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Unit>REL_TIME</Unit>
              <Target>\(formattedSeekTarget(for: timeInterval))</Target>
            </u:Seek>
            """,
            host: host
        )
    }

    func seekToTrack(host: String, trackNumber: Int) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Seek",
            body: """
            <u:Seek xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Unit>TRACK_NR</Unit>
              <Target>\(trackNumber)</Target>
            </u:Seek>
            """,
            host: host
        )
    }

    func setTransportURI(host: String, uri: String, metadataXML: String?) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "SetAVTransportURI",
            body: """
            <u:SetAVTransportURI xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escapedSOAPValue(uri))</CurrentURI>
              <CurrentURIMetaData>\(escapedSOAPValue(metadataXML ?? ""))</CurrentURIMetaData>
            </u:SetAVTransportURI>
            """,
            host: host
        )
    }

    func joinGroup(host: String, coordinatorID: String) async throws {
        try await setTransportURI(
            host: host,
            uri: "x-rincon:\(coordinatorID)",
            metadataXML: nil
        )
    }

    func becomeStandaloneGroup(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "BecomeCoordinatorOfStandaloneGroup",
            body: """
            <u:BecomeCoordinatorOfStandaloneGroup xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:BecomeCoordinatorOfStandaloneGroup>
            """,
            host: host
        )
    }

    func addURIToQueue(
        host: String,
        uri: String,
        metadataXML: String?,
        enqueueAsNext: Bool = true
    ) async throws -> Int {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "AddURIToQueue",
            body: """
            <u:AddURIToQueue xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <EnqueuedURI>\(escapedSOAPValue(uri))</EnqueuedURI>
              <EnqueuedURIMetaData>\(escapedSOAPValue(metadataXML ?? ""))</EnqueuedURIMetaData>
              <DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued>
              <EnqueueAsNext>\(enqueueAsNext ? 1 : 0)</EnqueueAsNext>
            </u:AddURIToQueue>
            """,
            host: host
        )

        let values = try SonosSOAPValuesParser(expectedElements: ["FirstTrackNumberEnqueued"]).parse(data)
        let value = values["FirstTrackNumberEnqueued"] ?? ""
        guard let trackNumber = Int(value), trackNumber > 0 else {
            throw ClientError.invalidQueueTrackNumber(value)
        }

        return trackNumber
    }

    func removeAllTracksFromQueue(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "RemoveAllTracksFromQueue",
            body: """
            <u:RemoveAllTracksFromQueue xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:RemoveAllTracksFromQueue>
            """,
            host: host
        )
    }

    func removeTrackRangeFromQueue(
        host: String,
        startingIndex: Int,
        numberOfTracks: Int,
        updateID: Int = 0
    ) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "RemoveTrackRangeFromQueue",
            body: """
            <u:RemoveTrackRangeFromQueue xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <UpdateID>\(updateID)</UpdateID>
              <StartingIndex>\(startingIndex)</StartingIndex>
              <NumberOfTracks>\(numberOfTracks)</NumberOfTracks>
            </u:RemoveTrackRangeFromQueue>
            """,
            host: host
        )
    }

    func reorderTracksInQueue(
        host: String,
        startingIndex: Int,
        numberOfTracks: Int,
        insertBefore: Int,
        updateID: Int = 0
    ) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "ReorderTracksInQueue",
            body: """
            <u:ReorderTracksInQueue xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <StartingIndex>\(startingIndex)</StartingIndex>
              <NumberOfTracks>\(numberOfTracks)</NumberOfTracks>
              <InsertBefore>\(insertBefore)</InsertBefore>
              <UpdateID>\(updateID)</UpdateID>
            </u:ReorderTracksInQueue>
            """,
            host: host
        )
    }

    private func formattedSeekTarget(for timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func escapedSOAPValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
