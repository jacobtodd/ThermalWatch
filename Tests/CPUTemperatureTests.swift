import Testing
@testable import ThermalWatch

struct CPUTemperatureTests {
    @Test func averagesAndFindsHottestCoreOnly() {
        let t = CPUSensors.temperature(from: ["Tp00": 60, "Tm04": 64, "TB0T": 36, "TD00": 29, "Tg08": 90])
        #expect(t == CPUTemperature(average: 62, hottest: 64))
    }
    @Test func ignoresImplausibleReadings() {
        #expect(CPUSensors.temperature(from: ["Tp00": 60, "Tp04": 0, "Tp08": 150])?.average == 60)
    }
    @Test func noCoreReadingsGivesNil() {
        #expect(CPUSensors.temperature(from: ["TB0T": 36]) == nil)
        #expect(CPUSensors.temperature(from: [:]) == nil)
    }
}
