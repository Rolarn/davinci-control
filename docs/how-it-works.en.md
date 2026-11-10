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
2. **Current limit level.** The kernel exposes `charge_control_limit` in `/sys/class/power_supply/battery` as read-only — it cannot be written even with root. But the kernel accepts the same value through the "battery" cooling device (`/sys/class/thermal/cooling_deviceN/cur_state`) — the same lever the stock thermal protection uses. The module writes there and reads it back. Levels are 0–16; from 15 the kernel stops charging, so the module never sets more than 12. How much current each level allows comes from the device tree, and each charger type has its own table (`qcom,thermal-fcc-qc3-normal` for Quick Charge 3, `qcom,thermal-mitigation-dcp` for a plain charger and so on); the panel shows the one in effect. For Quick Charge 3: level 8 is 2.7 A, 10 is 2.4 A, 12 is 2.0 A.

On top of that, hardware battery protection always works in the kernel (JEITA from the battery profile): from 15 to 45 °C up to 3.5 A and 4.4 V, from 45 to 58 °C up to 1.95 A and 4.1 V, above that charging stops. The module does not touch it.

### Modes

- **Care**: levels by sensor temperature: 41 °C — level 4, 43 °C — 8, 45 °C — 12. It relaxes a level only after cooling one more degree, to avoid jumping. Pause from 42 °C, resume at 38 °C.
- **Fast**: full current. If the sensor reaches 44.0 °C, the level goes up starting from 8 (2.7 A); below 42.5 °C it goes down. From 45 °C — straight to 12. This keeps the sensor just below 45 °C, where the kernel would cut current to 1.95 A. The pause is an emergency one, from 48 °C.

The heat pause lasts at least 2 minutes: the sensor sits by the connector and cools fast without current.

### The “battery” sensor

It sits by the charging connector and the protection board. On fast charging it reads 6–11 °C more than the battery itself within a couple of minutes. So a “hot battery” with a cold body is normal.

### Thermal configs

The ROM (thermal-engine) cuts charging current when the body warms up, from about 34 °C, using tables in `/vendor/etc/thermal-*.conf`. The module carries its own copies of these files where the list of levels in the charging rule is zeroed and everything else (CPU frequencies on heat) is as in the ROM.

The copies are mounted only if **all six stock files match the tested ones byte for byte** — their SHA-256 sums are in `module/thermal/orig.sha256`. If even one differs, the module leaves them alone and the panel says “left as is”. This way the module cannot break a ROM it does not know. The panel switch changes after a reboot.

On KernelSU file replacement works only with a metamodule (e.g. meta-overlayfs). Without it the panel says the files were not mounted.

## Kernel checks

On start the service looks at kernel parameters:

- `/sys/module/qpnp_smb5/parameters/disable_thermal` — when on, the kernel rejects current levels;
- `/sys/module/smb5_lib/parameters/skip_thermal` (VantomKernel) — when on, levels are accepted but have no effect.

In both cases Care and the hold do not work — the service writes this to the log and the panel shows a warning. The limit and the heat pause keep working.

## Drain in sleep

When the screen turns off unplugged, the service remembers the charge, the charge counter (`charge_counter`), awake time (`/proc/timer_list`) and mobile and Wi-Fi traffic. When the screen turns on and more than 30 minutes have passed, it records a measurement: −%, mAh, average current, deep sleep, the share of traffic over mobile data and the number of active SIMs. From the measurements the panel builds the average current by week; if it went up by 30% and at least 10 mA over the last week — a warning.

## Where things live

- Settings and data: `/data/adb/davinci-control/` (root only, deleted with the module).
- Saved log and diagnostics: `/sdcard/Download/davinci-control/`, names like `davinci-control_v1.0.0_diag_2026-11-09_1630.txt`.

## Checks before a release

The test bench in [`tests/`](../tests) runs the service on fake `/sys` and `/proc` and checks scenarios: Care, Fast, limit, unplugging, overnight drain, JEITA delay, skip_thermal, dropping a charge switch, installation on different root managers, thermal config replacement and removal. The panel is checked in a browser at 400 and 1000 px in both languages.
