import SwiftUI

struct RoomsGroupRow: View {
    let group: SonosDiscoveredGroup
    let isSelecting: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoomSurfaceIconView(
                    systemImage: "square.stack.3d.up.fill",
                    size: 44,
                    cornerRadius: 14,
                    font: .body.weight(.semibold)
                )

                VStack(alignment: .leading, spacing: 4) {
                    titleRow

                    Text(group.detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(group.memberNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                trailingState
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
        .padding(.vertical, 12)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(group.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isActive {
                RoomsActiveBadge()
            }
        }
    }

    private var trailingState: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(group.summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)

            if isSelecting {
                ProgressView()
                    .controlSize(.small)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "circle")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct RoomsListRow: View {
    let item: SonosRoomListItem
    let isSelecting: Bool
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isSelecting)
            } else {
                rowContent
            }
        }
        .padding(.vertical, 12)
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: item.kind.systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                titleRow

                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            trailingState
        }
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(item.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if item.isActive {
                RoomsActiveBadge()
            }
        }
    }

    private var trailingState: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(item.source.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if isSelecting {
                ProgressView()
                    .controlSize(.small)
            } else if item.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if action != nil {
                Image(systemName: "circle")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RoomsActiveBadge: View {
    var body: some View {
        Text("Active")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}
