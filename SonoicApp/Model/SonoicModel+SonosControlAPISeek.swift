import Foundation

extension SonoicModel {
    private static let sonosControlAPISeekPollDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollAttempts = 5
    private static let sonosControlAPISeekSlotWaitDelay: Duration = .milliseconds(100)
    private static let sonosControlAPISeekSlotWaitAttempts = 36

    private struct SonosControlAPISeekItemIDCandidate {
        var label: String
        var itemID: String?
    }

    func seekSonosControlAPIPlaybackIfAvailable(to timeInterval: TimeInterval) async -> Bool {
        sonoicPlaybackDebugLog("cloudseek entry target=\(timeInterval)")
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
            sonoicPlaybackDebugLog(
                "cloudseek unavailable canSend=false auth=\(String(describing: sonosControlAPIState.authorizationStatus)) mode=\(sonosControlAPIState.settings.mode.rawValue) target=\(timeInterval)"
            )
            return false
        }

        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudseek") else {
            sonoicPlaybackDebugLog(
                "cloudseek unavailable contextMissing auth=\(String(describing: sonosControlAPIState.authorizationStatus)) mode=\(sonosControlAPIState.settings.mode.rawValue) selectedGroup=\(sonoicPlaybackDebugID(sonosControlAPIState.settings.selectedGroupID)) cloudState=\(sonoicPlaybackDebugCloudStatus(sonosControlAPICloudState.status)) target=\(timeInterval)"
            )
            return false
        }

        guard await waitForSonosControlAPISeekTransportSlot(target: timeInterval) else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousObservedAt = nowPlayingObservedAt
        let boundedElapsedTime = markLocalSeek(to: timeInterval)
        beginManualSeekConfirmation(to: boundedElapsedTime)
        sonoicPlaybackDebugLog(
            "cloudseek start target=\(boundedElapsedTime) group=\(sonoicPlaybackDebugID(context.groupID))"
        )
        recordSeekDiagnostics(
            status: .pending,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: nil,
            errorDetail: nil
        )

        var observedElapsedTime: TimeInterval?
        var observedPlaybackState: SonosControlAPIPlaybackState?
        var didConfirmSeek = false
        var pollingErrorDetail: String?
        var requestedAt = Date()
        let didSeek = await performSonosControlAPITransportCommand(
            description: "Cloud seek",
            refreshQueueAfterSuccess: false,
            syncDelay: .milliseconds(100)
        ) {
            let status = try await sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            let metadataStatus = try? await sonosControlAPIClient.playbackMetadata(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            if status.availablePlaybackActions?.canSeek == false {
                throw SonosControlAPISeekFailure.unsupported
            }
            if metadataStatus?.currentItem?.policies?.canSeek == false {
                throw SonosControlAPISeekFailure.unsupported
            }
            sonoicPlaybackDebugLog(
                "cloudseek status canSeek=\(String(describing: status.availablePlaybackActions?.canSeek)) itemID=\(sonoicPlaybackDebugID(status.itemId)) metadataItemID=\(sonoicPlaybackDebugID(metadataStatus?.currentItem?.id)) positionMillis=\(String(describing: status.positionMillis))"
            )
            let didRestoreCloudQueueContext = restoreSonosControlAPICloudQueueContextIfNeeded(
                groupID: context.groupID,
                queueVersion: status.queueVersion
            )
            sonoicPlaybackDebugLog(
                "cloudseek cloudQueueContext restored=\(didRestoreCloudQueueContext) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueRuntimeState.sessionID)) itemCount=\(sonosControlAPICloudQueueRuntimeState.itemCount) rawItemID=\(sonoicPlaybackDebugID(status.itemId)) queueVersion=\(sonoicPlaybackDebugID(status.queueVersion))"
            )
            let itemIDCandidates = sonosControlAPISeekItemIDCandidates(from: status)
            sonoicPlaybackDebugLog(
                "cloudseek seekPayload candidates=\(itemIDCandidates.map { "\($0.label):\($0.itemID.map(sonoicPlaybackDebugID) ?? "omitted")" }.joined(separator: ",")) rawItemID=\(sonoicPlaybackDebugID(status.itemId))"
            )
            requestedAt = Date()
            let targetMillis = Int((boundedElapsedTime * 1_000).rounded())
            if let sessionSeekTarget = sonosControlAPICloudQueueSeekTarget(
                from: status,
                metadataStatus: metadataStatus
            ) {
                sonoicPlaybackDebugLog(
                    "cloudseek sessionSeek itemID=\(sonoicPlaybackDebugID(sessionSeekTarget.itemID)) session=\(sonoicPlaybackDebugID(sessionSeekTarget.sessionID)) targetMillis=\(targetMillis)"
                )
                try await sonosControlAPIClient.seekPlaybackSession(
                    sessionID: sessionSeekTarget.sessionID,
                    itemID: sessionSeekTarget.itemID,
                    positionMillis: targetMillis,
                    accessToken: context.accessToken
                )
                try await confirmSonosControlAPISeek(
                    groupID: context.groupID,
                    accessToken: context.accessToken,
                    targetElapsedTime: boundedElapsedTime,
                    requestedAt: requestedAt,
                    observedElapsedTime: &observedElapsedTime,
                    observedPlaybackState: &observedPlaybackState,
                    didConfirmSeek: &didConfirmSeek,
                    pollingErrorDetail: &pollingErrorDetail
                )
                return
            }

            if sonosControlAPICloudQueueRuntimeState.hasSessionContext {
                sonoicPlaybackDebugLog(
                    "cloudseek sessionContextUnmapped sessionSeekRequired rawItemID=\(sonoicPlaybackDebugID(status.itemId)) metadataItemID=\(sonoicPlaybackDebugID(metadataStatus?.currentItem?.id)) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueRuntimeState.sessionID)) itemCount=\(sonosControlAPICloudQueueRuntimeState.itemCount)"
                )
                throw SonosControlAPISeekFailure.sessionItemUnavailable
            }

            var lastSeekError: Error?
            for candidate in itemIDCandidates {
                sonoicPlaybackDebugLog(
                    "cloudseek attemptAbsolute candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                )
                do {
                    try await sonosControlAPIClient.seek(
                        groupID: context.groupID,
                        positionMillis: targetMillis,
                        itemID: candidate.itemID,
                        accessToken: context.accessToken
                    )
                    lastSeekError = nil
                    break
                } catch {
                    lastSeekError = error
                    if sonosControlAPIError(error, matchesStatus: 499, detailContains: "ERROR_DISALLOWED_BY_POLICY") {
                        sonoicPlaybackDebugLog(
                            "cloudseek disallowedByPolicy currentMillis=\(String(describing: status.positionMillis)) targetMillis=\(targetMillis) candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                        )
                        throw error
                    }

                    if sonosControlAPIError(error, matchesStatus: 400, detailContains: "ERROR_INVALID_OBJECT_ID") {
                        sonoicPlaybackDebugLog(
                            "cloudseek invalidObject candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                        )
                        continue
                    }

                    throw error
                }
            }
            if let lastSeekError {
                throw lastSeekError
            }
            try await confirmSonosControlAPISeek(
                groupID: context.groupID,
                accessToken: context.accessToken,
                targetElapsedTime: boundedElapsedTime,
                requestedAt: requestedAt,
                observedElapsedTime: &observedElapsedTime,
                observedPlaybackState: &observedPlaybackState,
                didConfirmSeek: &didConfirmSeek,
                pollingErrorDetail: &pollingErrorDetail
            )
        }

        if didSeek {
            if didConfirmSeek {
                clearManualSeekConfirmation()
                sonoicPlaybackDebugLog(
                    "cloudseek result=true confirmed=true target=\(boundedElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState))"
                )
                recordSeekDiagnostics(
                    status: .succeeded,
                    host: "Sonos Control API",
                    target: boundedElapsedTime,
                    observed: observedElapsedTime,
                    errorDetail: nil
                )
                return true
            }
            sonoicPlaybackDebugLog(
                "cloudseek result=true accepted=true confirmed=false target=\(boundedElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState))"
            )
            recordSeekDiagnostics(
                status: .succeeded,
                host: "Sonos Control API",
                target: boundedElapsedTime,
                observed: observedElapsedTime,
                errorDetail: pollingErrorDetail.map {
                    "Cloud accepted; status polling lagged: \($0)"
                } ?? "Cloud accepted; waiting for Sonos to report the requested position."
            )
            return true
        }

        clearManualSeekConfirmation()
        nowPlaying = previousNowPlaying
        nowPlayingObservedAt = previousObservedAt
        persistSharedExternalControlState()
        sonoicPlaybackDebugLog(
            "cloudseek result=false target=\(boundedElapsedTime) error='\(sonosControlAPIState.lastErrorDetail ?? "")'"
        )
        recordSeekDiagnostics(
            status: .failed,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: observedElapsedTime,
            errorDetail: sonosControlAPIState.lastErrorDetail
        )
        return false
    }

    private func confirmSonosControlAPISeek(
        groupID: String,
        accessToken: String,
        targetElapsedTime: TimeInterval,
        requestedAt: Date,
        observedElapsedTime: inout TimeInterval?,
        observedPlaybackState: inout SonosControlAPIPlaybackState?,
        didConfirmSeek: inout Bool,
        pollingErrorDetail: inout String?
    ) async throws {
        for attempt in 1 ... Self.sonosControlAPISeekPollAttempts {
            try await Task.sleep(for: Self.sonosControlAPISeekPollDelay)
            let observedStatus: SonosControlAPIPlaybackStatus
            do {
                observedStatus = try await sonosControlAPIClient.playbackStatus(
                    groupID: groupID,
                    accessToken: accessToken
                )
            } catch {
                pollingErrorDetail = error.localizedDescription
                sonoicPlaybackDebugLog(
                    "cloudseek pollFailed attempt=\(attempt) target=\(targetElapsedTime) error='\(error.localizedDescription)'"
                )
                return
            }
            observedPlaybackState = observedStatus.playbackState
            observedElapsedTime = observedStatus.positionMillis.map { TimeInterval($0) / 1_000 }
            sonoicPlaybackDebugLog(
                "cloudseek poll attempt=\(attempt) target=\(targetElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState)) itemID=\(sonoicPlaybackDebugID(observedStatus.itemId))"
            )
            if SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: targetElapsedTime,
                observedElapsedTime: observedElapsedTime,
                requestedAt: requestedAt,
                observedAt: .now,
                playbackState: observedPlaybackState
            ) {
                didConfirmSeek = true
                return
            }
        }
    }

    private func waitForSonosControlAPISeekTransportSlot(target: TimeInterval) async -> Bool {
        guard isManualTransportCommandInFlight else {
            return true
        }

        sonoicPlaybackDebugLog("cloudseek waiting transportInFlight=true target=\(target)")
        for attempt in 1 ... Self.sonosControlAPISeekSlotWaitAttempts {
            try? await Task.sleep(for: Self.sonosControlAPISeekSlotWaitDelay)
            if !isManualTransportCommandInFlight {
                sonoicPlaybackDebugLog("cloudseek waitComplete attempt=\(attempt) target=\(target)")
                return true
            }
        }

        sonoicPlaybackDebugLog("cloudseek blocked transportInFlight=true target=\(target)")
        return false
    }

    private func sonosControlAPISeekItemIDCandidates(
        from status: SonosControlAPIPlaybackStatus
    ) -> [SonosControlAPISeekItemIDCandidate] {
        guard let statusItemID = status.itemId?.sonoicNonEmptyTrimmed else {
            return [SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)]
        }

        guard Int(statusItemID) == nil else {
            return [SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)]
        }

        return [
            SonosControlAPISeekItemIDCandidate(label: "status", itemID: statusItemID),
            SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)
        ]
    }

    private func sonosControlAPICloudQueueSeekTarget(
        from status: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus?
    ) -> (sessionID: String, itemID: String, track: SonosControlAPITrack?)? {
        let currentIndex = sonosControlAPICloudQueueCurrentIndex(
            from: status,
            metadataStatus: metadataStatus
        )
        return sonosControlAPICloudQueueRuntimeState
            .playbackTarget(currentIndex: currentIndex)
            .map { ($0.sessionID, $0.itemID, $0.track) }
    }

    private func sonosControlAPICloudQueueCurrentIndex(
        from status: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus?
    ) -> Int? {
        sonosControlAPICloudQueueRuntimeState.currentIndex(
            playbackStatus: status,
            metadataStatus: metadataStatus,
            queueSnapshotCurrentItemIndex: queueState.snapshot?.currentItemIndex,
            manualPlaybackContextPayload: manualPlaybackContextPayload,
            manualQueueContextPayloads: manualQueueContextPayloads
        )
    }

    private func sonosControlAPIError(
        _ error: Error,
        matchesStatus statusCode: Int,
        detailContains detailNeedle: String
    ) -> Bool {
        guard case let SonosControlAPITransport.TransportError.httpStatus(status, detail) = error else {
            return false
        }

        guard status == statusCode else {
            return false
        }

        return detail?.localizedCaseInsensitiveContains(detailNeedle) == true
    }
}

private enum SonosControlAPISeekFailure: LocalizedError {
    case unsupported
    case sessionItemUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Sonos reported that the current item cannot seek."
        case .sessionItemUnavailable:
            "Sonoic could not match the current Cloud Queue item for seeking."
        }
    }
}
