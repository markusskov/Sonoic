import SwiftUI

struct RoomResolutionStateCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isLoading: Bool
    let actionTitle: String?
    let action: (() async -> Void)?

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 24, height: 24)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoomSurfaceIconView(systemImage: systemImage, tint: tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let actionTitle,
               let action
            {
                Button {
                    Task {
                        await action()
                    }
                } label: {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
    }
}
