import Foundation
import Testing
@testable import ThermalWatch

struct FanSafetyTests {
    let lim = FanLimits(min: 2317, max: 7826)
    let t0 = Date(timeIntervalSince1970: 0)
    func cool(_ avg: Double = 55, hottest: Double = 60) -> CPUTemperature { .init(average: avg, hottest: hottest) }

    @Test func floorCurve() {
        #expect(FanCurve.floor(temperature: 60, limits: lim) == 2317)
        #expect(FanCurve.floor(temperature: 75, limits: lim) == 5071.5)
        #expect(FanCurve.floor(temperature: 95, limits: lim) == 7826)
    }
    @Test func levelTargets() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 4695.6)
        #expect(FanCurve.target(level: .high, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 6260.8)
        #expect(FanCurve.target(level: .max, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 7826)
    }
    @Test func neverBelowTakeoverOrTemperatureFloor() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 5000, temperature: cool()) == 5000)
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool(85, hottest: 88)) > 6900)
    }
    @Test func hottestAt95GoesMax() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool(70, hottest: 95)) == 7826)
    }
    @Test func zeroRpmAtTakeoverStillAtLeastMinimum() {
        #expect(FanCurve.target(level: .medium, limits: FanLimits(min: 5000, max: 7826), rpmAtTakeover: 0, temperature: cool()) >= 5000)
    }
    @Test func startAndSleepAndDisconnectAllForceAuto() {
        var s = FanSafetyState(limits: [lim, lim])
        #expect(s.handle(.started, now: t0) == .auto)
        for e in [FanEvent.willSleep, .clientDisconnected] {
            _ = s.handle(.setLevel(.high, currentRPM: [2300, 2500]), now: t0)
            #expect(s.handle(e, now: t0) == .auto); #expect(s.level == .auto)
        }
    }
    @Test func tickAppliesPerFanTargets() {
        var s = FanSafetyState(limits: [lim, lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300, 6500]), now: t0)
        #expect(s.handle(.tick(cool()), now: t0 + 2) == .manual([6260.8, 6500]))
    }
    @Test func watchdogReturnsToAutoAfter10s() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.max, currentRPM: [2300]), now: t0)
        _ = s.handle(.heartbeat, now: t0 + 8)
        #expect(s.handle(.tick(cool()), now: t0 + 17) != .auto)
        #expect(s.handle(.tick(cool()), now: t0 + 18.1) == .auto)
    }
    @Test func missingTemperatureHandsBackToAuto() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300]), now: t0)
        #expect(s.handle(.tick(nil), now: t0 + 2) == .auto)
    }
    @Test func boostIsNotRestoredAfterTimeout() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300]), now: t0)
        _ = s.handle(.tick(cool()), now: t0 + 11)
        _ = s.handle(.heartbeat, now: t0 + 12)
        #expect(s.handle(.tick(cool()), now: t0 + 13) == .none)
    }
    @Test func changingLevelWhileBoostedKeepsOriginalTakeoverRpm() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.max, currentRPM: [2300]), now: t0)
        _ = s.handle(.setLevel(.medium, currentRPM: [7800]), now: t0 + 1)
        #expect(s.handle(.tick(cool()), now: t0 + 2) == .manual([4695.6]))
    }
}
