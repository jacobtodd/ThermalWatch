import Foundation
import ServiceManagement
import Testing
@testable import ThermalWatch

struct AutoBoostTests {
    let t0 = Date(timeIntervalSince1970: 0)
    @Test func kicksInAfter15sAtThreshold() {
        var p = AutoBoostPolicy(threshold: 80)
        #expect(p.update(temperature: 81, now: t0) == .auto)
        #expect(p.update(temperature: 82, now: t0 + 14) == .auto)
        #expect(p.update(temperature: 82, now: t0 + 15) == .high)
    }
    @Test func dipResetsTheTimer() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: 81, now: t0); _ = p.update(temperature: 79, now: t0 + 10)
        #expect(p.update(temperature: 81, now: t0 + 20) == .auto)
    }
    @Test func releasesAfter60sAt10Below() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: 85, now: t0); _ = p.update(temperature: 85, now: t0 + 15)
        #expect(p.update(temperature: 70, now: t0 + 20) == .high)
        #expect(p.update(temperature: 72, now: t0 + 79) == .high)   // 72 > 70: release timer resets
        #expect(p.update(temperature: 70, now: t0 + 80) == .high)
        #expect(p.update(temperature: 69, now: t0 + 140) == .auto)
    }
    @Test func manualOverrideWins() {
        var p = AutoBoostPolicy(threshold: 80); p.manualOverride = .max
        #expect(p.update(temperature: 50, now: t0) == .max)
    }
    @Test func unknownTemperatureNeverBoosts() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: nil, now: t0)
        #expect(p.update(temperature: nil, now: t0 + 30) == .auto)
    }
    @Test func unknownTemperatureWhileBoostedReleases() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: 85, now: t0); _ = p.update(temperature: 85, now: t0 + 15)
        #expect(p.update(temperature: nil, now: t0 + 20) == .auto)
    }
    @Test func helperStatusMapping() {
        #expect(HelperStatus.from(.notRegistered) == .notRegistered)
        #expect(HelperStatus.from(.requiresApproval) == .needsApproval)
        #expect(HelperStatus.from(.enabled) == .enabled)
        #expect(HelperStatus.from(.notFound) != .enabled)
        #expect(HelperStatus.from(.notFound, inApplications: true) == .notRegistered)
        #expect(HelperStatus.from(.notFound, inApplications: false) != .notRegistered)
    }
}
