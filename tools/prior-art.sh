#!/usr/bin/env bash
# Scan the usual sources for existing Linux work on a port's device and SoC, in one go (host-only).
# Usage: tools/prior-art.sh --port <id> [--codename <name>] [--soc <name>]
#
# Clones or updates cache/pmaports and cache/lk2nd (shallow), then reports: the pmaports device
# package and its deviceinfo, the kernel packages for the SoC, sibling devices on the same SoC,
# lk2nd's device tree for the device, and the closest existing Nerves systems. The report goes to
# ports/<id>/dossier/raw/prior-art-scan.txt; reading the files it points at and writing
# dossier/prior-art.md stays the researcher's job (skills/scout/prior-art.md).
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
PORT=""; CODENAME=""; SOC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --codename) CODENAME=$2; shift 2 ;;
    --soc) SOC=$2; shift 2 ;;
    *) sed -n '2,9p' "$0"; exit 2 ;;
  esac
done
P="$KIT/ports/$PORT"; Y="$P/port.yaml"
[ -n "$PORT" ] && [ -f "$Y" ] || { sed -n '2,9p' "$0"; exit 2; }
cfg() { python3 -I "$KIT/tools/lib/portcfg.py" "$Y" "$1" 2>/dev/null; }
[ -n "$CODENAME" ] || CODENAME=$(cfg device.codename)
[ -n "$SOC" ] || SOC=$(cfg device.soc | awk '{print $NF}')
[ -n "$CODENAME" ] || { echo "device.codename is empty in port.yaml (run the recon first, or pass --codename)"; exit 1; }

sync() { # dir url
  if [ -d "$1/.git" ]; then git -C "$1" pull -q --ff-only || echo "note: could not update $1, using the copy on disk"
  else git clone -q --depth 1 "$2" "$1" || { echo "cannot clone $2"; return 1; }; fi
}
mkdir -p "$KIT/cache" "$P/dossier/raw"
PM="$KIT/cache/pmaports"; LK="$KIT/cache/lk2nd"
sync "$PM" https://gitlab.postmarketos.org/postmarketOS/pmaports.git
sync "$LK" https://github.com/msm8916-mainline/lk2nd.git

OUT="$P/dossier/raw/prior-art-scan.txt"
{
  echo "# Prior-art scan for codename '$CODENAME', SoC '${SOC:-unknown}' ($(date -I))"
  echo "pmaports @ $(git -C "$PM" rev-parse --short HEAD 2>/dev/null), lk2nd @ $(git -C "$LK" rev-parse --short HEAD 2>/dev/null)"
  echo
  echo "## pmaports device package"
  found=0
  for d in "$PM"/device/*/device-*"$CODENAME"*; do
    [ -d "$d" ] || continue
    found=1
    echo "${d#"$KIT"/}"
    grep -E '^deviceinfo_(name|arch|dtb|flash_method|flash_offset_|flash_pagesize|kernel_cmdline|bootimg_|append_dtb|header_version|flash_heimdall)' \
      "$d/deviceinfo" 2>/dev/null | sed 's/^/    /'
    grep -E '^(depends|makedepends|subpackages)=|linux-|lk2nd|soc-|firmware-' "$d/APKBUILD" 2>/dev/null | head -20 | sed 's/^/    APKBUILD: /'
  done
  [ $found = 1 ] || echo "none named *$CODENAME* (try the model name: grep -rl <model> $PM/device/*/device-*/deviceinfo)"
  if [ -n "$SOC" ]; then
    echo
    echo "## pmaports kernel and firmware packages for $SOC"
    ls -d "$PM"/device/*/linux-*"$SOC"* "$PM"/device/*/firmware-*"$SOC"* 2>/dev/null | sed "s|^$KIT/||" || true
    echo
    echo "## Sibling devices on $SOC (first 25)"
    grep -rli "$SOC" "$PM"/device/*/device-*/deviceinfo 2>/dev/null | head -25 | sed "s|^$KIT/||; s|/deviceinfo$||"
  fi
  echo
  echo "## lk2nd"
  grep -rli "$CODENAME" "$LK/lk2nd/device/dts" 2>/dev/null | sed "s|^$KIT/||" | head -10
  grep -rqi "$CODENAME" "$LK/lk2nd/device/dts" 2>/dev/null || echo "no device tree names '$CODENAME' (check the model, and whether lk2nd supports the SoC at all)"
  echo
  echo "## Existing Nerves systems"
  "$KIT/tools/scaffold-system.sh" --port "$PORT" --list 2>/dev/null
} > "$OUT"
cat "$OUT"
echo
echo "saved: ${OUT#"$KIT"/}"
