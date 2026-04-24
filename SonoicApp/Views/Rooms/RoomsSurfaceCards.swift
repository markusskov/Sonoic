import SwiftUI

struct RoomsCurrentRoomCard: View {
    let roomName: String
    let roomSummary: String
    let setupProducts: [SonosActiveTarget.SetupProduct]
    let topologyStatus: SonosRoomDataStatus
    let isRefreshing: Bool
    let lastUpdatedAt: Date?
    let refreshAction: () async -> Void

    private var refreshStatusText: String {
        if isRefreshing {
            return "Refreshing room details..."
        }

        switch topologyStatus {
        case .idle, .loading:
            return "Loading bonded setup..."
        case .failed:
            return "Setup details unavailable right now."
        case .resolved:
            break
        }

        if let lastUpdatedAt {
            return "Updated \(lastUpdatedAt.formatted(.dateTime.hour().minute()))"
        }

        return "Pull down or tap refresh to reload this room."
    }

    private var refreshStatusDetail: String? {
        topologyStatus.failureDetail
    }

    var body: some View {
        RoomSurfaceCard(isInteractive: true) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(roomName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(roomSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }

            if !setupProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Setup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(setupProducts) { product in
                            HStack(spacing: 12) {
                                RoomProductIconView(product: product)

                                Text(product.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(topologyStatus.failureDetail == nil ? Color.secondary : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(refreshStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let refreshStatusDetail {
                        Text(refreshStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        await refreshAction()
                    }
                } label: {
                    Text(isRefreshing ? "Refreshing" : "Refresh")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
            }
        }
    }
}

struct RoomsDiscoveryStatusCard: View {
    let status: SonosRoomDiscoveryStatus
    let roomCount: Int
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let refreshAction: () async -> Void

    private var roomCountText: String? {
        guard roomCount > 0 else {
            return nil
        }

        if roomCount == 1 {
            return "1 room is available in Sonoic right now."
        }

        return "\(roomCount) rooms are available in Sonoic right now."
    }

    private var tint: Color {
        switch status {
        case .scanning, .resolving:
            .secondary
        case .ready:
            .green
        case .failed:
            .orange
        }
    }

    private var detailText: String {
        if let lastUpdatedAt,
           !isRefreshing
        {
            return "\(status.detail) Last updated \(lastUpdatedAt.formatted(.dateTime.hour().minute()))."
        }

        return status.detail
    }

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 24, height: 24)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Image(systemName: status.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 52, height: 52)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let roomCountText {
                        Text(roomCountText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task {
                    await refreshAction()
                }
            } label: {
                Label(isRefreshing ? "Refreshing" : "Refresh Discovery", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
        }
    }
}

struct RoomsHomeTheaterCard: View {
    let roomName: String
    let sourceName: String
    let isTVAudioActive: Bool
    let hasSubwoofer: Bool
    let hasSurrounds: Bool
    let settings: SonosHomeTheaterSettings?
    let isRefreshing: Bool

    var body: some View {
        RoomSurfaceCard(isInteractive: true) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "theatermasks.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Home Theater")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 6)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }

            HStack(spacing: 8) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }

    private var summaryText: String {
        if isTVAudioActive {
            return "\(roomName) is on TV Audio."
        }

        if let settings {
            return "Bass \(signedValue(settings.bass)), treble \(signedValue(settings.treble)) while \(sourceName) is active."
        }

        return "EQ, sub, speech, night sound, and TV checks for \(roomName)."
    }

    private var badges: [String] {
        var values = ["EQ"]

        if hasSubwoofer || settings?.supportsSubLevel == true {
            values.append("Sub")
        }

        if hasSurrounds {
            values.append("Surrounds")
        }

        if settings?.supportsSpeechEnhancement == true {
            values.append("Speech")
        }

        if settings?.supportsNightSound == true {
            values.append("Night")
        }

        if isTVAudioActive {
            values.append("TV")
        }

        return values
    }

    private func signedValue(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

struct RoomsGroupListCard: View {
    let groups: [SonosDiscoveredGroup]
    let selectingTargetID: String?
    let activeGroupID: String?
    let selectGroup: (SonosDiscoveredGroup) async -> Void

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    RoomsGroupRow(
                        group: group,
                        isSelecting: selectingTargetID == group.id,
                        isActive: activeGroupID == group.id,
                        action: {
                            Task {
                                await selectGroup(group)
                            }
                        }
                    )

                    if index < groups.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}

struct RoomsListCard: View {
    let items: [SonosRoomListItem]
    let selectingItemID: String?
    let selectItem: (SonosRoomListItem) async -> Void

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    RoomsListRow(
                        item: item,
                        isSelecting: selectingItemID == item.id,
                        action: item.source == .discovered ? {
                            Task {
                                await selectItem(item)
                            }
                        } : nil
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}

private struct RoomsGroupRow: View {
    let group: SonosDiscoveredGroup
    let isSelecting: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isActive {
                            Text("Active")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
        .padding(.vertical, 12)
    }
}

private struct RoomsListRow: View {
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
            Image(systemName: item.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if item.isActive {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }

                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

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
        .contentShape(Rectangle())
    }
}
