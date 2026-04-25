import Foundation

extension SonoicModel {
    func refreshAppleMusicAuthorizationState() {
        musicKitDiagnostics = .current
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()
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
        } catch {
            appleMusicServiceDetails = .failed(error.localizedDescription)
        }
    }
}
