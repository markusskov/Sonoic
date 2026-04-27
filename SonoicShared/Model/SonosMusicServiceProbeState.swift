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
        var snapshot = self
        let observedAccounts = SonosMusicServiceAccountSummary.observedAccounts(from: values)

        for observedAccount in observedAccounts where !snapshot.accounts.contains(where: {
            $0.serviceType == observedAccount.serviceType && $0.serialNumber == observedAccount.serialNumber
        }) {
            snapshot.accounts.append(observedAccount)
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

    var serviceType: String
    var serialNumber: String
    var nickname: String?
    var hasUsername: Bool
    var hasOAuthDeviceID: Bool
    var hasKey: Bool
    var source: Source = .statusAccounts

    var id: String {
        "\(serviceType)-\(serialNumber)"
    }

    var hasStatusAccount: Bool {
        source == .statusAccounts
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

        return parts.joined(separator: " · ")
    }

    static func observedAccounts(from values: [String?]) -> [SonosMusicServiceAccountSummary] {
        var seenIDs: Set<String> = []
        return values.compactMap(observedAccount).filter { account in
            seenIDs.insert(account.id).inserted
        }
    }

    private static func observedAccount(from value: String?) -> SonosMusicServiceAccountSummary? {
        guard let value = value?.sonoicNonEmptyTrimmed else {
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
            source: .observedPlayback
        )
    }
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
