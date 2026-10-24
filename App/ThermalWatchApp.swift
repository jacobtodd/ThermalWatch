import ServiceManagement
import SwiftUI

@main
struct ThermalWatchApp: App {
    @State private var monitor: SystemMonitor
    @State private var fans: FanHelperClient
    @AppStorage("showLoadInMenuBar") private var showLoadInMenuBar = false
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    init() {
        // Start sampling immediately, not when the menu bar label first renders.
        let monitor = SystemMonitor()
        let fans = FanHelperClient()
        monitor.onSnapshot = { snap in fans.update(temperature: snap.temperature?.average) }
        monitor.start()
        _monitor = State(initialValue: monitor)
        _fans = State(initialValue: fans)

        // Launch at login is on by default: register once, then respect the Settings toggle.
        // Only from /Applications, so test runs and dev builds never become login items.
        if Bundle.main.bundlePath.hasPrefix("/Applications/"), !UserDefaults.standard.bool(forKey: "didRegisterLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didRegisterLogin")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor, fans: fans)
        } label: {
            Text(Formatting.menuBarTitle(temperature: monitor.latest?.temperature?.average,
                                         load: monitor.latest?.load,
                                         showLoad: showLoadInMenuBar,
                                         fahrenheit: useFahrenheit))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
