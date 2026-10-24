import Foundation

enum BoostLevel: Int, Codable, Sendable, CaseIterable {
    case auto = 0, medium, high, max

    /// Share of the fan's maximum speed; nil for automatic.
    var fraction: Double? {
        switch self {
        case .auto: nil
        case .medium: 0.60
        case .high: 0.80
        case .max: 1.0
        }
    }
}

struct FanLimits: Sendable, Equatable {
    let min: Double
    let max: Double
}

enum FanCurve {
    static let floorStart = 60.0   // °C where the floor starts rising from the minimum speed
    static let floorFull = 90.0    // °C where the floor reaches full speed
    static let emergency = 95.0    // hottest core at/above this → full speed

    /// A conservative stand-in for what macOS would do at this temperature, so a boost
    /// can never leave the fans slower than automatic control would.
    static func floor(temperature: Double, limits: FanLimits) -> Double {
        let t = Swift.min(1, Swift.max(0, (temperature - floorStart) / (floorFull - floorStart)))
        return limits.min + (limits.max - limits.min) * t
    }

    static func target(level: BoostLevel, limits: FanLimits, rpmAtTakeover: Double, temperature: CPUTemperature) -> Double {
        if temperature.hottest >= emergency { return limits.max }
        let levelRPM = (level.fraction ?? 0) * limits.max
        let wanted = Swift.max(levelRPM, rpmAtTakeover, floor(temperature: temperature.average, limits: limits))
        let clamped = Swift.min(limits.max, Swift.max(limits.min, wanted))
        return (clamped * 10).rounded() / 10
    }
}

enum FanCommand: Equatable, Sendable {
    case none
    case auto
    case manual([Double]) // one target RPM per fan
}

enum FanEvent: Sendable {
    case started
    case setLevel(BoostLevel, currentRPM: [Double])
    case heartbeat
    case tick(CPUTemperature?)
    case clientDisconnected
    case willSleep
}

/// The root helper's rules, kept pure so they can be tested. Every path that loses
/// track of the app or the temperature hands the fans back to macOS.
struct FanSafetyState {
    static let heartbeatTimeout: TimeInterval = 10

    let limits: [FanLimits]
    private(set) var level: BoostLevel = .auto
    private var rpmAtTakeover: [Double] = []
    private var lastHeartbeat: Date = .distantPast

    init(limits: [FanLimits]) { self.limits = limits }

    mutating func handle(_ event: FanEvent, now: Date) -> FanCommand {
        switch event {
        case .started, .clientDisconnected, .willSleep, .setLevel(.auto, _):
            return returnToAuto()

        case let .setLevel(newLevel, currentRPM):
            if level == .auto { rpmAtTakeover = currentRPM }
            level = newLevel
            lastHeartbeat = now
            return .none

        case .heartbeat:
            lastHeartbeat = now
            return .none

        case let .tick(temperature):
            guard level != .auto else { return .none }
            guard now.timeIntervalSince(lastHeartbeat) <= Self.heartbeatTimeout,
                  let temperature else { return returnToAuto() }
            return .manual(limits.indices.map { i in
                FanCurve.target(level: level, limits: limits[i],
                                rpmAtTakeover: i < rpmAtTakeover.count ? rpmAtTakeover[i] : 0,
                                temperature: temperature)
            })
        }
    }

    private mutating func returnToAuto() -> FanCommand {
        level = .auto
        rpmAtTakeover = []
        return .auto
    }
}
