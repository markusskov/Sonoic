extension SonoicModel {
    func toggleDebugPlayback() {
        switch nowPlaying.playbackState {
        case .playing:
            nowPlaying.playbackState = .paused
        case .paused, .buffering:
            nowPlaying.playbackState = .playing
        }
    }

    func toggleDebugMute() {
        externalVolume.isMuted.toggle()
    }
}
