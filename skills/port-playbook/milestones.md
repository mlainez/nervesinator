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
| Root-enhanced recon (optional) | device-recon | Only if the phone is already rooted: full dmesg, `/sys/firmware/devicetree`, the vendor firmware list, `/proc/config.gz`, `dd` reads of the boot image |
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
| Feasibility verdict and kernel path decision | prior-art-scout → orchestrator | Write `$P/dossier/prior-art.md` with the scenario (A: mainline/pmOS-mainline device, B: mainline SoC without the board, C: downstream only) and a confidence level; record a decision |
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

## M5: Full backup (risk-green; risk-yellow if a temporary recovery is booted)

**Goal:** a copy of every partition we might ever need, so any later mistake can be undone.

| Task | Agent | Notes |
|---|---|---|
| Choose the backup method | flash-guardian | Root `dd` over adb, or a temporarily booted recovery (TWRP via `fastboot boot`), or `heimdall`/`edl`/`mtkclient` reads; never a method that writes |
| Dump all partitions except userdata and system | flash-guardian | `tools/backup-partitions.sh`: per partition `.img` + `SHA256SUMS`; radio calibration (`efs`, `modemst*`, `fsg`, `persist`, `nvram`, `nvdata`, `TA`) first |
| Verify backups and store a copy off the machine | flash-guardian + user | Re-read and compare hashes; the user copies `backups/` to a second place |
| Set the writable partitions allowlist | orchestrator + user | Usually `boot`, `recovery`, `userdata` (+ `cache`/`system` if used); record in `port.yaml` `safety.writable_partitions` |
| GATE M5 | orchestrator | Set `safety.backups_verified: true` |

**Exit:** `backups/SHA256SUMS` verifies; the allowlist is set; the user confirms an off-machine copy.
**Lesson:** "Why the IMEI/WiFi MAC/calibration live in a partition you must never lose".

---

## M6: Boot path proven (risk-yellow; risk-orange if a second stage is written to boot/recovery)

**Goal:** a repeatable way to load our own kernel, without touching the bootloader chain.

| Task | Agent | Notes |
|---|---|---|
| Decide whether a second-stage bootloader is needed | bootloader-strategist | Decision tree in [decisions.md](decisions.md); ADR |
| Round-trip test with the stock boot image | orchestrator | `fastboot boot stock-boot.img` (when it exists) proves temporary boot works; on devices without `fastboot boot`, flash the stock image back to the same partition to prove the flash path |
| Install or temporarily boot the second stage | flash-guardian | lk2nd: `fastboot boot lk2nd.img` first when supported, then flash to `boot` (or `recovery` to keep Android) only after the user agrees; U-Boot chainloaded the same way |
| Verify the second stage offers fastboot and boots extlinux | orchestrator | `fastboot devices` shows lk2nd; `fastboot oem log` readable; Android still bootable through the escape route |
| GATE M6 | orchestrator | |

**Exit:** the documented command to load a kernel from RAM works, and we can get back to stock.
**Lesson:** "Bootloaders that load bootloaders (and why lk2nd exists)", "Android boot image anatomy".

---

## M7: First light (risk-yellow)

**Goal:** see our kernel's boot log on the phone screen. Nothing persistent.

| Task | Agent | Notes |
|---|---|---|
| Prepare the kernel source and config | buildroot-engineer | From the chosen fork; config from pmaports (`config-*`) or `qcom_defconfig`/`multi_v7_defconfig` + the device fragment; enable `FB_SIMPLE`/`DRM_SIMPLEDRM`, `FRAMEBUFFER_CONSOLE`, `PSTORE_RAM`, `USB_GADGET`/`USB_CONFIGFS_*` |
| Build the first-light defconfig | buildroot-engineer | `<id>_firstlight_defconfig` in buildroot-android: kernel + a tiny initramfs whose init prints and sleeps; the boot image packed for this bootloader |
| Boot it temporarily | orchestrator | `fastboot boot` / lk2nd / experiment partition; ask the user for a photo of the screen |
| Analyse the result | boot-debugger | No output: check simplefb/panel, `earlycon`, ramoops after a warm reboot, lk2nd log. Loop until there is text |
| GATE M7 | orchestrator | Proof: the user's photo of the boot log |

**Exit:** a photo of the kernel log on screen; the recipe is reproducible from the defconfig.
**Lesson:** "What the kernel does in its first second", "Framebuffer and console: printing without a GPU".

---

## M8: Rescue shell (risk-yellow)

