import Foundation
import IOKit

// Talks to the System Management Controller (fans, temperature sensors).
// Layout mirrors the C `SMCKeyData_t` struct used by the AppleSMC user client.

struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct SMCPLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
// The 3 padding bytes matter: without them Swift packs the next fields into this
// struct's tail padding, the whole thing becomes 76 bytes, and every call fails.
struct SMCKeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0 }
typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

struct SMCParam {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var index: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum SMCError: Error {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyNotFound(String)
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

private func fourCCString(_ v: UInt32) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "????"
}

enum FanKey {
    static let fanCount = "FNum"
    static func actual(_ i: Int) -> String { "F\(i)Ac" }
    static func min(_ i: Int) -> String { "F\(i)Mn" }
    static func max(_ i: Int) -> String { "F\(i)Mx" }
    static func target(_ i: Int) -> String { "F\(i)Tg" }
    /// Lowercase on M5: 1 = manual, 0 = automatic.
    static func mode(_ i: Int) -> String { "F\(i)md" }
}

final class SMC {
    private enum Command: UInt8 { case readBytes = 5, writeBytes = 6, keyAtIndex = 8, keyInfo = 9 }
    private var connection: io_connect_t = 0

    init() throws(SMCError) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw .serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { throw .openFailed(kr) }
    }

    deinit { IOServiceClose(connection) }

    func readFloat(_ key: String) -> Float? {
        guard let (type, bytes) = read(key) else { return nil }
        switch type {
        case "flt " where bytes.count == 4: return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        case "ui8 " where bytes.count == 1: return Float(bytes[0])
        default: return nil
        }
    }

    func readUInt8(_ key: String) -> UInt8? {
        guard let (type, bytes) = read(key), type == "ui8 ", bytes.count == 1 else { return nil }
        return bytes[0]
    }

    func write(_ key: String, bytes: [UInt8]) throws(SMCError) {
        guard let info = keyInfo(fourCC(key)) else { throw .keyNotFound(key) }
        var p = SMCParam()
        p.key = fourCC(key)
        p.keyInfo.dataSize = info.dataSize
        p.command = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &p.bytes) { buf in
            for (i, b) in bytes.prefix(Int(info.dataSize)).enumerated() { buf[i] = b }
        }
        let kr = call(&p)
        guard kr == KERN_SUCCESS, p.result == 0 else { throw .callFailed(kr == KERN_SUCCESS ? kern_return_t(p.result) : kr) }
    }

    func keys() -> [String] {
        guard let (_, countBytes) = read("#KEY") else { return [] }
        let count = countBytes.reduce(0) { $0 << 8 | UInt32($1) }
        return (0..<count).compactMap { index in
            var p = SMCParam()
            p.command = Command.keyAtIndex.rawValue
            p.index = index
            guard call(&p) == KERN_SUCCESS, p.result == 0 else { return nil }
            return fourCCString(p.key)
        }
    }

    // MARK: - Private

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        let code = fourCC(key)
        guard let info = keyInfo(code) else { return nil }
        var p = SMCParam()
        p.key = code
        p.keyInfo.dataSize = info.dataSize
        p.command = Command.readBytes.rawValue
        guard call(&p) == KERN_SUCCESS, p.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: p.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (fourCCString(info.dataType), bytes)
    }

    private func keyInfo(_ code: UInt32) -> SMCKeyInfo? {
        var p = SMCParam()
        p.key = code
        p.command = Command.keyInfo.rawValue
        guard call(&p) == KERN_SUCCESS, p.result == 0 else { return nil }
        return p.keyInfo
    }

    private func call(_ p: inout SMCParam) -> kern_return_t {
        var output = SMCParam()
        var outputSize = MemoryLayout<SMCParam>.stride
        let kr = IOConnectCallStructMethod(connection, 2, &p, MemoryLayout<SMCParam>.stride, &output, &outputSize)
        p = output
        return kr
    }
}
