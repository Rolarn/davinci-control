# How it works — Davinci Control for Mi 9T / Redmi K20 (davinci)

[Русский](how-it-works.md) · **English**

The module is a few shell scripts and a web panel. No apps and no libraries: everything it does is visible in the sources in [`module/`](../module).

## What it consists of

| File | What it does |
|---|---|
| `customize.sh` | Installation: checks the device (davinci only) and the Magisk version, edits a copy of the phone's own `powerhint.json`, reports whether the thermal configs match the tested ones. |
| `post-fs-data.sh` | On every boot, before the module is mounted, decides whether to replace the thermal configs. |
| `service.sh` | After boot starts the background service and restarts it if it crashes. |
| `daemon.sh` | The background service: charge limit, heat pause, current levels, frequencies, brightness, sessions and overnight drain. |
| `tune.sh` | Panel backend: JSON data, text report, log, setting commands. |
| `diag.sh` | Diagnostics into one file with personal data masked. |
| `uev.sh` | Listens to kernel events through BusyBox `uevent` and wakes the service when a cable is connected or unplugged. |
| `action.sh` | The Action button: opens the panel in WebUI X, KsuWebUI or MMRL. |
| `uninstall.sh` | Removal: restores charging, the current level and frequencies, deletes module data. |
| `strings.tsv` | All log messages in Russian and English. |
| `webroot/` | The panel: HTML, CSS and JavaScript without libraries, the mascot is SVG. |

## Charging

The davinci charging driver (`qpnp-smb5`) gives two levers:

1. **Turn charging on or off** — the files `battery_charging_enabled`, `charging_enabled` or `input_suspend`. The module writes a value, reads it back and after 20 seconds checks that the battery really stopped charging. If a method does not work, the next one is used.
2. **Current limit level.** The kernel exposes `charge_control_limit` in `/sys/class/power_supply/battery` as read-only — it cannot be written even with root. But the kernel accepts the same value through the "battery" cooling device (`/sys/class/thermal/cooling_deviceN/cur_state`) — the same lever the stock thermal protection uses. The module writes there and reads it back. Levels are 0–16; the last ones almost stop charging, so the module never sets more than 13. How much current each level allows comes from the device tree, and each charger type has its own table (`qcom,thermal-fcc-qc3-normal` for Quick Charge 3, `qcom,thermal-mitigation-dcp` for a plain charger and so on). Quick Charge 3 has two tables: when the SMB1390 charge pump turns on at high current, the kernel uses `qcom,thermal-fcc-qc3-cp`, and the same level numbers mean a different current: level 8 is no longer 2.7 A but 3.0 A. So the module picks levels by amps, not by numbers: it checks which table is in effect (charger type and `smb_en_reason`) and takes the first levels with a current of at most 89, 78 and 58% of the full one — for a fast charger that is about 3.1, 2.7 and 2.0 A. The panel shows the table in effect.

On top of that, hardware battery protection always works in the kernel (JEITA from the battery profile): from 15 to 45 °C up to 3.5 A and 4.4 V, from 45 to 58 °C up to 1.95 A and 4.1 V, above that charging stops. The module does not touch it.

### Modes

- **Care**: current by sensor temperature: from 41 °C about 3.1 A, from 43 °C 2.7 A, from 45 °C 2.0 A (for a fast charger). It relaxes a level only after cooling one more degree, to avoid jumping. Pause from 42 °C, resume at 38 °C.
- **Fast**: full current. If the sensor reaches 44.0 °C, current goes down to 2.7 A and then level by level to 2.0 A; below 42.5 °C it comes back. From 45 °C — straight to 2.0 A. This keeps the sensor just below 45 °C, where the kernel would cut current to 1.95 A. The pause is an emergency one, from 48 °C.

### Charge by time

If a time is set, the module holds the limit, then lifts it in advance and charges to 100% by that hour. The lead time is simple: 1.5 minutes per percent with a charger above 15 W and 3 minutes with a plain one, plus 10 minutes. After the cable is unplugged everything starts over.

### If the service crashes

