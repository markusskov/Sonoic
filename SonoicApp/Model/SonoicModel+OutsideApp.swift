import SwiftUI
import WidgetKit

extension SonoicModel {
    private static let sharedStorePersistDebounceDelay: Duration = .milliseconds(300)
    private static let sharedStoreKeepAliveInterval: TimeInterval = 45

    var externalControlState: SonoicExternalControlState {
        guard hasManualSonosHost else {
            return .unconfigured
        }

        return SonoicExternalControlState(
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
        guard hasManualSonosHost else {
            return .unavailable
        }

        switch manualHostRefreshStatus {
        case .idle, .refreshing:
            return availabilityFromLastSuccessfulRefresh() ?? .connecting
        case .updated(let updatedAt):
            return availability(for: updatedAt)
        case .failed:
            return availabilityFromLastSuccessfulRefresh() ?? .unavailable
        }
    }

    func persistSharedExternalControlState(forceImmediate: Bool = false) {
        let state = externalControlState
        let canAdvanceProgress = !isManualPlayTransitionAwaitingConfirmation

        scheduleSharedExternalControlStatePersistence(state, forceImmediate: forceImmediate)

        nowPlayableSessionController.update(
            nowPlaying: nowPlaying,
            observedAt: nowPlayingObservedAt,
            activeTargetName: activeTarget.name,
            canControlPlayback: hasManualSonosHost,
            canAdvanceProgress: canAdvanceProgress
        )
    }

    private func scheduleSharedExternalControlStatePersistence(
        _ state: SonoicExternalControlState,
        forceImmediate: Bool
    ) {
        pendingSharedExternalControlState = state

        guard sharedStore != nil else {
            return
        }

        if forceImmediate {
            sharedStorePersistTask?.cancel()
            sharedStorePersistTask = nil
            persistPendingSharedExternalControlStateIfNeeded(forceWrite: true)
            return
        }

        guard sharedStorePersistTask == nil else {
            return
        }

        sharedStorePersistTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.sharedStorePersistDebounceDelay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.persistPendingSharedExternalControlStateIfNeeded()
        }
    }

    private func persistPendingSharedExternalControlStateIfNeeded(forceWrite: Bool = false) {
        defer {
            sharedStorePersistTask = nil
        }

        guard let sharedStore,
              let state = pendingSharedExternalControlState
        else {
            pendingSharedExternalControlState = nil
            return
        }

        pendingSharedExternalControlState = nil

        guard forceWrite || shouldPersistSharedExternalControlState(state) else {
            return
        }

        do {
            try sharedStore.saveExternalControlState(state)
            lastPersistedSharedWidgetPresentation = state.widgetPresentation
            lastSharedStorePersistAt = .now
            if shouldReloadWidgetTimelines(for: state) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            assertionFailure("Failed to save shared external control state: \(error)")
        }
    }

    private func shouldPersistSharedExternalControlState(_ state: SonoicExternalControlState) -> Bool {
        let widgetPresentation = state.widgetPresentation

        if lastPersistedSharedWidgetPresentation != widgetPresentation {
            return true
        }

        guard let lastSharedStorePersistAt else {
            return true
        }

        return Date().timeIntervalSince(lastSharedStorePersistAt) >= Self.sharedStoreKeepAliveInterval
    }

    private var externalTargetKind: SonoicExternalControlState.ActiveTarget.Kind {
        switch activeTarget.kind {
        case .room:
            .room
        case .group:
            .group
        }
    }

    private func availabilityFromLastSuccessfulRefresh() -> SonoicExternalControlState.Availability? {
        guard let manualHostLastSuccessfulRefreshAt else {
            return nil
        }

        return availability(for: manualHostLastSuccessfulRefreshAt)
    }

    private func availability(for updatedAt: Date) -> SonoicExternalControlState.Availability {
        let isStale = Date().timeIntervalSince(updatedAt) >= SonoicExternalControlState.staleInterval
        return isStale ? .stale : .ready
    }

    private func shouldReloadWidgetTimelines(for state: SonoicExternalControlState) -> Bool {
        let widgetPresentation = state.widgetPresentation
        defer {
            lastReloadedWidgetPresentation = widgetPresentation
        }

        return lastReloadedWidgetPresentation != widgetPresentation
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
