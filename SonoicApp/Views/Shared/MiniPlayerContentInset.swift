import SwiftUI

enum MiniPlayerLayout {
    static let horizontalPadding: CGFloat = 12
    static let bottomSpacing: CGFloat = 55
    static let barHeight: CGFloat = 78
    static let contentBreathingRoom: CGFloat = 28
    static let contentInset: CGFloat = barHeight + bottomSpacing + contentBreathingRoom
}

private struct MiniPlayerContentInsetModifier: ViewModifier {
    @Environment(SonoicModel.self) private var model

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if model.hasResolvedSonosPlaybackTarget {
                Color.clear
                    .frame(height: MiniPlayerLayout.contentInset)
            }
        }
    }
}

extension View {
    func miniPlayerContentInset() -> some View {
        modifier(MiniPlayerContentInsetModifier())
    }
}
