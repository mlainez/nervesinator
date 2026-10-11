# Reading list

All links below were checked to resolve when this list was written. Recommend at most two at a
time, matched to the current milestone and `learner.level` (🟢 beginner-friendly, 🟡 intermediate,
🔴 deep dive).

## The big picture (M0)

- 🟢 [Will it run Nerves? (talk notes)](https://github.com/mlainez/NervesMeetupEU-Will-it-run-nerves): the whole journey from bootloader to Nerves on exotic devices, with the Fairphone 2 and Kobo stories.
- 🟢 [Porting Nerves to a new device](https://hexdocs.pm/nerves/porting-guide.html): the official guide; read "A quick refresher on how Linux boots" first.
- 🟢 [Running Nerves on Android e-waste (forum thread)](https://elixirforum.com/t/running-nerves-on-android-e-waste/70187): real-world logs of porting phones.
- 🟡 [The journey to running Nerves on a Kobo Clara](https://elixirforum.com/t/the-journey-to-running-nerves-on-a-kobo-clara-e-reader/73331): what to do when secure boot says no.
- 🟡 [Bootlin embedded Linux training (free slides)](https://bootlin.com/doc/training/embedded-linux/): the best free course on bootloaders, kernels and rootfs.

## Reconnaissance and Android internals (M1)

- 🟢 [postmarketOS glossary](https://wiki.postmarketos.org/wiki/Glossary): all the acronyms in one place.
- 🟢 [Android partitions (pmOS wiki)](https://wiki.postmarketos.org/wiki/Android_partitions): what each drawer holds.
- 🟡 [Android partitions overview (AOSP)](https://source.android.com/docs/core/architecture/partitions)
- 🟡 [Boot process (pmOS wiki)](https://wiki.postmarketos.org/wiki/Boot_process)

## Prior art (M2)

- 🟢 [postmarketOS device list](https://wiki.postmarketos.org/wiki/Devices): is your phone there?
- 🟢 [Porting to a new device (pmOS)](https://wiki.postmarketos.org/wiki/Porting_to_a_new_device)
- 🟡 [pmaports repository](https://gitlab.postmarketos.org/postmarketOS/pmaports): device packages, kernels, firmware.
- 🟡 [deviceinfo reference](https://wiki.postmarketos.org/wiki/Deviceinfo_reference): how to read a pmOS device's `deviceinfo` (boot image offsets, flash method…).
- 🟡 [Mainlining (pmOS)](https://wiki.postmarketos.org/wiki/Mainlining) and the [Mainlining guide](https://wiki.postmarketos.org/wiki/Mainlining_Guide)
- 🟡 [Device tree for dummies (Thomas Petazzoni, PDF)](https://bootlin.com/pub/conferences/2014/elc/petazzoni-device-tree-dummies/petazzoni-device-tree-dummies.pdf)
- 🔴 [Linux and the devicetree (kernel docs)](https://docs.kernel.org/devicetree/usage-model.html)
- 🔴 [Elixir cross-referencer](https://elixir.bootlin.com/linux/latest/source): browse the kernel source and find any driver or DT binding.
- 🟡 SoC communities: [msm8916-mainline](https://github.com/msm8916-mainline/linux), [msm8226-mainline](https://github.com/msm8226-mainline), [msm8953-mainline](https://github.com/msm8953-mainline/linux), [msm8974-mainline](https://github.com/msm8974-mainline/linux)
- 🟡 Downstream: [LineageOS devices](https://wiki.lineageos.org/devices/), [LineageOS GitHub](https://github.com/LineageOS), [TheMuppets (proprietary blobs)](https://github.com/TheMuppets)

## Unbrick kit, unlocking, chain of trust (M3–M5)

- 🟢 [Fastboot (pmOS wiki)](https://wiki.postmarketos.org/wiki/Fastboot)
- 🟢 [Heimdall (pmOS wiki)](https://wiki.postmarketos.org/wiki/Heimdall), [Heimdall (maintained fork)](https://git.sr.ht/~grimler/Heimdall): for Samsung download mode.
- 🟡 [fastboot protocol README (AOSP)](https://android.googlesource.com/platform/system/core/+/main/fastboot/README.md)
- 🟡 [Verified boot flow (AOSP)](https://source.android.com/docs/security/features/verifiedboot/boot-flow): what the orange/yellow/red boot states mean.
- 🔴 [Android Verified Boot 2.0 README](https://android.googlesource.com/platform/external/avb/+/main/README.md)
- 🔴 [mtkclient](https://github.com/bkerler/mtkclient) and [edl](https://github.com/bkerler/edl): MediaTek BROM and Qualcomm EDL tools (read-only use in this kit).

## Boot images and second-stage bootloaders (M6)

- 🟢 [lk2nd (pmOS wiki)](https://wiki.postmarketos.org/wiki/Lk2nd)
- 🟡 [lk2nd repository](https://github.com/msm8916-mainline/lk2nd): supported SoCs/devices and how it boots extlinux.
- 🟡 [Boot image header (AOSP)](https://source.android.com/docs/core/architecture/bootloader/boot-image-header): versions 0 to 4.
- 🟡 [mkbootimg (AOSP)](https://android.googlesource.com/platform/system/tools/mkbootimg/)
- 🔴 [U-Boot on Qualcomm](https://docs.u-boot.org/en/latest/board/qualcomm/index.html) and [all U-Boot boards](https://docs.u-boot.org/en/latest/board/index.html)

## First light and rescue shell (M7–M8)

- 🟢 [USB Internet (pmOS)](https://wiki.postmarketos.org/wiki/USB_Internet)
- 🟢 [unudhcpd](https://gitlab.postmarketos.org/postmarketOS/unudhcpd): the one-client DHCP server.
- 🟡 [Inspecting the initramfs (pmOS)](https://wiki.postmarketos.org/wiki/Inspecting_the_initramfs)
- 🟡 [Dump ramoops (pmOS)](https://wiki.postmarketos.org/wiki/Dump_ramoops): read the kernel's last words after a crash.
- 🟡 [Serial debugging (pmOS)](https://wiki.postmarketos.org/wiki/Serial_debugging)
- 🟡 [ramfs, rootfs and initramfs (kernel docs)](https://docs.kernel.org/filesystems/ramfs-rootfs-initramfs.html)
- 🔴 [USB gadget configfs (kernel docs)](https://docs.kernel.org/usb/gadget_configfs.html)
- 🔴 [ramoops (kernel docs)](https://docs.kernel.org/admin-guide/ramoops.html), [kernel parameters](https://docs.kernel.org/admin-guide/kernel-parameters.html), [serial console](https://docs.kernel.org/admin-guide/serial-console.html)

## Buildroot (M9)

- 🟢 [Bootlin Buildroot training (free slides)](https://bootlin.com/doc/training/buildroot/)
- 🟡 [Buildroot manual](https://buildroot.org/downloads/manual/manual.html): read "Customization outside Buildroot" (BR2_EXTERNAL) and "Adding new packages".
- 🟡 [buildroot-android](https://github.com/Spin42/buildroot-android): the reference layout for Android devices (FP2, Nexus 7, TB3-710F).

## Hardware enablement (M10)

- 🟡 [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/)
- 🟡 Qualcomm userspace: [rmtfs](https://github.com/linux-msm/rmtfs), [qrtr](https://github.com/linux-msm/qrtr), [tqftpserv](https://github.com/linux-msm/tqftpserv), [pd-mapper](https://github.com/linux-msm/pd-mapper)
- 🔴 [DSI panel driver generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator): turns a downstream panel DT into a mainline driver.

## Nerves (M11)

- 🟢 [Nerves getting started](https://hexdocs.pm/nerves/getting-started.html)
- 🟡 [Anatomy of a Nerves system](https://hexdocs.pm/nerves/systems.html), [Customizing systems](https://hexdocs.pm/nerves/customizing-systems.html)
- 🟡 [nerves_system_bootstrap](https://github.com/mlainez/nerves_system_bootstrap): generate a Nerves system from a Buildroot defconfig.
- 🟡 [nerves_system_br](https://github.com/nerves-project/nerves_system_br), [erlinit](https://github.com/nerves-project/erlinit), [fwup](https://github.com/fwup-home/fwup)
- 🟡 [nerves_system_bbb](https://github.com/nerves-project/nerves_system_bbb): a clean reference system to copy from.
- 🟡 [Nerves toolchains](https://github.com/nerves-project/toolchains/releases)
- 🟢 [VintageNet](https://hexdocs.pm/vintage_net/readme.html), [NervesSSH](https://hexdocs.pm/nerves_ssh/readme.html)
