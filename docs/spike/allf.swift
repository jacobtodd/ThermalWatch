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
var total = 0
if let k = readKey(fourCC("#KEY")) { total = Int(k.bytes.reduce(0) { $0 << 8 | UInt32($1) }) }
for idx in 0..<total {
  var p = SMCParam(); p.data8 = 8; p.data32 = UInt32(idx); guard call(&p) == KERN_SUCCESS else { continue }
  let name = str(p.key); guard name.hasPrefix("F") || name.lowercased().contains("fan") || name.hasPrefix("MS") else { continue }
  var q = SMCParam(); q.key = p.key; q.data8 = 9; _ = call(&q)
  let r = readKey(p.key)
  print(name, str(q.keyInfo.dataType), String(format: "attr=0x%02x", q.keyInfo.dataAttributes), r.map { $0.bytes.map { String(format: "%02x", $0) }.joined() } ?? "unreadable", r.flatMap(asFloat).map { "\($0)" } ?? "")
}
