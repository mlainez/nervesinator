---
name: boot-test
description: Stage S3 of a port - prove a boot path from RAM and get a shell. Chooses the second stage (lk2nd, chainloaded mainline U-Boot, or none), packs Android boot images (headers v0-v4, appended DTB, QCDT, Samsung footers, lk2nd extlinux), builds the first-light and rescue images from the prebuilt initramfs, boots them with await-boot and judges the result from the host. Use when tools/kit-next.sh shows stage S3 and whenever a kernel must be packed or test-booted.
---

# S3 Boot from RAM

Temporary before permanent: every image is proven from RAM (`fastboot boot`, or the second
stage's) before anything is written for good. Where no RAM boot exists, `boot` is the experiment
partition and the stock flash mode restores it.

| Need | Reference |
|---|---|
| Which second stage, and why | `port-playbook` decisions.md section 2; `open` unlock.md, "Second-stage bootloaders" |
| Pack a boot image for this bootloader | [boot-images.md](boot-images.md) |
| First-light and rescue images, the kit gadget, kernel options | [test-images.md](test-images.md) |
| No lk2nd for the SoC: chainloaded U-Boot | [uboot-chainload.md](uboot-chainload.md), [soc-notes/](soc-notes/) |

## The loop

1. **Boot path.** Decide the second stage, record it (`path.bootloader`, `path.boot_method`,
   `safety.ram_boot`, `safety.experiment_partition`). A second stage is RAM-booted first when the
   stock bootloader can, then flashed to `boot` with `tools/safe-flash.sh` (allowlisted at G2, so
   it does not ask). Check that the stock flash mode is still reachable afterwards.
2. **Build.** A `builder` agent builds only the kernel, DTB and modules; the userspace is the
   prebuilt initramfs plus the device cpio (`tools/mk-test-initramfs.sh --image firstlight|rescue`).
   Build first light and rescue in one go: they share the kernel.
3. **Boot and judge.**
   ```bash
   tools/await-boot.sh --port <id> --image <boot.img> --stage firstlight
   tools/await-boot.sh --port <id> --image <boot.img> --stage rescue && tools/usbnet.sh
   ```
   PASS, FAIL or HUNG is decided from USB, with nobody at the phone; the record lands in
   `journal/boots/`. A photo is optional. On FAIL, hand the record to `boot-debugger` and loop.
4. **Inventory**, over ssh from the rescue shell (`scout` recon.md, "Linux-side recon"):
   `dossier/raw/linux-dmesg.txt`, `dossier/partitions-linux.md` (block device ↔ name ↔ class), the
   battery readings, and the key-free way back (`tools/return-to-flash.sh`).

The Nerves system (S4) is built on the host while this runs: it only needs the kernel choice.
