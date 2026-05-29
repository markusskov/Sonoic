import Testing
@testable import Sonoic

struct SonoicAppleMusicAuthorizationStateTests {
    @Test(arguments: [
        (SonoicAppleMusicAuthorizationState.Status.notDetermined, "Not Connected", nil),
        (.requesting, "Connecting", "Connecting..."),
        (.authorized, "Connected", nil),
        (.denied, "Denied", "Enable Apple Music in iOS Settings."),
        (.restricted, "Restricted", "This device does not allow Apple Music access."),
        (.unavailable, "Unavailable", "Apple Music authorization is not available right now.")
    ])
    func exposesSettingsPresentation(
        status: SonoicAppleMusicAuthorizationState.Status,
        expectedTitle: String,
        expectedSettingsDetail: String?
    ) {
        let state = SonoicAppleMusicAuthorizationState(status: status)

        #expect(state.title == expectedTitle)
        #expect(state.settingsDetail == expectedSettingsDetail)
    }
}
