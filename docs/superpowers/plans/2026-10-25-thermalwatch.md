# ThermalWatch Implementation Plan

> **Status (2026-10-25):** Tasks 1–7 built and committed. Task 8 (end-to-end fan checks on the real Mac) is pending the user's Login Items approval of the helper. Deviations made during the build are listed in the design doc under "Changes made during the build".

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal macOS menu bar app for an M5 Pro MacBook Pro. It shows CPU temperature, load and fan speed live, names the processes heating the Mac, and can boost the fans safely through a root helper.

**Architecture:** One XcodeGen project with three targets:
- `ThermalWatch`: the SwiftUI `MenuBarExtra` app. It reads the SMC, CPU ticks and processes itself, with no root needed.
- `ThermalWatchHelper`: a root launchd daemon, registered with `SMAppService.daemon`. Its only job is fan writes, and it enforces every fan-safety rule itself.
- `ThermalWatchTests`: Swift Testing.

Code both the app and the helper need lives in `Shared/` and is compiled into both. Every decision rule is a pure value type with unit tests: CPU %, warnings, auto-boost, the fan floor curve, the helper state machine. The I/O wrappers stay thin.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + Swift Charts, IOKit (AppleSMC), libproc, NSXPC, ServiceManagement, XcodeGen, Swift Testing, Xcode 27.1.

**Spec:** `docs/superpowers/specs/2026-10-25-thermalwatch-design.md`. Verified SMC facts are in its "Constraints and verified facts" section, and working reference code is in `docs/spike/`.

## Global Constraints

**Platform**
- No App Sandbox. Hardened runtime on. Team `URYTQJBX8K`, automatic signing, bundle ID prefix `com.jacobtodd`.
- App bundle ID `com.jacobtodd.thermalwatch`. Helper label and mach service: `com.jacobtodd.thermalwatch.helper`.
- Deployment target macOS 27.0, Swift 6.0, `LSUIElement: true`.
- The app must run from `/Applications` for `SMAppService.daemon` to work.

**SMC**
- `SMCParam` is exactly 80 bytes. Add 3 explicit padding bytes after `keyInfo.dataAttributes` (see `docs/spike/probe.swift`).
- Commands: 9 key info, 5 read, 6 write, 8 key by index, all through selector 2.
- Fan keys:
  - `FNum` (ui8)
  - `F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}Tg` (flt)
  - `F{i}md` (ui8, lowercase: 1 = manual, 0 = auto)
- To take manual control: write `F{i}md=1`, then `F{i}Tg`.

**Behaviour**
- Menu bar: text only, no icon. Temperature only by default (`58°`), or `58° · 33%` when "Show CPU load in menu bar" is on.
- Refresh every 2 s while the popover is open and every 5 s while it's closed.
- History: 10 minutes. Keep average CPU under 1% while the popover is closed.

**Warnings**
- An app qualifies when it isn't frontmost and averages ≥25% CPU for ≥10 min. Show at most 3.
- "Quit" only for GUI apps (`terminate()`). "Ignore" mutes the app until relaunch.

**Boost levels**
- Auto, Medium = 0.60 × `F{i}Mx`, High = 0.80 × `F{i}Mx`, Max = `F{i}Mx`.

**Fan floor**
- floor(t) = `Mn + (Mx − Mn) × clamp((t − 60) / 30, 0, 1)`.
- target = max(levelRPM, rpmAtTakeover, floor(avgCPU)).
- Hottest CPU sensor ≥ 95°C → `Mx`.

**Auto-boost**
- Off by default; threshold default 80°C.
- On when temp ≥ threshold for 15 s → High.
- Back to Auto when temp ≤ threshold − 10 for 60 s.
- A manual choice overrides it until the user sets Auto again.

**Helper safety**
- Returns to Auto when:
  - there's no heartbeat for 10 s
  - the XPC connection drops
  - the system is about to sleep
  - the helper starts
- Does not restore a boost after sleep or timeout.

**Settings (`@AppStorage` keys)**
- `showLoadInMenuBar` = false
- `useFahrenheit` = false
- `autoBoostEnabled` = false
- `autoBoostThreshold` = 80.0
- Launch at login via `SMAppService.mainApp`, on by default: register on first launch.

## Review Focus

1. **App killed (`kill -9`) or crashes while boosted.** Expected: the fans are back on Auto within about 10 s, because the helper watchdog fires. Pinned in Task 6 (`watchdogReturnsToAutoAfter10s`) and checked end to end in Task 8.
2. **The temperature read fails mid-boost** (SMC open fails, or the sensor keys are missing). Expected: the helper returns the fans to Auto rather than holding a fixed speed blind. The UI shows `—°` instead of `0°`, and auto-boost doesn't fire. Pinned in Task 6 (`missingTemperatureHandsBackToAuto`), Task 2 (`noCoreReadingsGivesNil`) and Task 4 (`menuBarTitleWithoutTemperature`).
3. **A process exits or its PID is reused between samples.** Expected: no negative, absurd or stale CPU % entries. Pinned in Task 3 (`exitedOrReusedPidIsSkipped`).
4. **The helper isn't approved, or the user turns it off in Login Items.** Expected: monitoring keeps working fully, and the boost control shows "Enable fan control…" in place of the levels. Pinned in Task 7 (`helperStatusMapping`).
5. **The fans read 0 RPM, or the takeover RPM is 0.** Expected: the fan view sits still with no division by zero, and boost targets stay ≥ `Mn`. Pinned in Task 6 (`zeroRpmAtTakeoverStillAtLeastMinimum`) and Task 5 (`fanSpinPeriodForZeroRpm`).

