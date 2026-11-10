# Stages in detail

Each step lists who does it and the **evidence** that marks it done; `tools/kit-next.sh` checks
exactly that evidence (`tools/lib/kit_next.py`). `$P` is `ports/<id>`. Proofs that leave no file
go in `port.yaml` under `checks:` as `<name>: "<proof>"`.

## S1 Scout (`scout`)

Nothing writes to the device. After recon, the other steps run in parallel.

| Step | Who | Evidence |
|---|---|---|
| Device recon | `researcher` (read-only adb) | `$P/dossier/device.md`, `dossier/partitions.md`; `device.soc`, `device.arch`, `device.flash_mode`, `device.product` |
| Prior art and kernel path | `researcher` | `dossier/prior-art.md`; `path.kernel_repo`, `path.bootloader` |
| Closest existing Nerves system | `researcher` or orchestrator | `path.reference_system` (a repository, or `none`) |
| Unbrick kit | `researcher` + one short hands-on session for the key combos | `dossier/unbrick.md`; `device.return_mode`; stock firmware in `backups/stock/` (or `checks.stock_firmware`) |
| Unlock plan and its costs | `researcher` | `dossier/unlock.md` |
| **Gate G1** | the user | `G1` in `gates_passed`; `learner.accepted_costs` |

## S2 Open (`open`)

| Step | Who | Evidence |
|---|---|---|
| Unlock the bootloader | orchestrator, `tools/safe-flash.sh … unlock` (the guard asks) | `safety.bootloader_unlocked: yes` or `not-needed` |
| Verified backups | orchestrator, `tools/backup-partitions.sh` | `backups/SHA256SUMS`; `safety.backups_verified: true` |
| **Gate G2** | the user types `allow writes <partition…> [no backup <partition…>]` | the write allowlist of the port |

## S3 Boot from RAM (`boot-test`)

| Step | Who | Evidence |
|---|---|---|
| Boot path (second stage or stock, RAM boot method) | orchestrator; `builder` for a chainloaded U-Boot | `path.boot_method`, `safety.ram_boot` |
| First light | `builder` builds, orchestrator runs `tools/await-boot.sh --stage firstlight` | a PASS record in `journal/boots/*-firstlight/` |
| Rescue shell | same, `--stage rescue`, then `tools/usbnet.sh` | a PASS record in `journal/boots/*-rescue/` |
| Linux hardware inventory | `researcher` over ssh | `dossier/partitions-linux.md`, `dossier/raw/linux-dmesg.txt` |

A failed boot goes to `boot-debugger` with its record; loop until PASS.

## S4 Nerves (`nerves-system`)

The host steps start as soon as G1 passed.

| Step | Who | Evidence |
|---|---|---|
| Nerves system scaffold | `builder`, `tools/scaffold-system.sh` | `$P/nerves_system_<name>/mix.exs` |
| A/B layout, proven on a file image | `builder` | `path.nerves_layout`; `checks.fwup_host` |
| Firmware built | `builder` | a `.fw` under `$P/<app>/_build/*/nerves/images/` |
| First Nerves boot | orchestrator: `tools/safe-flash.sh`, then `tools/await-boot.sh --watch-only --stage nerves --host nerves.local` | a PASS record in `journal/boots/*-nerves/` (or `checks.nerves_boot`) |
| Upload and revert | orchestrator | `checks.upload`, `checks.revert` |
| Charging and battery | `researcher` + `builder` | `checks.charging` |

## S5 Peripherals (`peripherals`)

One backlog task per peripheral the user wants (`path.peripherals`), plus the work discovered on
the way. It never blocks S6. `tools/kit-next.sh` shows the number of open tasks.

## S6 Share (`share`)

| Step | Who | Evidence |
|---|---|---|
| README, installer, licence | `builder`; the orchestrator reviews the installer | `README.md`, `install.sh`, `LICENSE` in the Nerves system |
| **Gate G3** | the user | `G3` in `gates_passed` |
| Release | orchestrator | `checks.release` |
| Row in awesome-nerves-systems, line in `tools/lib/family.tsv` | orchestrator | `checks.awesome_row` |

## Optional: the Buildroot branch (`buildroot-port`)

When the user also wants a buildroot-android board (`path.buildroot_branch: true`): a single-root
Buildroot system on `userdata`, with a key-free reflash script, contributed as a pull request. It
branches off after S3 and is independent of S4; rootfs placement is in decisions.md section 3.
