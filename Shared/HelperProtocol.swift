import Foundation

@objc protocol FanHelperProtocol {
    /// `level` is a `BoostLevel` raw value. Reply is nil on success, or an error message.
    func setBoost(_ level: Int, reply: @escaping (String?) -> Void)
    func heartbeat()
    func ping(reply: @escaping (Int) -> Void)
}

enum HelperConstants {
    static let machService = "com.jacobtodd.thermalwatch.helper"
    static let plistName = "com.jacobtodd.thermalwatch.helper.plist"
    static let version = 1
    static let teamID = "URYTQJBX8K"
    /// Only the real ThermalWatch app (signed by Jacob's team) may drive the fans.
    static let clientRequirement =
        "identifier \"com.jacobtodd.thermalwatch\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    /// The app only talks to the genuine helper.
    static let helperRequirement =
        "identifier \"com.jacobtodd.thermalwatch.helper\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
}