---

### Task 1: Project skeleton and SMC access

**Files:**
- Create: `project.yml`, `Makefile`, `.gitignore` (`build/`, `*.xcodeproj`, `.superpowers/`)
- Create: `App/ThermalWatchApp.swift` (a placeholder `MenuBarExtra` with label `Text("ThermalWatch")`), `App/Info.plist`
- Create: `Helper/main.swift` (a placeholder that exits 0)
- Create: `Helper/com.jacobtodd.thermalwatch.helper.plist`
- Create: `Shared/SMC.swift`
- Test: `Tests/SMCTests.swift`

**Interfaces:**
- Produces:
  - `final class SMC`, with:
    - `init() throws(SMCError)`, which opens `AppleSMC`
    - `func readFloat(_ key: String) -> Float?`, which handles `flt ` and `ui8 ` types
    - `func readUInt8(_ key: String) -> UInt8?`
    - `func write(_ key: String, bytes: [UInt8]) throws(SMCError)`
    - `func keys() -> [String]`, which enumerates via `#KEY` and command 8
  - `enum SMCError: Error { case serviceNotFound, openFailed(kern_return_t), callFailed(kern_return_t), keyNotFound(String) }`
  - `func fourCC(_ s: String) -> UInt32`
  - `enum FanKey { static func actual(_ i: Int) -> String /* "F\(i)Ac" */; min, max, target, mode /* "F\(i)md" */ }`
  - `static let fanCount = "FNum"`
  - `SMC` is not `Sendable`. Each owner holds its own instance.

