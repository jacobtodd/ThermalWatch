import SwiftUI

struct BoostControl: View {
    let client: FanHelperClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if client.status == .enabled {
                Picker("Fans", selection: Binding(get: { client.manualSelection }, set: { client.choose($0) })) {
                    Text("Auto").tag(BoostLevel.auto)
                    Text("Medium").tag(BoostLevel.medium)
                    Text("High").tag(BoostLevel.high)
                    Text("Max").tag(BoostLevel.max)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if client.autoBoostActive {
                    Label("Auto-boost active", systemImage: "bolt.fill").font(.caption).foregroundStyle(.orange)
                }
            } else {
                Button("Enable fan control…") { client.enable() }
                Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { client.refreshStatus() }
    }

    private var caption: String {
        switch client.status {
        case .needsApproval: "Approve ThermalWatch in System Settings → General → Login Items, then reopen this menu."
        case .unavailable(let reason): reason
        default: "Boosting the fans needs a small admin helper. You'll approve it once in System Settings."
        }
    }
}
