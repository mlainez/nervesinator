# MediaTek traps

`preloader`, `nvram`, `nvdata`, `proinfo`, `protect*`, `seccfg` are untouchable;
SP Flash Tool "Format All + Download" erases calibration: never use it. mtkclient reads are fine.
Many MTK devices reserve a tail of `userdata` (BMT pool/encryption footer): do not grow
filesystems into it. Mainline's last partition can even extend over the BMT pool (seen: 21 MiB
past the scatter's USRDATA), so size and resize filesystems to the **scatter** size. MTK LK's
`fastboot getvar partition-size:*` can be wrong (and list a name several times): take sizes from
the scatter file or Linux sysfs into `device.partition_sizes`; `safe-flash.sh` ignores LK's value
on `mtk-*` flash modes. The scatter file is the source of truth for offsets and sizes; `boot`
and `recovery` often have no Linux block device, so fwup cannot write them from Linux. In
fastboot, `product` is the platform name, not the model. LK honours boot-mode bits in the PMIC
RTC (seen on MT6323: PDN1 bit 13 fastboot, bit 4 recovery), which gives both a key-free
`reboot-mode` from Linux and a boot-once guard (`boot-test/uboot-chainload.md`); check it on the device. LK
arms the watchdog (up to about 31 s): the kernel, U-Boot and Nerves (`nerves_heart`) must feed it.
Scatter names to know: `uboot` is LK, `ebr1/ebr2` are partition records,
`bmtpool`, `kb`/`dkb`, `pro_info` (all on the forbidden list).