- [ ] **Step 1: Write `project.yml` and `Makefile`.** Copy the DiscPop shape (a sibling XcodeGen menu bar app's `project.yml` and `Makefile`), with these differences:
  - **Targets:**
    - `ThermalWatch` (application), sources `App` + `Shared`
    - `ThermalWatchHelper` (tool), sources `Helper` + `Shared`
    - `ThermalWatchTests` (bundle.unit-test), sources `Tests`, depends on `ThermalWatch`
  - **Entitlements:** no `com.apple.security.app-sandbox`. The app's entitlements file is empty.
  - **App target, copyFiles:**
    - the helper product into `Contents/MacOS`
    - `Helper/com.jacobtodd.thermalwatch.helper.plist` into `Contents/Library/LaunchDaemons`
  - **Helper plist keys:**
    - `Label`
    - `BundleProgram = Contents/MacOS/ThermalWatchHelper`
    - `MachServices = {com.jacobtodd.thermalwatch.helper: true}`
    - `AssociatedBundleIdentifiers = [com.jacobtodd.thermalwatch]`
  - **Makefile targets:**
    - `test`
    - `build`
    - `install`: Release build, then `ditto` to `/Applications/ThermalWatch.app`
    - `run`: `open /Applications/ThermalWatch.app`
    - no `archive`
- [ ] **Step 2: Write the failing tests.**

```swift
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
```

- [ ] **Step 3: Run `make test`.** Expected: FAIL, because `SMC`, `SMCParam` and `fourCC` aren't defined.
- [ ] **Step 4: Implement `Shared/SMC.swift`.** Port it from `docs/spike/probe.swift` (`SMCParam`, `call`, `readKey`), keeping the 3 padding bytes. `write` uses command 6 with the size from command 9, and throws `callFailed` when `kr != 0` or `result != 0`.
- [ ] **Step 5: Run `make test`.** Expected: PASS (4 tests). Then run `make build`. Expected: succeeds, and `ThermalWatch.app/Contents/MacOS/ThermalWatchHelper` and `Contents/Library/LaunchDaemons/com.jacobtodd.thermalwatch.helper.plist` both exist in the build product.
- [ ] **Step 6: Commit.** Message: `feat: project skeleton and SMC access`.

### Task 2: CPU temperature from the core sensors

**Files:**
- Create: `Shared/CPUTemperature.swift`
- Create: `Tools/calibrate-sensors.sh`, a one-off script that runs a load and then reads the sensors
- Test: `Tests/CPUTemperatureTests.swift`

**Interfaces:**
- Consumes: `SMC.keys()`, `SMC.readFloat`.
- Produces:
  - `struct CPUTemperature: Equatable, Sendable { let average: Double; let hottest: Double }`
  - `enum CPUSensors { static let corePrefixes: [String] }`
  - `static func isCoreKey(_ key: String) -> Bool`
  - `static func temperature(from readings: [String: Float]) -> CPUTemperature?`. Drop readings outside 10–120°C. Return nil if no core keys remain.
  - `final class TemperatureReader`, with:
    - `init(smc: SMC)`, which caches the core keys once from `smc.keys()`
    - `func read() -> CPUTemperature?`

- [ ] **Step 1: Calibrate.**
  1. Write `Tools/calibrate-sensors.sh`. It builds and runs a `T*` dump based on `docs/spike/probe.swift`, saves it as `idle.txt`, starts 18 × `yes > /dev/null` for 30 s, dumps the sensors again to `load.txt`, kills the load, and prints keys sorted by rise.
  2. Run it.
  3. Expected: one family, probably `Tp`, rises by 15°C or more under load while `TB*`/`TD*` stay flat. Record the families that rose in `corePrefixes`, and paste the top of the output into the commit message.
  4. If more than one CPU family rises (for example `Tp` and `Te`), include all of them.
- [ ] **Step 2: Write the failing tests.** Use the confirmed prefix, shown here as `Tp`.

```swift
struct CPUTemperatureTests {
    @Test func averagesAndFindsHottestCoreOnly() {
        let t = CPUSensors.temperature(from: ["Tp00": 60, "Tp04": 64, "TB0T": 36, "TD00": 29])
        #expect(t == CPUTemperature(average: 62, hottest: 64))
    }
    @Test func ignoresImplausibleReadings() {
        #expect(CPUSensors.temperature(from: ["Tp00": 60, "Tp04": 0, "Tp08": 150])?.average == 60)
    }
    @Test func noCoreReadingsGivesNil() {
        #expect(CPUSensors.temperature(from: ["TB0T": 36]) == nil)
        #expect(CPUSensors.temperature(from: [:]) == nil)
    }
}
```

- [ ] **Step 3: Run `make test`.** Expected: the 3 new tests FAIL.
- [ ] **Step 4: Implement** `CPUSensors` and `TemperatureReader` in `Shared/CPUTemperature.swift`.
- [ ] **Step 5: Run `make test`.** Expected: PASS.
- [ ] **Step 6: Commit.** Message: `feat: CPU temperature from calibrated core sensors`, with the calibration output in the body.

### Task 3: CPU load and process sampling

**Files:**
- Create: `App/Sampling/CPULoad.swift`
- Create: `App/Sampling/ProcessSampler.swift`
- Test: `Tests/SamplingTests.swift`

**Interfaces:**
- Produces:
  - `struct CoreTicks: Sendable { var user, system, idle, nice: UInt64 }`
  - `enum CPULoad { static func load(previous: [CoreTicks], current: [CoreTicks]) -> Double? }`. Returns 0...1 overall, or nil if the core counts differ or no time has passed.
  - `static func readTicks() -> [CoreTicks]`, from `host_processor_info`
  - `struct ProcessSample: Sendable { let pid: pid_t; let name: String; let startTime: UInt64; let cpuTimeNs: UInt64 }`
  - `struct ProcessUsage: Identifiable, Sendable { let pid: pid_t; let name: String; let cpuPercent: Double /* 100 = one core */; var id: pid_t { pid } }`
  - `enum ProcessSampler`, with:
    - `static func sample() -> [ProcessSample]`. Uses `proc_listallpids` + `PROC_PIDTASKINFO`, converts Mach time via `mach_timebase_info`, takes `startTime` from `PROC_PIDTBSDINFO` `pbi_start_tvsec`, and skips processes it can't read.
    - `static func usage(previous: [ProcessSample], current: [ProcessSample], intervalNs: UInt64) -> [ProcessUsage]`. Sorted by CPU, descending.

- [ ] **Step 1: Write the failing tests.**

```swift
struct SamplingTests {
    @Test func overallLoadAcrossCores() {
        let a = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0), .init(user: 0, system: 0, idle: 0, nice: 0)]
        let b = [CoreTicks(user: 50, system: 25, idle: 25, nice: 0), .init(user: 0, system: 0, idle: 100, nice: 0)]
        #expect(CPULoad.load(previous: a, current: b) == 0.375)
    }
    @Test func loadIsNilWhenCoreCountChangesOrNoTimePassed() {
        #expect(CPULoad.load(previous: [], current: [.init(user: 1, system: 0, idle: 0, nice: 0)]) == nil)
        let a = [CoreTicks(user: 5, system: 0, idle: 5, nice: 0)]
        #expect(CPULoad.load(previous: a, current: a) == nil)
    }
    @Test func processPercentIsPerCore() {
        let p = [ProcessSample(pid: 10, name: "Logic Pro", startTime: 1, cpuTimeNs: 0)]
        let c = [ProcessSample(pid: 10, name: "Logic Pro", startTime: 1, cpuTimeNs: 1_500_000_000)]
        #expect(ProcessSampler.usage(previous: p, current: c, intervalNs: 1_000_000_000).first?.cpuPercent == 150)
    }
    @Test func exitedOrReusedPidIsSkipped() {
        let p = [ProcessSample(pid: 10, name: "old", startTime: 1, cpuTimeNs: 9_000_000_000),
                 ProcessSample(pid: 11, name: "gone", startTime: 1, cpuTimeNs: 0)]
        let c = [ProcessSample(pid: 10, name: "new", startTime: 2, cpuTimeNs: 1_000)]
        #expect(ProcessSampler.usage(previous: p, current: c, intervalNs: 1_000_000_000).isEmpty)
    }
}
```

- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement both files.** `usage` matches processes by `(pid, startTime)`, drops negative deltas and new PIDs, and excludes ThermalWatch's own PID.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat: CPU load and per-process sampling`.

### Task 4: Live monitor and menu bar text

**Files:**
- Create: `App/Monitor/SystemMonitor.swift`
- Create: `App/Monitor/History.swift`
- Create: `App/Monitor/Formatting.swift`
- Create: `App/Monitor/ChipInfo.swift`
- Modify: `App/ThermalWatchApp.swift`
- Test: `Tests/MonitorTests.swift`

**Interfaces:**
- Consumes: `SMC`, `TemperatureReader`, `CPULoad`, `ProcessSampler`, `FanKey`.
- Produces:
  - `struct FanReading: Sendable { let rpm: Double; let min: Double; let max: Double }`
  - `struct Snapshot: Sendable { let date: Date; let temperature: CPUTemperature?; let load: Double?; let fans: [FanReading] }`
  - `struct History { init(capacity: Int); mutating func append(_ s: Snapshot); var items: [Snapshot] }`. A ring buffer with capacity `120`: 10 min at 5 s.
  - `@MainActor @Observable final class SystemMonitor`, with:
    - `var latest: Snapshot?`
    - `var history: History`
    - `var topProcesses: [ProcessUsage]` (top 5)
    - `var popoverOpen: Bool`. Its `didSet` switches the interval between 2 s and 5 s and samples immediately on open.
    - `func start()`
  - `enum Formatting`, with:
    - `static func temperature(_ c: Double?, fahrenheit: Bool) -> String`: `"58°"`, or `"—°"` for nil
    - `static func menuBarTitle(temperature: Double?, load: Double?, showLoad: Bool, fahrenheit: Bool) -> String`
  - `enum ChipInfo { static var chipName: String /* machdep.cpu.brand_string */; static var modelName: String; static var powerSource: String /* "on power adapter" | "on battery" via IOPSCopyPowerSourcesInfo */ }`

- [ ] **Step 1: Write the failing tests.**

```swift
struct MonitorTests {
    @Test func menuBarTitleTemperatureOnlyByDefault() {
        #expect(Formatting.menuBarTitle(temperature: 58.4, load: 0.33, showLoad: false, fahrenheit: false) == "58°")
    }
    @Test func menuBarTitleWithLoad() {
        #expect(Formatting.menuBarTitle(temperature: 58.4, load: 0.33, showLoad: true, fahrenheit: false) == "58° · 33%")
    }
    @Test func menuBarTitleWithoutTemperature() {
        #expect(Formatting.menuBarTitle(temperature: nil, load: nil, showLoad: true, fahrenheit: false) == "—° · —%")
    }
    @Test func fahrenheit() { #expect(Formatting.temperature(100, fahrenheit: true) == "212°") }
    @Test func historyKeepsNewest120() {
        var h = History(capacity: 120)
        for i in 0..<130 { h.append(Snapshot(date: .init(timeIntervalSince1970: Double(i)), temperature: nil, load: nil, fans: [])) }
        #expect(h.items.count == 120); #expect(h.items.first?.date.timeIntervalSince1970 == 10)
    }
}
```

- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement the files.**
  - `SystemMonitor` does its I/O off the main actor in a private `Sampler` actor that owns the `SMC` and `TemperatureReader`. It publishes results on the main actor.
  - Process sampling runs only while the popover is open, and also every 60 s while it's closed so Task 5's warnings can keep their 10-minute windows. The builder may tune that rate within the CPU budget.
  - `ThermalWatchApp` uses `MenuBarExtra { PopoverPlaceholder } label: { Text(Formatting.menuBarTitle(...)) }` with `.menuBarExtraStyle(.window)`. It reads `@AppStorage("showLoadInMenuBar")` and `@AppStorage("useFahrenheit")`.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Run `make install run`.** Expected: the menu bar shows a temperature such as `57°` that changes within 5 s of `yes > /dev/null &` × 18 starting (kill them afterwards).
- [ ] **Step 6: Check the CPU budget.** Close the popover, wait 30 s, then run `ps -o %cpu= -p $(pgrep -x ThermalWatch)` every 5 s for 60 s. Expected: average < 1.0.
- [ ] **Step 7: Commit.** Message: `feat: live system monitor and menu bar temperature`.

### Task 5: The popover UI

**Files:**
- Create: `App/Views/PopoverView.swift`
- Create: `App/Views/GaugeRing.swift`
- Create: `App/Views/FanView.swift`
- Create: `App/Views/HistoryChart.swift`
- Create: `App/Views/ProcessListView.swift`
- Create: `App/Views/WarningsView.swift`
- Create: `App/Monitor/BackgroundWarnings.swift`
- Modify: `App/Monitor/SystemMonitor.swift` (add `warnings`, `ignore(_:)` and `quit(_:)`)
- Modify: `App/ThermalWatchApp.swift`
- Test: `Tests/WarningsTests.swift`, `Tests/FanViewTests.swift`

**Interfaces:**
- Consumes: `SystemMonitor`, `Snapshot`, `ProcessUsage`, `ChipInfo`, `Formatting`.
- Produces:
  - `struct BusyWarning: Identifiable, Equatable { let pid: pid_t; let name: String; let busySince: Date; let isGUIApp: Bool; var id: pid_t { pid } }`
  - `struct WarningTracker`, with:
    - `var ignored: Set<String>`, which holds names
    - `mutating func update(usage: [ProcessUsage], frontmostPID: pid_t?, guiPIDs: Set<pid_t>, now: Date) -> [BusyWarning]`. Uses a 10-min sliding average per `(pid, name)`, the ≥25% threshold and frontmost exclusion, sorts by `busySince`, and returns at most 3.
  - `enum FanAnimation { static func spinPeriod(rpm: Double, max: Double) -> Double? }`. Returns seconds per turn, or nil (no spin) when rpm ≤ 0. The rate is proportional to rpm/max: 0.4 s at max, 3 s at the minimum fan speed.
  - `SystemMonitor.warnings: [BusyWarning]`, `func ignore(_ w: BusyWarning)`, `func quit(_ w: BusyWarning)`

- [ ] **Step 1: Write the failing tests.**

```swift
struct WarningsTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func logic(_ pct: Double) -> [ProcessUsage] { [ProcessUsage(pid: 42, name: "Logic Pro", cpuPercent: pct)] }

    @Test func busyBackgroundAppWarnsAfter10Minutes() {
        var w = WarningTracker()
        for m in 0..<10 { #expect(w.update(usage: logic(47), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
        let out = w.update(usage: logic(47), frontmostPID: 1, guiPIDs: [42], now: t0 + 600)
        #expect(out.map(\.name) == ["Logic Pro"]); #expect(out.first?.isGUIApp == true)
    }
    @Test func frontmostAppNeverWarns() {
        var w = WarningTracker()
        for m in 0...11 { #expect(w.update(usage: logic(90), frontmostPID: 42, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func belowThresholdNeverWarns() {
        var w = WarningTracker()
        for m in 0...11 { #expect(w.update(usage: logic(20), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func ignoredAppIsMuted() {
        var w = WarningTracker(); w.ignored = ["Logic Pro"]
        for m in 0...11 { #expect(w.update(usage: logic(90), frontmostPID: 1, guiPIDs: [42], now: t0 + Double(m * 60)).isEmpty) }
    }
    @Test func atMostThreeWarnings() {
        var w = WarningTracker()
        let many = (1...5).map { ProcessUsage(pid: pid_t($0), name: "p\($0)", cpuPercent: 50) }
        var out: [BusyWarning] = []
        for m in 0...10 { out = w.update(usage: many, frontmostPID: 99, guiPIDs: [], now: t0 + Double(m * 60)) }
        #expect(out.count == 3)
    }
}
struct FanViewTests {
    @Test func fanSpinPeriodForZeroRpm() { #expect(FanAnimation.spinPeriod(rpm: 0, max: 7826) == nil) }
    @Test func fanSpinsFasterAtHigherRpm() {
        #expect(FanAnimation.spinPeriod(rpm: 7826, max: 7826)! < FanAnimation.spinPeriod(rpm: 2317, max: 7826)!)
    }
}
```

- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement `WarningTracker` and `FanAnimation`, then wire `warnings` into `SystemMonitor`.** Get the frontmost app and GUI PIDs from `NSWorkspace.shared`. `quit` calls `NSRunningApplication(processIdentifier:)?.terminate()`, and only for `isGUIApp`.
- [ ] **Step 4: Build the views to match `docs/spike/popover-mockup.html`.** Its menu bar strip is outdated: the menu bar is text only. Layout:
  1. Header: `ChipInfo.chipName` in bold, then `"\(modelName) · \(powerSource)"` in secondary text
  2. An `HStack` with two `GaugeRing`s (temperature on 0–100°C, orange, captioned "CPU temp · hottest 64°" using `CPUTemperature.hottest`; load on 0–1, green; the value animates with `.animation(.easeOut, value:)`) and a `FanView`. The fan is SF Symbol `fan.fill`, rotated by a `TimelineView(.animation)` using `FanAnimation.spinPeriod`, captioned with RPM. With two fans, show the average and both RPMs in the caption.
  3. A "Last 10 minutes" `HistoryChart`: Swift Charts `LineMark`s for temperature (°C), load (×100) and fan (as % of max), with the y-axis on 0–100.
  4. A "Using your chip" `ProcessListView` (icon + name + `%`; above 50% shows in orange)
  5. `WarningsView` with "Quit" (GUI apps only) and "Ignore" buttons
  6. A footer with a Settings… button (the target comes in Task 7) and Quit ThermalWatch
  The popover is about 340 pt wide. `onAppear` and `onDisappear` set `monitor.popoverOpen`.
- [ ] **Step 5: Run `make test`.** Expected: PASS.
- [ ] **Step 6: Run `make install run`, open the popover and take a screenshot.** Run `screencapture -x popover.png` (into a scratch folder), then look at it.
  - Expected: every section is present, the fan spins and the gauges are filled.
  - Start `yes > /dev/null` × 6 in the background. Within 5 s that process shows in "Using your chip". Kill them afterwards.
  - Re-run Task 4 Step 6 (closed-popover CPU < 1%).
- [ ] **Step 7: Commit.** Message: `feat: popover with gauges, fan, history chart, processes and warnings`.

### Task 6: Fan-safety logic and the root helper

**Files:**
- Create: `Shared/FanSafety.swift`, with the pure floor curve and the helper state machine
- Create: `Shared/HelperProtocol.swift`
- Modify: `Helper/main.swift`
- Create: `Helper/HelperService.swift`, the XPC listener plus the I/O around `FanSafety`
- Test: `Tests/FanSafetyTests.swift`

**Interfaces:**
- Consumes: `SMC`, `FanKey`, `TemperatureReader`, `CPUTemperature`.
- Produces:
  - `enum BoostLevel: Int, Codable, Sendable, CaseIterable { case auto = 0, medium, high, max }`
  - `struct FanLimits: Sendable, Equatable { let min: Double; let max: Double }`
  - `enum FanCurve`, with:
    - `static func floor(temperature: Double, limits: FanLimits) -> Double`
    - `static func target(level: BoostLevel, limits: FanLimits, rpmAtTakeover: Double, temperature: CPUTemperature) -> Double`
  - `enum FanCommand: Equatable { case none, auto, manual([Double]) /* one target per fan */ }`
  - `struct FanSafetyState`, with:
    - `init(limits: [FanLimits])`
    - `var level: BoostLevel`
    - `mutating func handle(_ e: FanEvent, now: Date) -> FanCommand`
  - `enum FanEvent { case started, setLevel(BoostLevel, currentRPM: [Double]), heartbeat, tick(CPUTemperature?), clientDisconnected, willSleep }`
  - `@objc protocol FanHelperProtocol { func setBoost(_ level: Int, reply: @escaping (String?) -> Void); func heartbeat(); func ping(reply: @escaping (Int) -> Void) }`
  - `enum HelperConstants { static let machService = "com.jacobtodd.thermalwatch.helper"; static let plistName = "com.jacobtodd.thermalwatch.helper.plist"; static let version = 1; static let clientRequirement: String }`. The requirement is `identifier "com.jacobtodd.thermalwatch" and anchor apple generic and certificate leaf[subject.OU] = "URYTQJBX8K"`.

The state machine's rules (this is the algorithm, implemented in `handle`):

```
started / clientDisconnected / willSleep → level = .auto; return .auto
setLevel(.auto, _)                        → level = .auto; return .auto
setLevel(l, rpm)                          → if previously .auto: rpmAtTakeover = rpm; level = l; lastHeartbeat = now
                                            return .none   (the next tick applies the targets)
heartbeat                                 → lastHeartbeat = now; return .none
tick(_)    when level == .auto            → .none
tick(_)    when now - lastHeartbeat > 10s → level = .auto; return .auto
tick(nil)                                 → level = .auto; return .auto       (blind: let macOS decide)
tick(t)                                   → .manual(per fan: FanCurve.target(level, limits[i], rpmAtTakeover[i], t))
FanCurve.target = hottest >= 95 ? max : max(levelRPM, rpmAtTakeover, floor(average)), clamped to [min, max]
levelRPM: medium 0.60·max, high 0.80·max, max max
```

- [ ] **Step 1: Write the failing tests.**

```swift
struct FanSafetyTests {
    let lim = FanLimits(min: 2317, max: 7826)
    let t0 = Date(timeIntervalSince1970: 0)
    func cool(_ avg: Double = 55, hottest: Double = 60) -> CPUTemperature { .init(average: avg, hottest: hottest) }

    @Test func floorCurve() {
        #expect(FanCurve.floor(temperature: 60, limits: lim) == 2317)
        #expect(FanCurve.floor(temperature: 75, limits: lim) == 5071.5)
        #expect(FanCurve.floor(temperature: 95, limits: lim) == 7826)
    }
    @Test func levelTargets() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 4695.6)
        #expect(FanCurve.target(level: .high, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 6260.8)
        #expect(FanCurve.target(level: .max, limits: lim, rpmAtTakeover: 2300, temperature: cool()) == 7826)
    }
    @Test func neverBelowTakeoverOrTemperatureFloor() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 5000, temperature: cool()) == 5000)
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool(85, hottest: 88)) > 6900)
    }
    @Test func hottestAt95GoesMax() {
        #expect(FanCurve.target(level: .medium, limits: lim, rpmAtTakeover: 2300, temperature: cool(70, hottest: 95)) == 7826)
    }
    @Test func zeroRpmAtTakeoverStillAtLeastMinimum() {
        #expect(FanCurve.target(level: .medium, limits: FanLimits(min: 5000, max: 7826), rpmAtTakeover: 0, temperature: cool()) >= 5000)
    }
    @Test func startAndSleepAndDisconnectAllForceAuto() {
        var s = FanSafetyState(limits: [lim, lim])
        #expect(s.handle(.started, now: t0) == .auto)
        for e in [FanEvent.willSleep, .clientDisconnected] {
            _ = s.handle(.setLevel(.high, currentRPM: [2300, 2500]), now: t0)
            #expect(s.handle(e, now: t0) == .auto); #expect(s.level == .auto)
        }
    }
    @Test func tickAppliesPerFanTargets() {
        var s = FanSafetyState(limits: [lim, lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300, 6500]), now: t0)
        #expect(s.handle(.tick(cool()), now: t0 + 2) == .manual([6260.8, 6500]))
    }
    @Test func watchdogReturnsToAutoAfter10s() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.max, currentRPM: [2300]), now: t0)
        _ = s.handle(.heartbeat, now: t0 + 8)
        #expect(s.handle(.tick(cool()), now: t0 + 17) != .auto)
        #expect(s.handle(.tick(cool()), now: t0 + 18.1) == .auto)
    }
    @Test func missingTemperatureHandsBackToAuto() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300]), now: t0)
        #expect(s.handle(.tick(nil), now: t0 + 2) == .auto)
    }
    @Test func boostIsNotRestoredAfterTimeout() {
        var s = FanSafetyState(limits: [lim])
        _ = s.handle(.setLevel(.high, currentRPM: [2300]), now: t0)
        _ = s.handle(.tick(cool()), now: t0 + 11)
        _ = s.handle(.heartbeat, now: t0 + 12)
        #expect(s.handle(.tick(cool()), now: t0 + 13) == .none)
    }
}
```

- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement `Shared/FanSafety.swift` and `Shared/HelperProtocol.swift`.** Compare doubles in tests within 0.01, or round targets to 0.1 rpm.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Implement the helper.**
  - `main.swift` creates an `NSXPCListener(machServiceName:)` whose delegate calls `connection.setCodeSigningRequirement(HelperConstants.clientRequirement)`, exports `FanHelperProtocol`, and sets `invalidationHandler`/`interruptionHandler` → `.clientDisconnected`.
  - `HelperService` owns the `SMC`, `TemperatureReader` and `FanSafetyState`, all on one serial `DispatchQueue`.
  - It feeds `.started` at launch.
  - It runs a 2 s `.tick(reader.read())` timer.
  - It registers `IORegisterForSystemPower` and feeds `.willSleep` on `kIOMessageSystemWillSleep` before calling `IOAllowPowerChange`.
  - It applies commands: `.auto` writes `F{i}md=0` for each fan. `.manual(t)` writes `F{i}md=1` followed by `F{i}Tg=Float(t[i])`.
  - `setBoost` reads `F{i}Ac` for `currentRPM`.
  - It logs through `os.Logger(subsystem: "com.jacobtodd.thermalwatch.helper", category: "fan")`.
- [ ] **Step 6: Smoke-test the helper binary directly.**
  1. Run `make build`.
  2. Open a Terminal window via `osascript` running `sudo <build>/ThermalWatch.app/Contents/MacOS/ThermalWatchHelper`, as the spike did. The user enters their password.
  3. Run `log show --last 1m --predicate 'subsystem == "com.jacobtodd.thermalwatch.helper"'`. Expected: a "started → auto" line. `docs/spike/allf` (rebuild it from `allf.swift`) shows `F0md` = 00.
  4. Stop it with Ctrl-C in that window.
- [ ] **Step 7: Commit.** Message: `feat: fan-safety state machine and root helper`.

### Task 7: Boost control, auto-boost and settings in the app

**Files:**
- Create: `App/Fan/FanHelperClient.swift`
- Create: `App/Fan/AutoBoost.swift`
- Create: `App/Views/BoostControl.swift`
- Create: `App/Views/SettingsView.swift`
- Modify: `App/Views/PopoverView.swift` (add `BoostControl` under the gauges)
- Modify: `App/ThermalWatchApp.swift` (add a `Settings` scene, and register launch at login on first launch)
- Test: `Tests/AutoBoostTests.swift`

**Interfaces:**
- Consumes: `BoostLevel`, `FanHelperProtocol`, `HelperConstants`, `SystemMonitor.latest`.
- Produces:
  - `enum HelperStatus: Equatable { case notRegistered, needsApproval, enabled, unavailable(String) }`
  - `static func HelperStatus.from(_ s: SMAppService.Status) -> HelperStatus`
  - `@MainActor @Observable final class FanHelperClient`, with:
    - `var status: HelperStatus`
    - `var level: BoostLevel` (what the user or auto-boost last asked for)
    - `func enable()`, which calls `register()` and opens Login Items settings if approval is needed
    - `func set(_ level: BoostLevel)`
    - It sends a heartbeat every 3 s while `level != .auto` and reconnects on interruption.
  - `struct AutoBoostPolicy`, with:
    - `var threshold: Double`
    - `var manualOverride: BoostLevel?`
    - `mutating func update(temperature: Double?, now: Date) -> BoostLevel`
  - Settings reads the `@AppStorage` keys from Global Constraints, plus a "Launch at login" toggle bound to `SMAppService.mainApp`.

- [ ] **Step 1: Write the failing tests.**

```swift
import ServiceManagement
struct AutoBoostTests {
    let t0 = Date(timeIntervalSince1970: 0)
    @Test func kicksInAfter15sAtThreshold() {
        var p = AutoBoostPolicy(threshold: 80)
        #expect(p.update(temperature: 81, now: t0) == .auto)
        #expect(p.update(temperature: 82, now: t0 + 14) == .auto)
        #expect(p.update(temperature: 82, now: t0 + 15) == .high)
    }
    @Test func dipResetsTheTimer() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: 81, now: t0); _ = p.update(temperature: 79, now: t0 + 10)
        #expect(p.update(temperature: 81, now: t0 + 20) == .auto)
    }
    @Test func releasesAfter60sAt10Below() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: 85, now: t0); _ = p.update(temperature: 85, now: t0 + 15)
        #expect(p.update(temperature: 70, now: t0 + 20) == .high)
        #expect(p.update(temperature: 72, now: t0 + 79) == .high)   // 72 > 70: release timer resets
        #expect(p.update(temperature: 70, now: t0 + 80) == .high)
        #expect(p.update(temperature: 69, now: t0 + 140) == .auto)
    }
    @Test func manualOverrideWins() {
        var p = AutoBoostPolicy(threshold: 80); p.manualOverride = .max
        #expect(p.update(temperature: 50, now: t0) == .max)
    }
    @Test func unknownTemperatureNeverBoosts() {
        var p = AutoBoostPolicy(threshold: 80)
        _ = p.update(temperature: nil, now: t0)
        #expect(p.update(temperature: nil, now: t0 + 30) == .auto)
    }
    @Test func helperStatusMapping() {
        #expect(HelperStatus.from(.notRegistered) == .notRegistered)
        #expect(HelperStatus.from(.requiresApproval) == .needsApproval)
        #expect(HelperStatus.from(.enabled) == .enabled)
        #expect(HelperStatus.from(.notFound) != .enabled)
    }
}
```

- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement `AutoBoostPolicy`, `HelperStatus` and `FanHelperClient`.** The client uses `NSXPCConnection(machServiceName:options: .privileged)` with `setCodeSigningRequirement` for the helper's identifier `com.jacobtodd.thermalwatch.helper` plus the same team requirement. On `NSApplication.willTerminateNotification`, synchronously send `setBoost(0)` (use `synchronousRemoteObjectProxyWithErrorHandler`) so quitting returns the fans to Auto immediately rather than waiting for the 10 s watchdog.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Build the UI.**
  - `BoostControl` shows a segmented `Picker` (Auto · Medium · High · Max) when `status == .enabled`. Otherwise it shows a "Enable fan control…" button that calls `enable()`, with a caption explaining the Login Items approval.
  - Picking a level sets `manualOverride` (nil for Auto) and calls `client.set`.
  - When auto-boost is enabled, `SystemMonitor`'s tick runs `policy.update` with the average temperature and calls `client.set` when the result changes. Show "Auto-boost active" under the picker when that's what's driving it.
  - `SettingsView` is a small `Form` with:
    - show load in menu bar
    - °C/°F
    - launch at login
    - auto-boost on/off
    - threshold `Stepper` 60–95, step 5
  - The popover's "Settings…" opens it with `SettingsLink`.
  - On first launch, call `SMAppService.mainApp.register()` once, tracked by `@AppStorage("didRegisterLogin")`.
- [ ] **Step 6: Commit.** Message: `feat: boost control, auto-boost and settings`.

### Task 8: End-to-end check on the real Mac

**Files:**
- Create: `docs/VERIFY.md`, a checklist with the results recorded

- [ ] **Step 1: Install and approve.** Run `make install run`. Click "Enable fan control…" and approve it in System Settings → Login Items (the user does this step). Expected: the boost picker appears.
- [ ] **Step 2: Manual boost.** Pick Max. Expected: the popover fan RPM reaches about 7,800 within 5 s and the fan spins faster. Pick Auto. Expected: back to about 2,300 within 5 s.
- [ ] **Step 3: Crash safety.** Pick High, then `kill -9 $(pgrep -x ThermalWatch)`. Within 15 s, run `docs/spike/allf | grep -E 'F[01](md|Ac)'`. Expected: `F0md`/`F1md` = 00 and RPM back near idle.
- [ ] **Step 4: Sleep safety.** Relaunch and pick High, then run `pmset sleepnow`. Wake the Mac. Expected: the fans are on Auto (`F0md` = 00), and the picker shows Auto.
- [ ] **Step 5: Quit safety.** Pick Medium, then choose Quit ThermalWatch from the popover. Expected: the fans are on Auto within 10 s. Expected to be near-instant because of Task 7's quit hook.
- [ ] **Step 6: Auto-boost.** Turn on auto-boost at threshold 60 (for testing). Start `yes > /dev/null` × 18. Expected: within about 20 s of crossing 60°C the picker shows "Auto-boost active" and the RPM rises. Kill the load. Expected: back to Auto about 60 s after it drops below 50°C. Set the threshold back to 80.
- [ ] **Step 7: Budget and warnings.** Re-run the closed-popover CPU check (< 1%). Leave Logic Pro open and busy in the background for 10 min. Expected: a "Logic Pro has been busy…" warning appears with Quit and Ignore, and Ignore removes it.
- [ ] **Step 8: Record the results in `docs/VERIFY.md` and commit.** Message: `docs: end-to-end verification results`.
