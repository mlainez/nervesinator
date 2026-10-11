#!/bin/sh
# Bring up USB networking on the phone.
# - If the kernel has the legacy g_ether built in, usb0 already exists: just configure it.
# - Otherwise build an NCM + RNDIS gadget through configfs and bind it to the first UDC.
# Then serve exactly one DHCP lease with unudhcpd: phone 10.0.42.1, computer 10.0.42.2.
IP=${IP:-10.0.42.1}
CLIENT=${CLIENT:-10.0.42.2}
G=/sys/kernel/config/usb_gadget/g1

wait_for() { i=0; while [ ! -e "$1" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; }

if ! ip link show usb0 >/dev/null 2>&1; then
  if [ ! -d /sys/kernel/config/usb_gadget ]; then
    echo "usb-gadget: no configfs usb_gadget and no usb0 (enable CONFIG_USB_CONFIGFS_NCM or CONFIG_USB_ETH)"
    exit 1
  fi
  wait_for /sys/class/udc
  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  [ -n "$UDC" ] || { echo "usb-gadget: no UDC found (USB controller/PHY driver missing?)"; exit 1; }
  mkdir -p $G
  echo 0x18d1 > $G/idVendor
  echo 0xd001 > $G/idProduct
  mkdir -p $G/strings/0x409
  echo "porting-kit" > $G/strings/0x409/manufacturer
  echo "Rescue initramfs" > $G/strings/0x409/product
  echo "$(cat /proc/sys/kernel/random/boot_id | cut -c1-8)" > $G/strings/0x409/serialnumber
  mkdir -p $G/configs/c.1/strings/0x409
  echo "NCM+RNDIS" > $G/configs/c.1/strings/0x409/configuration
  if mkdir -p $G/functions/ncm.usb0 2>/dev/null; then
    ln -s $G/functions/ncm.usb0 $G/configs/c.1/
  fi
  if mkdir -p $G/functions/rndis.usb1 2>/dev/null; then
    ln -s $G/functions/rndis.usb1 $G/configs/c.1/
  fi
  echo "$UDC" > $G/UDC
  wait_for /sys/class/net/usb0
fi

ip addr add $IP/24 dev usb0 2>/dev/null
ip link set usb0 up
if command -v unudhcpd >/dev/null; then
  unudhcpd -i usb0 -s $IP -c $CLIENT >/dev/null 2>&1 &
fi
echo "usb-gadget: usb0 up at $IP (computer gets $CLIENT)"
