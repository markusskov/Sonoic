import SwiftUI

struct SettingsStatusRow: View {
    let title: String
    let statusTitle: String
    let detail: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(statusTitle)
                    .font(.subheadline.weight(.medium))

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SettingsDiscoveredPlayerRow: View {
    let player: SonosDiscoveredPlayer
    let isSelected: Bool
    let isSelecting: Bool
    let selectPlayer: () async -> Void

    var body: some View {
        Button(action: selectTapped) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(player.detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                selectionState
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
    }

    @ViewBuilder
    private var selectionState: some View {
        if isSelecting {
            ProgressView()
                .controlSize(.small)
        } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle")
                .font(.headline)
                .foregroundStyle(.tertiary)
        }
    }

    private func selectTapped() {
        Task {
            await selectPlayer()
        }
    }
}

struct SettingsDiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }
}
