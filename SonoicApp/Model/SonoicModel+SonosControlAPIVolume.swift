import Foundation

extension SonoicModel {
    private struct SonosControlAPICommandUnavailableError: LocalizedError {
        var errorDescription: String? {
            "Sonos Cloud control is unavailable."
        }
    }

    func fetchSonosControlAPIActiveTargetVolume() async throws -> SonoicExternalControlState.Volume {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            let volume = try await sonosControlAPIClient.groupVolume(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            return sonoicExternalVolume(from: volume)
        }

        let playerID = try sonosControlAPIActivePlayerID()
        let volume = try await sonosControlAPIClient.playerVolume(
            playerID: playerID,
            accessToken: context.accessToken
        )
        return sonoicExternalVolume(from: volume)
    }

    func setSonosControlAPIActiveTargetVolume(to level: Int) async throws {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            try await sonosControlAPIClient.setGroupVolume(
                groupID: context.groupID,
                level: level,
                accessToken: context.accessToken
            )
        } else {
            let playerID = try sonosControlAPIActivePlayerID()
            try await sonosControlAPIClient.setPlayerVolume(
                playerID: playerID,
                level: level,
                accessToken: context.accessToken
            )
        }
    }

    func setSonosControlAPIActiveTargetMute(_ isMuted: Bool) async throws {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudMute") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            try await sonosControlAPIClient.setGroupMute(
                groupID: context.groupID,
                isMuted: isMuted,
                accessToken: context.accessToken
            )
        } else {
            let playerID = try sonosControlAPIActivePlayerID()
            try await sonosControlAPIClient.setPlayerMute(
                playerID: playerID,
                isMuted: isMuted,
                accessToken: context.accessToken
            )
        }
    }

    func fetchSonosControlAPIPlayerVolume(playerID: String) async throws -> SonoicExternalControlState.Volume {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        let volume = try await sonosControlAPIClient.playerVolume(
            playerID: playerID,
            accessToken: tokenSet.accessToken
        )
        return sonoicExternalVolume(from: volume)
    }

    func setSonosControlAPIPlayerVolume(playerID: String, to level: Int) async throws {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        try await sonosControlAPIClient.setPlayerVolume(
            playerID: playerID,
            level: level,
            accessToken: tokenSet.accessToken
        )
    }

    func setSonosControlAPIPlayerMute(playerID: String, isMuted: Bool) async throws {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerMute") else {
            throw SonosControlAPICommandUnavailableError()
        }

        try await sonosControlAPIClient.setPlayerMute(
            playerID: playerID,
            isMuted: isMuted,
            accessToken: tokenSet.accessToken
        )
    }

    private func sonosControlAPIActivePlayerID() throws -> String {
        if activeTarget.kind == .room,
           let activePlayerID = activeTarget.id.sonoicNonEmptyTrimmed
        {
            return activePlayerID
        }

        guard let target = activeSonosControlAPICommandTarget(requiresActiveTargetMatch: true),
              let playerID = (target.playerID ?? target.coordinatorPlayerID)?.sonoicNonEmptyTrimmed
        else {
            throw SonosControlAPICommandUnavailableError()
        }

        return playerID
    }

    private func sonoicExternalVolume(
        from volume: SonosControlAPIVolumeState
    ) -> SonoicExternalControlState.Volume {
        SonoicExternalControlState.Volume(
            level: min(max(volume.volume, 0), 100),
            isMuted: volume.muted
        )
    }
}
