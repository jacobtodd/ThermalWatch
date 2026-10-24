import SwiftUI

/// A fan that spins at a speed proportional to the real fans, and sits still when they're off.
struct FanView: View {
    let fans: [FanReading]

    private var averageRPM: Double { fans.isEmpty ? 0 : fans.map(\.rpm).reduce(0, +) / Double(fans.count) }
    private var maxRPM: Double { fans.map(\.max).max() ?? 0 }

    var body: some View {
        VStack(spacing: 4) {
            SpinningFan(period: FanAnimation.spinPeriod(rpm: averageRPM, max: maxRPM))
                .frame(width: 84, height: 84)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var caption: String {
        switch fans.count {
        case 0: "No fans"
        case 1: Formatting.rpm(fans[0].rpm)
        default: fans.map { "\(Int($0.rpm.rounded()))" }.joined(separator: " · ") + " rpm"
        }
    }
}

private struct SpinningFan: View {
    let period: Double?
    @State private var angle: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        // Integrate angle over time so speed changes are smooth rather than jumping.
        TimelineView(.animation(paused: period == nil)) { context in
            Image(systemName: "fan.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.cyan.gradient)
                .rotationEffect(.degrees(angle))
                .onChange(of: context.date) { _, now in
                    defer { lastTick = now }
                    guard let period, let last = lastTick else { return }
                    angle = (angle + now.timeIntervalSince(last) / period * 360).truncatingRemainder(dividingBy: 360)
                }
        }
        .onChange(of: period == nil) { lastTick = nil }
    }
}
