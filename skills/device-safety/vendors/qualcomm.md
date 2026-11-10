# Qualcomm traps

`fastboot flash` to `aboot`/`sbl1` = hard brick, and only EDL with a signed firehose
programmer for this exact device saves it. `modemst1/2`, `fsg`, `fsc`, `persist` = IMEI/calibration.
Anti-rollback (`ro.boot.anti_rollback`, Pixel/OnePlus ARB): flashing an *older* stock bootloader
can brick: when restoring, use the same or a newer stock build. Under lk2nd, `getvar product` is
the SoC board name (e.g. `lk2nd-msm8916`): `safe-flash.sh` then matches `getvar lk2nd:compatible`
against `device.lk2nd_compatible`. On some SoCs (seen on msm8226), holding Vol Up + Vol Down while
lk2nd starts reboots into EDL (`05c6:9008`); a battery pull (or a long power-key hold) gets out of it.
