import Foundation

extension SonoicModel {
    var supportDiagnosticsSummary: String {
        supportDiagnosticsSummary(generatedAt: .now, bundle: .main)
    }

    func supportDiagnosticsSummary(
        generatedAt: Date,
        bundle: Bundle
    ) -> String {
        var lines = [
            "Sonoic Support Summary",
            "Generated: \(Self.supportDiagnosticsTimestamp(generatedAt))",
            "App: \(Self.supportDiagnosticsAppVersion(bundle: bundle))",
            "Apple Music: \(appleMusicAuthorizationState.title)",
            "Sonos Auth: \(sonosControlAPIState.authorizationStatus.supportDiagnosticsTitle)",
            "Sonos Mode: \(sonosControlAPIState.settings.mode.rawValue)",
            "Sonos Cloud: \(sonosControlAPICloudState.supportDiagnosticsSummary)",
            "Plus: \(plusState.supportDiagnosticsSummary)",
            "Target: \(supportDiagnosticsTargetSummary)",
            "Playback: \(nowPlaying.playbackState.title) · Source: \(SonoicDiagnosticsRedactor.redacted(nowPlaying.sourceName))",
            "Queue: \(queueState.supportDiagnosticsSummary)",
            "Refresh: \(manualHostRefreshStatus.supportDiagnosticsSummary)"
        ]

        lines.append(contentsOf: supportDiagnosticsErrorLines)
        return lines.joined(separator: "\n")
    }

    private var supportDiagnosticsTargetSummary: String {
        guard hasManualSonosHost else {
            return "No manual host configured"
        }

        guard activeTarget != Self.unconfiguredTarget else {
            return "Manual host configured · no active target"
        }

        let memberCount = max(1, activeTarget.memberNames.count)
        return "\(activeTarget.kind.title) selected · members=\(memberCount)"
    }

