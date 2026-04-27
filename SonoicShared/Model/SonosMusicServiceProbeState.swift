import Foundation

struct SonosMusicServiceProbeState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var status: Status
    var snapshot: SonosMusicServiceProbeSnapshot?

    static let idle = SonosMusicServiceProbeState(status: .idle, snapshot: nil)

    var isLoading: Bool {
        status == .loading
    }
}

struct SonosMusicServiceProbeSnapshot: Equatable {
    var observedAt: Date
    var serviceListVersion: String?
    var services: [SonosMusicServiceDescriptor]
    var accounts: [SonosMusicServiceAccountSummary]

    var knownServiceRows: [SonosMusicServiceProbeRow] {
        [SonosServiceDescriptor.appleMusic, .spotify, .sonosRadio].map { knownService in
            let service = services.first { service in
                SonosServiceCatalog.descriptor(named: service.name) == knownService
                    || SonosServiceCatalog.descriptor(forSonosServiceID: service.id) == knownService
            }
            let serviceType = service?.serviceType ?? knownService.sonosServiceType
            let matchedAccounts = serviceType.map { serviceType in
                accounts.filter { $0.serviceType == serviceType }
            } ?? []

            return SonosMusicServiceProbeRow(
                service: knownService,
                sonosService: service,
                accounts: matchedAccounts
            )
        }
    }

    func includingObservedAccounts(from values: [String?]) -> SonosMusicServiceProbeSnapshot {
        includingObservedAccounts(
            from: values.map { SonosMusicServiceObservedValue(value: $0, origin: .unknown) }
        )
    }

    func includingObservedAccounts(
        from observedValues: [SonosMusicServiceObservedValue]
    ) -> SonosMusicServiceProbeSnapshot {
        var snapshot = self
        let observedAccounts = SonosMusicServiceAccountSummary.observedAccounts(from: observedValues)

        for observedAccount in observedAccounts {
            if let accountIndex = snapshot.accounts.firstIndex(where: {
                $0.serviceType == observedAccount.serviceType && $0.serialNumber == observedAccount.serialNumber
            }) {
                snapshot.accounts[accountIndex].observedOrigins.formUnion(observedAccount.observedOrigins)
            } else {
                snapshot.accounts.append(observedAccount)
            }
        }

        return snapshot
    }
}

struct SonosMusicServiceProbeRow: Identifiable, Equatable {
    var service: SonosServiceDescriptor
    var sonosService: SonosMusicServiceDescriptor?
    var accounts: [SonosMusicServiceAccountSummary]

    var id: String {
        service.id
    }

    var statusTitle: String {
        guard sonosService != nil else {
            return "Not Found"
        }

        guard !accounts.isEmpty else {
            return "No Account"
        }

        return accounts.contains(where: \.hasStatusAccount) ? "Ready" : "Observed"
    }

    var detailText: String {
        guard let sonosService else {
            return "Not configured on Sonos."
        }

        let accountText = accounts.count == 1 ? "1 account" : "\(accounts.count) accounts"
        return "sid \(sonosService.id) · type \(sonosService.serviceTypeText) · \(accountText)"
    }

    var playbackHint: SonosMusicServicePlaybackHint? {
        guard service.kind == .appleMusic else {
            return nil
        }

        let launchSerials = orderedSerials(matching: \.isObservedFromLaunchPayload)
        let trackSerials = orderedSerials(matching: \.isObservedFromResolvedTrack)
        guard !launchSerials.isEmpty || !trackSerials.isEmpty else {
            return nil
        }

        return SonosMusicServicePlaybackHint(
            launchSerials: launchSerials,
            trackSerials: trackSerials
        )
    }

    private func orderedSerials(
        matching predicate: (SonosMusicServiceAccountSummary) -> Bool
    ) -> [String] {
        accounts
            .filter(predicate)
            .map(\.serialNumber)
            .reduce(into: [String]()) { result, serialNumber in
                guard !result.contains(serialNumber) else {
                    return
                }

                result.append(serialNumber)
            }
    }
}

struct SonosMusicServicePlaybackHint: Equatable {
    var launchSerials: [String]
    var trackSerials: [String]

    var launchText: String? {
        serialText(prefix: "Launch", serials: launchSerials)
    }

    var trackText: String? {
        serialText(prefix: "Track", serials: trackSerials)
    }

    var preferredLaunchSerial: String? {
        launchSerials.first
    }

    private func serialText(prefix: String, serials: [String]) -> String? {
        guard !serials.isEmpty else {
            return nil
        }

        return "\(prefix) sn \(serials.joined(separator: ", "))"
    }
}

struct SonosMusicServiceDescriptor: Identifiable, Equatable {
    var id: String
    var name: String
    var uri: String?
    var secureURI: String?
    var containerType: String?
    var capabilities: String?
    var authPolicy: String?
    var presentationMapURI: String?
    var stringsURI: String?

