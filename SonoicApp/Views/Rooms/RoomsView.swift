import SwiftUI

struct RoomsView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Rooms",
            systemImage: "speaker.wave.3.fill",
            message: "Local speaker discovery, grouping, and target selection will live here."
        )
        .navigationTitle("Rooms")
    }
}

#Preview {
    NavigationStack {
        RoomsView()
    }
}
