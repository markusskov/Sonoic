import SwiftUI

struct HomeTheaterSliderRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Int>
    let valueText: String
    let isEnabled: Bool
    let editingChanged: (Bool) -> Void

    private var doubleRange: ClosedRange<Double> {
        Double(range.lowerBound) ... Double(range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 12)

                Text(valueText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("\(range.lowerBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .leading)

                Slider(value: $value, in: doubleRange, step: 1, onEditingChanged: editingChanged)
                    .disabled(!isEnabled)

                Text("+\(range.upperBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}

struct HomeTheaterDialogLevelPicker: View {
    @Binding var level: Int
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Speech Level", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Speech Level", selection: $level) {
                Text("Low").tag(1)
                Text("Med").tag(2)
                Text("High").tag(3)
                Text("Max").tag(4)
            }
            .pickerStyle(.segmented)
            .disabled(!isEnabled)
        }
        .padding(.top, 4)
    }
}

struct HomeTheaterUnavailableRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
}

func homeTheaterSignedValueText(_ value: Int) -> String {
    value > 0 ? "+\(value)" : "\(value)"
}
