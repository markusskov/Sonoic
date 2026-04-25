import AVFoundation
import AVFAudio
import MediaPlayer
import UIKit

@MainActor
final class SonoicNowPlayableSessionController: NSObject {
    typealias PlaybackCommandHandler = () async -> Bool
    typealias SeekCommandHandler = (TimeInterval) async -> Bool

    private let anchorPlayer = AVPlayer()
    private let nowPlayingSession: MPNowPlayingSession
    private var playHandler: PlaybackCommandHandler?
    private var pauseHandler: PlaybackCommandHandler?
    private var nextHandler: PlaybackCommandHandler?
    private var previousHandler: PlaybackCommandHandler?
    private var seekHandler: SeekCommandHandler?
    private var currentNowPlaying: SonosNowPlayingSnapshot?
    private var currentPlaybackState: SonosNowPlayingSnapshot.PlaybackState = .paused
    private var canAdvanceProgress = true
    private var currentObservedAt = Date()
    private var progressUpdateTask: Task<Void, Never>?
    private var anchorPreparationTask: Task<Void, Never>?

    override init() {
        anchorPlayer.isMuted = true
        anchorPlayer.volume = 0
        anchorPlayer.actionAtItemEnd = .pause
        nowPlayingSession = MPNowPlayingSession(players: [anchorPlayer])
        super.init()
        nowPlayingSession.automaticallyPublishesNowPlayingInfo = false
        configureAudioSession()
    }

    func setCommandHandlers(
        play: PlaybackCommandHandler?,
        pause: PlaybackCommandHandler?,
        next: PlaybackCommandHandler?,
        previous: PlaybackCommandHandler?,
        seek: SeekCommandHandler?
    ) {
        playHandler = play
        pauseHandler = pause
        nextHandler = next
        previousHandler = previous
        seekHandler = seek

        let commandCenter = nowPlayingSession.remoteCommandCenter
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            return self?.handleCommand(self?.playHandler) ?? .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            return self?.handleCommand(self?.pauseHandler) ?? .commandFailed
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleCommand(self?.nextHandler) ?? .commandFailed
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handleCommand(self?.previousHandler) ?? .commandFailed
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }

            let handler = currentPlaybackState == .playing ? pauseHandler : playHandler
            return handleCommand(handler)
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent,
                  let seekHandler
            else {
                return .commandFailed
            }

            Task {
                _ = await seekHandler(event.positionTime)
            }

