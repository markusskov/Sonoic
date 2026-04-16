import Foundation

extension SonoicModel {
    private static let manualHostTargetIDPrefix = "manual-host:"

    func resetManualHostIdentity() {
        resolvedManualHostIdentityHost = nil
        resolvedManualHostTopologyHost = nil
        manualHostIdentityStatus = .idle
        manualHostTopologyStatus = .idle

        let nextTarget = hasManualSonosHost
            ? manualHostPlaceholderTarget(for: manualSonosHost)
            : Self.defaultTarget

        guard activeTarget != nextTarget else {
            return
        }

        activeTarget = nextTarget
    }

    func refreshManualHostIdentityIfNeeded() async {
        guard hasManualSonosHost else {
            manualHostIdentityStatus = .idle
            return
        }

        let normalizedHost = normalizedManualSonosHost(manualSonosHost)
        guard resolvedManualHostIdentityHost != normalizedHost else {
            manualHostIdentityStatus = .resolved
            return
        }

        manualHostIdentityStatus = .loading

        do {
            let deviceInfo = try await deviceInfoClient.fetchDeviceInfo(host: manualSonosHost)
            applyManualHostDeviceInfo(deviceInfo, host: normalizedHost)
            manualHostIdentityStatus = .resolved
        } catch {
            manualHostIdentityStatus = .failed(error.localizedDescription)
        }
    }

    private func applyManualHostDeviceInfo(_ deviceInfo: SonosDeviceInfo, host: String) {
        let playerDetail = deviceInfo.playerDetail ?? host
        let resolvedTarget = SonosActiveTarget(
            id: deviceInfo.preferredTargetID ?? manualHostTargetID(for: host),
            name: deviceInfo.roomName,
            householdName: playerDetail,
            kind: .room,
            memberNames: [deviceInfo.roomName]
        )

        resolvedManualHostIdentityHost = host

        guard activeTarget != resolvedTarget else {
            return
        }

        activeTarget = resolvedTarget
    }

    private func manualHostPlaceholderTarget(for host: String) -> SonosActiveTarget {
        let normalizedHost = normalizedManualSonosHost(host)

        return SonosActiveTarget(
            id: manualHostTargetID(for: normalizedHost),
            name: normalizedHost,
            householdName: normalizedHost,
            kind: .room,
            memberNames: [normalizedHost]
        )
    }

    private func manualHostTargetID(for host: String) -> String {
        "\(Self.manualHostTargetIDPrefix)\(host)"
    }

    func normalizedManualSonosHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
