import SwiftUI

struct PopoverView: View {
    let monitor: SystemMonitor
    let fans: FanHelperClient
    @AppStorage("useFahrenheit") private var useFahrenheit = false
    @State private var visible = false
    @State private var lastSize = CGSize(width: 340, height: 560)

    var body: some View {
        Group {
            // While hidden, read nothing from the monitor: SwiftUI then has no reason to
            // re-render or animate a window nobody can see. Same-size blank keeps the window steady.
            if visible {
                content.onGeometryChange(for: CGSize.self) { $0.size } action: { lastSize = $0 }
            } else {
                Color.clear.frame(width: lastSize.width, height: lastSize.height)
            }
        }
        .background(WindowVisibilityReader { isVisible in
            visible = isVisible
            monitor.popoverOpen = isVisible
        })
    }

    private var content: some View {
        let snap = monitor.latest
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 2) {
                Text(ChipInfo.chipName).font(.headline)
                Text("\(ChipInfo.modelName) · \(ChipInfo.powerSource)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                GaugeRing(fraction: snap?.temperature.map { $0.average / 100 },
                          label: Formatting.temperature(snap?.temperature?.average, fahrenheit: useFahrenheit),
                          caption: "CPU · hottest \(Formatting.temperature(snap?.temperature?.hottest, fahrenheit: useFahrenheit))",
                          color: .orange)
                Spacer()
                GaugeRing(fraction: snap?.load, label: Formatting.percent(snap?.load), caption: "CPU load", color: .green)
                Spacer()
                FanView(fans: snap?.fans ?? [])
            }

            BoostControl(client: fans)

            section("Last 10 minutes")
            HistoryChart(history: monitor.history.items)

            section("Using your chip")
            ProcessListView(monitor: monitor)

            WarningsView(monitor: monitor)

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer()
                Button("Quit ThermalWatch") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
    }
}
