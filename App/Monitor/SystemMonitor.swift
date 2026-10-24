import Foundation
import Observation

/// Does all the hardware reading off the main thread. Owns the SMC connection.
private actor Sampler {
    private let smc: SMC?
    private let temperatures: TemperatureReader?
    private let fanCount: Int
    private var previousTicks: [CoreTicks] = []
    private var previousProcesses: [ProcessSample] = []
    private var previousProcessTime: UInt64 = 0

    init() {
        let smc = try? SMC()
        self.smc = smc
        temperatures = smc.map(TemperatureReader.init)
        fanCount = Int(smc?.readUInt8(FanKey.fanCount) ?? 0)
    }

    func snapshot() -> Snapshot {
        let ticks = CPULoad.readTicks()
        let load = CPULoad.load(previous: previousTicks, current: ticks)
        previousTicks = ticks
        let fans: [FanReading] = (0..<fanCount).compactMap { i in
            guard let smc, let rpm = smc.readFloat(FanKey.actual(i)),
                  let min = smc.readFloat(FanKey.min(i)), let max = smc.readFloat(FanKey.max(i)) else { return nil }
            return FanReading(rpm: Double(rpm), min: Double(min), max: Double(max))
        }
        return Snapshot(date: .now, temperature: temperatures?.read(), load: load, fans: fans)
    }

    func processes() -> [ProcessUsage] {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let current = ProcessSampler.sample()
        defer { previousProcesses = current; previousProcessTime = now }
        guard previousProcessTime > 0 else { return [] }
        return ProcessSampler.usage(previous: previousProcesses, current: current, intervalNs: now - previousProcessTime)
    }
}

@MainActor @Observable
final class SystemMonitor {
    static let openInterval: Duration = .seconds(2)
    static let closedInterval: Duration = .seconds(5)
    /// While closed, processes are still sampled now and then so background warnings keep working.
    static let closedProcessInterval: TimeInterval = 60

    private(set) var latest: Snapshot?
    private(set) var history = History(capacity: 120) // 10 min at the closed 5 s rate
    private(set) var topProcesses: [ProcessUsage] = []
    /// Every process from the latest process sample, for warnings.
    private(set) var allProcesses: [ProcessUsage] = []
    /// Called after each process sample (warnings hook in here).
    @ObservationIgnored var onProcesses: (([ProcessUsage]) -> Void)?
    /// Called after each snapshot (auto-boost hooks in here).
    @ObservationIgnored var onSnapshot: ((Snapshot) -> Void)?

    var popoverOpen = false {
        didSet { if popoverOpen != oldValue { restart() } }
    }

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastProcessSample: Date = .distantPast
    @ObservationIgnored private var lastHistoryAppend: Date = .distantPast

    func start() { restart() }

    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.popoverOpen ? Self.openInterval : Self.closedInterval)
            }
        }
    }

    private func tick() async {
        let snap = await sampler.snapshot()
        latest = snap
        // Keep the graph at a steady 5 s spacing whether or not the popover is open.
        if snap.date.timeIntervalSince(lastHistoryAppend) >= 4.5 {
            history.append(snap)
            lastHistoryAppend = snap.date
        }
        onSnapshot?(snap)

        if popoverOpen || snap.date.timeIntervalSince(lastProcessSample) >= Self.closedProcessInterval {
            let usage = await sampler.processes()
            lastProcessSample = snap.date
            allProcesses = usage
            topProcesses = Array(usage.prefix(5))
            onProcesses?(usage)
        }
    }
}
