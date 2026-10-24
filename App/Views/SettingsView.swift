import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("showLoadInMenuBar") private var showLoadInMenuBar = false
    @AppStorage("useFahrenheit") private var useFahrenheit = false
    @AppStorage("autoBoostEnabled") private var autoBoostEnabled = false
    @AppStorage("autoBoostThreshold") private var autoBoostThreshold = 80.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show CPU load in menu bar", isOn: $showLoadInMenuBar)
                Picker("Temperature unit", selection: $useFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section("Fans") {
                Toggle("Auto-boost when hot", isOn: $autoBoostEnabled)
                Stepper(value: $autoBoostThreshold, in: 60...95, step: 5) {
                    Text("Boost at \(Formatting.temperature(autoBoostThreshold, fahrenheit: useFahrenheit))")
                }
                .disabled(!autoBoostEnabled)
                Text("Fans go to High after 15 s at this temperature, and back to Auto once 10° cooler for a minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
