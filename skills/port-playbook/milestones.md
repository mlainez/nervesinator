# Milestones in detail

Each milestone lists its **goal**, the **tasks** (the same titles as `templates/backlog-seed.json`),
the **agent** that does the work, the **exit criteria** checked at the gate, and the **lesson** to
teach at the gate. `<id>` is the port id, `$P` is `ports/<id>`.

---

## M0: Setup & safety briefing (risk-green)

**Goal:** a ready host, a workspace, and a user who knows the safety rules and how this will go.

| Task | Agent | Notes |
|---|---|---|
| Check host tools | orchestrator | `tools/check-host.sh`; install what is missing (adb, fastboot, git, python3, build deps for Buildroot, and depending on the device heimdall/mtkclient/edl, mkbootimg, Elixir+Nerves for M11) |
| Create learner profile | orchestrator | Ask: experience with Linux, the command line, electronics, Elixir; depth (short/normal/deep); language. Store in `port.yaml` `learner:` |
| Safety briefing | orchestrator | Explain the risk levels, the gates, what "brick" means (soft vs hard) and why backups come first. Ask the user to back up their personal data (photos…) now: unlocking will wipe it |
| Root preference | orchestrator | Explain root (a uid 0 shell on Android), what it gives the port (full recon: dmesg, `/proc/cmdline`, the device tree, the raw boot image; raw `dd` backups of every partition, which some vendor modes cannot read back) and its costs (usually needs an unlocked bootloader or a custom recovery flash, may trip KNOX or void warranty, may be impossible on locked devices). Ask; record `safety.root` |
| GATE M0 | orchestrator | |

**Exit:** `check-host.sh` passes for the tools needed up to M3; profile saved; briefing done.
**Lesson:** "Three pillars: bootloader, kernel, rootfs", and what this project will turn the phone into.

---

## M1: Reconnaissance (risk-green)

**Goal:** know the device inside out without changing anything.

| Task | Agent | Notes |
|---|---|---|
| Collect Android properties and hardware info | device-recon | `tools/recon/collect.sh <serial> $P/dossier/raw` (getprop, /proc/cpuinfo, /proc/cmdline, /proc/partitions, by-name links, dmesg if readable, input devices, display, modules, `/proc/config.gz`) |
| Identify the SoC, board and peripheral chips | device-recon | SoC, RAM, eMMC/UFS, PMIC, display panel + controller, touch IC, WiFi/BT chip, modem, sensors, charger. Cite where each fact comes from |
| Map the partition table | device-recon | Names, sizes, block devices; mark each partition as bootloader-chain / radio-calibration / boot / system / userdata (see the `device-safety` skill) |
| Identify the boot image format | device-recon | Boot image header version, page size, base/offsets, cmdline, appended DTB or QCDT `dt.img`, AVB/dm-verity, A/B slots, Samsung SEAndroid footer. From the stock boot image if it can be read, otherwise from `getprop` and the prior art |
| Check bootloader and secure-boot state | device-recon | `ro.boot.*`, `ro.oem_unlock_supported`, `sys.oem_unlock_allowed`, verified boot state, KNOX warranty bit, flash mode (fastboot / Samsung download / MTK BROM) |
| Root-enhanced recon | device-recon | Now if `safety.root: already`. Otherwise close it as Done with a note: deferred to the M5 root shell, or N/A when root is declined or not possible. Reads: full dmesg, `/sys/firmware/devicetree`, the vendor firmware list, `/proc/config.gz`, `dd` reads of the boot image |
| Write device dossier summary | device-recon | `$P/dossier/device.md` + fill the `device:` section of `port.yaml` |
| GATE M1 | orchestrator | |

**Exit:** SoC, arch (armv7/aarch64), partition map, flash mode and boot image format known, each with a source.
**Lesson:** "What is an SoC?", "Partitions: the drawers of the phone", "Who checks what at boot (chain of trust)".

---

## M2: Prior art & feasibility (risk-green)

**Goal:** never start from zero. Find who has already booted Linux on this SoC or this device.

