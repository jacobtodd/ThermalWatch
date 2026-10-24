import Foundation
import Testing
@testable import ThermalWatch

struct MonitorTests {
    @Test func menuBarTitleTemperatureOnlyByDefault() {
        #expect(Formatting.menuBarTitle(temperature: 58.4, load: 0.33, showLoad: false, fahrenheit: false) == "58°")
    }
    @Test func menuBarTitleWithLoad() {
        #expect(Formatting.menuBarTitle(temperature: 58.4, load: 0.33, showLoad: true, fahrenheit: false) == "58° · 33%")
    }
    @Test func menuBarTitleWithoutTemperature() {
        #expect(Formatting.menuBarTitle(temperature: nil, load: nil, showLoad: true, fahrenheit: false) == "—° · —%")
    }
    @Test func fahrenheit() { #expect(Formatting.temperature(100, fahrenheit: true) == "212°") }
    @Test func historyKeepsNewest120() {
        var h = History(capacity: 120)
        for i in 0..<130 { h.append(Snapshot(date: .init(timeIntervalSince1970: Double(i)), temperature: nil, load: nil, fans: [])) }
        #expect(h.items.count == 120); #expect(h.items.first?.date.timeIntervalSince1970 == 10)
    }
    @Test func chipNameIsM5Pro() { #expect(ChipInfo.chipName == "Apple M5 Pro") }
}