The charging session is kept in a file and survives a reboot and a service restart. A supervisor restarts the service; if it crashes 20 times in a row, the supervisor turns charging on, lifts the current limit and leaves it alone — the phone keeps its stock behaviour.

The heat pause lasts at least 2 minutes: the sensor sits by the connector and cools fast without current.

### The “battery” sensor

It sits by the charging connector and the protection board. On fast charging it reads 6–11 °C more than the battery itself within a couple of minutes. So a “hot battery” with a cold body is normal.

### Thermal configs

The ROM (thermal-engine) cuts charging current when the body warms up, from about 34 °C, using tables in `/vendor/etc/thermal-*.conf`. The module carries its own copies of these files where the list of levels in the charging rule is zeroed and everything else (CPU frequencies on heat) is as in the ROM.

The copies are mounted only if **all six stock files match the tested ones byte for byte** — their SHA-256 sums are in `module/thermal/orig.sha256`. If even one differs, the module leaves them alone and the panel says “left as is”. This way the module cannot break a ROM it does not know. The panel switch applies after a reboot; the text under it says what is in effect now — checked against the files the system really sees.

On KernelSU file replacement works only with a metamodule (e.g. meta-overlayfs). Without it the panel says the files were not mounted.

## Kernel checks

On start the service looks at kernel parameters:

- `/sys/module/qpnp_smb5/parameters/disable_thermal` — when on, the kernel rejects current levels;
- `/sys/module/smb5_lib/parameters/skip_thermal` (VantomKernel) — when on, levels are accepted but have no effect.

In both cases Care and the hold do not work — the service writes this to the log and the panel shows a warning. The limit and the heat pause keep working.

## Drain in sleep

When the screen turns off unplugged, the service remembers the charge, the precise charge gauge (`bms/capacity_raw`, hundredths of a percent; `charge_counter` if it is missing), awake time (`/proc/timer_list`) and mobile and Wi-Fi traffic. When the screen turns on and more than 30 minutes have passed, it records a measurement: −%, mAh, average current, deep sleep, the share of traffic over mobile data and the number of active SIMs. From the measurements the panel builds the average current by week; if it went up by 30% and at least 10 mA over the last week — a warning.

The “Drain by hour” chart is built from the history the service writes every 5 minutes (less often in sleep — it never wakes the phone): the solid line is the average current for each hour of the last day, the dashed lines are the usual 7-day level with the screen on and in sleep.

## Diagnostics

The report takes about a minute. Each of the 12 steps runs in its own supervised process: if a kernel read never answers (such a read cannot be interrupted even by a signal), the step is abandoned, the file keeps a note of where it stopped, and collection goes on. System commands are limited to 10 seconds, and the file records how long each step took. If the diagnostics process is gone, the panel sees it and lets you start again. `/sys/power/wakeup_count` is deliberately not read: reading it waits until no wakeup source is active and can hang for minutes.

## Restarting the module

The “Restart the module” button (or `tune.sh restart`) stops the supervisor, the service and diagnostics and starts the service again without rebooting the phone. Before that a snapshot of the module's processes is recorded: the state of each and the place in the kernel where it waits — the snapshot goes into the log and diagnostics. Settings, the log, history and the current charging session are kept; during the restart charging is on and the current limit is lifted.

## Notifications and the app log

Both are off by default. Notifications are posted with `cmd notification post` as the system shell (shown as “Shell”). The app log records package names only, and only into the log on the phone.

## Where things live

- Settings and data: `/data/adb/davinci-control/` (root only, deleted with the module).
- Saved log and diagnostics: `/sdcard/Download/davinci-control/`, names like `davinci-control_v1.0.0_diag_2026-11-09_1630.txt`.

## Checks before a release

The test bench in [`tests/`](../tests) runs the service on fake `/sys` and `/proc` and checks scenarios: Care, Fast, limit, unplugging, overnight drain, JEITA delay, skip_thermal, dropping a charge switch, the current table with the charge pump on, a reboot in the middle of a charge, charge-by-time, notifications, broken settings, the failsafe, a stuck command in diagnostics, installation on different root managers, thermal config replacement and removal. The panel is checked in a browser at 400 and 1000 px in both languages.
