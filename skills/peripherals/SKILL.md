---
name: peripherals
description: Stage S5 of a port - making the peripherals the user wants work, one backlog task each - proprietary firmware blobs (from the device, stock firmware, pmaports firmware packages, linux-firmware), postmarketOS userspace translated for Nerves (rmtfs, qrtr, tqftpserv, pd-mapper, WCNSS, MediaTek CONSYS, Broadcom WiFi), charging, and driver or device-tree fixes in the kernel fork with a fast hardware loop. Use after the first Nerves boot, or when dmesg reports a firmware load or probe failure.
---

# S5 Peripherals

S5 is open-ended and never blocks sharing the port: a system with USB networking, updates and
charging is already worth publishing. Ask the user once which peripherals they want
(`path.peripherals`), then create one backlog task per peripheral (`backlog-workflow`).

| Need | Reference |
|---|---|
| Blobs, daemons, recipes by SoC family, charging | [firmware.md](firmware.md) |
| A driver or device-tree fix | [kernel-work.md](kernel-work.md) |
| How the same peripheral was solved on a similar device | the reference system (`path.reference_system`) and `nerves-system` family.md |

## Per peripheral

1. Start from the exact failure (the `dmesg` line, the missing device) and from the reference
   system's solution when it has the same chip.
2. A `researcher` finds the blobs and the userspace; a `builder` packages them and fixes the
   kernel; `boot-debugger` reads the logs. Independent peripherals run in parallel on the host;
   the device has one owner at a time (`tools/device-owner.sh`).
3. Define the acceptance test before the first try. Iterate by copying only what changed
   (`scp -O`, `mix upload`), then checkpoint: a clean full build, a key-free install, the test
   again, a tagged commit.
4. Blobs are never committed: a `prepare_firmware.sh` copies them from the backups or the device.
   Per-device data (WiFi NV, calibration) never leaves the user's machine.
