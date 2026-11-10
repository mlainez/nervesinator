# Samsung traps

No `fastboot boot`; download mode (Vol- + Home/Bixby + Power, or `adb reboot download`)
with Heimdall/Odin. **Never** `--repartition`/`--pit`. Flashing anything unofficial trips the
**KNOX warranty e-fuse** (irreversible, Samsung Pay/Knox features gone). Newer models: the "OEM
unlock" toggle + FRP + "RMM/KG state: prenormal" can block flashing ("Only official released
binaries are allowed"). lk2nd and test images go to `BOOT`. Keeping Android is not a goal: download
mode lives in the untouched `aboot` and can always reflash `BOOT`. Flash per partition only: an AP
tar can carry class B images (`persist.img.ext4` on some Qualcomm models), so a whole-AP Odin
flash overwrites calibration. The PIT's `PGPT`, `PIT`, `MD5` and `SGPT` entries are not partitions
to flash. After a heimdall command with `--no-reboot`, the next one in the same download mode
session needs `--resume` (`tools/safe-flash.sh --resume`), or reboot into download mode first.
