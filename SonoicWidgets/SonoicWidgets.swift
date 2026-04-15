import WidgetKit
import SwiftUI

struct SonoicWidgetEntry: TimelineEntry {
    let date: Date
    let externalControlState: SonoicExternalControlState
}

struct SonoicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SonoicWidgetEntry {
        SonoicWidgetEntry(date: .now, externalControlState: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SonoicWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SonoicWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let fallbackRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        let nextRefresh: Date

        if entry.externalControlState.staleDate > entry.date {
            nextRefresh = min(entry.externalControlState.staleDate, fallbackRefresh)
        } else {
            nextRefresh = fallbackRefresh
        }

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> SonoicWidgetEntry {
        SonoicWidgetEntry(date: .now, externalControlState: SonoicExternalStateLoader.load())
    }
}

struct SonoicWidgetsEntryView: View {
    let entry: SonoicWidgetEntry

    private var availabilityTint: Color {
        if freshness.isStale, entry.externalControlState.availability == .ready {
            return .orange
        }

        switch entry.externalControlState.availability {
        case .ready:
            return .green
        case .connecting:
            return .orange
        case .stale, .unavailable:
            return .red
        }
    }

    private var freshness: SonoicExternalControlState.Freshness {
        entry.externalControlState.freshness(relativeTo: entry.date)
    }

    private var freshnessTint: Color {
        freshness.isStale ? .orange : .secondary
    }

    var body: some View {
        let state = entry.externalControlState

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Label(state.activeTarget.name, systemImage: state.activeTarget.kind.systemImage)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: state.availability.systemImage)
                    .foregroundStyle(availabilityTint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.nowPlaying.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = state.nowPlaying.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Label(state.playbackState.title, systemImage: state.playbackState.controlSystemImage)
                Spacer(minLength: 0)
                Label(state.volume.labelText, systemImage: state.volume.systemImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(state.nowPlaying.sourceName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Label(freshness.title, systemImage: freshness.systemImage)
                Spacer(minLength: 0)
                Text(state.updatedAt, style: .relative)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(freshnessTint)
        }
    }
}

struct SonoicWidgets: Widget {
    let kind: String = "SonoicWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SonoicWidgetProvider()) { entry in
            SonoicWidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows the selected Sonos target and the current outside-app playback snapshot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    SonoicWidgets()
} timeline: {
    SonoicWidgetEntry(date: .now, externalControlState: .preview)
}

#Preview(as: .systemMedium) {
    SonoicWidgets()
} timeline: {
    SonoicWidgetEntry(date: .now, externalControlState: .preview)
}
