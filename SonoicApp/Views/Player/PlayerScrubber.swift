import SwiftUI

struct PlayerScrubber: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    var step: Double?
    var isEnabled = true
    var showsThumb = true
    var accessibilityLabel = "Scrubber"
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let thumbCenterX = progressFraction * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.16 : 0.08))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.88 : 0.28))
                    .frame(width: max(thumbCenterX, trackHeight), height: trackHeight)

                if showsThumb {
                    Circle()
                        .fill(.white.opacity(isEnabled ? 0.96 : 0.45))
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                        .overlay {
                        Circle()
                            .stroke(.white.opacity(0.36), lineWidth: 1)
                        }
                        .offset(x: min(max(thumbCenterX - thumbDiameter / 2, 0), width - thumbDiameter))
                }
            }
            .frame(height: thumbDiameter)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .opacity(isEnabled ? 1 : 0.6)
        }
        .frame(height: thumbDiameter)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            adjustValue(direction: direction)
        }
    }

    private var progressFraction: Double {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else {
            return 0
        }

        return min(max((value - bounds.lowerBound) / span, 0), 1)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard isEnabled else {
                    return
                }

                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }

                updateValue(for: gesture.location.x, width: width)
            }
            .onEnded { gesture in
                guard isEnabled else {
                    return
                }

                updateValue(for: gesture.location.x, width: width)
                isDragging = false
                onEditingChanged(false)
            }
    }

    private func updateValue(for locationX: CGFloat, width: CGFloat) {
        let clampedX = min(max(locationX, 0), width)
        let rawValue = bounds.lowerBound + (Double(clampedX / width) * (bounds.upperBound - bounds.lowerBound))
        value = snapped(rawValue)
    }

    private func snapped(_ rawValue: Double) -> Double {
        guard let step, step > 0 else {
            return min(max(rawValue, bounds.lowerBound), bounds.upperBound)
        }

        let steppedValue = (rawValue / step).rounded() * step
        return min(max(steppedValue, bounds.lowerBound), bounds.upperBound)
    }

    private func adjustValue(direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else {
            return
        }

        let adjustment = step ?? max((bounds.upperBound - bounds.lowerBound) / 20, 1)
        switch direction {
        case .increment:
            value = snapped(value + adjustment)
        case .decrement:
            value = snapped(value - adjustment)
        @unknown default:
            break
        }
    }
}
