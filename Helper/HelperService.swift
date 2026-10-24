import Foundation
import IOKit
import IOKit.pwr_mgt
import os

// IOKit's message constants are C macros Swift can't import (iokit_common_msg(0x280) / (0x270)).
private let messageSystemWillSleep: natural_t = 0xE000_0280
private let messageCanSystemSleep: natural_t = 0xE000_0270

let helperLog = Logger(subsystem: "com.jacobtodd.thermalwatch.helper", category: "fan")

/// Root-side fan control. All state lives on one serial queue; `FanSafetyState` decides,
/// this class only does the SMC reads/writes around it.
final class HelperService: NSObject, NSXPCListenerDelegate, FanHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jacobtodd.thermalwatch.helper.fan")
    private let smc: SMC?
    private let temperatures: TemperatureReader?
    private var state: FanSafetyState
    private var timer: DispatchSourceTimer?
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    fileprivate var rootPowerPort: io_connect_t = 0
    private var activeConnection: ObjectIdentifier?

    override init() {
        let smc = try? SMC()
        self.smc = smc
        temperatures = smc.map(TemperatureReader.init)
        let count = Int(smc?.readUInt8(FanKey.fanCount) ?? 0)
        let limits = (0..<count).map { i in
            FanLimits(min: Double(smc?.readFloat(FanKey.min(i)) ?? 0), max: Double(smc?.readFloat(FanKey.max(i)) ?? 0))
        }
        state = FanSafetyState(limits: limits)
        super.init()
    }

    func start() {
        helperLog.notice("helper started, \(self.state.limits.count) fans, smc=\(self.smc != nil)")
        queue.sync { feed(.started) } // a previous crash may have left the fans in manual mode
        registerForSleep()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            feed(.tick(temperatures?.read()))
        }
        timer.resume()
        self.timer = timer
    }

    // MARK: - XPC

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = self
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in self?.disconnected(id) }
        connection.interruptionHandler = { [weak self] in self?.disconnected(id) }
        queue.sync { activeConnection = id }
        connection.resume()
        return true
    }

    private func disconnected(_ connection: ObjectIdentifier) {
        queue.async { [self] in
            // Only the current client's loss matters; an old connection closing must not cancel a new boost.
            guard connection == activeConnection else { return }
            helperLog.notice("client disconnected")
            feed(.clientDisconnected)
        }
    }

    func setBoost(_ level: Int, reply: @escaping (String?) -> Void) {
        guard let level = BoostLevel(rawValue: level) else { return reply("unknown level \(level)") }
        nonisolated(unsafe) let reply = reply // XPC reply blocks may be called from any queue
        queue.async { [self] in
            let rpm = (0..<state.limits.count).map { Double(smc?.readFloat(FanKey.actual($0)) ?? 0) }
            helperLog.notice("setBoost \(String(describing: level), privacy: .public) at rpm \(rpm, privacy: .public)")
            feed(.setLevel(level, currentRPM: rpm))
            if level != .auto { feed(.tick(temperatures?.read())) } // apply now, not in up to 2 s
            reply(smc == nil ? "SMC unavailable" : nil)
        }
    }

    func heartbeat() {
        queue.async { [self] in feed(.heartbeat) }
    }

    func ping(reply: @escaping (Int) -> Void) { reply(HelperConstants.version) }

    // MARK: - Applying commands (on `queue`)

    private func feed(_ event: FanEvent) {
        dispatchPrecondition(condition: .onQueue(queue))
        apply(state.handle(event, now: .now))
    }

    private func apply(_ command: FanCommand) {
        guard let smc else { return }
        switch command {
        case .none:
            return
        case .auto:
            for i in state.limits.indices {
                do { try smc.write(FanKey.mode(i), bytes: [0]) } catch { helperLog.error("auto F\(i): \(String(describing: error), privacy: .public)") }
            }
            helperLog.notice("fans → auto")
        case let .manual(targets):
            for (i, rpm) in targets.enumerated() {
                do {
                    try smc.write(FanKey.mode(i), bytes: [1])
                    try smc.write(FanKey.target(i), bytes: withUnsafeBytes(of: Float(rpm)) { Array($0) })
                } catch {
                    helperLog.error("manual F\(i): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    // MARK: - Sleep

    private func registerForSleep() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPowerPort = IORegisterForSystemPower(refcon, &powerPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let service = Unmanaged<HelperService>.fromOpaque(refcon).takeUnretainedValue()
            service.powerEvent(messageType, argument: messageArgument)
        }, &powerNotifier)
        if let powerPort { IONotificationPortSetDispatchQueue(powerPort, queue) }
    }

    private func powerEvent(_ type: natural_t, argument: UnsafeMutableRawPointer?) {
        switch type {
        case messageSystemWillSleep:
            helperLog.notice("system will sleep")
            feed(.willSleep)
            IOAllowPowerChange(rootPowerPort, Int(bitPattern: argument))
        case messageCanSystemSleep:
            IOAllowPowerChange(rootPowerPort, Int(bitPattern: argument))
        default:
            break
        }
    }
}
