import SwiftUI

struct WarningsView: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 6) {
            ForEach(monitor.warnings) { w in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(monitor.displayName(pid: w.pid, fallback: w.name)) has been busy for \(Self.duration(since: w.busySince)) while you weren't using it.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer()
                    Button("Ignore") { monitor.ignore(w) }
                    if w.isGUIApp { Button("Quit") { monitor.quit(w) } }
                }
                .controlSize(.small)
            }
        }
        .padding(monitor.warnings.isEmpty ? 0 : 10)
        .background(monitor.warnings.isEmpty ? Color.clear : Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        .animation(.default, value: monitor.warnings)
    }

    static func duration(since date: Date) -> String {
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h"
    }
}
