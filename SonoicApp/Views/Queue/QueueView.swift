import SwiftUI

struct QueueView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Queue",
            systemImage: "list.triangle",
            message: "Queue inspection, play next, reordering, and save-to-playlist actions will live here."
        )
        .navigationTitle("Queue")
    }
}

#Preview {
    NavigationStack {
        QueueView()
    }
}
