import Foundation

struct BusyWarning: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let busySince: Date
    let isGUIApp: Bool
    var id: pid_t { pid }
}

/// Spots apps that keep the chip busy while you're not using them:
/// not frontmost, averaging ≥25% CPU over the last 10 minutes.
struct WarningTracker {
    static let threshold = 25.0
    static let window: TimeInterval = 600
    static let maxWarnings = 3

    var ignored: Set<String> = []

    private struct Key: Hashable { let pid: pid_t; let name: String }
    private struct Track { var busySince: Date; var samples: [(date: Date, percent: Double)] }
    private var tracks: [Key: Track] = [:]

    mutating func update(usage: [ProcessUsage], frontmostPID: pid_t?, guiPIDs: Set<pid_t>, now: Date) -> [BusyWarning] {
        var next: [Key: Track] = [:]
        for u in usage where u.pid != frontmostPID && !ignored.contains(u.name) {
            let key = Key(pid: u.pid, name: u.name)
            // Only start tracking once something is actually busy (keeps memory flat across ~800 processes).
            guard tracks[key] != nil || u.cpuPercent >= Self.threshold else { continue }
            var track = tracks[key] ?? Track(busySince: now, samples: [])
            track.samples.append((now, u.cpuPercent))
            track.samples.removeAll { now.timeIntervalSince($0.date) > Self.window }
            // A quiet stretch restarts the clock, so "busy for 2h" means 2 busy hours.
            if Self.average(track.samples) < Self.threshold { track.busySince = now }
            next[key] = track
        }
        tracks = next // apps that quit, went frontmost, or got ignored are forgotten

        return tracks
            .filter { now.timeIntervalSince($0.value.busySince) >= Self.window }
            .map { BusyWarning(pid: $0.key.pid, name: $0.key.name, busySince: $0.value.busySince, isGUIApp: guiPIDs.contains($0.key.pid)) }
            .sorted { ($0.busySince, $0.pid) < ($1.busySince, $1.pid) }
            .prefix(Self.maxWarnings)
            .map { $0 }
    }

    private static func average(_ samples: [(date: Date, percent: Double)]) -> Double {
        samples.isEmpty ? 0 : samples.map(\.percent).reduce(0, +) / Double(samples.count)
    }
}