    var serviceType: String? {
        guard let serviceID = Int(id) else {
            return nil
        }

        return String((serviceID * 256) + 7)
    }

    var serviceTypeText: String {
        serviceType ?? "Unknown"
    }
}

struct SonosMusicServiceAccountSummary: Identifiable, Equatable {
    enum Source: Equatable {
        case statusAccounts
        case observedPlayback
    }

    enum ObservedOrigin: String, Hashable {
        case currentURI
        case trackURI
        case favoriteURI
        case favoriteMetadata
        case unknown

        var displayTitle: String? {
            switch self {
            case .currentURI:
                "current URI"
            case .trackURI:
                "track URI"
            case .favoriteURI:
                "saved item URI"
            case .favoriteMetadata:
                "saved metadata"
            case .unknown:
                nil
            }
        }
    }

    var serviceType: String
    var serialNumber: String
    var nickname: String?
    var hasUsername: Bool
    var hasOAuthDeviceID: Bool
    var hasKey: Bool
    var source: Source = .statusAccounts
    var observedOrigins: Set<ObservedOrigin> = []

    var id: String {
        "\(serviceType)-\(serialNumber)"
    }

    var hasStatusAccount: Bool {
        source == .statusAccounts
    }

    var isObservedFromLaunchPayload: Bool {
        !observedOrigins.isDisjoint(with: [.currentURI, .favoriteURI, .favoriteMetadata])
    }

    var isObservedFromResolvedTrack: Bool {
        observedOrigins.contains(.trackURI)
    }

    var displayName: String {
        nickname?.sonoicNonEmptyTrimmed ?? "Account sn \(serialNumber)"
    }

    var redactedDetail: String {
        var parts = ["sn \(serialNumber)"]

        if hasUsername {
            parts.append("user")
        }

        if hasOAuthDeviceID {
            parts.append("oauth device")
        }

        if hasKey {
            parts.append("key")
        }

        parts.append(contentsOf: observedOriginTitles)

        return parts.joined(separator: " · ")
    }

    static func observedAccounts(from values: [String?]) -> [SonosMusicServiceAccountSummary] {
        observedAccounts(
            from: values.map { SonosMusicServiceObservedValue(value: $0, origin: .unknown) }
        )
    }

    static func observedAccounts(from values: [SonosMusicServiceObservedValue]) -> [SonosMusicServiceAccountSummary] {
        var seenIDs: Set<String> = []
        var accounts: [SonosMusicServiceAccountSummary] = []

        for value in values {
            guard let account = observedAccount(from: value) else {
                continue
            }

            if let accountIndex = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[accountIndex].observedOrigins.formUnion(account.observedOrigins)
                continue
            }

            guard seenIDs.insert(account.id).inserted else {
                continue
            }

            accounts.append(account)
        }

        return accounts
    }

    private var observedOriginTitles: [String] {
        let orderedOrigins: [ObservedOrigin] = [.currentURI, .trackURI, .favoriteURI, .favoriteMetadata, .unknown]
        return orderedOrigins.compactMap { origin in
            observedOrigins.contains(origin) ? origin.displayTitle : nil
        }
    }

    private static func observedAccount(
        from observedValue: SonosMusicServiceObservedValue
    ) -> SonosMusicServiceAccountSummary? {
        guard let value = observedValue.value?.sonoicNonEmptyTrimmed else {
            return nil
        }

        let query = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(separator: "?", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init) ?? value

        let pairs = query.split(separator: "&").reduce(into: [String: String]()) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                return
            }

            result[String(parts[0]).lowercased()] = String(parts[1])
        }

        guard let sid = pairs["sid"],
              let serialNumber = pairs["sn"]?.sonoicNonEmptyTrimmed,
              let serviceID = Int(sid)
        else {
            return nil
        }

        return SonosMusicServiceAccountSummary(
            serviceType: String((serviceID * 256) + 7),
            serialNumber: serialNumber,
            nickname: "Observed in playback",
            hasUsername: false,
            hasOAuthDeviceID: false,
            hasKey: false,
            source: .observedPlayback,
            observedOrigins: [observedValue.origin]
        )
    }
}

struct SonosMusicServiceObservedValue: Equatable {
    var value: String?
    var origin: SonosMusicServiceAccountSummary.ObservedOrigin
}

extension SonosServiceDescriptor {
    var sonosServiceID: String? {
        switch kind {
        case .appleMusic:
            "204"
        case .spotify:
            "9"
        case .sonosRadio:
            "236"
        case .genericStreaming:
            nil
        }
    }

    var sonosServiceType: String? {
        guard let sonosServiceID,
              let serviceID = Int(sonosServiceID)
        else {
            return nil
        }

        return String((serviceID * 256) + 7)
    }
}
