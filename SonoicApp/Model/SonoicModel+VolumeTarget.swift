import Foundation

extension SonoicModel {
    func fetchExternalVolumeForActiveTarget() async throws -> SonoicExternalControlState.Volume {
        if sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI {
            return try await fetchSonosControlAPIActiveTargetVolume()
        }

        guard activeTarget.kind == .group else {
            return try await renderingControlClient.fetchVolume(host: manualSonosHost)
        }

        do {
            return try await groupRenderingControlClient.fetchVolume(host: activeGroupRenderingHost())
        } catch {
            return try await renderingControlClient.fetchVolume(host: manualSonosHost)
        }
    }

    func setExternalMuteForActiveTarget(_ isMuted: Bool) async throws {
        if sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI {
            try await setSonosControlAPIActiveTargetMute(isMuted)
            return
        }

        if activeTarget.kind == .group {
            try await groupRenderingControlClient.setMute(host: activeGroupRenderingHost(), isMuted: isMuted)
        } else {
            try await renderingControlClient.setMute(host: manualSonosHost, isMuted: isMuted)
        }
    }

    func setExternalVolumeForActiveTarget(to level: Int) async throws {
        if sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI {
            try await setSonosControlAPIActiveTargetVolume(to: level)
            return
        }

        if activeTarget.kind == .group {
            try await groupRenderingControlClient.setVolume(host: activeGroupRenderingHost(), level: level)
        } else {
            try await renderingControlClient.setVolume(host: manualSonosHost, level: level)
        }
    }

    private func activeGroupRenderingHost() async -> String {
        await manualSonosCoordinatorHost() ?? manualSonosHost
    }
}
