import Testing
@testable import Sonoic

@MainActor
struct SonosPlayablePayloadPreparerTests {
    private let preparer = SonosPlayablePayloadPreparer()

    @Test
    func preparesDirectAppleMusicPayload() throws {
        let payload = payload(
            uri: "  x-sonosapi-hls:song%3a1440845464?sid=204  ",
            metadataXML: "  <DIDL-Lite />  "
        )

        let preparedPayload = try preparer.prepare(payload)

        #expect(preparedPayload.uri == "x-sonosapi-hls:song%3a1440845464?sid=204")
        #expect(preparedPayload.metadataXML == "<DIDL-Lite />")
    }

    @Test
    func preparesDirectCollectionPayloadWithoutMetadata() throws {
        let payload = payload(
            uri: "x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204",
            metadataXML: nil,
            kind: .collection
        )

        let preparedPayload = try preparer.prepare(payload)

        #expect(preparedPayload.uri == payload.uri)
        #expect(preparedPayload.metadataXML == nil)
    }

    @Test
    func rejectsQueueOwnedURI() throws {
        let payload = payload(uri: "x-rincon-queue:RINCON_123#0")

        #expect(throws: SonosPlayablePayloadPreparer.Failure.queueOwnedURI) {
            try preparer.prepare(payload)
        }
        #expect(payload.validationFailureReason == "Queue-owned URIs cannot be launched as source payloads.")
    }

    @Test
    func rejectsGroupCoordinatorURI() {
        let payload = payload(uri: "x-rincon:RINCON_123")

        #expect(throws: SonosPlayablePayloadPreparer.Failure.groupCoordinatorURI) {
            try preparer.prepare(payload)
        }
    }

    @Test
    func rejectsUnsupportedHTTPURI() {
        let payload = payload(uri: "https://example.com/song.mp3")

        #expect(throws: SonosPlayablePayloadPreparer.Failure.unsupportedURI("https://example.com/song.mp3")) {
            try preparer.prepare(payload)
        }
    }

    @Test
    func queueNextRequiresItemPayload() {
        let payload = payload(
            uri: "x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204",
            metadataXML: "<DIDL-Lite />",
            kind: .collection,
            launchMode: .queueNext
        )

        #expect(throws: SonosPlayablePayloadPreparer.Failure.queueNextRequiresItem) {
            try preparer.prepare(payload)
        }
    }

    @Test
    func queueNextRequiresMetadata() {
        let payload = payload(
            uri: "x-sonosapi-hls:song%3a1440845464?sid=204",
            metadataXML: nil,
            launchMode: .queueNext
        )

        #expect(throws: SonosPlayablePayloadPreparer.Failure.queueNextRequiresMetadata) {
            try preparer.prepare(payload)
        }
    }

    @Test
    func preparesQueueNextItemPayload() throws {
        let payload = payload(
            uri: "x-sonosapi-hls:song%3a1440845464?sid=204",
            metadataXML: "<DIDL-Lite />",
            launchMode: .queueNext
        )

        let preparedPayload = try preparer.prepare(payload)

        #expect(preparedPayload.launchMode == .queueNext)
        #expect(preparedPayload.metadataXML == "<DIDL-Lite />")
    }

    private func payload(
        uri: String,
        metadataXML: String? = nil,
        kind: SonosPlayablePayload.Kind = .item,
        launchMode: SonosPlayablePayload.LaunchMode = .direct
    ) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: "payload",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            service: .appleMusic,
            uri: uri,
            metadataXML: metadataXML,
            kind: kind,
            launchMode: launchMode
        )
    }
}
