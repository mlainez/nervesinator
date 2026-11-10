# Huawei / HiSilicon (Kirin) traps

The boot chain is `xloader`, `fastboot` (the bootloader partition
itself), `vector`, `fw_lpm3`, `teeos`, `trustfirmware`, `sensorhub`, `hisee_*`, `bl2`; `nvme`
(IMEI, MACs, the unlock-code hash, FBLOCK), `oeminfo` and `modemnvm_*`/`modem_secure`/`modem_om`
are class B (all on the forbidden list). Huawei fastboot refuses most getvars ("Command not
allowed"): read the model with `fastboot oem get-product-model`, the state with
`oem lock-state info`, `oem get-build-number`, `oem get_bootinfo`. There is no `fastboot boot`, so
no RAM boot: test images go to an experiment partition (e.g. `recovery_ramdisk`). Treble Kirin
devices have no `boot` partition: the kernel image is in `kernel`, the ramdisk in `ramdisk`, and
recovery is `recovery_ramdisk` + `recovery_vendor` sharing that `kernel`. The DTB comes from the
`dts` partition (Huawei's own format) plus `dto` (both forbidden by default: a port that needs
its own DTB there decides it with the user, through an override). `ptable`, `vrl*`, the
eRecovery partitions and the unknown vendor partitions are on the forbidden list too. A dload or
service ROM writes class A itself through the vendor updater: a user-run path only. Versions:
`oem get-build-number` gives the base version + cust + preload (e.g. `9.1.0.401(C432E13R1P7)`),
which differs from `ro.build.display.id`; anti-rollback compares the base version, so a
restore uses the same or a newer base. Huawei stopped giving unlock codes in
2018; the community path (PotatoNV through a test point) writes `nvme`, class B: only with the
user's override, after explaining it. BootROM rescue mode enumerates as `12d1:3609` ("USB COM 1.0")
and `hisi-idt` loads images there: rung 3 of the unbrick ladder, run by the user. Never relock.
EMUI's by-name directory carries a dangling `boot_a -> kernel_a` alias: it is not an A/B slot
(`device.android_ab` stays false).
