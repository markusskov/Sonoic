import SwiftUI

enum MiniPlayerLayout {
    static let bottomSpacing: CGFloat = 55
    static let contentInset: CGFloat = 65
}

private struct MiniPlayerContentInsetModifier: ViewModifier {
    @Environment(SonoicModel.self) private var model

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if model.hasManualSonosHost {
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
