import SwiftUI

struct HomeServicesSection: View {
    let summaries: [SonoicHomeSourceSummary]

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        HomeServiceChip(summary: summary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeServiceChip: View {
    let summary: SonoicHomeSourceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: summary.service.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    titleRow

                    Text(summary.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(summary.service.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if summary.isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
