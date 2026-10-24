# ThermalWatch: design

*2026-10-25. "ThermalWatch" is a placeholder name.*

## Why

Jacob's new MacBook Pro (Apple M5 Pro, Mac17,9, macOS 27.0.1) felt surprisingly hot and its battery drained quickly while he was developing apps. A scan of the machine showed it wasn't overheating (macOS had recorded no thermal warnings). Background work was keeping the chip busy:

- Photos media analysis at about 107% CPU
- Logic Pro at about 47% while idle, with 7 hours of CPU time
- Logitech G Hub updater and agent at about 20%
- Amphetamine, caffeinate and Xcode stopping the Mac from sleeping

He wants a menu bar app that shows, live and with animation, how hot the Mac is, what the fans are doing and what's causing the heat. He also wants to be able to push the fans up when he chooses, or automatically when it gets hot, which was his original "kick the fan in" request.

## Goals

1. Show the CPU temperature, overall CPU load and fan speed at a glance, with animation.
2. Show *why* the Mac is warm: the processes using the most CPU, and warnings about apps that stay busy while he isn't using them.
3. Manual fan boost, plus an optional automatic boost above a temperature he sets.
4. Stay light on resources. A monitor that drains the battery defeats the point.

## Non-goals

- **App Store distribution.** It's for Jacob's own use only. Research and testing showed a sandboxed App Store build can't read the fans, the temperatures or other processes. That's why there's no sandbox, and private SMC access is fine.
- GPU, memory, network or disk monitoring.
- History beyond the last 10 minutes, or logging to disk.
- Supporting other Macs. It should work on other Apple Silicon Macs, but only this M5 Pro has to work.

## Anti-goals (would make it a failure even if it works)

- **The fans get stuck** in manual mode after a quit, crash or sleep.
- **The fans run slower** than macOS would run them. Boost must only ever add cooling.
- **The app itself is a noticeable CPU or battery load.**
- **The animation lies.** For example, the popover fan spinning while the real fans are off.
- **Budget:** keep average CPU under about 1% while the popover is closed.

## Constraints and verified facts

All of these were tested on Jacob's Mac on 2026-10-25. The spike code is in `docs/spike/`.

**SMC access (fans and temperatures)**
- Opening the `AppleSMC` service and calling `IOConnectCallStructMethod` with selector 2 works **without root** when the app is not sandboxed.
- **Gotcha:** in Swift, the `SMCKeyData_t` struct must be exactly **80 bytes**. Swift packs following fields into the tail padding of the nested `keyInfo` struct, which makes it 76 bytes and makes every call fail with `0xe00002c2`. Add 3 explicit padding bytes after `dataAttributes`. See `docs/spike/probe.swift`.
- Commands: 9 = key info, 5 = read bytes, 6 = write bytes, 8 = key name by index. Total key count is in `#KEY` (3,611 on this Mac).

**Fans**
- `FNum` = 2 fans.
- `F0Ac`/`F1Ac` (type `flt`) = actual RPM. About 2,300–2,500 at idle.
- `F0Mn` = 2,317 (minimum) and `F0Mx` = 7,826 (maximum).
- The fans may stop entirely when cool (normal on Apple Silicon). The UI must handle 0 RPM.

**Fan control (M5 specific)**
- The manual-mode key is lowercase **`F0md`/`F1md`** (`ui8`). Uppercase `F0Md` and the M1-era `Ftst` unlock key **don't exist** on this machine.
- Write `F0md=1`, then write target RPM to `F0Tg` (`flt`).
- Return to automatic with `F0md=0`.
- Writes need **root**. Without it they fail with `0xe00002c1` (not privileged).
- Test result: with a 70% target (5,478 rpm), both fans reached about 5,480 rpm within 4 seconds and held it. After returning to Auto, they were back at about 2,300 rpm within 1 second. See `docs/spike/fantest.log`.

**Temperatures**
- About 256 `T*` keys of type `flt` read sensible values (10–120°C).
- Families seen: `Tp**` (about 25 keys, around 59–61°C at moderate load), `Ts**`, `Tm**`, `Tg**`, `Te`/`TP`/`TR`/`TU` dies, and `TB*T` battery.
- **Which keys are CPU cores on M5 hasn't been confirmed.** My expectation, unverified: `Tp**` are performance cores.

**CPU load and processes**
- `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` works and reports 18 cores.
- `proc_listallpids` + `proc_pidinfo(PROC_PIDTASKINFO)` work unsandboxed. About 800 of 1,000 processes are readable as a normal user; root-owned ones like `kernel_task` aren't, which is acceptable.
- `pti_total_user` and `pti_total_system` are in Mach time units. Convert them with `mach_timebase_info` on Apple Silicon.

**Platform**
- Personal build, signed with Jacob's team `URYTQJBX8K`.
- Follow the DiscPop conventions: XcodeGen `project.yml`, Swift 6, `LSUIElement` menu bar app, bundle prefix `com.jacobtodd`. The deployment target can be macOS 27, since it only runs here.
- **No App Sandbox.** Hardened runtime is fine.

