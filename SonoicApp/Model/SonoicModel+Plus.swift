import Foundation

extension SonoicModel {
    var hasPlus: Bool {
        plusState.isUnlocked
    }

    func canUsePlusFeature(_ feature: SonoicPlusFeature) -> Bool {
        hasPlus
    }

    func configurePlusIfPossible() {
        plusState = plusController.configureIfPossible()

        guard plusState.status != .notConfigured else {
            return
        }

        Task {
            await refreshPlusState()
        }
    }

    func refreshPlusState() async {
        guard plusState.status != .notConfigured else {
            plusState = plusController.configureIfPossible()
            if plusState.status == .notConfigured {
                return
            }

            return await refreshPlusState()
        }

        plusState = SonoicPlusState(
            status: .refreshing,
            entitlementIdentifier: plusState.entitlementIdentifier,
            updatedAt: plusState.updatedAt
        )
        plusState = await plusController.refreshState()
    }

    func restorePlusPurchases() async {
        plusState = SonoicPlusState(
            status: .refreshing,
            entitlementIdentifier: plusState.entitlementIdentifier,
            updatedAt: plusState.updatedAt
        )
        plusState = await plusController.restorePurchases()
    }
}