| Task | Agent | Notes |
|---|---|---|
| Clone or update pmaports | prior-art-scout | `cache/pmaports` (shared across ports) |
| Search pmaports for the device and SoC | prior-art-scout | `device-*-<codename>`, `linux-postmarketos-*-<soc>`, `firmware-*`, `soc-*`; read `deviceinfo`, `APKBUILD`, kernel `config-*`, and the `modules-initfs` |
| Search the postmarketOS wiki | prior-art-scout | Device page, SoC page, the feature table, known issues, notes on flashing |
| Search mainline Linux and SoC forks | prior-art-scout | `arch/arm*/boot/dts/<vendor>/` for the board/SoC; msm8916-mainline, msm8974-mainline, sdm845-mainline, linux-sunxi, mainline-for-mediatek… |
| Check second-stage bootloader support | prior-art-scout | lk2nd device list and the SoC (Qualcomm), mainline U-Boot board list, Samsung/Exynos U-Boot work |
| Search downstream sources (LineageOS, vendor) | prior-art-scout | `LineageOS/android_device_<vendor>_<codename>`, `android_kernel_*`, TheMuppets blobs, the vendor's open-source release |
| Feasibility verdict and kernel path decision | prior-art-scout → orchestrator | Write `$P/dossier/prior-art.md` with the scenario (A: mainline/pmOS-mainline device, B: mainline SoC without the board, C: downstream only) and a confidence level, plus the reusable buildroot-android pieces (closest board, packages); record a decision |
| GATE M2 | orchestrator | Go / no-go with the user |

**Exit:** a decision records the kernel source (repo + branch/commit + DTB name) and the bootloader path; `port.yaml` `path:` is filled.
**Lesson:** "Mainline vs downstream kernels", "What postmarketOS is and why its work is gold", "The device tree: a map of the house".

---

## M3: Unbrick kit (risk-green, a few risk-yellow reboots)

**Goal:** before the first change that cannot be undone, prove that we can always go back to stock.

| Task | Agent | Notes |
|---|---|---|
| Locate and download stock firmware | bootloader-strategist | The exact build matching `ro.build.fingerprint` (or newer); checksum it; store under `$P/backups/stock/` |
| Install and test the flash tool | bootloader-strategist + orchestrator | fastboot / heimdall (`heimdall print-pit` reads only) / mtkclient (`printgpt` reads only); check it sees the device |
| Test every boot mode entry | orchestrator | adb reboot bootloader/recovery/download; the key combos; how to force power off. Record them in `port.yaml` `device.modes` |
| Document the emergency recovery procedure | bootloader-strategist | `$P/dossier/unbrick.md`: soft-brick → reflash stock boot; bootloop → recovery/download mode; hard-brick → EDL/BROM/Odin options and what they need |
| Research the root method | bootloader-strategist | Only if `safety.root: wanted`. Standard, documented methods only (custom recovery, patched boot image, vendor tool), never exploits or closed one-click rooting apps. Record what it writes, whether it trips KNOX/warranty, and how to restore stock. Set `safety.root_method`, or `safety.root: not-possible` |
| GATE M3 | orchestrator | Set `safety.unbrick_kit_ready: true` |

**Exit:** stock firmware on disk with a checksum; the flash tool talks to the device; every mode tested; unbrick.md written.
**Lesson:** "Soft brick vs hard brick", "Boot ROM: the part you can never break (and EDL/BROM)".

---

## M4: Bootloader unlock (risk-orange, wipes data)

**Goal:** a bootloader that accepts unsigned images, with full knowledge of what that costs.

| Task | Agent | Notes |
|---|---|---|
| Research the unlock procedure for this device | bootloader-strategist | The OEM toggle, `fastboot flashing unlock` vs `oem unlock`, vendor tokens (Motorola/Sony/Xiaomi waits), Samsung (often no unlock needed on old Qualcomm models, OEM unlock toggle on newer ones), what is irreversible (KNOX e-fuse, Sony TA/DRM keys: back up TA **before**) |
| Pre-unlock checklist | flash-guardian | Personal data backed up by the user, battery > 50 %, OEM unlock toggle on, FRP considered, irreversible effects explained |
| Unlock the bootloader | flash-guardian (user approves) | Run only after the user's typed yes; the hook asks for confirmation as well |
| Verify unlocked state and Android still boots | orchestrator | `fastboot getvar unlocked` / the download mode screen; boot back to Android; re-enable adb |
| GATE M4 | orchestrator | |

**Exit:** the bootloader reports unlocked (or "no unlock needed" is proven, for example a Samsung that accepts custom boot images); Android still boots.
**Lesson:** "Chain of trust and signatures", "What unlocking really changes".

---

## M5: Full backup (risk-green; risk-yellow if a temporary recovery is booted; risk-orange if the root shell needs a flash)

**Goal:** a copy of every partition we might ever need, so any later mistake can be undone.

