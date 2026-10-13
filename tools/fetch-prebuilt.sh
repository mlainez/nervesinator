#!/usr/bin/env bash
# Put the prebuilt first-light/rescue initramfs for an architecture into cache/prebuilt/<version>/.
# Usage:
#   tools/fetch-prebuilt.sh --arch aarch64|armv7 [--version <tag>]
#   tools/fetch-prebuilt.sh --arch aarch64|armv7 --from-dir <buildroot images dir> --image rescue|firstlight
#
# The version is pinned in tools/lib/prebuilt.conf. Downloads <image>-<arch>.cpio.gz for both
# images and SHA256SUMS from the release, and refuses any file whose sha256 does not match.
# --from-dir imports a local build (output/images/rootfs.cpio.gz) under version "local".
# Prints the directory. Host-only.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tools/lib/prebuilt.conf"
ARCH=""; VERSION=$PREBUILT_VERSION; FROM=""; IMAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH=$2; shift 2 ;;
    --version) VERSION=$2; shift 2 ;;
    --from-dir) FROM=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    *) sed -n '2,11p' "$0"; exit 2 ;;
  esac
done
case "$ARCH" in aarch64|armv7) ;; *) sed -n '2,11p' "$0"; exit 2 ;; esac

if [ -n "$FROM" ]; then
  case "$IMAGE" in rescue|firstlight) ;; *) echo "--from-dir needs --image rescue|firstlight"; exit 2 ;; esac
  [ -f "$FROM/rootfs.cpio.gz" ] || { echo "no rootfs.cpio.gz in $FROM"; exit 1; }
  D="$KIT/cache/prebuilt/local"; mkdir -p "$D"
  cp "$FROM/rootfs.cpio.gz" "$D/$IMAGE-$ARCH.cpio.gz"
  (cd "$D" && { grep -v " $IMAGE-$ARCH.cpio.gz\$" SHA256SUMS 2>/dev/null; sha256sum "$IMAGE-$ARCH.cpio.gz"; } > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS)
  echo "$D"
  exit 0
fi

if [ -z "$VERSION" ]; then
  echo "no prebuilt release is pinned yet (tools/lib/prebuilt.conf): build from source (rescue-initramfs)"
  echo "or import a local build: tools/fetch-prebuilt.sh --arch $ARCH --from-dir <images dir> --image rescue"
  exit 1
fi
D="$KIT/cache/prebuilt/$VERSION"; mkdir -p "$D"
URL="https://github.com/$PREBUILT_REPO/releases/download/$VERSION"
curl -fsSL -o "$D/SHA256SUMS" "$URL/SHA256SUMS" || { echo "cannot download $URL/SHA256SUMS"; exit 1; }
for image in firstlight rescue; do
  f="$image-$ARCH.cpio.gz"
  if [ ! -f "$D/$f" ] || ! (cd "$D" && grep " $f\$" SHA256SUMS | sha256sum -c --quiet - 2>/dev/null); then
    curl -fsSL -o "$D/$f" "$URL/$f" || { echo "cannot download $URL/$f"; exit 1; }
  fi
  (cd "$D" && grep " $f\$" SHA256SUMS | sha256sum -c --quiet -) || { echo "$f does not match SHA256SUMS"; rm -f "$D/$f"; exit 1; }
done
echo "$D"
