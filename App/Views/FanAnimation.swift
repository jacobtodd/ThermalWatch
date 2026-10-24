import Foundation

enum FanAnimation {
    /// Seconds per full turn of the on-screen fan, or nil when the real fans are stopped.
    /// Proportional to real speed: 0.4 s per turn at max RPM, capped at 3 s when very slow.
    static func spinPeriod(rpm: Double, max: Double) -> Double? {
        guard rpm > 0, max > 0 else { return nil }
        return Swift.min(3, 0.4 * max / rpm)
    }
}
