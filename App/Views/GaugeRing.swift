import SwiftUI

/// A ring that fills to `fraction` (0...1) and animates between values.
struct GaugeRing: View {
    let fraction: Double?
    let label: String
    let caption: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction ?? 0)))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: fraction)
                Text(label)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: label)
            }
            .frame(width: 84, height: 84)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
