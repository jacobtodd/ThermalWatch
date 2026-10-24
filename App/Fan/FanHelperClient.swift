import AppKit
import Observation
import ServiceManagement
import os

private let clientLog = Logger(subsystem: "com.jacobtodd.thermalwatch", category: "fan")

enum HelperStatus: Equatable {
    case notRegistered, needsApproval, enabled
    case unavailable(String)

    /// macOS reports a never-registered daemon as `.notFound`; that only means trouble
    /// when the app isn't in /Applications (where SMAppService needs it).
    static func from(_ status: SMAppService.Status, inApplications: Bool = true) -> HelperStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .requiresApproval: .needsApproval
        case .enabled: .enabled
        case .notFound: inApplications ? .notRegistered : .unavailable("Move ThermalWatch to /Applications to enable fan control.")
        @unknown default: .unavailable("Unknown helper status.")
        }
    }
}

/// The app's side of fan control: registers the root helper, sends levels, keeps the
/// heartbeat going while boosted, and runs auto-boost.
@MainActor @Observable
final class FanHelperClient {
    static let heartbeatInterval: Duration = .seconds(3)

    private(set) var status: HelperStatus = .notRegistered
    /// What the fans are currently being asked to do.
    private(set) var level: BoostLevel = .auto
    /// The user's own pick in the popover (Auto unless they chose a level).
    var manualSelection: BoostLevel { policy.manualOverride ?? .auto }
    var autoBoostActive: Bool { policy.manualOverride == nil && level != .auto }
    private(set) var lastError: String?

    @ObservationIgnored private var policy = AutoBoostPolicy(threshold: 80)
    @ObservationIgnored private let service = SMAppService.daemon(plistName: HelperConstants.plistName)
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    init() {
        refreshStatus()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.handBackOnQuit() }
        }
    }

    func refreshStatus() {
        status = HelperStatus.from(service.status, inApplications: Bundle.main.bundlePath.hasPrefix("/Applications/"))
    }

    func enable() {
        do {
            try service.register()
        } catch {
            clientLog.error("register failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        if status == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// The user picked a level in the popover.
    func choose(_ newLevel: BoostLevel) {
        policy.manualOverride = newLevel == .auto ? nil : newLevel
        send(newLevel)
    }

    /// Called on every monitor snapshot.
    func update(temperature: Double?) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "autoBoostEnabled") || policy.manualOverride != nil else {
            if level != .auto { send(.auto) }
            return
        }
        let threshold = defaults.object(forKey: "autoBoostThreshold") as? Double ?? 80
        policy.threshold = threshold
        let wanted = policy.update(temperature: temperature, now: .now)
        if wanted != level { send(wanted) }
    }

    // MARK: - XPC

    private func send(_ newLevel: BoostLevel) {
        guard status == .enabled else { level = .auto; return }
        level = newLevel
        proxy()?.setBoost(newLevel.rawValue) { error in
            guard let error else { return }
            Task { @MainActor in
                self.lastError = error
                clientLog.error("setBoost: \(error, privacy: .public)")
            }
        }
        heartbeatTask?.cancel()
        guard newLevel != .auto else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                self?.proxy()?.heartbeat()
            }
        }
    }

    private func proxy() -> FanHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
            c.setCodeSigningRequirement(HelperConstants.helperRequirement)
            c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            let lost: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.connectionLost() }
            }
            c.invalidationHandler = lost
            c.interruptionHandler = lost
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { error in
            clientLog.error("xpc: \(error.localizedDescription, privacy: .public)")
        } as? FanHelperProtocol
    }

    /// The helper hands the fans back to Auto when it loses us; mirror that here.
    private func connectionLost() {
        connection = nil
        heartbeatTask?.cancel()
        level = .auto
        refreshStatus()
    }

    private func handBackOnQuit() {
        guard level != .auto, let connection else { return }
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in } as? FanHelperProtocol
        proxy?.setBoost(BoostLevel.auto.rawValue) { _ in }
    }
}
