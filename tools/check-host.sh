#!/usr/bin/env bash
# Check the host tools needed by the porting kit, grouped by the stage that needs them.
# Usage: tools/check-host.sh            exit 1 if a tool needed now (S1 Scout) is missing
set -u
. /etc/os-release 2>/dev/null || true
case "${ID:-}${ID_LIKE:-}" in
  *fedora*) PM="sudo dnf install" ;; *debian*|*ubuntu*) PM="sudo apt install" ;;
  *arch*) PM="sudo pacman -S" ;; *suse*) PM="sudo zypper install" ;; *) PM="(your package manager) install" ;;
esac
[ -e /run/ostree-booted ] && echo "note: immutable OS detected: install build tools in a toolbox/distrobox container"
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ -e "$KIT/tools/AGENTS.md" ] || [ -d "$KIT/tools/skills" ] && \
  echo "warning: a copy of the kit sits inside tools/ (tools/AGENTS.md, tools/skills…): remove it, the kit belongs at the project root"
missing_now=0
chk() { # group tool package-hint
  if command -v "$2" >/dev/null 2>&1; then printf "  ✅ %-14s %s\n" "$2" "$(command -v "$2")"
  else printf "  %s %-14s -> %s\n" "$([ "$1" = now ] && echo ❌ || echo ⏳)" "$2" "$3"; [ "$1" = now ] && missing_now=1; fi
}
echo "== Needed now (S1 Scout, S2 Open)"
chk now adb      "$PM android-tools (or adb)"
chk now fastboot "$PM android-tools (or fastboot)"
chk now git      "$PM git"
chk now python3  "$PM python3"
chk now curl     "$PM curl"
chk now lsusb    "$PM usbutils"
chk later backlog "npm i -g backlog.md   (or: bun add -g backlog.md); tracks peripherals and discovered work"
echo "== Device-specific flash tools (when the device needs them)"
chk later heimdall "Samsung: $PM heimdall (or build https://git.sr.ht/~grimler/Heimdall)"
chk later edl      "Qualcomm EDL reads: pip install --user edlclient (https://github.com/bkerler/edl)"
chk later mtk      "MediaTek BROM: https://github.com/bkerler/mtkclient"
echo "== Boot images and kernels (S3 Boot from RAM)"
chk later mkbootimg "pip install --user mkbootimg (or buildroot-android board/tb3_710f/scripts/mkbootimg.py)"
chk later dtc       "$PM dtc"
chk later cpio      "$PM cpio"
chk later lz4       "$PM lz4"
echo "== Kernel and Buildroot builds (S3 on)"
for t in make gcc g++ patch perl rsync bc bison flex unzip file wget which tar xz; do chk later "$t" "$PM $t"; done
echo "== Nerves (S4)"
if grep -qE "^hosts:.*mdns" /etc/nsswitch.conf 2>/dev/null; then
  echo "  ✅ mDNS name resolution (nss-mdns) for nerves.local"
else
  echo "  ⏳ no mDNS in /etc/nsswitch.conf: ssh nerves.local will not resolve ($PM nss-mdns avahi;"
  echo "     in a distrobox the container's nsswitch.conf is the one that counts)"
fi
chk later elixir      "https://elixir-lang.org/install.html (asdf/mise recommended)"
chk later mix         "comes with Elixir"
chk later fwup        "https://github.com/fwup-home/fwup#installing"
if command -v fwup >/dev/null && fwup --version 2>&1 | grep -q "No version is set"; then
  echo "  ⚠️  fwup is managed by asdf with no version selected: add it to .tool-versions or set ASDF_FWUP_VERSION"
elif command -v fwup >/dev/null && ! fwup --version >/dev/null 2>&1; then
  echo "  ⚠️  fwup does not run here (missing libraries?): run it where it was installed, e.g. inside the distrobox"
fi
chk later mksquashfs  "$PM squashfs-tools"
chk later mcopy       "$PM mtools"
echo "== Shared caches (cache/)"
for c in buildroot-dl buildroot-ccache prebuilt; do
  if [ -d "$KIT/cache/$c" ]; then echo "  ✅ cache/$c ($(du -sh "$KIT/cache/$c" 2>/dev/null | cut -f1))"
  else echo "  ⏳ cache/$c not created yet"; fi
done
. "$KIT/tools/lib/prebuilt.conf"
echo "  prebuilt test images: ${PREBUILT_VERSION:-no release pinned (tools/lib/prebuilt.conf)}"
echo "== Kit adapter (Claude Code: agents, skills, the guard hook)"
for l in agents skills; do
  if [ -d "$KIT/.claude/$l" ] && [ "$(cd "$KIT/.claude/$l" && pwd -P)" = "$(cd "$KIT/$l" && pwd -P)" ]; then
    echo "  ✅ .claude/$l -> $l/"
  else
    echo "  ❌ .claude/$l does not resolve to $l/: mkdir -p \"$KIT/.claude\" && ln -sfn ../$l \"$KIT/.claude/$l\""; missing_now=1
  fi
done
for h in session_context.py checkpoint.py; do
  grep -q "$h" "$KIT/.claude/settings.json" 2>/dev/null && echo "  ✅ .claude/settings.json runs hooks/$h" \
    || echo "  ⏳ .claude/settings.json does not run hooks/$h (state at session start, port checkpoints): add it (README, Hooks)"
done
for h in device_guard.py start_trigger.py; do
  if grep -q "$h" "$KIT/.claude/settings.json" 2>/dev/null; then
    echo "  ✅ .claude/settings.json runs hooks/$h"
  else
    echo "  ❌ .claude/settings.json does not run hooks/$h: add it (README, Hooks)"; missing_now=1
  fi
done
echo "== USB permissions"
if command -v adb >/dev/null && adb devices 2>/dev/null | grep -q "no permissions"; then
  echo "  ❌ adb reports 'no permissions': install udev rules ($PM android-udev-rules or systemd uaccess) and replug"
  missing_now=1
else
  echo "  ✅ no adb permission problem detected"
fi
[ $missing_now = 0 ] && echo "host ready to scout" || { echo "install the ❌ items, then run again"; exit 1; }
