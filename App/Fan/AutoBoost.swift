import Foundation

/// Turns the fans up when the CPU stays hot, and back to Auto once it has properly cooled.
struct AutoBoostPolicy {
    static let engageAfter: TimeInterval = 15
    static let releaseAfter: TimeInterval = 60
    static let releaseMargin = 10.0
    static let boostLevel = BoostLevel.high

    var threshold: Double
    /// A level the user picked by hand; it wins until they set Auto again (nil).
    var manualOverride: BoostLevel?

    private(set) var boosted = false
    private var hotSince: Date?
    private var coolSince: Date?

    init(threshold: Double) { self.threshold = threshold }

    mutating func update(temperature: Double?, now: Date) -> BoostLevel {
        if let manualOverride { return manualOverride }
        guard let temperature else {
            // Can't see the temperature: never boost blind, let macOS decide.
            boosted = false; hotSince = nil; coolSince = nil
            return .auto
        }
        if !boosted {
            if temperature >= threshold {
                hotSince = hotSince ?? now
                if now.timeIntervalSince(hotSince!) >= Self.engageAfter { boosted = true; coolSince = nil }
            } else {
                hotSince = nil
            }
        } else if temperature <= threshold - Self.releaseMargin {
            coolSince = coolSince ?? now
            if now.timeIntervalSince(coolSince!) >= Self.releaseAfter { boosted = false; hotSince = nil }
        } else {
            coolSince = nil
        }
        return boosted ? Self.boostLevel : .auto
    }
}
