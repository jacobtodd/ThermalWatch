import Darwin

struct CoreTicks: Sendable {
    var user, system, idle, nice: UInt64
    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
}

enum CPULoad {
    /// Overall load across all cores, 0...1. Nil if the core count changed or no time passed.
    static func load(previous: [CoreTicks], current: [CoreTicks]) -> Double? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (a, b) in zip(previous, current) {
            // Counters can wrap or reset (e.g. after sleep); skip such cores.
            guard b.total >= a.total, b.busy >= a.busy else { continue }
            busy += b.busy - a.busy
            total += b.total - a.total
        }
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    static func readTicks() -> [CoreTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return CoreTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                             idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }
}