## What Jacob decided

**Menu bar**
- **Text only, no icon:** the CPU temperature, e.g. `58°`. Jacob dropped the menu bar icon, so nothing animates in the menu bar and the closed app stays cheap.
- **CPU load in the menu bar is off by default**, with a setting to turn it on (`58° · 33%`).

**Popover, top to bottom.** See `docs/spike/popover-mockup.html` for the agreed look. Its menu bar strip still shows load, which is now off by default.
1. A heading with the chip name ("Apple M5 Pro"), and a line underneath with the Mac model and power source.
2. Three items side by side:
   - a CPU temperature ring gauge
   - an overall CPU load ring gauge
   - a spinning fan with its RPM
   All animate as values change.
3. A live graph of the last 10 minutes, with temperature, load and fan speed as three lines scrolling continuously.
4. "Using your chip": the top processes by CPU %.
5. Warnings about apps that stay busy in the background, e.g. "Logic has been busy for 2h while you weren't using it."

**Fan boost**
- Included in v1, with a manual control and an optional auto-boost.
- Safety rules: boost-only (never below what macOS would choose) and always return to Auto on quit, sleep or crash.

## My calls (Claude), which Jacob can override

**Readings**
- **CPU temperature number:** the average of the CPU-core sensor keys. The builder must confirm which keys those are on M5 by loading the CPU (e.g. `yes > /dev/null` × 18) and watching which keys rise. Show the hottest core as secondary text.
- **Refresh rate:** every 2 s while the popover is open and every 5 s while it's closed.
- **Graph:** an in-memory ring buffer covering 10 minutes at the closed-popover rate. Use Swift Charts.

**Processes and warnings**
- **Top processes:** the top 5 by CPU % over the last sample interval. Use the app name and icon for GUI apps (match against `NSRunningApplication`) and the process name otherwise.
- **"Busy in the background" warning:** a GUI app that isn't frontmost and has averaged ≥25% CPU for ≥10 minutes. Background processes, like `lghub_updater`, qualify at the same thresholds.
- **Warning actions:**
  - "Quit" (graceful `terminate()`) for GUI apps only. Background processes get no kill button.
  - "Ignore" mutes that app's warnings until the next launch.
- At most 3 warnings are shown.

**Fan boost UI**
- A segmented control in the popover: **Auto · Medium (60%) · High (80%) · Max**, where the percentages are of `F*Mx`.
- Auto-boost settings: off by default; when on, the threshold defaults to 80°C.
  - Kick in when the CPU temperature has been at or above the threshold for 15 s, boosting to High.
  - Return to Auto once it has been at least 10°C below the threshold for 60 s.
  - A manual choice overrides auto-boost until you set it back to Auto.

**Fan boost safety**
- **Boost-only:** once `F*md=1` is set, macOS stops choosing a speed, so the helper has to keep providing "at least what macOS would do" for the whole boost, not just at the start.
  - The helper reads the CPU temperature itself, without trusting the app, and enforces a **temperature floor**: target = max(chosen level, the RPM at the moment it took control, floor(temp)).
  - floor(temp) runs linearly from `F*Mn` at 60°C to `F*Mx` at 90°C.
  - If the hottest CPU sensor reaches 95°C, go to Max.
  - This approximates macOS's curve conservatively, staying on the louder side. The builder may tune the curve by watching what Auto mode does under load.
- **After sleep or a helper timeout** puts the fans back in Auto, a manual boost does *not* come back on by itself. The control resets to Auto, and auto-boost decides again from scratch.
- **Privileged helper:** a small launchd daemon registered with `SMAppService.daemon(plistName:)`, approved once in System Settings → Login Items. It talks to the app over XPC and only accepts connections from the app's own code signature.
- **The helper owns the safety rules:**
  - Without a heartbeat from the app for 10 s, it returns to Auto.
  - It returns to Auto on system sleep.
  - It sets Auto when it starts, in case of a previous crash.
  - It returns to Auto if the XPC connection drops.
- **Monitoring needs no helper.** Reading the SMC is done in-process without root. The helper is only needed for writes, so the app is fully useful even if the helper isn't approved; the boost control just shows a "Enable fan control…" button.

**Settings window**
- Show CPU load in the menu bar (off).
- °C / °F.
- Launch at login (`SMAppService.mainApp`, on).
- Auto-boost on/off and its threshold.

**Install and naming**
- The app needs to live in `/Applications` for `SMAppService` daemons to work.
- Name it "ThermalWatch" for now. Jacob may rename it.

## Left to the builder

- Code structure, file layout and concurrency design, within Swift 6 strict concurrency.
- Animation implementation details (SwiftUI `TimelineView`, Core Animation, etc.) inside the popover, as long as the anti-goals above hold.
- How to name the chip and model. `machdep.cpu.brand_string` gives "Apple M5 Pro"; the friendly model name is up to you.
- Test scope: personal app, so keep it lean. Unit-test the pure logic (CPU % maths, warning rules, auto-boost hysteresis, boost-only clamping) and skip UI tests.
