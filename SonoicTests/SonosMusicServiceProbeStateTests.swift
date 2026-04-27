import Foundation
import Testing
@testable import Sonoic

@Suite("Sonos music service probe state")
@MainActor
struct SonosMusicServiceProbeStateTests {
    @Test("matches known services to account service types")
    func matchesKnownServicesToAccounts() throws {
        let snapshot = SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: "123",
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: "https://apple.example/ws",
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: "AppLink",
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
                SonosMusicServiceDescriptor(
                    id: "9",
                    name: "Spotify",
                    uri: nil,
                    secureURI: "https://spotify.example/ws",
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: "OAuth",
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: [
                SonosMusicServiceAccountSummary(
                    serviceType: "52231",
                    serialNumber: "7",
                    nickname: nil,
                    hasUsername: true,
                    hasOAuthDeviceID: true,
                    hasKey: true
                ),
            ]
        )

        let rows = snapshot.knownServiceRows
        let appleMusic = try #require(rows.first { $0.service == .appleMusic })
        let spotify = try #require(rows.first { $0.service == .spotify })

        #expect(appleMusic.statusTitle == "Ready")
        #expect(appleMusic.detailText == "sid 204 · type 52231 · 1 account")
        #expect(appleMusic.accounts.first?.redactedDetail == "sn 7 · user · oauth device · key")
        #expect(spotify.statusTitle == "No Account")
    }

    @Test("infers account serials from Sonos playback URIs")
    func infersAccountsFromPlaybackURIs() throws {
        let snapshot = SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: nil,
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: nil,
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: []
        ).includingObservedAccounts(from: [
            "x-sonos-http:librarytrack%3aabc.m4p?sid=204&flags=8232&sn=7",
            "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&amp;flags=8300&amp;sn=7",
        ])

        let appleMusic = try #require(snapshot.knownServiceRows.first { $0.service == .appleMusic })

        #expect(appleMusic.statusTitle == "Observed")
        #expect(appleMusic.accounts.count == 1)
        #expect(appleMusic.accounts.first?.serviceType == "52231")
        #expect(appleMusic.accounts.first?.serialNumber == "7")
        #expect(appleMusic.accounts.first?.redactedDetail == "sn 7")
    }

    @Test("labels observed account origins")
    func labelsObservedAccountOrigins() throws {
        let snapshot = SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: nil,
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: nil,
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: []
        ).includingObservedAccounts(from: [
            SonosMusicServiceObservedValue(
                value: "x-sonos-http:librarytrack%3aabc.m4p?sid=204&flags=8232&sn=7",
                origin: .trackURI
            ),
            SonosMusicServiceObservedValue(
                value: "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&amp;flags=8300&amp;sn=7",
                origin: .favoriteURI
            ),
        ])

        let appleMusic = try #require(snapshot.knownServiceRows.first { $0.service == .appleMusic })

        #expect(appleMusic.accounts.first?.redactedDetail == "sn 7 · track URI · favorite URI")
    }

    @Test("summarizes playback account hints")
    func summarizesPlaybackAccountHints() throws {
        let snapshot = SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: nil,
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: nil,
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: []
        ).includingObservedAccounts(from: [
            SonosMusicServiceObservedValue(
                value: "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&flags=8300&sn=3",
                origin: .currentURI
            ),
            SonosMusicServiceObservedValue(
                value: "x-rincon-cpcontainer:1006206cplaylist%3aabc?sid=204&flags=8300&sn=3",
                origin: .favoriteURI
            ),
            SonosMusicServiceObservedValue(
                value: "x-sonos-http:librarytrack%3aabc.m4p?sid=204&flags=8232&sn=7",
                origin: .trackURI
            ),
        ])

        let appleMusic = try #require(snapshot.knownServiceRows.first { $0.service == .appleMusic })
        let playbackHint = try #require(appleMusic.playbackHint)

        #expect(playbackHint.launchText == "Launch sn 3")
        #expect(playbackHint.trackText == "Track sn 7")
        #expect(playbackHint.preferredLaunchSerial == "3")
    }

    @Test("service type derives from Sonos service id")
    func serviceTypeDerivesFromServiceID() {
        let appleMusic = SonosMusicServiceDescriptor(
            id: "204",
            name: "Apple Music",
            uri: nil,
            secureURI: nil,
            containerType: nil,
            capabilities: nil,
            authPolicy: nil,
            presentationMapURI: nil,
            stringsURI: nil
        )

        #expect(appleMusic.serviceType == "52231")
        #expect(SonosServiceDescriptor.appleMusic.sonosServiceType == "52231")
        #expect(SonosServiceDescriptor.spotify.sonosServiceType == "2311")
    }
}
