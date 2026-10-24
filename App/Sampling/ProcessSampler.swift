import Darwin
import Foundation

struct ProcessSample: Sendable {
    let pid: pid_t
    let name: String
    let startTime: UInt64
    let cpuTimeNs: UInt64
}

struct ProcessUsage: Identifiable, Sendable {
    let pid: pid_t
    let name: String
    /// 100 = one full core.
    let cpuPercent: Double
    var id: pid_t { pid }
}

enum ProcessSampler {
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    /// Every process we're allowed to read. Root-owned ones (kernel_task etc.) are skipped.
    static func sample() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let found = proc_listallpids(&pids, capacity * Int32(MemoryLayout<pid_t>.size))
        guard found > 0 else { return [] }

        return pids.prefix(Int(found)).compactMap { pid in
            guard pid > 0 else { return nil }
            var task = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 else { return nil }
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let machTime = task.pti_total_user + task.pti_total_system
            return ProcessSample(pid: pid,
                                 name: String(decoding: nameBuf.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self),
                                 startTime: bsd.pbi_start_tvsec,
                                 cpuTimeNs: machTime * UInt64(timebase.numer) / UInt64(timebase.denom))
        }
    }

    /// CPU % per process between two samples, busiest first.
    /// Processes are matched by (pid, start time) so a reused PID never inherits old CPU time.
    static func usage(previous: [ProcessSample], current: [ProcessSample], intervalNs: UInt64) -> [ProcessUsage] {
        guard intervalNs > 0 else { return [] }
        struct Key: Hashable { let pid: pid_t; let start: UInt64 }
        let before = Dictionary(previous.map { (Key(pid: $0.pid, start: $0.startTime), $0.cpuTimeNs) }, uniquingKeysWith: { a, _ in a })
        let me = getpid()
        return current.compactMap { s in
            guard s.pid != me,
                  let old = before[Key(pid: s.pid, start: s.startTime)],
                  s.cpuTimeNs >= old else { return nil }
            return ProcessUsage(pid: s.pid, name: s.name, cpuPercent: Double(s.cpuTimeNs - old) / Double(intervalNs) * 100)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