| Task | Agent | Notes |
|---|---|---|
| Get a root shell | flash-guardian (user approves) | Only if `safety.root: wanted` and a method was found. RAM first: `fastboot boot` of a recovery or patched boot image when the bootloader allows it. If a write is needed (Samsung download mode), the target is class D and its backup is the matching image from the stock firmware: copy it to `backups/<name>.img`, add it to `SHA256SUMS`, allowlist the partition with the user, and check the new image against the partition size in `dossier/partitions.md`. Flash plan, the user's yes, `safety.root: done`. Then re-run root-enhanced recon to fill the M1 gaps |
| Choose the backup method | flash-guardian | Root `dd` over adb, or a temporarily booted recovery (TWRP via `fastboot boot`), or `heimdall`/`edl`/`mtkclient` reads; never a method that writes |
| Dump all partitions except userdata and system | flash-guardian | `tools/backup-partitions.sh`: per partition `.img` + `SHA256SUMS`; radio calibration (`efs`, `modemst*`, `fsg`, `persist`, `nvram`, `nvdata`, `TA`) first |
| Verify backups and store a copy off the machine | flash-guardian + user | Re-read and compare hashes; the user copies `backups/` to a second place |
| Set the writable partitions allowlist | orchestrator + user | Default `boot` + `userdata`; any other partition only when the user explicitly asks. Record in `port.yaml` `safety.writable_partitions`; for `userdata`, either a backup or the user's confirmed `safety.accepted_loss` |
| GATE M5 | orchestrator | Set `safety.backups_verified: true` |

**Exit:** `backups/SHA256SUMS` verifies; the allowlist is set; the user confirms an off-machine copy.
**Lesson:** "Why the IMEI/WiFi MAC/calibration live in a partition you must never lose".

---

## M6: Boot path proven (risk-yellow; risk-orange if a second stage is written to boot)

**Goal:** a repeatable way to load our own kernel, without touching the bootloader chain.

| Task | Agent | Notes |
|---|---|---|
| Decide whether a second-stage bootloader is needed | bootloader-strategist (+ uboot-engineer when lk2nd does not support the SoC) | Confirm or revise the M2 boot path with what M3-M5 showed (unlock result, `fastboot boot` support); decision tree in [decisions.md](decisions.md); ADR |
| Round-trip test with the stock boot image | orchestrator | `fastboot boot stock-boot.img` (when the stock bootloader offers it) proves temporary boot works; on devices without it, flash the stock image back to the same partition from the flash mode to prove the flash path. Not through lk2nd: it cannot boot a stock image whose QCDT uses vendor ids (Samsung), see `boot-images` |
| Install or temporarily boot the second stage | flash-guardian | lk2nd: `fastboot boot lk2nd.img` first when supported, then flash to `boot` only after the user agrees; U-Boot chainloaded the same way |
| Verify the second stage offers fastboot and boots extlinux | orchestrator | `fastboot devices` shows lk2nd; `fastboot oem log` readable; `aboot` flash mode (fastboot / Samsung download mode) still reachable to reflash `boot` |
| GATE M6 | orchestrator | |

**Exit:** the documented command to load a kernel from RAM works, and we can get back to stock.
**Lesson:** "Bootloaders that load bootloaders (and why lk2nd exists)", "Android boot image anatomy".

---

## M7: First light (risk-yellow)

**Goal:** see our kernel's boot log on the phone screen. Nothing persistent.

| Task | Agent | Notes |
|---|---|---|
| Fork or clone buildroot-android | buildroot-engineer | Ask the user for their fork of Spin42/buildroot-android; clone into `$P/buildroot-android`, branch `port/<id>`; the first-light and rescue defconfigs live there (see `buildroot-port`) |
| Prepare the kernel source and config | buildroot-engineer | From the chosen fork; config from pmaports (`config-*`) or `qcom_defconfig`/`multi_v7_defconfig` + the device fragment; enable `FB_SIMPLE`/`DRM_SIMPLEDRM`, `FRAMEBUFFER_CONSOLE`, `PSTORE_RAM`, `USB_GADGET`/`USB_CONFIGFS_*` |
| Build the first-light defconfig | buildroot-engineer | `<id>_firstlight_defconfig` in buildroot-android: kernel + a tiny initramfs whose init prints and sleeps; the boot image packed for this bootloader |
| Boot it temporarily | orchestrator | `tools/await-boot.sh --port <id> --image <boot.img> --stage firstlight` (RAM boot through safe-flash, then watches USB): PASS when the kit gadget's console says `KIT-READY`. A photo of the screen is optional. Without a RAM boot: flash to the experiment partition, reboot, `await-boot.sh --watch-only` |
| Analyse the result | boot-debugger | From `journal/boots/<run>/`: FAIL (back in the flash mode: lk2nd log, ramoops on the next good boot), HUNG (no watchdog fired: needs a human), screen only (USB controller/PHY not probing). Loop until PASS |
| GATE M7 | orchestrator | Proof: the `await-boot` PASS record (banner and dmesg over USB), or the user's photo of the boot log |

