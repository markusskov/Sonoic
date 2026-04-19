import SwiftUI

struct QueueSnapshotList: View {
    let snapshot: SonosQueueSnapshot
    let nowPlaying: SonosNowPlayingSnapshot
    let playQueueItem: (Int) async -> Void
    let refreshAction: () async -> Void

    private var currentTitle: String {
        snapshot.currentItem?.title ?? nowPlaying.title
    }

    private var currentSubtitle: String {
        if let subtitle = snapshot.currentItem?.subtitle {
            return subtitle
        }

        return nowPlaying.subtitle ?? nowPlaying.sourceName
    }

    private var queueSummary: String {
        if let currentPositionText = snapshot.currentPositionText {
            return "\(currentPositionText) • \(snapshot.itemCountText)"
        }

        return snapshot.itemCountText
    }

    var body: some View {
        List {
            Section("Current Item") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(currentSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(queueSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(snapshot.itemCountText) {
                ForEach(Array(snapshot.items.enumerated()), id: \.element.id) { index, item in
                    QueueItemRow(
                        position: index + 1,
                        item: item,
                        isCurrent: snapshot.currentItemIndex == index,
                        playAction: playQueueItem
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshAction()
        }
    }
}

private struct QueueItemRow: View {
    let position: Int
    let item: SonosQueueItem
    let isCurrent: Bool
    let playAction: (Int) async -> Void

    var body: some View {
        Button {
            Task {
                await playAction(position)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(position)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.body.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if isCurrent {
                            Text("Playing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let durationText = item.durationText {
                    Text(durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
