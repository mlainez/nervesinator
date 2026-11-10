#!/usr/bin/env bash
# Build the generic first-light and rescue initramfs for both architectures and publish them as a
# release, so that no port builds its test images' userspace from source.
# Usage: tools/publish-prebuilt.sh --tree <buildroot-android checkout> --tag <tag> [--only-pack] [--execute]
#
# Builds configs/{firstlight,rescue}_{aarch64,armv7}_defconfig out of tree (through
# tools/br-make.sh, so downloads are shared), collects <image>-<arch>.cpio.gz and SHA256SUMS in
# cache/prebuilt/<tag>/, and prints the release command. --only-pack skips the builds and packs
# what cache/prebuilt-build/ already holds. --execute creates the release with `gh` in the
# repository named in tools/lib/prebuilt.conf; without it nothing leaves this machine.
# Afterwards set PREBUILT_VERSION=<tag> in tools/lib/prebuilt.conf.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tools/lib/prebuilt.conf"
TREE=""; TAG=""; PACK=0; EXEC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) TREE=$2; shift 2 ;;
    --tag) TAG=$2; shift 2 ;;
    --only-pack) PACK=1; shift ;;
    --execute) EXEC=1; shift ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
  esac
done
[ -n "$TAG" ] && [ -d "$TREE/buildroot" ] && [ -d "$TREE/buildroot-external" ] || { sed -n '2,12p' "$0"; exit 2; }
TREE=$(cd "$TREE" && pwd)
BUILD="$KIT/cache/prebuilt-build"; D="$KIT/cache/prebuilt/$TAG"; mkdir -p "$BUILD" "$D"

for arch in aarch64 armv7; do
  for image in firstlight rescue; do
    O="$BUILD/$image-$arch"
    if [ $PACK = 0 ]; then
      echo "== building ${image}_${arch}_defconfig"
      "$KIT/tools/br-make.sh" "$TREE/buildroot" O="$O" BR2_EXTERNAL="$TREE/buildroot-external" "${image}_${arch}_defconfig" >/dev/null \
        && "$KIT/tools/br-make.sh" "$TREE/buildroot" O="$O" -j"$(nproc)" > "$O.log" 2>&1 \
        || { echo "build failed: $O.log"; exit 1; }
    fi
    [ -f "$O/images/rootfs.cpio.gz" ] || { echo "missing $O/images/rootfs.cpio.gz"; exit 1; }
    cp "$O/images/rootfs.cpio.gz" "$D/$image-$arch.cpio.gz"
  done
done
(cd "$D" && sha256sum firstlight-*.cpio.gz rescue-*.cpio.gz > SHA256SUMS && cat SHA256SUMS)
SRC=$(git -C "$TREE" rev-parse HEAD 2>/dev/null)
[ -z "$(git -C "$TREE" status --porcelain 2>/dev/null)" ] || echo "warning: $TREE has uncommitted changes: the release would not match commit $SRC"
CMD=(gh release create "$TAG" --repo "$PREBUILT_REPO" --target "$SRC" --title "Prebuilt test images $TAG"
     --notes "Generic first-light and rescue initramfs for aarch64 and armv7, built from commit $SRC."
     "$D"/firstlight-aarch64.cpio.gz "$D"/firstlight-armv7.cpio.gz "$D"/rescue-aarch64.cpio.gz "$D"/rescue-armv7.cpio.gz "$D"/SHA256SUMS)
echo "release command:"; printf ' %q' "${CMD[@]}"; echo
if [ $EXEC = 1 ]; then
  "${CMD[@]}" && echo "published: now set PREBUILT_VERSION=$TAG in tools/lib/prebuilt.conf"
else
  echo "dry run: nothing was published. Re-run with --only-pack --execute to create the release."
fi
