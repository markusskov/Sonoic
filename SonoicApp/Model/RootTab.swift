import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home
    case rooms
    case queue
    case settings

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .home:
            "Home"
        case .rooms:
            "Rooms"
        case .queue:
            "Queue"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "dot.radiowaves.left.and.right"
        case .rooms:
            "speaker.wave.3.fill"
        case .queue:
            "list.triangle"
        case .settings:
            "slider.horizontal.3"
        }
    }
}
