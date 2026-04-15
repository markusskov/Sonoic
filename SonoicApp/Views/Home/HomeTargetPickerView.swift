import SwiftUI

struct HomeTargetPickerView: View {
    let activeTarget: SonosActiveTarget
    let availableTargets: [SonosActiveTarget]
    let selectTarget: (SonosActiveTarget) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(availableTargets) { target in
                Button {
                    selectTarget(target)
                    dismiss()
                } label: {
                    HomeTargetPickerRow(
                        target: target,
                        isSelected: target.id == activeTarget.id
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose Target")
        }
    }
}

private struct HomeTargetPickerRow: View {
    let target: SonosActiveTarget
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: target.kind.systemImage)
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(target.name)
                        .foregroundStyle(.primary)

                    if isSelected {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Text(target.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if target.kind == .group {
                    Text(target.membersDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeTargetPickerView(
        activeTarget: SonosActiveTarget(
            id: "living-room",
            name: "Living Room",
            householdName: "Markus's Sonos",
            kind: .room,
            memberNames: ["Living Room"]
        ),
        availableTargets: [
            SonosActiveTarget(
                id: "living-room",
                name: "Living Room",
                householdName: "Markus's Sonos",
                kind: .room,
                memberNames: ["Living Room"]
            ),
            SonosActiveTarget(
                id: "everywhere",
                name: "Everywhere",
                householdName: "Markus's Sonos",
                kind: .group,
                memberNames: ["Living Room", "Kitchen", "Bedroom"]
            )
        ],
        selectTarget: { _ in }
    )
}
