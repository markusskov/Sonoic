import Foundation

extension SonoicModel {
    func refreshAppleMusicAuthorizationState() {
        musicKitDiagnostics = .current
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()

        if !appleMusicAuthorizationState.allowsCatalogSearch {
            appleMusicRequestReadiness = .idle
        }
    }

    func requestAppleMusicAuthorization() async {
        guard appleMusicAuthorizationState.canRequestAuthorization else {
            refreshAppleMusicAuthorizationState()
            return
        }

        appleMusicAuthorizationState = SonoicAppleMusicAuthorizationState(status: .requesting)
        appleMusicAuthorizationState = await appleMusicCatalogSearchClient.requestAuthorizationState()

        if appleMusicAuthorizationState.allowsCatalogSearch {
            await refreshAppleMusicServiceDetails()
        }
    }

    func refreshAppleMusicServiceDetails() async {
        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicServiceDetails = .idle
            return
        }

        appleMusicServiceDetails.status = .loading

        do {
            appleMusicServiceDetails = try await appleMusicCatalogSearchClient.fetchServiceDetails()
            recordAppleMusicRequestSuccess()
        } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
            return
        } catch {
            appleMusicServiceDetails = .failed(
                appleMusicFailureDetail(from: error, endpointFamily: .serviceDetails)
            )
        }
    }

    func recordAppleMusicRequestSuccess() {
        appleMusicRequestReadiness = .ready(preserving: appleMusicRequestReadiness)
    }

    func appleMusicFailureDetail(
        from error: Error,
        endpointFamily: SonoicAppleMusicEndpointFamily
    ) -> String {
        let failure = SonoicAppleMusicCatalogSearchClient.appleMusicRequestFailure(
            from: error,
            endpointFamily: endpointFamily
        )
        appleMusicRequestReadiness = .failed(failure)
        return failure.displayDetail
    }
}