**Exit:** the banner observed by the host over USB (`await-boot` PASS; a photo is optional); the recipe is reproducible from the defconfig.
**Lesson:** "What the kernel does in its first second", "Framebuffer and console: printing without a GPU".

---

## M8: Rescue shell (risk-yellow)

**Goal:** a full shell into Linux running from RAM, over USB, for investigation.

| Task | Agent | Notes |
|---|---|---|
| Build the rescue initramfs defconfig | buildroot-engineer | `<id>_rescue_defconfig`: busybox, dropbear (or telnetd), unudhcpd, a configfs USB gadget (NCM/RNDIS), the rootfs as initramfs; templates in `templates/rescue/` |
| Boot rescue and connect over USB networking | orchestrator | `tools/await-boot.sh --stage rescue`, then `tools/usbnet.sh`: host gets 10.0.42.2, phone 10.0.42.1; `ssh root@10.0.42.1`. Check the way back: `reboot-mode <bootloader or download>` from the shell lands in the flash mode without keys (on Qualcomm the restart reason survives only a warm reset) |
| Linux hardware inventory | device-recon (over ssh) | `dmesg`, `/sys/bus/*/devices`, `/proc/device-tree`, eMMC partitions as Linux sees them, failed probes, firmware requests, and the battery: voltage and charger state from `/sys/class/power_supply/*` (from now on every `await-boot` record logs them) |
| Map Android partitions to Linux block devices | device-recon | `mmcblk0pN` ↔ name table in `dossier/partitions-linux.md` |
| GATE M8 | orchestrator | |

**Exit:** ssh works; the inventory and the partition map are written.
**Lesson:** "PID 1 and the initramfs", "USB gadgets: the phone pretends to be a network card".

---

## M9: Persistent Buildroot (risk-orange)

**Goal:** a real Buildroot system on flash, structured like buildroot-android, that survives a reboot.
It has a **single root filesystem**: no A/B slots and no slot switching (they come with Nerves in M11).

| Task | Agent | Notes |
|---|---|---|
| Add the board to buildroot-android | buildroot-engineer | `board/<id>/`, `configs/<id>_defconfig`, `linux.config`, overlay, genimage; follow the repo's conventions |
| Choose rootfs placement and boot flow | buildroot-engineer + orchestrator | Recommend the default: the whole system in one image on `userdata`, writing only `boot` and `userdata` (ext2 + /extlinux under lk2nd or U-Boot, else `boot.img` with root on `userdata`; decisions.md section 3); other options only with a reason; ADR |
| Build the full system | buildroot-engineer | |
| Flash plan and first persistent flash | flash-guardian (user approves) | Only allowlisted partitions; keep the rescue path (RAM boot) available |
| Boot, ssh in, check reflash cycle | orchestrator | On an Android A/B phone (`device.android_ab`), an init script marks the active slot successful at every boot (qbootctl or the vendor equivalent), and several reboots in a row prove the slot stays bootable. Write a `reflash.sh` like tb3_710f's: talks only to this serial; it returns to the flash mode with `tools/return-to-flash.sh` (`reboot-mode <device.return_mode>`), flashes, and waits for ssh, with no keys |
| Choose what comes next with the user | orchestrator + user | Once Buildroot boots, ask: (1) Nerves now (M11), (2) peripherals in Buildroot first (M10), or (3) a chosen subset (e.g. power, WiFi) then Nerves. Charging (the first M10 task) and the init inventory are done in every case. Record a decision and `path.after_buildroot` / `path.peripherals`; tasks for peripherals not chosen get the `deferred` label and stay in the backlog |
| GATE M9 | orchestrator | |

**Exit:** survives a reboot; ssh works; a documented key-free reflash cycle (`reboot-mode` from Linux lands in the flash mode); the rescue boot still works.
**Lesson:** "Buildroot: a kitchen that cooks a whole OS from source", "External trees and defconfigs".

---

## M10: Hardware enablement (risk-orange)

**Goal:** make the peripherals the user cares about work. One child task per peripheral.

**Charging comes first** (the first task below): a port that drains its battery stops everything and needs
hands. It is never deferred, and long or unattended device work waits for it. When the M9 decision
goes to Nerves early, M10 shrinks to charging, the chosen subset and the init inventory; the other
peripheral tasks keep their `deferred` label for later. Done means: the battery
voltage (PMIC ADC/VADC) and, when there is one, the fuel gauge's capacity are readable; the phone
charges on every supply the user will use (a PC port **and** a wall supply); and it keeps charging
across every reboot and flash path the port uses (warm and cold reset, the vendor flash mode, the
second-stage bootloader), re-checked after each flash path is first used. Checklist:
`firmware-userspace` section 4, Charging.

