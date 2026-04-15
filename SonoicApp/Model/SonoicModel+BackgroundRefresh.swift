import BackgroundTasks
import UIKit

extension SonoicModel {
    func scheduleBackgroundPlayerRefreshIfPossible() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: SonoicBackgroundRefresh.taskIdentifier)

        guard hasManualSonosHost else {
            return
        }

        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: SonoicBackgroundRefresh.taskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(SonoicBackgroundRefresh.earliestBeginInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            assertionFailure("Unable to schedule background refresh: \(error)")
        }
    }

    func handleBackgroundPlayerRefresh() async {
        scheduleBackgroundPlayerRefreshIfPossible()

        guard hasManualSonosHost else {
            return
        }

        _ = await syncManualSonosState(showProgress: false)
    }

    func refreshPlayerStateOnBackgroundTransitionIfPossible() {
        guard hasManualSonosHost else {
            return
        }

        endBackgroundExecutionIfNeeded()

        backgroundExecutionIdentifier = UIApplication.shared.beginBackgroundTask(withName: "SonoicPlayerRefresh") {
            self.endBackgroundExecutionIfNeeded()
        }

        Task { @MainActor in
            _ = await syncManualSonosState(showProgress: false)
            endBackgroundExecutionIfNeeded()
        }
    }

    func endBackgroundExecutionIfNeeded() {
        guard backgroundExecutionIdentifier != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundExecutionIdentifier)
        backgroundExecutionIdentifier = .invalid
    }
}
