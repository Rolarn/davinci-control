# FAQ — Davinci Control for Mi 9T / Redmi K20 (davinci)

[Русский](FAQ.md) · **English**

Tap a question to open the answer.

<p align="center"><img src="../assets/mascot/export/faq.svg" width="120" alt="Curious mascot"></p>

<details>
<summary><b>Which phones is the module for?</b></summary>

Only Xiaomi Mi 9T and Redmi K20 (codename davinci). On any other device the installer refuses: the module writes to kernel nodes and files that exist on davinci specifically.

</details>

<details>
<summary><b>How is the Mi 9T different from the Mi 9T Pro and Redmi K20 Pro?</b></summary>

The Mi 9T Pro and Redmi K20 Pro are a different device (raphael) with another chip and charging. The module will not install on them.

</details>

<details>
<summary><b>Do I need root?</b></summary>

Yes. The module installs via Magisk 24+ (tested on Magisk Alpha 31100). KernelSU and APatch are supported in code but untested.

</details>

<details>
<summary><b>How do I open the panel?</b></summary>

The Action button on the module card in Magisk (Magisk 28+). The panel opens in WebUI X, KsuWebUI or MMRL — you need one of these apps with root. Without them Action shows a text report.

</details>

<details>
<summary><b>Does it work on MIUI?</b></summary>

Partly. MIUI has no powerhint.json, so that part is skipped. MIUI thermal configs differ from the tested ones, so the module leaves them alone. The charge limit, modes and statistics work.

</details>

<details>
<summary><b>What is the difference between Care and Fast?</b></summary>

Care reduces current in steps as soon as the battery warms above 41 °C and pauses from 42 °C: slower, but the battery lasts longer. Fast gives full current and only lowers it a little near 44 °C, so the kernel does not cut current to 1.95 A above 45 °C. The pause in Fast is an emergency one, from 48 °C.

</details>

<details>
<summary><b>Why does the sensor show 44° while the phone is cold?</b></summary>

The “battery” sensor sits by the charging connector. On fast charging it reads 6–11 °C more than the battery itself within a couple of minutes. The module accounts for that, and the panel labels it as a sensor.

</details>

<details>
<summary><b>Why does charging slow down sharply after 45°?</b></summary>

That is hardware protection in the kernel (JEITA): above 45 °C current is limited to 1.95 A and voltage to 4.1 V. After half charge that is almost a stop. Fast mode keeps the sensor just below this threshold.

</details>

<details>
<summary><b>What is the stock current reduction on heat?</b></summary>

The ROM cuts charging current when the body warms up (from about 34 °C), using tables in the stock thermal configs. The module can install its own configs without this rule — only if the stock ones match the tested ones byte for byte. Battery protection in the kernel always works. The switch is in the panel, it changes after a reboot.

</details>

<details>
<summary><b>Why does the panel say “left as is”?</b></summary>

Your ROM's thermal configs differ from the tested ones. The module does not know what is in them, so it does not replace them — that way another ROM cannot be broken. Everything else works.

</details>

<details>
<summary><b>How does the charge limit work?</b></summary>

When the charge reaches the limit, the module turns charging off through the kernel and the phone runs on the cable. It starts again when the charge drops by 5%. The module checks that charging really stopped; if a method does not work, it tries another.

</details>

<details>
<summary><b>I need 100% before a trip. How?</b></summary>

The “Charge to 100% once” button in Charging. The limit setting stays as is, and the one-time charge cancels itself when you unplug the cable.

</details>

<details>
<summary><b>Does the module wake the phone and drain the battery?</b></summary>

No. The service wakes every 15–60 seconds only while the phone is awake anyway. In sleep it holds no wakelocks and does not wake the CPU.

</details>

<details>
<summary><b>Where does the overnight drain in mA come from?</b></summary>

From the battery charge counter (charge_counter): how many mAh went during a screen-off period, divided by time. That is more precise than percent. A measurement counts if the screen was off for more than 30 minutes unplugged.

</details>

<details>
<summary><b>What do “mobile data share” and “SIM” mean in overnight drain?</b></summary>

They are hints at the causes. Mobile data costs more than Wi-Fi, and every active SIM keeps the modem busy. If drain went up, compare nights with a different mobile data share and number of SIMs.

</details>

<details>
<summary><b>When does the drain warning appear?</b></summary>

If the average sleep current over the last week went up by 30% and at least 10 mA compared with the three weeks before (at least two nights in each). The warning can be turned off in Usage.

</details>

<details>
<summary><b>What are skip_thermal and disable_thermal?</b></summary>

Parameters in some kernels. When on, the kernel rejects or ignores current limit levels. Then Care and the hold below 45° do not work — the panel warns about it. The limit and the heat pause still work.

</details>

<details>
<summary><b>How do I report a bug?</b></summary>

In the panel: Log and diagnostics → Collect diagnostics (about a minute) or Save the log only. The file appears in Download/davinci-control and is not sent anywhere. E-mail, IP and MAC addresses and long numbers are replaced with placeholders, but look through the file before posting. Then open an issue on GitHub and attach the file.

</details>

<details>
<summary><b>What data does the module collect?</b></summary>

None to send: the module does not go online. It keeps the log, charge history and measurements on your phone in /data/adb/davinci-control and deletes them with the module. Logging app installs and removals is off until you turn it on yourself.

</details>

<details>
<summary><b>How do I get 100% by morning without sitting at 100% all night?</b></summary>

Turn on “Charge to 100% by a set time” in the Charging card and pick the hour. Overnight the phone holds the limit and tops up to 100% in advance. The time repeats every day.

</details>

<details>
<summary><b>Notifications do not arrive</b></summary>

They are off by default: turn on Notifications in the Panel card — a test one arrives at once. Notifications come from the system app Shell; if the test one does not show, allow notifications for it in Android settings.

</details>

<details>
<summary><b>How do I remove the module completely?</b></summary>

Remove it in the root manager and reboot. Charging, the current level and frequencies go back to stock, module data is deleted. Files you saved in Download/davinci-control stay.

</details>

<details>
<summary><b>Does it conflict with other charging modules?</b></summary>

Yes, if another module also controls the charge limit or the current level (for example ACC). Keep only one such module enabled. The module notices when someone else changes the level and writes it to the log.

</details>

<details>
<summary><b>Will the Balance profile make the phone slower?</b></summary>

Hardly noticeably: little cores are capped at 1612 MHz, and the interface mostly runs on them anyway. Big cores are unlimited. Heat goes down.

</details>

<details>
<summary><b>How do I change the panel language and the mascot colour?</b></summary>

The Panel block: language (system, Russian, English) and the mascot colour — Glacier Blue, Flame Red or Carbon Black. The language changes the log too.

</details>

<details>
<summary><b>Will there be an app without root?</b></summary>

There is an idea: a companion app with statistics (a possible 1.1.0). Controlling charging without root is impossible, but viewing statistics is possible. Watch the ideas list on GitHub.

</details>

No answer here? [Ask in issues](https://github.com/Rolarn/davinci-control/issues/new/choose).
