import SwiftUI
import WidgetKit

extension SonoicModel {
    var externalControlState: SonoicExternalControlState {
        SonoicExternalControlState(
            activeTarget: .init(
                id: activeTarget.id,
                name: activeTarget.name,
                kind: externalTargetKind
            ),
            nowPlayingSnapshot: nowPlaying,
            volume: externalVolume,
            availability: externalAvailability,
            updatedAt: .now
        )
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isSceneActive = true
            endBackgroundExecutionIfNeeded()
            scheduleBackgroundPlayerRefreshIfPossible()
            startManualHostRefreshLoopIfPossible()
        case .inactive:
            isSceneActive = false
            stopManualHostRefreshLoop()
        case .background:
            isSceneActive = false
            stopManualHostRefreshLoop()
            scheduleBackgroundPlayerRefreshIfPossible()
            refreshPlayerStateOnBackgroundTransitionIfPossible()
        @unknown default:
            isSceneActive = false
            stopManualHostRefreshLoop()
            scheduleBackgroundPlayerRefreshIfPossible()
        }
    }

    private var externalAvailability: SonoicExternalControlState.Availability {
        switch connectionState {
        case .ready:
            .ready
        case .connecting:
            .connecting
        case .stale:
            .stale
        case .unavailable:
            .unavailable
        }
    }

    func persistSharedExternalControlState() {
        let state = externalControlState
        let canAdvanceProgress = !isManualPlayTransitionAwaitingConfirmation

        if let sharedStore {
            do {
                try sharedStore.saveExternalControlState(state)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                assertionFailure("Failed to save shared external control state: \(error)")
            }
        }

        nowPlayableSessionController.update(
            nowPlaying: nowPlaying,
            observedAt: nowPlayingObservedAt,
            activeTargetName: activeTarget.name,
            canControlPlayback: hasManualSonosHost,
            canAdvanceProgress: canAdvanceProgress
        )
    }

    private var externalTargetKind: SonoicExternalControlState.ActiveTarget.Kind {
        switch activeTarget.kind {
        case .room:
            .room
        case .group:
            .group
        }
    }

    func configureNowPlayableSessionController() {
        nowPlayableSessionController.setCommandHandlers(
            play: { [weak self] in
                guard let self else {
                    return false
                }

                return await self.playManualSonosPlayback()
            },
            pause: { [weak self] in
                guard let self else {
                    return false
                }

                return await self.pauseManualSonosPlayback()
            },
            next: { [weak self] in
                guard let self else {
                    return false
                }

                return await self.skipToNextManualSonosTrack()
            },
            previous: { [weak self] in
                guard let self else {
                    return false
                }

                return await self.skipToPreviousManualSonosTrack()
            },
            seek: { [weak self] timeInterval in
                guard let self else {
                    return false
                }

                return await self.seekManualSonosPlayback(to: timeInterval)
            }
        )
    }
}
