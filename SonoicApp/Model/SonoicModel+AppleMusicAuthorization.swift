import Foundation

extension SonoicModel {
    func refreshAppleMusicAuthorizationState() {
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()
    }

    func requestAppleMusicAuthorization() async {
        guard appleMusicAuthorizationState.canRequestAuthorization else {
            refreshAppleMusicAuthorizationState()
            return
        }

        appleMusicAuthorizationState = SonoicAppleMusicAuthorizationState(status: .requesting)
        appleMusicAuthorizationState = await appleMusicCatalogSearchClient.requestAuthorizationState()
    }
}
