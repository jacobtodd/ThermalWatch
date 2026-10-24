import Foundation

struct FanReading: Sendable {
    let rpm: Double
    let min: Double
    let max: Double
}

struct Snapshot: Sendable {
    let date: Date
    let temperature: CPUTemperature?
    let load: Double?
    let fans: [FanReading]
}

/// Fixed-size ring buffer of recent snapshots, oldest first.
struct History {
    private var buffer: [Snapshot] = []
    private var start = 0
    let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    mutating func append(_ s: Snapshot) {
        if buffer.count < capacity {
            buffer.append(s)
        } else {
            buffer[start] = s
            start = (start + 1) % capacity
        }
    }

    var items: [Snapshot] { Array(buffer[start...] + buffer[..<start]) }
}