Create child tasks (`-p <M10 parent>`) from the M8 inventory and the user's priorities: display/backlight,
touch, WiFi, Bluetooth, modem/SMS/data, audio, battery/charger, sensors, camera, GPU.

For each one: **firmware-hunter** finds blobs and the pmOS userspace (APKBUILD dependencies, OpenRC
services → Buildroot packages and `S??` scripts); **buildroot-engineer** packages them;
**boot-debugger** reads the dmesg. **Write down every init script**, since each one becomes Elixir in M11.

**Iterate with scp, checkpoint with a full build** (`buildroot-port` section 7): each try rebuilds only
what changed and copies it over ssh (`scp -O`), with a test kernel booted once through a mechanism
that falls back on its own; each working peripheral ends with a clean full build, a key-free
install, a re-check and a tagged commit.

| Task | Agent |
|---|---|
| Make charging work and read the battery | firmware-hunter, buildroot-engineer |
| Prioritise peripherals with the user | orchestrator |
| (child tasks per peripheral) | firmware-hunter, buildroot-engineer |
| Write the init-scripts inventory for Nerves | buildroot-engineer → `$P/dossier/init-inventory.md` |
| GATE M10 | orchestrator |

**Exit:** the chosen peripherals work in Buildroot; the init inventory lists every script, daemon and blob.
**Lesson:** "Firmware blobs: tiny programs for tiny computers inside the phone".

---

## M11: Nerves system (risk-orange)

**Goal:** a Nerves system with A/B updates, living inside the Android partition table. A/B appears
here for the first time, through the standard Nerves mechanism (fwup env, rootfs A/B, app partition);
the Buildroot board stays single-root.

| Task | Agent | Notes |
|---|---|---|
| Design the A/B layout inside Android partitions | nerves-architect | Usually a sub-image in `userdata` (MBR + fwup env + rootfs A/B + app f2fs) mapped by an initramfs (kpartx/losetup), or using `boot`+`system`+`userdata`; ADR |
| Bootstrap the Nerves system | nerves-architect | Study the official nerves-project systems, then the user's phone systems for the Android parts; `nerves_system_bootstrap` from the Buildroot defconfig, then adapt: toolchain, kernel options (squashfs, f2fs, gadget built in), erlinit.config, fwup.conf, fwup-ops.conf |
| Review the system against official Nerves systems | nerves-architect | Diff `linux.config`, erlinit, fwup and the overlay against the nerves-project systems (`nerves-port` section 2b); remove first-light/debug options (`CONFIG_LOGO`, verbose loglevel, `DEBUG_INFO`), add what Nerves needs; table in `dossier/nerves-config-review.md` |
| Boot flow for slot switching | nerves-architect | How the bootloader (lk2nd extlinux / U-Boot env / initramfs) picks the active slot; how revert works |
| Port init scripts to Elixir | nerves-app-engineer | On an Android A/B phone, ship qbootctl (or the vendor equivalent) and an ex_qbootctl-style app that marks the slot successful once boot is stable. From init-inventory.md: VintageNet (WiFi/QMI), custom OTP apps for firmware loaders, rmtfs, etc. Iterate on apps with `mix upload` (or `scp -O` of single files), checkpoint with a full `mix firmware` and a clean install |
| Build firmware and first flash | nerves-architect + flash-guardian | `mix firmware`, `mix firmware.image`, flash to the allowlisted partition |
| Test mix upload, revert and factory reset | orchestrator | Upload over USB networking; `Nerves.Runtime.revert`; check it boots the other slot |
| GATE M11 | orchestrator | |

**Exit:** IEx over ssh; `mix upload` works; revert proven.
**Lesson:** "erlinit and the BEAM as PID 1", "A/B: two parachutes", "fwup".

---

## M12: Share it (risk-green)

| Task | Agent |
|---|---|
| Write device documentation (what works, how to flash) | buildroot-engineer / nerves-architect (`docs/<id>.md` in buildroot-android style) |
| Prepare a PR to buildroot-android | orchestrator (the user decides whether to open it) |
| Write the Dependencies section of the Nerves system's README | nerves-architect (`nerves-port` section 8) |
| Write the one-command installer (stock phone to Nerves) | nerves-architect + flash-guardian (review) |
| Set up the release recipe (images, SHA256SUMS, GPL sources) | nerves-architect |
| Compile the learner journal | tutor |
| GATE M12 | orchestrator |
