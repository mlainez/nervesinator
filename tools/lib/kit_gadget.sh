# Find the kit's own test images on USB (sourced by detect-devices.sh and await-boot.sh).
# Every image the kit builds enumerates as 1d6b:0104, manufacturer "porting-kit",
# product "<port id>-<image>" (firstlight, rescue, system), serial = device.serial,
# with an ACM serial console (ttyACM on the host) and NCM networking (phone at 10.0.42.1).
KIT_VID=1d6b
KIT_PID=0104
KIT_MANUFACTURER=porting-kit

# Prints one line per kit gadget: "<serial> <product> <tty or -> <net interface or ->".
kit_gadgets() {
  local d tty net
  for d in "${KIT_USB_SYSFS:-/sys/bus/usb/devices}"/*; do
    [ -f "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor")" = "$KIT_VID" ] && [ "$(cat "$d/idProduct")" = "$KIT_PID" ] || continue
    [ "$(cat "$d/manufacturer" 2>/dev/null)" = "$KIT_MANUFACTURER" ] || continue
    tty=$(ls -d "$d"/*/tty/ttyACM* 2>/dev/null | head -1)
    [ -n "$tty" ] && tty=/dev/${tty##*/} || tty=-
    net=$(ls -d "$d"/*/net/* 2>/dev/null | head -1); net=${net##*/}
    echo "$(cat "$d/serial" 2>/dev/null || echo ?) $(cat "$d/product" 2>/dev/null || echo ?) $tty ${net:--}"
  done
}
