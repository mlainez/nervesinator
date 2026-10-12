#!/usr/bin/env bash
# Find the USB network interface of a phone running the rescue/buildroot system and check that it
# answers at 10.0.42.1. Never changes the host network on its own: prints the command if needed.
# Usage: tools/usbnet.sh [phone-ip]
set -u
IP=${1:-10.0.42.1}
ifc=""
for d in /sys/class/net/*; do
  drv=$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)" 2>/dev/null)
  case "$drv" in cdc_ncm|cdc_ether|rndis_host|cdc_eem) ifc=$(basename "$d"); break ;; esac
done
[ -n "$ifc" ] || { echo "no USB network interface (cdc_ncm/cdc_ether/rndis_host) found: is the phone booted into the rescue system?"; exit 1; }
echo "interface: $ifc ($drv)"
for i in $(seq 1 15); do
  addr=$(ip -4 -o addr show dev "$ifc" | awk '{print $4}')
  [ -n "$addr" ] && break; sleep 1
done
if [ -z "${addr:-}" ]; then
  echo "no IPv4 address on $ifc yet (DHCP from unudhcpd failed?). Set one manually, for example:"
  echo "  nmcli dev set $ifc managed yes && nmcli con add type ethernet ifname $ifc ipv4.method auto"
  echo "  or: sudo ip addr add 10.0.42.2/24 dev $ifc && sudo ip link set $ifc up"
  exit 1
fi
echo "host address: $addr"
if ping -c 2 -W 2 "$IP" >/dev/null 2>&1; then
  echo "phone answers at $IP:  ssh root@$IP   (rescue password: root)"
  echo "back to the flash mode without keys: tools/return-to-flash.sh --port <id>"
else
  echo "phone does not answer at $IP"; exit 1
fi