**Goal:** a full shell into Linux running from RAM, over USB, for investigation.

| Task | Agent | Notes |
|---|---|---|
| Build the rescue initramfs defconfig | buildroot-engineer | `<id>_rescue_defconfig`: busybox, dropbear (or telnetd), unudhcpd, a configfs USB gadget (NCM/RNDIS), the rootfs as initramfs; templates in `templates/rescue/` |
| Boot rescue and connect over USB networking | orchestrator | `tools/usbnet.sh`: host gets 10.0.42.2, phone 10.0.42.1; `ssh root@10.0.42.1` |
| Linux hardware inventory | device-recon (over ssh) | `dmesg`, `/sys/bus/*/devices`, `/proc/device-tree`, eMMC partitions as Linux sees them, failed probes, firmware requests |
| Map Android partitions to Linux block devices | device-recon | `mmcblk0pN` ↔ name table in `dossier/partitions-linux.md` |
| GATE M8 | orchestrator | |

**Exit:** ssh works; the inventory and the partition map are written.
**Lesson:** "PID 1 and the initramfs", "USB gadgets: the phone pretends to be a network card".

---

## M9: Persistent Buildroot (risk-orange)

**Goal:** a real Buildroot system on flash, structured like buildroot-android, that survives a reboot.

| Task | Agent | Notes |
|---|---|---|
| Fork or clone buildroot-android and add the board | buildroot-engineer | `board/<id>/`, `configs/<id>_defconfig`, `linux.config`, overlay, genimage; follow the repo's conventions |
| Choose rootfs placement and boot flow | buildroot-engineer + orchestrator | Decision tree in decisions.md (extlinux on userdata through lk2nd, boot.img + root on userdata, sub-image…); ADR |
| Build the full system | buildroot-engineer | |
| Flash plan and first persistent flash | flash-guardian (user approves) | Only allowlisted partitions; keep the rescue path (RAM boot) available |
| Boot, ssh in, check reflash cycle | orchestrator | Write a `reflash.sh` like tb3_710f's: talks only to this serial |
| GATE M9 | orchestrator | |

**Exit:** survives a reboot; ssh works; a documented reflash cycle; the rescue boot still works.
**Lesson:** "Buildroot: a kitchen that cooks a whole OS from source", "External trees and defconfigs".

---

## M10: Hardware enablement (risk-orange)

**Goal:** make the peripherals the user cares about work. One child task per peripheral.

Create child tasks (`-p <M10 parent>`) from the M8 inventory and the user's priorities: display/backlight,
touch, WiFi, Bluetooth, modem/SMS/data, audio, battery/charger, sensors, camera, GPU.

For each one: **firmware-hunter** finds blobs and the pmOS userspace (APKBUILD dependencies, OpenRC
services → Buildroot packages and `S??` scripts); **buildroot-engineer** packages them;
**boot-debugger** reads the dmesg. **Write down every init script**, since each one becomes Elixir in M11.

| Task | Agent |
|---|---|
| Prioritise peripherals with the user | orchestrator |
| (child tasks per peripheral) | firmware-hunter, buildroot-engineer |
| Write the init-scripts inventory for Nerves | buildroot-engineer → `$P/dossier/init-inventory.md` |
| GATE M10 | orchestrator |

**Exit:** the chosen peripherals work in Buildroot; the init inventory lists every script, daemon and blob.
**Lesson:** "Firmware blobs: tiny programs for tiny computers inside the phone".

---

## M11: Nerves system (risk-orange)

**Goal:** a Nerves system with A/B updates, living inside the Android partition table.

| Task | Agent | Notes |
|---|---|---|
| Design the A/B layout inside Android partitions | nerves-architect | Usually a sub-image in `userdata` (MBR + fwup env + rootfs A/B + app f2fs) mapped by an initramfs (kpartx/losetup), or using `boot`+`system`+`userdata`; ADR |
| Bootstrap the Nerves system | nerves-architect | `nerves_system_bootstrap` from the Buildroot defconfig, then adapt: toolchain, kernel options (squashfs, f2fs, gadget built in), erlinit.config, fwup.conf, fwup-ops.conf |
| Boot flow for slot switching | nerves-architect | How the bootloader (lk2nd extlinux / U-Boot env / initramfs) picks the active slot; how revert works |
| Port init scripts to Elixir | nerves-architect | From init-inventory.md: VintageNet (WiFi/QMI), custom OTP apps for firmware loaders, rmtfs, etc. |
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
| Compile the learner journal | tutor |
| GATE M12 | orchestrator |
