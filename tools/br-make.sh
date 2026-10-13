#!/usr/bin/env bash
# Run a Buildroot make with the kit's shared caches, so no port downloads or compiles twice.
# Usage: tools/br-make.sh <buildroot dir> [make arguments…]
#   e.g. tools/br-make.sh ports/<id>/buildroot-android/buildroot O=$PWD/ports/<id>/output/rescue -j16
#
# Sets BR2_DL_DIR=cache/buildroot-dl and BR2_CCACHE_DIR=cache/buildroot-ccache (Buildroot reads both
# from the environment); ccache is used when the defconfig has BR2_CCACHE=y.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] && [ -f "$1/Makefile" ] || { sed -n '2,8p' "$0"; exit 2; }
BR=$1; shift
mkdir -p "$KIT/cache/buildroot-dl" "$KIT/cache/buildroot-ccache"
export BR2_DL_DIR="$KIT/cache/buildroot-dl" BR2_CCACHE_DIR="$KIT/cache/buildroot-ccache"
exec make -C "$BR" "$@"