            return .success
        }
    }

    func update(
        nowPlaying: SonosNowPlayingSnapshot,
        observedAt: Date,
        activeTargetName: String,
        canControlPlayback: Bool,
        canAdvanceProgress: Bool
    ) {
        guard canControlPlayback else {
            clear()
            return
        }

        configureAudioSession()
        currentNowPlaying = nowPlaying
        currentPlaybackState = nowPlaying.playbackState
        self.canAdvanceProgress = canAdvanceProgress
        currentObservedAt = observedAt
        preparePlaybackAnchorIfNeeded(activeTargetName: activeTargetName)
        publishNowPlayingInfo(nowPlaying: effectiveNowPlayingSnapshot(at: .now), publishedAt: .now, activeTargetName: activeTargetName)
        syncAnchorPlayback(nowPlaying: nowPlaying, observedAt: observedAt)
        updateCommandAvailability(for: nowPlaying)
        updateProgressLoop(activeTargetName: activeTargetName)
        activateNowPlayingSession()
    }

    func clear() {
        anchorPlayer.pause()
        anchorPlayer.seek(to: .zero)
        anchorPreparationTask?.cancel()
        anchorPreparationTask = nil
        progressUpdateTask?.cancel()
        progressUpdateTask = nil
        currentNowPlaying = nil
        currentPlaybackState = .paused
        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingSession.nowPlayingInfoCenter.playbackState = .stopped
        updateCommandAvailability(isEnabled: false)

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            assertionFailure("Unable to deactivate the audio session: \(error)")
        }
    }

    private func publishNowPlayingInfo(
        nowPlaying: SonosNowPlayingSnapshot,
        publishedAt: Date,
        activeTargetName: String
    ) {
        let playbackRate = effectivePlaybackRate(for: nowPlaying.playbackState)
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyCurrentPlaybackDate: publishedAt,
        ]

        if let artistName = nowPlaying.artistName.sonoicNonEmptyTrimmed {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artistName
        }

        if let albumTitle = nowPlaying.albumTitle.sonoicNonEmptyTrimmed {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        } else {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = activeTargetName
        }

        if let elapsedTime = nowPlaying.elapsedTime {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        }

        if let duration = nowPlaying.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artwork = SonoicNowPlayableArtworkProvider.artwork(for: nowPlaying.artworkIdentifier) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingSession.nowPlayingInfoCenter.playbackState = nowPlayingInfoCenterPlaybackState(for: nowPlaying.playbackState)
    }

    private func updateProgressLoop(activeTargetName: String) {
        progressUpdateTask?.cancel()
        progressUpdateTask = nil

        guard let currentNowPlaying,
              currentNowPlaying.playbackState == .playing,
              canAdvanceProgress,
              currentNowPlaying.elapsedTime != nil,
              currentNowPlaying.duration != nil
        else {
            return
        }

        progressUpdateTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                let publicationDate = Date()
                let nowPlaying = self.effectiveNowPlayingSnapshot(at: publicationDate)
                self.publishNowPlayingInfo(
                    nowPlaying: nowPlaying,
                    publishedAt: publicationDate,
                    activeTargetName: activeTargetName
                )
            }
        }
    }

    private func effectiveNowPlayingSnapshot(at referenceDate: Date) -> SonosNowPlayingSnapshot {
        guard var currentNowPlaying else {
            return SonosNowPlayingSnapshot(
                title: "",
                artistName: nil,
                albumTitle: nil,
                sourceName: "",
                playbackState: .paused
            )
        }

        guard currentNowPlaying.playbackState == .playing,
              canAdvanceProgress,
              let elapsedTime = currentNowPlaying.elapsedTime
        else {
            return currentNowPlaying
        }

        let advancedElapsedTime = elapsedTime + max(referenceDate.timeIntervalSince(currentObservedAt), 0)

        if let duration = currentNowPlaying.duration {
            currentNowPlaying.elapsedTime = min(advancedElapsedTime, duration)
        } else {
            currentNowPlaying.elapsedTime = advancedElapsedTime
        }

        return currentNowPlaying
    }

    private func syncAnchorPlayback(nowPlaying: SonosNowPlayingSnapshot, observedAt: Date) {
        guard anchorPlayer.currentItem != nil else {
            return
        }

        let desiredElapsedTime = anchorElapsedTime(for: nowPlaying, observedAt: observedAt)
        let currentElapsedTime = anchorPlayer.currentTime().seconds
        let needsSeek: Bool

        if currentElapsedTime.isNaN || currentElapsedTime.isInfinite {
            needsSeek = true
        } else {
            let seekTolerance = nowPlaying.playbackState == .playing ? 1.5 : 0.25
            needsSeek = abs(currentElapsedTime - desiredElapsedTime) > seekTolerance
        }

        if needsSeek {
            anchorPlayer.seek(
                to: CMTime(seconds: desiredElapsedTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        switch nowPlaying.playbackState {
        case .playing:
            anchorPlayer.playImmediately(atRate: 1.0)
        case .paused, .buffering:
            anchorPlayer.pause()
        }
    }

    private func updateCommandAvailability(for nowPlaying: SonosNowPlayingSnapshot) {
        let commandCenter = nowPlayingSession.remoteCommandCenter
        commandCenter.playCommand.isEnabled = nowPlaying.playbackState != .playing
        commandCenter.pauseCommand.isEnabled = nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = nowPlaying.supportsTrackNavigation
        commandCenter.previousTrackCommand.isEnabled = nowPlaying.supportsTrackNavigation
        commandCenter.changePlaybackPositionCommand.isEnabled = seekHandler != nil && nowPlaying.duration != nil
    }

    private func updateCommandAvailability(isEnabled: Bool) {
        let commandCenter = nowPlayingSession.remoteCommandCenter
        commandCenter.playCommand.isEnabled = isEnabled
        commandCenter.pauseCommand.isEnabled = isEnabled
        commandCenter.togglePlayPauseCommand.isEnabled = isEnabled
        commandCenter.nextTrackCommand.isEnabled = isEnabled
        commandCenter.previousTrackCommand.isEnabled = isEnabled
        commandCenter.changePlaybackPositionCommand.isEnabled = isEnabled
    }

    private func handleCommand(_ handler: PlaybackCommandHandler?) -> MPRemoteCommandHandlerStatus {
        guard let handler else {
            return .commandFailed
        }

        Task {
            _ = await handler()
        }

        return .success
    }

    private func preparePlaybackAnchorIfNeeded(activeTargetName: String) {
        guard anchorPlayer.currentItem == nil,
              anchorPreparationTask == nil
        else {
            return
        }

        anchorPreparationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return Result<URL, Error>.success(try SonoicSilentAudioAnchor().fileURL())
                } catch {
                    return Result<URL, Error>.failure(error)
                }
            }.value

            guard let self,
                  !Task.isCancelled
            else {
                return
            }

            anchorPreparationTask = nil

            switch result {
            case let .success(fileURL):
                guard anchorPlayer.currentItem == nil else {
                    return
                }

                anchorPlayer.replaceCurrentItem(with: AVPlayerItem(url: fileURL))

                if let currentNowPlaying {
                    let publicationDate = Date()
                    publishNowPlayingInfo(
                        nowPlaying: effectiveNowPlayingSnapshot(at: publicationDate),
                        publishedAt: publicationDate,
                        activeTargetName: activeTargetName
                    )
                    syncAnchorPlayback(nowPlaying: currentNowPlaying, observedAt: currentObservedAt)
                    updateProgressLoop(activeTargetName: activeTargetName)
                    activateNowPlayingSession()
                }
            case let .failure(error):
                assertionFailure("Unable to prepare the local playback anchor: \(error)")
            }
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try audioSession.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            assertionFailure("Unable to configure the audio session for the now playable session: \(error)")
        }
    }

    private func activateNowPlayingSession() {
        Task {
            _ = await nowPlayingSession.becomeActiveIfPossible()
        }
    }

    private func effectivePlaybackRate(for playbackState: SonosNowPlayingSnapshot.PlaybackState) -> Double {
        guard canAdvanceProgress || playbackState != .playing else {
            return 0
        }

        return playbackRate(for: playbackState)
    }

    private func playbackRate(for playbackState: SonosNowPlayingSnapshot.PlaybackState) -> Double {
        switch playbackState {
        case .playing:
            1.0
        case .paused, .buffering:
            0
        }
    }

    private func nowPlayingInfoCenterPlaybackState(
        for playbackState: SonosNowPlayingSnapshot.PlaybackState
    ) -> MPNowPlayingPlaybackState {
        switch playbackState {
        case .playing:
            .playing
        case .paused:
            .paused
        case .buffering:
            .interrupted
        }
    }

    private func anchorElapsedTime(
        for nowPlaying: SonosNowPlayingSnapshot,
        observedAt: Date,
        referenceDate: Date = .now
    ) -> TimeInterval {
        guard let elapsedTime = nowPlaying.elapsedTime else {
            return 0
        }

        guard nowPlaying.playbackState == .playing else {
            return elapsedTime
        }

        let advancedElapsedTime = elapsedTime + max(referenceDate.timeIntervalSince(observedAt), 0)

        if let duration = nowPlaying.duration {
            return min(advancedElapsedTime, duration)
        }

        return advancedElapsedTime
    }
}
