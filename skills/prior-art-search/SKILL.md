---
name: prior-art-search
description: How to find existing Linux work for a device or SoC - cloning and grepping pmaports (deviceinfo, kernel APKBUILDs and configs, firmware packages), the postmarketOS wiki, mainline device trees, SoC mainline communities, lk2nd/U-Boot support, LineageOS device and kernel trees, TheMuppets blobs - and how to grade what you find. Use in M2 and in M10 when looking for peripheral support.
---

# Prior-art search

Goal: answer "who already booted Linux on this device or SoC, with which kernel, how, and what works?"
Every finding goes into `dossier/prior-art.md` with a link/path and a date (last commit).

## 1. pmaports (the richest source)

```bash
mkdir -p cache
[ -d cache/pmaports ] || git clone --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git cache/pmaports
git -C cache/pmaports pull --ff-only
```

Search, from most to least specific (`<codename>` = `ro.product.device`, `<soc>` = msm8226, mt6735…):

```bash
ls -d cache/pmaports/device/*/device-*<codename>*                   # the device package
grep -rl "<codename>\|<model>" cache/pmaports/device/*/device-*/deviceinfo
ls -d cache/pmaports/device/*/linux-*<soc>* cache/pmaports/device/*/linux-*<codename>*
ls -d cache/pmaports/device/*/firmware-*<codename>* cache/pmaports/device/*/firmware-*<soc>*
grep -rl "<soc>" cache/pmaports/device/*/device-*/deviceinfo | head -50   # sibling devices on the same SoC
```

Directories: `device/main` and `device/community` (maintained, usually mainline) vs `device/testing`
(may be downstream or not booting) vs `device/archived`.

What to read in a device package:

| File | What it tells you |
|---|---|
| `deviceinfo` | `deviceinfo_arch`, `deviceinfo_dtb`, `deviceinfo_flash_method` (fastboot/heimdall-bootimg/heimdall-isorec/0xffff…), `deviceinfo_flash_offset_*` and `pagesize` (boot image layout), `deviceinfo_kernel_cmdline`, `deviceinfo_bootimg_qcdt`, `deviceinfo_append_dtb`, `deviceinfo_bootimg_mtk_mkimage`, `deviceinfo_flash_heimdall_partition_*`, `deviceinfo_screen_*`, `deviceinfo_getty` (serial console) |
| `APKBUILD` | depends (firmware packages, `soc-qcom-*`, `lk2nd-*`), subpackages (nonfree firmware), `_pmb_select` |
| `modules-initfs` | modules needed early (display, USB, touch) |
| `*.rules`, `*.conf`, `*.initd` | udev rules, ALSA UCM, services: the userspace the hardware needs |

In the kernel package (`linux-postmarketos-qcom-msm8226`, …): the `APKBUILD` gives `_repository`/`_commit`
or the tarball URL (= our kernel source), and `config-*` is a working kernel config.

## 2. postmarketOS wiki

The device page (`https://wiki.postmarketos.org/wiki/<Vendor>_<Model>_(<vendor>-<codename>)`), the
SoC page (`Qualcomm_Snapdragon_…`, `MediaTek_…`), and the feature table: what works, how to flash, quirks
(volume keys to enter modes, lk2nd notes). Use WebFetch; quote the relevant lines into the dossier.

## 3. Mainline Linux and SoC communities

```bash
# shallow, sparse clone of the DTS directories only (fast)
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git cache/linux
git -C cache/linux sparse-checkout set arch/arm/boot/dts arch/arm64/boot/dts Documentation/devicetree/bindings
grep -rl "<codename>\|<model>" cache/linux/arch/arm*/boot/dts/ | head
ls cache/linux/arch/arm*/boot/dts/*/ | grep -i "<soc>"
```

Then the SoC forks (`msm8916-mainline/linux`, `msm8226-mainline`, `msm8953-mainline/linux`,
`msm8974-mainline/linux`, `sdm845-mainline`, `mainlining/…`, `linux-sunxi`), the
[postmarketOS kernel list](https://wiki.postmarketos.org/wiki/Mainlining) and a GitHub search
(`gh search code "<codename>" --filename "*.dts"`; `gh search repos "<soc> mainline"`).

## 4. Second-stage bootloaders

- **lk2nd** (Qualcomm msm8916/8939/8952/8953/8974/8226/8610/…): clone `cache/lk2nd`,
  `grep -ril "<codename>\|<model>" cache/lk2nd/lk2nd/device/dts/`. Check the releases page for prebuilt
  images per SoC (`lk2nd-msm8226.img`, …) and the README section on the device's vendor (Samsung notes!).
- **U-Boot**: `docs.u-boot.org` board list; Qualcomm chainloaded U-Boot ("qcom" board docs).
- pmaports `boot/` or `main/` packages named `lk2nd-*`, `u-boot-*`.

## 5. Downstream sources (fallback and blob source)

- LineageOS: `github.com/LineageOS/android_device_<vendor>_<codename>` (and the `-common` / SoC
  common trees), `android_kernel_<vendor>_<soc>`: the downstream DT (`arch/arm/boot/dts/qcom/*<codename>*`),
  panel definitions, the defconfig, `proprietary-files.txt` (= the list of blobs and where they live).
- TheMuppets: `github.com/TheMuppets/proprietary_vendor_<vendor>` for the blobs themselves.
- The vendor's open-source release portal (Samsung opensource.samsung.com, …).

## 6. Reusable buildroot-android pieces

List what the port can take from Spin42/buildroot-android (`buildroot-port` section 0): the board of
the closest SoC family, the packages the device's peripherals will need, the scripts to copy.

## 7. Grade and decide

Write `dossier/prior-art.md` with:

1. A table: source, what it is, kernel version/branch, last activity, what works (display, touch,
   USB, WiFi, modem…), how it boots, link.
2. The scenario (A/B/C from `port-playbook` decisions.md) and the recommended kernel
   (repo + commit + defconfig/config file + DTB name), with confidence and reasons.
3. The recommended boot path and whether a second stage exists.
4. Risks and unknowns ("pmOS page says WiFi needs the `wcnss` firmware from the modem partition").
5. What to reuse later: config fragments, firmware packages, udev rules, UCM, services.
