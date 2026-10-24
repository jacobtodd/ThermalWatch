import Testing
@testable import ThermalWatch

struct SMCTests {
    @Test func paramStructMatchesCLayout() { #expect(MemoryLayout<SMCParam>.stride == 80) }
    @Test func fourCCPacksBigEndian() { #expect(fourCC("FNum") == 0x464E_756D) }
    @Test func fanKeyNamesUseLowercaseModeKey() {
        #expect(FanKey.mode(1) == "F1md"); #expect(FanKey.target(0) == "F0Tg")
    }
    // Hardware test: this app only targets Jacob's M5 Pro.
    @Test func readsTwoFansWithSaneLimits() throws {
        let smc = try SMC()
        #expect(smc.readUInt8(FanKey.fanCount) == 2)
        let max = try #require(smc.readFloat(FanKey.max(0)))
        #expect(max > 5000 && max < 10000)
    }
}
