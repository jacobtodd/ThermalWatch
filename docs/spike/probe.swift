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

print("== SMC ==")
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
print("AppleSMC service:", svc != 0)
let openR = IOServiceOpen(svc, mach_task_self_, 0, &conn)
print("IOServiceOpen:", openR == KERN_SUCCESS ? "OK" : String(format: "FAILED 0x%x", openR))
if openR == KERN_SUCCESS {
  if let n = readKey(fourCC("FNum")) { print("Fan count:", n.bytes.first ?? 0) }
  for i in 0..<4 { if let r = readKey(fourCC("F\(i)Ac")), let v = asFloat(r) { print("Fan \(i) actual RPM:", v) } }
  for i in 0..<4 { if let r = readKey(fourCC("F\(i)Mx")), let v = asFloat(r) { print("Fan \(i) max RPM:", v) } }
  // enumerate temperature keys
  var total = 0
  if let k = readKey(fourCC("#KEY")) { total = Int(k.bytes.reduce(0) { $0 << 8 | UInt32($1) }) }
  print("Total SMC keys:", total)
  var temps: [(String, Float)] = []
  for idx in 0..<total {
    var p = SMCParam(); p.data8 = 8; p.data32 = UInt32(idx)
    guard call(&p) == KERN_SUCCESS else { continue }
    let name = str(p.key)
    guard name.hasPrefix("T"), let r = readKey(p.key), r.type == "flt ", let v = asFloat(r), v > 10, v < 120 else { continue }
    temps.append((name, v))
  }
  print("Temp keys (flt, 10-120):", temps.count)
  print(temps.map { "\($0.0)=\(String(format: "%.1f", $0.1))" }.joined(separator: " "))
}

// ---- CPU load ----
print("== CPU load ==")
func ticks() -> [(UInt32,UInt32,UInt32,UInt32)] {
  var count: natural_t = 0; var info: processor_info_array_t?; var n: mach_msg_type_number_t = 0
  guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &n) == KERN_SUCCESS, let info else { return [] }
  defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(n) * 4) }
  return (0..<Int(count)).map { c in let b = c * Int(CPU_STATE_MAX); return (UInt32(info[b]), UInt32(info[b+1]), UInt32(info[b+2]), UInt32(info[b+3])) }
}
let a = ticks(); Thread.sleep(forTimeInterval: 1); let b = ticks()
if a.isEmpty { print("host_processor_info FAILED") } else {
  var busy = 0.0, all = 0.0
  for (x, y) in zip(a, b) { let u = Double(y.0-x.0), s = Double(y.1-x.1), i = Double(y.2-x.2), n = Double(y.3-x.3); busy += u+s+n; all += u+s+i+n }
  print("Cores:", a.count, "Load:", String(format: "%.0f%%", busy/all*100))
}

// ---- processes ----
print("== Processes ==")
let np = proc_listallpids(nil, 0)
var pids = [pid_t](repeating: 0, count: Int(np) + 64)
let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
var readable = 0; var samples: [(String, UInt64)] = []
for pid in pids.prefix(Int(got)) where pid > 0 {
  var ti = proc_taskinfo()
  if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 {
    readable += 1
    var name = [CChar](repeating: 0, count: 256); proc_name(pid, &name, 256)
    samples.append((String(cString: name), ti.pti_total_user + ti.pti_total_system))
  }
}
print("PIDs listed:", got, "task info readable:", readable)
print("Top by total CPU time:", samples.sorted { $0.1 > $1.1 }.prefix(5).map { $0.0 })

print("== thermalState ==", ProcessInfo.processInfo.thermalState.rawValue)
print("sandboxed:", ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
