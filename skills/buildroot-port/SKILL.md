---
name: buildroot-port
description: Building the device's Buildroot systems in the Spin42/buildroot-android layout - forking/cloning the tree, adding board/<id> (linux.config, overlay, genimage, post-image, scripts), the firstlight/rescue/full defconfigs, kernel from a git fork with LINUX_OVERRIDE_SRCDIR, out-of-tree builds with O=, savedefconfig/linux-update-defconfig, custom packages, and reflash scripts. Use in M7-M10.
---

# Buildroot port (buildroot-android style)

## 0. Reuse before you create

Before writing a package, script, overlay file or config, look for it in
[Spin42/buildroot-android](https://github.com/Spin42/buildroot-android) and reuse or extend it. Add
something new only when nothing fits, and then in the same style.

- **Packages** (`buildroot-external/package/`): `rmtfs`, `qrtr`, `tqftpserv`, `rpmsgexport`,
  `hexagonrpc`, `adsp-boot` (Qualcomm remote processors and their services), `reboot-mode`,
  `unudhcpd`, `first-boot-resize`, `sim-selector`, `alsa-ucm-conf`, `citros-initramfs`, the firmware
  packages (`fp2-firmware`, `fp3-firmware`, `grate-firmware`, `tb3-firmware`) and the MediaTek
  `mt8127-*` connectivity stack.
- **Boards** (`buildroot-external/board/`): `fairphone2` (msm8974), `fairphone3` (sdm632),
  `grouper` (Tegra 3), `tb3_710f` (mt8127), with their scripts (`create_boot_image.sh`, `flash.sh`,
  `reflash.sh`, `install_rootfs.sh`, `prepare_firmware.sh`, `mkrescue_image.sh`) and `docs/tb3_710f.md`.
- **Closest board first:** copy patterns from the board of the same SoC family (FP2's msm8974 for an
  msm8226 phone's WCNSS, modem and remoteproc), then from any board with the same boot path.

## 1. The tree

Work in `ports/<id>/buildroot-android/`, a clone of the user's fork of
[Spin42/buildroot-android](https://github.com/Spin42/buildroot-android) (ask the user for the fork URL;
fall back to the upstream repo and a local branch `port/<id>`):

```bash
git clone --recurse-submodules <fork-url> ports/<id>/buildroot-android
git -C ports/<id>/buildroot-android switch -c port/<id>
```

Layout to add (mirror the existing boards: `fairphone2`, `grouper`, `tb3_710f`):

```
buildroot-external/
  configs/<id>_firstlight_defconfig     M7
  configs/<id>_rescue_defconfig         M8
  configs/<id>_defconfig                M9 (the real system)
  board/<id>/linux.config               full kernel config (savedefconfig output)
  board/<id>/linux-firstlight.fragment  optional
  board/<id>/overlay/                   /etc (fstab, network/interfaces, dhcp, ssh), extlinux/ if lk2nd
  board/<id>/rescue-overlay/            from templates/rescue
  board/<id>/genimage.cfg               when an image of userdata is produced
  board/<id>/overlay/extlinux/extlinux.conf   the default layout: the rootfs image itself is the
                                        ext2 userdata image (BR2_TARGET_ROOTFS_EXT2_2r1=y,
                                        BR2_LINUX_KERNEL_INSTALL_TARGET=y for /boot); see
                                        boot-images section 3 for the ext2 rules
  board/<id>/post-image.sh              packs boot.img (mkbootimg args from port.yaml device.bootimg)
  board/<id>/scripts/flash.sh           flashes by serial only, checks the product (copy tb3_710f's)
  board/<id>/scripts/reflash.sh         reboot-mode <device.return_mode> (tools/return-to-flash.sh)
                                        → fastboot or heimdall flash → wait for ssh; no keys
  package/<id>-firmware/                proprietary blobs (not committed: see firmware-userspace)
docs/<id>.md                            what works, how to flash (tb3_710f.md is the model)
```

The external tree's name is `ANDROID`, so paths use `$(BR2_EXTERNAL_ANDROID_PATH)`.

## 2. Build out of tree, one output dir per defconfig

```bash
cd ports/<id>/buildroot-android/buildroot
make BR2_EXTERNAL=../buildroot-external O=$PWD/../../output/firstlight <id>_firstlight_defconfig
make O=$PWD/../../output/firstlight -j$(nproc)          # run in the background; teach meanwhile
```

Outputs go to `ports/<id>/output/<name>/images/` (git-ignored). First builds take 30–90 min
(toolchain + kernel); the next ones are incremental.

## 3. Kernel from a fork

```
BR2_LINUX_KERNEL_CUSTOM_GIT=y
BR2_LINUX_KERNEL_CUSTOM_REPO_URL="<repo from the M2 decision>"
BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION="<tag or commit SHA, pinned>"
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_ANDROID_PATH)/board/<id>/linux.config"
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="<vendor>/<dtb-name-without-.dtb>"
BR2_LINUX_KERNEL_APPENDED_DTB=y            # when the bootloader wants zImage-dtb
BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_X_Y=y   # match the kernel version
```

To iterate on kernel code, use a local checkout: `output/<name>/local.mk` with
`LINUX_OVERRIDE_SRCDIR = /path/to/linux` and `make linux-rebuild`.

Kernel config workflow: `make linux-menuconfig` → `make linux-update-defconfig` (writes back to
`board/<id>/linux.config`). Buildroot config: `make menuconfig` → `make savedefconfig`.

## 4. Packages

Copy the style of the existing packages in `buildroot-external/package/` (`Config.in` + `.mk`,
`generic-package`/`meson-package`/`cmake-package`, init scripts `S??name`), and add each one to
`buildroot-external/Config.in`. Reuse what's already there: `unudhcpd`, `qrtr`, `rmtfs`, `tqftpserv`,
`hexagonrpc`, `first-boot-resize`, `reboot-mode`, `sim-selector`.

## 5. Rules

- The Buildroot board has a single root filesystem. Never design A/B slots, a slot switcher
  or a custom update loader for it: A/B comes with Nerves (M11, standard fwup).
- Pin every git version (kernel, packages) to a tag or SHA in committed defconfigs.
- Every init script added for hardware → a line in `dossier/init-inventory.md`: what it does, why,
  in what order, what it depends on. Nerves (M11) replaces each one with Elixir.
- Never commit proprietary blobs; packages fetch them from a local path prepared by a script.
- The flash scripts address the device by serial and refuse if the product doesn't match.
- Commit in the buildroot-android clone with clear messages; the port repo records the commit SHA in
  task notes.

## 6. Shell scripts that run on the device

Every script that runs on the phone (init scripts, overlays, bring-up helpers, test images) is
POSIX `sh` for BusyBox `ash`, and uses only what **that** image's BusyBox has:

- No bashisms: no `[[ ]]`, arrays, `$'...'`, process substitution, `function`, `source`.
- Check the applet and the option before using them: `busybox --list` on the device, or the image's
  BusyBox config (Buildroot: `output/<name>/build/busybox-*/.config`; Nerves: the system's busybox
  fragment over `nerves_system_br`'s default). Images differ: the Nerves BusyBox has no `od`,
  `timeout` or `mountpoint`, and no `head -c` (FEATURE_FANCY_HEAD), while a Buildroot board's
  BusyBox may have them; the Android 4.4 toolbox has none of `head`/`tail`/`tr`/`basename`/`which`.
- Portable forms: `dd bs=N count=1 2>/dev/null` instead of `head -c`/`tail -c`; a `sleep 1` loop
  instead of `timeout`; `grep -q " $dir " /proc/mounts` instead of `mountpoint`; whole seconds for
  `sleep`; `hexdump`/`xxd` only when listed. No GNU-only options (`grep -P`, `sed -E` unchecked,
  `stat -c` formats, `date -d`, `readlink -e`, `sort -V`, `xargs -d`).
- Never hide the errors of a step whose result matters: log failures to `/dev/kmsg` and check the
  result (a MAC address must match its format before it is written anywhere).
- Test in the exact image the script ships in (on the device, or in qemu with that BusyBox):
  `sh -n` on the host checks syntax only, not applets or options. To check an applet or option on
  the host, run the image's own BusyBox: `qemu-arm-static -L <unpacked root> <unpacked root>/bin/busybox
  <applet> --help` (`qemu-aarch64-static` on arm64), for the initramfs as well as the rootfs.
- Read the **screen console** as well as dmesg: a script's stderr goes to the console, not the
  kernel log (an unsupported `mdev -d` printed its usage on the screen at every boot and never
  reached dmesg). On a running system, capture what the user sees (`nerves-port` section 7).
- In Nerves, work done after the BEAM starts belongs in Elixir (`File`, `:binary`, `System.cmd`
  with checked output), not in shell: Nerves keeps BusyBox minimal on purpose.

## 7. Iterate with scp, checkpoint with a full build (M10, M11)

Once a persistent system with ssh runs, peripheral work does not rebuild and reflash the whole
system for each try.

**Iterate.** Rebuild only what changed, copy it over the USB network, test over ssh:

- DTS only: `make dtbs` (or the single `<vendor>/<board>.dtb` target) in the kernel tree or in
  `output/<name>/build/linux-*`. Not `make linux-rebuild`: with `LINUX_OVERRIDE_SRCDIR` its rsync
  touches every timestamp and recompiles the whole kernel (minutes per try).
- Kernel code or config: `make linux-rebuild`, or a direct kernel build; modules with
  `make modules_install INSTALL_MOD_PATH=<dir>`.
- One package: `make <pkg>-rebuild`.
- Copy with `scp -O` (the legacy protocol: dropbear has no `sftp-server`, which modern OpenSSH `scp`
  needs by default) to where the system reads it: `/boot` (as `extlinux.conf` names them),
  `/lib/modules/<version>` then `depmod`, `/lib/firmware`, `/etc`, single binaries.
- Reload the module or reboot, test over ssh, and log the try in
  `journal/peripherals/<peripheral>.md` (what changed, the result).

**Keep a way back with nobody there.** Never overwrite the known-good kernel or DTB in place. A
test kernel boots once, through a mechanism that falls back on its own:

1. `kexec` from the running system (`kexec -l /boot/zImage-test --dtb=/boot/test.dtb
   --reuse-cmdline && kexec -e`), when the SoC supports it: the next reboot is the good kernel.
2. A RAM boot through the second stage's fastboot (`tools/return-to-flash.sh`, then
   `tools/await-boot.sh` with a boot.img of the test kernel and `root=` on the installed rootfs),
   when that fastboot is reachable by command (not on Samsung, where the return mode is download).
3. A bootloader one-shot or boot counter, if the bootloader has one. An extlinux `default` switched
   to the test label and switched back "after a good boot" is **not** a fallback: a test kernel
   that never boots never switches it back, and the phone loops.

With none of these, kernel tries are attended. Panic reboot (`panic=10`) and the watchdog cover
crashes; an early hang with no watchdog still needs hands.

**Checkpoint.** When a peripheral works, fold the changes into the tree (`linux-update-defconfig`,
DTS patches in `board/<id>/linux-patches/`, packages, overlay files), run a full build of the
defconfig from a clean output directory, install it the vendor's key-free way
(`tools/return-to-flash.sh`, then fastboot or heimdall `userdata`), and verify again from the clean
image: the peripheral, boot, ssh, reboot, and the return to the flash mode. Commit, tag
`checkpoint/<id>/<peripheral>` in buildroot-android, and record the tag in the backlog task.
