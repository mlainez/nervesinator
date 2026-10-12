#!/usr/bin/env bash
# Regression tests for hooks/device_guard.py. Usage: tests/test_device_guard.sh
set -u
G="$(cd "$(dirname "$0")/.." && pwd)/hooks/device_guard.py"
fail=0
t() { # expected-label command
  out=$(python3 -I "$G" --check "$2" 2>&1); got=${out%%:*}
  if [ "$got" != "$1" ]; then echo "FAIL want=$1 got=$out :: $2"; fail=1; else echo "ok   $1  $2"; fi
}
t ALLOW "adb devices -l"
t ALLOW "adb -s X shell getprop ro.product.device"
t ALLOW "fastboot -s X getvar all"
t ALLOW "fastboot -s X boot out/boot.img"
t ALLOW "fastboot -s X oem log"
t ALLOW "heimdall print-pit"
t ALLOW "grep 'fastboot flash aboot' notes.md"
t ALLOW "dd if=/dev/zero of=out.img bs=1M count=8"
t ALLOW "adb -s X shell su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot.img'"
t ALLOW "edl printgpt"
t ALLOW "tools/safe-flash.sh --port samsung-x flash boot boot.img"
t ASK   "fastboot -s X flash boot boot.img"
t ASK   "fastboot -s X flash boot_a lk2nd.img"
t ASK   "fastboot -s X flashing unlock"
t ASK   "fastboot -s X oem unlock"
t ASK   "fastboot -s X -w"
t ASK   "heimdall flash --BOOT lk2nd.img --no-reboot"
t ASK   "ssh root@10.0.42.1 'dd if=/tmp/rootfs.ext4 of=/dev/mmcblk0p7 bs=1M'"
t ASK   "adb -s X shell su -c 'dd if=/sdcard/b.img of=/dev/block/by-name/boot'"
t ASK   "tools/safe-flash.sh --port samsung-x --execute flash boot boot.img"
t ASK   "tools/safe-flash.sh --port samsung-x --resume --execute flash recovery twrp.img"
t ALLOW "tools/safe-flash.sh --port samsung-x --execute boot first-light.img"
t ASK   "tools/safe-flash.sh --port boot --mode fastboot --execute flash boot boot.img"
t ASK   "tools/safe-flash.sh --port samsung-x --execute unlock"
t ALLOW "tools/await-boot.sh --port samsung-x --image first-light.img --timeout 120"
t ASK   "tools/await-boot.sh --port samsung-x --image a.img; fastboot -s X flash boot a.img"
t ASK   "mtk da seccfg unlock"
t DENY  "fastboot flash boot boot.img"
t DENY  "fastboot -s X flash aboot lk2nd.img"
t DENY  "fastboot -s X flash sbl1_a x.img"
t DENY  "fastboot -s X erase persist"
t DENY  "fastboot -s X flashing lock"
t DENY  "fastboot -s X oem lock"
t DENY  "fastboot -s X flashall"
t DENY  "heimdall flash --repartition --pit s.pit --BOOT b.img"
t DENY  "heimdall flash --ABOOT x.img"
t DENY  "heimdall flash --EFS x.img"
t DENY  "odin4 -b BL.tar.md5"
t DENY  "edl w aboot x.img"
t DENY  "mtk w preloader x.bin"
t DENY  "sudo dd if=img of=/dev/sda bs=4M"
t DENY  "adb -s X shell su -c 'dd if=x of=/dev/block/mmcblk0boot0'"
t DENY  "adb -s X shell su -c 'dd if=x of=/dev/block/mmcblk0'"
t DENY  "adb -s X shell su -c 'dd if=x of=/dev/block/platform/msm_sdcc.1/by-name/modemst1'"
t DENY  "ssh root@10.0.42.1 sgdisk -Z /dev/mmcblk0"
t DENY  "ssh root@10.0.42.1 'echo 0 > /sys/block/mmcblk0boot0/force_ro'"
t DENY  "bash -c 'fastboot -s X flash tz tz.img'"
t DENY  "echo ZmFzdGJvb3Q= | base64 -d | sh # fastboot"
# Host block devices (a phone in USB mass storage mode, or the wrong disk) and U-Boot fastboot
t ASK   "fwup -a -d /dev/sdb -i app.fw -t complete"
t ASK   "sudo fwup -a -i app.fw -t upgrade"
t ALLOW "fwup -a -i app.fw -t complete -d test.img"
t ALLOW "fwup -c -f fwup.conf -o app.fw"
t ASK   "mix burn"
t DENY  "fastboot -s X oem run:mw 0x0 0"
t DENY  "fastboot -s X oem run reset"
t ALLOW "fastboot -s X oem console"
t ALLOW "fastboot -s X oem ums"
t ALLOW "fastboot -s X oem board:ums"
t ALLOW "fastboot -s X oem board:console"
t DENY  "fastboot -s X oem board:run"
t DENY  "fastboot -s X oem board:run:reset"
t ASK   "fastboot -s X oem board:something-else"
# heredoc bodies written to a file are text; bodies fed to a shell are commands
t ALLOW $'cat > notes.md <<\'EOF\'\nroot shell over telnet; mmcblk0boot0 force_ro=1\nEOF'
t ALLOW $'tee notes.md <<EOF\nfastboot -s X flash aboot x.img\nEOF'
t DENY  $'cat <<\'EOF\' | ssh root@10.0.42.1 sh\necho 0 > /sys/block/mmcblk0boot0/force_ro\nEOF'
t DENY  $'ssh root@10.0.42.1 sh <<\'EOF\'\nsgdisk -Z /dev/mmcblk0\nEOF'
t DENY  $'bash <<EOF\nfastboot -s X flash tz tz.img\nEOF'

# Full-autonomy grant: ask becomes allow, deny stays deny, agents cannot touch the grant
P=$(mktemp -d); mkdir -p "$P/x"; echo x > "$P/.active"
tg() { # expected-label command
  out=$(python3 -I "$G" --ports "$P" --check "$2" 2>&1); got=${out%%:*}
  if [ "$got" != "$1" ]; then echo "FAIL want=$1 got=$out :: [grant] $2"; fail=1; else echo "ok   $1  [grant] $2"; fi
}
printf '{"mode": "full", "goal": "t", "expires_at": "2999-01-01T00:00:00+00:00"}' > "$P/x/.autonomy-grant"
tg ALLOW "tools/safe-flash.sh --port x --execute flash userdata u.img"
tg DENY  "fastboot -s X flash aboot x.img"
tg DENY  "rm ports/x/.autonomy-grant"
printf '{"mode": "full", "goal": "t", "expires_at": "2000-01-01T00:00:00+00:00"}' > "$P/x/.autonomy-grant"
tg ASK   "tools/safe-flash.sh --port x --execute flash userdata u.img"
rm -r "$P"
exit $fail
