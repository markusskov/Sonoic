import SwiftUI

extension PlayerSheetView {
    var volumeBinding: Binding<Double> {
        Binding(
            get: {
                volumeLevel
            },
            set: { newValue in
                volumeLevel = min(max(newValue.rounded(), 0), 100)
                scheduleVolumeCommit()
            }
        )
    }

    var volumeLabelText: String {
        model.externalVolume.isMuted ? "Muted" : "\(Int(volumeLevel.rounded()))%"
    }

    var volumeSystemImage: String {
        if model.externalVolume.isMuted || volumeLevel == 0 {
            return "speaker.slash.fill"
        }

        if volumeLevel < 34 {
            return "speaker.wave.1.fill"
        }

        if volumeLevel < 67 {
            return "speaker.wave.2.fill"
        }

        return "speaker.wave.3.fill"
    }

    var muteButtonTitle: String {
        model.externalVolume.isMuted ? "Unmute" : "Mute"
    }

    var muteButtonSystemImage: String {
        model.externalVolume.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    var artworkReloadKey: String {
        [
            model.nowPlaying.artworkIdentifier,
            model.nowPlaying.title,
            model.nowPlaying.artistName,
            model.nowPlaying.albumTitle,
            model.nowPlaying.sourceName,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    var progressContentIdentity: String {
        if let queueSnapshot = model.queueState.snapshot,
           let currentItem = queueSnapshot.currentItem
        {
            let values: [String?] = [
                "queue",
                queueSnapshot.sourceURI,
                queueSnapshot.currentItemIndex.map { String($0) },
                currentItem.id,
                currentItem.title,
                currentItem.artistName,
                currentItem.albumTitle,
            ]

            return values
                .compactMap { $0?.sonoicNonEmptyTrimmed }
                .joined(separator: "|")
        }

        let values: [String?] = [
            model.nowPlaying.title,
            model.nowPlaying.artistName,
            model.nowPlaying.albumTitle,
            model.nowPlaying.sourceName,
        ]

        return values
            .compactMap { $0?.sonoicNonEmptyTrimmed }
            .joined(separator: "|")
    }

    func seek(to timeInterval: TimeInterval) async -> Bool {
        await model.seekManualSonosPlayback(to: timeInterval)
    }

    func handleVolumeEditingChanged(_ isEditing: Bool) {
        isAdjustingVolume = isEditing

        if !isEditing {
            commitVolumeImmediately()
        }
    }

    func scheduleVolumeCommit() {
        volumeCommitTask?.cancel()

        let targetLevel = Int(volumeLevel.rounded())
        volumeCommitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            Task { @MainActor in
                _ = await model.setManualSonosVolume(to: targetLevel)
            }
        }
    }

    func commitVolumeImmediately() {
        volumeCommitTask?.cancel()
        volumeCommitTask = nil

        let targetLevel = Int(volumeLevel.rounded())
        Task { @MainActor in
            _ = await model.setManualSonosVolume(to: targetLevel)
        }
    }

    func skipToPreviousTrack() async {
        _ = await model.skipToPreviousManualSonosTrack()
    }

    func togglePlayback() async {
        await model.toggleManualSonosPlayback()
    }

    func skipToNextTrack() async {
        _ = await model.skipToNextManualSonosTrack()
    }

    func toggleMute() {
        Task {
            await model.toggleManualSonosMute()
        }
    }

    func openRooms() {
        model.selectedTab = .rooms
        dismiss()
    }

    func openQueue() {
        model.selectedTab = .queue
        dismiss()
    }

    func openArtist(_ artistName: String) {
        Task { @MainActor in
            guard let item = await model.appleMusicArtistRouteItem(named: artistName) else {
                return
            }

            model.pendingSourceItemDetailRoute = item
            dismiss()
        }
    }
}
