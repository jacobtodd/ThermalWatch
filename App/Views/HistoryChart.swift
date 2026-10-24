import Charts
import SwiftUI

/// Last 10 minutes of temperature, load and fan speed on one 0–100 scale.
struct HistoryChart: View {
    static let height: CGFloat = 110
    let history: [Snapshot]

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let value: Double
    }

    private var points: [Point] {
        history.flatMap { s -> [Point] in
            var out: [Point] = []
            if let t = s.temperature { out.append(.init(date: s.date, series: "Temp", value: t.average)) }
            if let l = s.load { out.append(.init(date: s.date, series: "Load", value: l * 100)) }
            if !s.fans.isEmpty, let max = s.fans.map(\.max).max(), max > 0 {
                let avg = s.fans.map(\.rpm).reduce(0, +) / Double(s.fans.count)
                out.append(.init(date: s.date, series: "Fan", value: avg / max * 100))
            }
            return out
        }
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                .foregroundStyle(by: .value("Series", p.series))
                .lineStyle(StrokeStyle(lineWidth: p.series == "Temp" ? 2 : 1.5, dash: p.series == "Fan" ? [3, 3] : []))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(["Temp": Color.orange, "Load": Color.green, "Fan": Color.cyan])
        .chartYScale(domain: 0...100)
        .chartYAxis { AxisMarks(values: [0, 50, 100]) }
        .chartXAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 4)
        .animation(.easeInOut(duration: 0.6), value: history.count)
        .frame(height: Self.height)
    }
}
