import Foundation

struct CPUTemperature: Equatable, Sendable {
    let average: Double
    let hottest: Double
}

enum CPUSensors {
    /// The M5 Pro's two CPU core clusters. Found with Tools/calibrate-sensors.sh:
    /// under full load `Tm` rose 11–16°C and `Tp` 10–13°C, while GPU (`Tg`) rose
    /// a uniform ~8°C and the battery/board sensors stayed flat.
    static let corePrefixes = ["Tp", "Tm"]
    static let plausibleRange: ClosedRange<Float> = 10...120

    static func isCoreKey(_ key: String) -> Bool {
        corePrefixes.contains { key.hasPrefix($0) }
    }

    static func temperature(from readings: [String: Float]) -> CPUTemperature? {
        let values = readings
            .filter { isCoreKey($0.key) && plausibleRange.contains($0.value) }
            .map { Double($0.value) }
        guard let hottest = values.max() else { return nil }
        return CPUTemperature(average: values.reduce(0, +) / Double(values.count), hottest: hottest)
    }
}

final class TemperatureReader {
    private let smc: SMC
    private let coreKeys: [String]

    init(smc: SMC) {
        self.smc = smc
        coreKeys = smc.keys().filter(CPUSensors.isCoreKey)
    }

    func read() -> CPUTemperature? {
        var readings: [String: Float] = [:]
        for key in coreKeys { readings[key] = smc.readFloat(key) }
        return CPUSensors.temperature(from: readings)
    }
}
