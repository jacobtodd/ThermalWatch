import SwiftUI

@main
struct ThermalWatchApp: App {
    @State private var monitor: SystemMonitor
    @AppStorage("showLoadInMenuBar") private var showLoadInMenuBar = false
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    init() {
        // Start sampling immediately, not when the menu bar label first renders.
        let monitor = SystemMonitor()
        monitor.start()
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor)
        } label: {
            Text(Formatting.menuBarTitle(temperature: monitor.latest?.temperature?.average,
                                         load: monitor.latest?.load,
                                         showLoad: showLoadInMenuBar,
                                         fahrenheit: useFahrenheit))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
