import Foundation

enum SonoicPlusFeature: String, CaseIterable, Identifiable {
    case alternateIcons
    case themes
    case homeCustomization
    case extraWidgets
    case roomPresets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alternateIcons:
            "Alternate Icons"
        case .themes:
            "Themes"
        case .homeCustomization:
            "Custom Home"
        case .extraWidgets:
            "Extra Widgets"
        case .roomPresets:
            "Room Presets"
        }
    }

    var detail: String {
        switch self {
        case .alternateIcons:
            "Classic, dark, glass, and seasonal looks."
        case .themes:
            "Accent styles and OLED-friendly surfaces."
        case .homeCustomization:
            "Reorder Home and pin the rooms you use most."
        case .extraWidgets:
            "More widget layouts, colors, and room variants."
        case .roomPresets:
            "Save volume, EQ, speech, and night sound setups."
        }
    }

    var systemImage: String {
        switch self {
        case .alternateIcons:
            "app.badge"
        case .themes:
            "paintpalette"
        case .homeCustomization:
            "square.grid.2x2"
        case .extraWidgets:
            "rectangle.stack"
        case .roomPresets:
            "slider.horizontal.3"
        }
    }
}
