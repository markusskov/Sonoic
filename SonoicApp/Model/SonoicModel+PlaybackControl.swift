import Foundation

extension SonoicModel {
    var canControlSonosPlayback: Bool {
        activeSonosControlAPIGroupID() != nil
    }

    func toggleSonosPlayback() async {
        let didToggle: Bool
        switch nowPlaying.playbackState {
        case .playing:
            didToggle = await pauseSonosPlayback()
        case .paused, .buffering:
            didToggle = await playSonosPlayback()
        }

        if !didToggle {
            recordCloudPlaybackControlUnavailable("Cloud playback is unavailable.")
        }
    }

    func playSonosPlayback() async -> Bool {
        let didPlay = await playSonosControlAPIPlaybackIfAvailable()
        if !didPlay {
            recordCloudPlaybackControlUnavailable("Cloud play is unavailable.")
        }
        return didPlay
    }

    func pauseSonosPlayback() async -> Bool {
        let didPause = await pauseSonosControlAPIPlaybackIfAvailable()
        if !didPause {
            recordCloudPlaybackControlUnavailable("Cloud pause is unavailable.")
        }
        return didPause
    }

    func skipToNextSonosTrack() async -> Bool {
        let didSkip = await skipToNextSonosControlAPITrackIfAvailable()
        if !didSkip {
            recordCloudPlaybackControlUnavailable("Cloud next is unavailable.")
        }
        return didSkip
    }

    func skipToPreviousSonosTrack() async -> Bool {
        let didSkip = await skipToPreviousSonosControlAPITrackIfAvailable()
        if !didSkip {
            recordCloudPlaybackControlUnavailable("Cloud previous is unavailable.")
        }
        return didSkip
    }

    func seekSonosPlayback(to timeInterval: TimeInterval) async -> Bool {
        let didSeek = await seekSonosControlAPIPlaybackIfAvailable(to: timeInterval)
        if !didSeek {
            recordCloudPlaybackControlUnavailable("Cloud seek is unavailable.")
        }
        return didSeek
    }

    func playLocalSonosQueueItem(at position: Int) async -> Bool {
        await playManualSonosQueueItem(at: position)
    }

    func playSonosFavorite(_ favorite: SonosFavoriteItem) async -> Bool {
        let didPlay = await playSonosControlAPIFavoriteIfAvailable(favorite)
        if !didPlay {
            recordCloudPlaybackControlUnavailable("Cloud favorite playback is unavailable.")
        }
        return didPlay
    }

    func toggleSonosMute() async {
        let didMute = await toggleSonosControlAPIMuteIfAvailable()
        if !didMute {
            recordCloudPlaybackControlUnavailable("Cloud mute is unavailable.")
        }
    }

    func setSonosVolume(to level: Int) async -> Bool {
        let didSetVolume = await setSonosControlAPIVolumeIfAvailable(to: level)
        if !didSetVolume {
            recordCloudPlaybackControlUnavailable("Cloud volume is unavailable.")
        }
        return didSetVolume
    }

    private func recordCloudPlaybackControlUnavailable(_ detail: String) {
        guard sonosControlAPIState.lastErrorDetail == nil else {
            return
        }

        sonosControlAPIState.lastErrorDetail = detail
        sonosControlAPIState.lastUpdatedAt = .now
    }
}
