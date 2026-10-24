import SwiftUI

@main
struct ThermalWatchApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("ThermalWatch").padding()
        } label: {
            Text("ThermalWatch")
        }
        .menuBarExtraStyle(.window)
    }
}
