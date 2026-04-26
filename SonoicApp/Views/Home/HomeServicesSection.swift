import SwiftUI

struct HomeServicesSection: View {
    let sources: [SonoicSource]

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(sources) { source in
                        NavigationLink {
                            SourceDetailView(source: source)
                        } label: {
                            HomeServiceChip(source: source)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeServiceChip: View {
    let source: SonoicSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: source.service.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    titleRow
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 168, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(source.service.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if source.isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
