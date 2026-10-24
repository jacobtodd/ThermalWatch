// Prints every plausible temperature sensor as "KEY VALUE". Compiled with Shared/SMC.swift.
let smc = try SMC()
for key in smc.keys() where key.hasPrefix("T") {
    if let v = smc.readFloat(key), v > 10, v < 120 { print(key, v) }
}
