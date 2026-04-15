import SwiftUI

struct HomeTargetCard: View {
    let activeTarget: SonosActiveTarget
    let connectionState: SonosConnectionState
    let sourceName: String
    let showTargetPicker: () -> Void

    private var connectionTint: Color {
        switch connectionState {
        case .ready:
            .green
        case .connecting:
            .orange
        case .stale, .unavailable:
            .red
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activeTarget.name)
                            .font(.title3.weight(.semibold))

                        Text(activeTarget.summary)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button("Change", systemImage: "arrow.right.circle", action: showTargetPicker)
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Label(activeTarget.kind.title, systemImage: activeTarget.kind.systemImage)
                    Label(connectionState.title, systemImage: connectionState.systemImage)
                        .foregroundStyle(connectionTint)
                }
                .font(.footnote.weight(.medium))

                LabeledContent("Household", value: activeTarget.householdName)
                LabeledContent("Source", value: sourceName)

                if activeTarget.kind == .group {
                    LabeledContent("Rooms", value: activeTarget.membersDescription)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionState.controlPath.title)
                        .font(.subheadline.weight(.semibold))

                    Text(connectionState.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Active Target", systemImage: "speaker.wave.3.fill")
        }
    }
}

#Preview {
    HomeTargetCard(
        activeTarget: SonosActiveTarget(
            id: "living-room",
            name: "Living Room",
            householdName: "Markus's Sonos",
            kind: .room,
            memberNames: ["Living Room"]
        ),
        connectionState: .ready(.localNetwork),
        sourceName: "Apple Music",
        showTargetPicker: {}
    )
    .padding()
}
