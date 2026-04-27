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