    private var supportDiagnosticsErrorLines: [String] {
        var lines: [String] = []

        if let detail = sonosControlAPIAuthorizationState.detail?.sonoicNonEmptyTrimmed {
            lines.append("Sonos Auth Detail: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = sonosControlAPIState.lastErrorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Last Control API Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let description = sonosControlAPIState.lastCommandDescription?.sonoicNonEmptyTrimmed {
            lines.append("Last Control API Command: \(SonoicDiagnosticsRedactor.redacted(description))")
        }

        if let detail = manualHostRefreshStatus.detail?.sonoicNonEmptyTrimmed {
            lines.append("Player Refresh Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = queueOperationErrorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Queue Operation Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = queueDiagnostics.lastRefreshErrorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Queue Refresh Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = queueDiagnostics.lastMutationErrorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Queue Mutation Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = seekDiagnostics.errorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Seek Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if let detail = discoveryErrorDetail?.sonoicNonEmptyTrimmed {
            lines.append("Discovery Error: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        if case let .failed(detail) = appleMusicServiceDetails.status,
           detail.sonoicNonEmptyTrimmed != nil
        {
            lines.append("Apple Music Detail: \(SonoicDiagnosticsRedactor.redacted(detail))")
        }

        return lines
    }

    private static func supportDiagnosticsTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func supportDiagnosticsAppVersion(bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.sonoicNonEmptyTrimmed, build?.sonoicNonEmptyTrimmed) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "build \(build)"
        case (nil, nil):
            return "Unavailable"
        }
    }
}

enum SonoicDiagnosticsRedactor {
    private struct Replacement {
        var pattern: String
        var template: String
    }

    private static let replacements = [
        Replacement(
            pattern: "\\bBearer\\s+[A-Za-z0-9._~+/=-]{6,}",
            template: "Bearer <redacted>"
        ),
        Replacement(
            pattern: "\"(access_token|refresh_token|id_token|client_secret|authorization_code|code|token|state|email|app_user_id|appUserID|customer_id|customerUserId|subscriber_id|subscriberId|transaction_id|transactionId|original_transaction_id|originalTransactionId)\"\\s*:\\s*\"[^\"]+\"",
            template: "\"$1\":\"<redacted>\""
        ),
        Replacement(
            pattern: "([?&](?:access_token|refresh_token|id_token|client_secret|authorization_code|code|token|state|email|app_user_id|appUserID|customer_id|customerUserId|subscriber_id|subscriberId|transaction_id|transactionId|original_transaction_id|originalTransactionId)=)[^\\s&#]+",
            template: "$1<redacted>"
        ),
        Replacement(
            pattern: "\\b(access_token|refresh_token|id_token|client_secret|authorization_code|token|email|app_user_id|appUserID|customer_id|customerUserId|subscriber_id|subscriberId|transaction_id|transactionId|original_transaction_id|originalTransactionId|SONOS_CLIENT_SECRET|BROKER_CODE_SIGNING_SECRET)\\s*[:=]\\s*[^\\s&,;]+",
            template: "$1=<redacted>"
        ),
        Replacement(
            pattern: "\\$RCAnonymousID:[A-Za-z0-9._:-]+",
            template: "<revenuecat-app-user-id>"
        ),
        Replacement(
            pattern: "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",
            template: "<email>"
        ),
        Replacement(
            pattern: "\\bgh[opsu]_[A-Za-z0-9_]{10,}\\b",
            template: "<redacted-token>"
        ),
        Replacement(
            pattern: "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\b",
            template: "<redacted-jwt>"
        ),
        Replacement(
            pattern: "\\bRINCON_[A-Za-z0-9_]+\\b",
            template: "<sonos-player-id>"
        ),
        Replacement(
            pattern: "\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b",
            template: "<uuid>"
        ),
        Replacement(
            pattern: "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b",
            template: "<ip-address>"
        ),
        Replacement(
            pattern: "\\b[A-Za-z0-9-]+\\.local\\b",
            template: "<local-host>"
        )
    ]

    static func redacted(_ value: String, maxLength: Int = 240) -> String {
        var output = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        for replacement in replacements {
            guard let expression = try? NSRegularExpression(
                pattern: replacement.pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }

            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = expression.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: replacement.template
            )
        }

        output = output.sonoicNonEmptyTrimmed ?? "Unavailable"
        guard output.count > maxLength else {
            return output
        }

        let endIndex = output.index(output.startIndex, offsetBy: maxLength)
        return "\(output[..<endIndex])..."
    }
}

private extension SonosControlAPIState.AuthorizationStatus {
    var supportDiagnosticsTitle: String {
        switch self {
        case .notConfigured:
            return "Not Configured"
        case .ready:
            return "Ready"
        case .expired:
            return "Expired"
        }
    }
}

private extension SonosControlAPICloudState {
    var supportDiagnosticsSummary: String {
        switch status {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case let .failed(detail):
            return "Failed · \(SonoicDiagnosticsRedactor.redacted(detail))"
        case let .verified(snapshot):
            return snapshot.supportDiagnosticsSummary
        }
    }
}

private extension SonoicPlusState {
    var supportDiagnosticsSummary: String {
        let entitlement = "entitlement=\(SonoicDiagnosticsRedactor.redacted(entitlementIdentifier, maxLength: 80))"
        let updateState = updatedAt == nil ? "updated=none" : "updated=present"

        switch status {
        case .notConfigured:
            return "Disabled · \(entitlement)"
        case .refreshing:
            return "Checking · \(entitlement) · \(updateState)"
        case .available:
            return "Available · \(entitlement) · \(updateState)"
        case .unlocked:
            return "Unlocked · \(entitlement) · \(updateState)"
        case let .failed(detail):
            return "Failed · \(entitlement) · \(updateState) · detail=\(SonoicDiagnosticsRedactor.redacted(detail))"
        }
    }
}

private extension SonosControlAPICloudSnapshot {
    var supportDiagnosticsSummary: String {
        var parts = [
            "Verified",
            "households=\(households.count)",
            "groups=\(groupCount)",
            "players=\(playerCount)",
            "favorites=\(favoriteCount)",
            "playlists=\(playlistCount)"
        ]

        let contentDiagnostics = contentFetchDiagnosticsByHouseholdID.values.flatMap(\.supportDiagnosticsParts)
        if !contentDiagnostics.isEmpty {
            parts.append("content=[\(contentDiagnostics.joined(separator: "; "))]")
        }

        return parts.joined(separator: " · ")
    }
}

private extension SonosControlAPICloudContentFetchDiagnostics {
    var supportDiagnosticsParts: [String] {
        [
            favorites.map { "favorites \($0.supportDiagnosticsSummary)" },
            playlists.map { "playlists \($0.supportDiagnosticsSummary)" }
        ]
        .compactMap(\.self)
    }
}

private extension SonosControlAPICloudContentFetchResult {
    var supportDiagnosticsSummary: String {
        switch status {
        case let .loaded(count, version):
            return "loaded count=\(count) version=\(version == nil ? "none" : "present")"
        case let .failed(detail, isAuthorizationFailure):
            return "failed auth=\(isAuthorizationFailure ? "yes" : "no") detail=\(SonoicDiagnosticsRedactor.redacted(detail))"
        }
    }
}

private extension SonosQueueState {
    var supportDiagnosticsSummary: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case let .unavailable(detail):
            return "Unavailable · \(SonoicDiagnosticsRedactor.redacted(detail))"
        case let .failed(detail):
            return "Failed · \(SonoicDiagnosticsRedactor.redacted(detail))"
        case let .loaded(snapshot):
            let currentIndex = snapshot.currentItemIndex.map { "\($0 + 1)" } ?? "none"
            return "Loaded · items=\(snapshot.items.count) · current=\(currentIndex) · localMutation=\(snapshot.supportsLocalMutation ? "yes" : "no")"
        }
    }
}

private extension SonosManualHostRefreshStatus {
    var supportDiagnosticsSummary: String {
        switch self {
        case .idle:
            return "Idle"
        case .refreshing:
            return "Refreshing"
        case .updated:
            return "Updated"
        case let .failed(detail):
            return "Failed · \(SonoicDiagnosticsRedactor.redacted(detail))"
        }
    }
}
