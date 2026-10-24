import SwiftUI

struct ProcessListView: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.topProcesses.isEmpty {
                Text("Measuring…").font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(monitor.topProcesses) { p in
                HStack(spacing: 8) {
                    Group {
                        if let icon = monitor.icon(for: p.pid) {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: "gearshape").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(monitor.displayName(pid: p.pid, fallback: p.name)).lineLimit(1)
                    Spacer()
                    Text("\(Int(p.cpuPercent.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(p.cpuPercent > 50 ? .orange : .secondary)
                }
                .font(.callout)
                .padding(.vertical, 4)
                Divider().opacity(0.4)
            }
        }
        .animation(.default, value: monitor.topProcesses.map(\.pid))
    }
}
