import SwiftUI

@main
struct SonoicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = SonoicModel()

    var body: some Scene {
        let model = model

        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    model.configurePlusIfPossible()
                }
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    model.handleScenePhase(newPhase)
                }
        }
        .backgroundTask(.appRefresh(SonoicBackgroundRefresh.taskIdentifier)) {
            await model.handleBackgroundPlayerRefresh()
        }
    }
}
