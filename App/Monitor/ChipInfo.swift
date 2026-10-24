import Foundation
import IOKit
import IOKit.ps

enum ChipInfo {
    static let chipName: String = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"

    /// e.g. "MacBook Pro (14-inch, M5 Pro)", from the device tree.
    static let modelName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { IOObjectRelease(entry) }
        if entry != 0,
           let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
               .takeRetainedValue() as? Data,
           let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
           !name.isEmpty {
            return name
        }
        return sysctlString("hw.model") ?? "Mac"
    }()

    static var powerSource: String {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return type == kIOPMACPowerKey ? "on power adapter" : "on battery"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
