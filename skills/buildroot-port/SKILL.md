---
name: buildroot-port
description: Building the device's Buildroot systems in the Spin42/buildroot-android layout - forking/cloning the tree, adding board/<id> (linux.config, overlay, genimage, post-image, scripts), the firstlight/rescue/full defconfigs, kernel from a git fork with LINUX_OVERRIDE_SRCDIR, out-of-tree builds with O=, savedefconfig/linux-update-defconfig, custom packages, and reflash scripts. Use in M7-M10.
---

# Buildroot port (buildroot-android style)

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
  board/<id>/post-image.sh              packs boot.img (mkbootimg args from port.yaml device.bootimg)
  board/<id>/scripts/flash.sh           flashes by serial only, checks the product (copy tb3_710f's)
  board/<id>/scripts/reflash.sh         ssh → bootloader → flash → wait for ssh
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

- Pin every git version (kernel, packages) to a tag or SHA in committed defconfigs.
- Every init script added for hardware → a line in `dossier/init-inventory.md`: what it does, why,
  in what order, what it depends on. Nerves (M11) replaces each one with Elixir.
- Never commit proprietary blobs; packages fetch them from a local path prepared by a script.
- The flash scripts address the device by serial and refuse if the product doesn't match.
- Commit in the buildroot-android clone with clear messages; the port repo records the commit SHA in
  task notes.
