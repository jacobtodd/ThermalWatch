import Foundation
import IOKit

// ---- SMC ----
struct KeyDataVer { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
typealias Bytes32 = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
struct SMCParam {
  var key: UInt32 = 0; var vers = KeyDataVer(); var pLimit = PLimit(); var keyInfo = KeyInfo()
  var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0; var data32: UInt32 = 0
  var bytes: Bytes32 = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func str(_ v: UInt32) -> String { String(bytes: [24,16,8,0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "?" }

var conn: io_connect_t = 0
func call(_ p: inout SMCParam) -> kern_return_t {
  var out = SMCParam(); var size = MemoryLayout<SMCParam>.stride
  let r = IOConnectCallStructMethod(conn, 2, &p, MemoryLayout<SMCParam>.stride, &out, &size)
  p = out; return r
}
func readKey(_ key: UInt32) -> (type: String, bytes: [UInt8])? {
  var p = SMCParam(); p.key = key; p.data8 = 9
  guard call(&p) == KERN_SUCCESS, p.result == 0 else { return nil }
  let info = p.keyInfo
  var q = SMCParam(); q.key = key; q.keyInfo.dataSize = info.dataSize; q.data8 = 5
  guard call(&q) == KERN_SUCCESS, q.result == 0 else { return nil }
  let b = withUnsafeBytes(of: q.bytes) { Array($0.prefix(Int(info.dataSize))) }
  return (str(info.dataType), b)
}
func asFloat(_ r: (type: String, bytes: [UInt8])) -> Float? {
  if r.type == "flt ", r.bytes.count == 4 { return r.bytes.withUnsafeBytes { $0.load(as: Float.self) } }
  if r.type == "ui8 " { return Float(r.bytes[0]) }
  return nil
}

let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
_ = IOServiceOpen(svc, mach_task_self_, 0, &conn)
func write(_ k: String, _ bytes: [UInt8]) -> String {
  var p = SMCParam(); p.key = fourCC(k); p.data8 = 9; _ = call(&p)
  var q = SMCParam(); q.key = fourCC(k); q.keyInfo.dataSize = p.keyInfo.dataSize; q.data8 = 6
  withUnsafeMutableBytes(of: &q.bytes) { for (i, b) in bytes.enumerated() { $0[i] = b } }
  let kr = call(&q); return String(format: "kr=0x%x result=%d", kr, q.result)
}
func fbytes(_ f: Float) -> [UInt8] { withUnsafeBytes(of: f) { Array($0) } }
func rpm(_ i: Int) -> Float { readKey(fourCC("F\(i)Ac")).flatMap(asFloat) ?? -1 }
func restore() { print("restore F0md:", write("F0md", [0]), "F1md:", write("F1md", [0])) }
signal(SIGINT) { _ in restore(); exit(1) }; signal(SIGTERM) { _ in restore(); exit(1) }
let maxR = readKey(fourCC("F0Mx")).flatMap(asFloat) ?? 7826
let target = (maxR * 0.7).rounded()
print("uid:", getuid(), "before:", rpm(0), rpm(1), "target:", target)
print("set F0md=1:", write("F0md", [1]), "F1md=1:", write("F1md", [1]))
print("set F0Tg:", write("F0Tg", fbytes(target)), "F1Tg:", write("F1Tg", fbytes(target)))
for s in 1...8 { Thread.sleep(forTimeInterval: 1); print("t+\(s)s rpm:", rpm(0), rpm(1), "md:", readKey(fourCC("F0md"))?.bytes ?? []) }
restore()
for s in 1...6 { Thread.sleep(forTimeInterval: 1); print("after +\(s)s rpm:", rpm(0), rpm(1)) }
