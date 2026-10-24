import Foundation
import Testing
@testable import ThermalWatch

struct WarningsTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func logic(_ pct: Double) -> [ProcessUsage] { [ProcessUsage(pid: 42, name: "Logic Pro", cpuPercent: pct)] }

    @Test func busyBackgroundAppWarnsAfter10Minutes() {
        var w = WarningTracker()
        for m in 0..<10 { #expect(w.update(usage: logic(47), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
        let out = w.update(usage: logic(47), frontmostPID: 1, guiPIDs: [42], now: t0 + 600)
        #expect(out.map(\.name) == ["Logic Pro"]); #expect(out.first?.isGUIApp == true)
    }
    @Test func frontmostAppNeverWarns() {
        var w = WarningTracker()
        for m in 0...11 { #expect(w.update(usage: logic(90), frontmostPID: 42, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func belowThresholdNeverWarns() {
        var w = WarningTracker()
        for m in 0...11 { #expect(w.update(usage: logic(20), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func ignoredAppIsMuted() {
        var w = WarningTracker(); w.ignored = ["Logic Pro"]
        for m in 0...11 { #expect(w.update(usage: logic(90), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func atMostThreeWarnings() {
        var w = WarningTracker()
        let many = (1...5).map { ProcessUsage(pid: pid_t($0), name: "p\($0)", cpuPercent: 50) }
        var out: [BusyWarning] = []
        for m in 0...10 { out = w.update(usage: many, frontmostPID: 99, guiPIDs: [], now: t0 + Double(m * 60)) }
        #expect(out.count == 3)
    }
    @Test func becomingFrontmostClearsTheWarning() {
        var w = WarningTracker()
        for m in 0...10 { _ = w.update(usage: logic(47), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)) }
        #expect(w.update(usage: logic(47), frontmostPID: 42, guiPIDs: [42], now: t0 + 660).isEmpty)
    }
}

struct FanViewTests {
    @Test func fanSpinPeriodForZeroRpm() { #expect(FanAnimation.spinPeriod(rpm: 0, max: 7826) == nil) }
    @Test func fanSpinsFasterAtHigherRpm() {
        #expect(FanAnimation.spinPeriod(rpm: 7826, max: 7826)! < FanAnimation.spinPeriod(rpm: 2317, max: 7826)!)
    }
}
