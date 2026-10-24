import Testing
@testable import ThermalWatch

struct SamplingTests {
    @Test func overallLoadAcrossCores() {
        let a = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0), .init(user: 0, system: 0, idle: 0, nice: 0)]
        let b = [CoreTicks(user: 50, system: 25, idle: 25, nice: 0), .init(user: 0, system: 0, idle: 100, nice: 0)]
        #expect(CPULoad.load(previous: a, current: b) == 0.375)
    }
    @Test func loadIsNilWhenCoreCountChangesOrNoTimePassed() {
        #expect(CPULoad.load(previous: [], current: [.init(user: 1, system: 0, idle: 0, nice: 0)]) == nil)
        let a = [CoreTicks(user: 5, system: 0, idle: 5, nice: 0)]
        #expect(CPULoad.load(previous: a, current: a) == nil)
    }
    @Test func processPercentIsPerCore() {
        let p = [ProcessSample(pid: 10, name: "Logic Pro", startTime: 1, cpuTimeNs: 0)]
        let c = [ProcessSample(pid: 10, name: "Logic Pro", startTime: 1, cpuTimeNs: 1_500_000_000)]
        #expect(ProcessSampler.usage(previous: p, current: c, intervalNs: 1_000_000_000).first?.cpuPercent == 150)
    }
    @Test func exitedOrReusedPidIsSkipped() {
        let p = [ProcessSample(pid: 10, name: "old", startTime: 1, cpuTimeNs: 9_000_000_000),
                 ProcessSample(pid: 11, name: "gone", startTime: 1, cpuTimeNs: 0)]
        let c = [ProcessSample(pid: 10, name: "new", startTime: 2, cpuTimeNs: 1_000)]
        #expect(ProcessSampler.usage(previous: p, current: c, intervalNs: 1_000_000_000).isEmpty)
    }
    @Test func liveSampleSeesProcesses() {
        #expect(ProcessSampler.sample().count > 100)
        #expect(CPULoad.readTicks().count == 18)
    }
}
