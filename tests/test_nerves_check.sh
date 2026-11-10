#!/usr/bin/env bash
# Regression tests for tools/lib/nerves_check.py on a minimal synthetic Nerves system: a system
# that follows the porting guide passes; a single boot slot and the other departures FAIL.
# Usage: tests/test_nerves_check.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
C="$KIT/tools/lib/nerves_check.py"
T=$(mktemp -d)
fail=0

fixture() { # a fresh compliant system in $T/sys
  rm -rf "$T/sys"; S="$T/sys"; mkdir -p "$S/fwup_include" "$S/rootfs_overlay/etc" "$S/uboot"
  cat > "$S/mix.exs" <<'EOF'
defmodule NervesSystemFixture.MixProject do
  use Mix.Project
  @app :nerves_system_fixture
  def project do
    [app: @app, compilers: Mix.compilers() ++ [:nerves_package], nerves_package: nerves_package(), deps: deps()]
  end
  defp nerves_package do
    [type: :system, artifact_sites: [{:github_releases, "o/#{@app}"}], platform: Nerves.System.BR,
     platform_config: [defconfig: "nerves_defconfig"], checksum: package_files()]
  end
  defp deps do
    [{:nerves, "~> 1.11", runtime: false}, {:nerves_system_br, "1.35.3", runtime: false},
     {:nerves_toolchain_armv7_nerves_linux_gnueabihf, "~> 15.3.0", runtime: false}]
  end
  defp package_files do
    ["nerves_defconfig", "rootfs_overlay", "linux-6.6.defconfig", "fwup.conf", "fwup-ops.conf",
     "fwup_include", "post-build.sh", "post-createfs.sh", "uboot", "VERSION"]
  end
end
EOF
  cat > "$S/nerves_defconfig" <<'EOF'
BR2_arm=y
BR2_cortex_a7=y
BR2_TOOLCHAIN_EXTERNAL=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y
BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD=y
BR2_TOOLCHAIN_EXTERNAL_URL="https://example.org/nerves_toolchain_armv7_nerves_linux_gnueabihf.tar.xz"
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="armv7-nerves-linux-gnueabihf"
BR2_ROOTFS_SKELETON_CUSTOM=y
BR2_ROOTFS_SKELETON_CUSTOM_PATH="${BR2_EXTERNAL_NERVES_PATH}/board/nerves-common/skeleton"
BR2_INIT_NONE=y
BR2_ROOTFS_OVERLAY="${BR2_EXTERNAL_NERVES_PATH}/board/nerves-common/rootfs_overlay ${NERVES_DEFCONFIG_DIR}/rootfs_overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="${NERVES_DEFCONFIG_DIR}/post-build.sh ${BR2_EXTERNAL_NERVES_PATH}/board/nerves-common/post-build.sh"
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="${NERVES_DEFCONFIG_DIR}/linux-6.6.defconfig"
BR2_PACKAGE_BUSYBOX_CONFIG="${BR2_EXTERNAL_NERVES_PATH}/board/nerves-common/busybox.config"
BR2_NERVES_SYSTEM_NAME="nerves_system_fixture"
BR2_PACKAGE_NBTTY=y
BR2_PACKAGE_NERVES_CONFIG=y
EOF
  printf 'CONFIG_SQUASHFS=y\nCONFIG_SQUASHFS_LZ4=y\nCONFIG_F2FS_FS=y\nCONFIG_USB_GADGET=y\nCONFIG_USB_ETH=y\n' > "$S/linux-6.6.defconfig"
  cat > "$S/fwup_include/fwup-common.conf" <<'EOF'
define(NERVES_FW_DEVPATH, "/dev/nerves-userdata")
define(NERVES_FW_APPLICATION_PART0_DEVPATH, "/dev/nerves-app")
define(NERVES_FW_APPLICATION_PART0_FSTYPE, "f2fs")
define(NERVES_FW_APPLICATION_PART0_TARGET, "/root")
define(UBOOT_ENV_OFFSET, 2048)
define(UBOOT_ENV_COUNT, 16)
define(BOOT_A_PART_OFFSET, 4096)
define(BOOT_A_PART_COUNT, 131072)
define-eval(BOOT_B_PART_OFFSET, "${BOOT_A_PART_OFFSET} + ${BOOT_A_PART_COUNT}")
define(BOOT_B_PART_COUNT, 131072)
define-eval(ROOTFS_A_PART_OFFSET, "${BOOT_B_PART_OFFSET} + ${BOOT_B_PART_COUNT}")
define(ROOTFS_A_PART_COUNT, 524288)
define-eval(ROOTFS_B_PART_OFFSET, "${ROOTFS_A_PART_OFFSET} + ${ROOTFS_A_PART_COUNT}")
define(ROOTFS_B_PART_COUNT, 524288)
define-eval(APP_PART_OFFSET, "${ROOTFS_B_PART_OFFSET} + ${ROOTFS_B_PART_COUNT}")
define(APP_PART_COUNT, 1048576)
mbr mbr-a {
    partition 0 { block-offset = ${BOOT_A_PART_OFFSET} block-count = ${BOOT_A_PART_COUNT} type = 0x83 }
    partition 1 { block-offset = ${ROOTFS_A_PART_OFFSET} block-count = ${ROOTFS_A_PART_COUNT} type = 0x83 }
    partition 2 { block-offset = ${APP_PART_OFFSET} block-count = ${APP_PART_COUNT} type = 0x83 }
}
mbr mbr-b {
    partition 0 { block-offset = ${BOOT_B_PART_OFFSET} block-count = ${BOOT_B_PART_COUNT} type = 0x83 }
    partition 1 { block-offset = ${ROOTFS_B_PART_OFFSET} block-count = ${ROOTFS_B_PART_COUNT} type = 0x83 }
    partition 2 { block-offset = ${APP_PART_OFFSET} block-count = ${APP_PART_COUNT} type = 0x83 }
}
uboot-environment uboot-env {
    block-offset = ${UBOOT_ENV_OFFSET}
    block-count = ${UBOOT_ENV_COUNT}
}
EOF
  cat > "$S/fwup.conf" <<'EOF'
require-fwup-version="1.0.0"
include("${NERVES_SDK_IMAGES:-.}/fwup_include/fwup-common.conf")
task complete {
    on-init {
        mbr_write(mbr-a)
        uboot_setenv(uboot-env, "nerves_fw_active", "a")
        uboot_setenv(uboot-env, "a.nerves_fw_version", ${NERVES_FW_VERSION})
        uboot_setenv(uboot-env, "a.nerves_fw_platform", ${NERVES_FW_PLATFORM})
        uboot_setenv(uboot-env, "a.nerves_fw_architecture", ${NERVES_FW_ARCHITECTURE})
        uboot_setenv(uboot-env, "a.nerves_fw_application_part0_devpath", ${NERVES_FW_APPLICATION_PART0_DEVPATH})
        uboot_setenv(uboot-env, "a.nerves_fw_validated", "1")
    }
    on-resource boot.img { raw_write(${BOOT_A_PART_OFFSET}) }
    on-resource rootfs.img { raw_write(${ROOTFS_A_PART_OFFSET}) }
}
task upgrade.a {
    require-partition-offset(1, ${ROOTFS_B_PART_OFFSET})
    on-resource boot.img { raw_write(${BOOT_A_PART_OFFSET}) }
    on-resource rootfs.img { raw_write(${ROOTFS_A_PART_OFFSET}) }
    on-finish { uboot_setenv(uboot-env, "a.nerves_fw_validated", "0") mbr_write(mbr-a) }
}
task upgrade.b {
    require-partition-offset(1, ${ROOTFS_A_PART_OFFSET})
    on-resource boot.img { raw_write(${BOOT_B_PART_OFFSET}) }
    on-resource rootfs.img { raw_write(${ROOTFS_B_PART_OFFSET}) }
    on-finish { uboot_setenv(uboot-env, "b.nerves_fw_validated", "0") mbr_write(mbr-b) }
}
EOF
  cat > "$S/fwup-ops.conf" <<'EOF'
task factory-reset { on-init { raw_memset(${APP_PART_OFFSET}, 256, 0xff) } }
task prevent-revert.a { on-init { uboot_unsetenv(uboot-env, "a.nerves_fw_platform") } }
task revert.a { on-init { mbr_write(mbr-a) } }
task status.aa { on-init { info("a") } }
task validate.a { on-init { uboot_setenv(uboot-env, "a.nerves_fw_validated", "1") } }
EOF
  printf -- '-s "/usr/bin/nbtty"\n-m /dev/nerves-app:/root:f2fs:nodev:\n-d /usr/bin/boardid\n-n nerves-%%s\n' > "$S/rootfs_overlay/etc/erlinit.config"
  printf '/dev/nerves-userdata 0x100000 0x2000\n' > "$S/rootfs_overlay/etc/fw_env.config"
  printf -- '-b uboot_env -u nerves_serial_number\n' > "$S/rootfs_overlay/etc/boardid.config"
  echo 'echo boot' > "$S/uboot/boot.cmd"
  echo 0.1.0 > "$S/VERSION"
  touch "$S/post-build.sh" "$S/post-createfs.sh" "$S/Config.in" "$S/external.mk"
}

expect() { # label, expected exit, text that must appear (or - for none)
  local out rc
  out=$(python3 -I "$C" "$T/sys"); rc=$?
  if [ "$rc" = "$2" ] && { [ "$3" = - ] || echo "$out" | grep -q -- "$3"; }; then echo "ok   $1"
  else echo "FAIL $1: rc=$rc"; echo "$out" | grep -E '^(FAIL|WARN)' | head -5; fail=1; fi
}

fixture; expect "a system that follows the guide passes" 0 "0 FAIL, 0 WARN"

fixture; sed -i 's/on-resource boot.img { raw_write(${BOOT_B_PART_OFFSET}) }//' "$S/fwup.conf"
expect "an upgrade that leaves boot B alone fails" 1 "FAIL fwup: upgrade.b writes boot B"

fixture; sed -i '/BOOT_B_PART/d' "$S/fwup_include/fwup-common.conf"
expect "a single boot slot fails" 1 "FAIL fwup: BOOT_B_PART_OFFSET defined"

fixture; sed -i '/ROOTFS_B_PART_OFFSET/d' "$S/fwup_include/fwup-common.conf"
expect "a single rootfs slot fails" 1 "FAIL fwup: ROOTFS_B_PART_OFFSET defined"

fixture; sed -i '/BR2_INIT_NONE/d' "$S/nerves_defconfig"
expect "an init system other than erlinit fails" 1 "FAIL nerves_defconfig: BR2_INIT_NONE=y"

fixture; sed -i 's/CONFIG_F2FS_FS=y/CONFIG_F2FS_FS=m/' "$S/linux-6.6.defconfig"
expect "f2fs as a module fails" 1 "FAIL kernel: CONFIG_F2FS_FS=y"

fixture; sed -i '/SQUASHFS_LZ4/d' "$S/linux-6.6.defconfig"
expect "no LZ4 is a warning, not a failure" 0 "WARN kernel: CONFIG_SQUASHFS_LZ4=y"

fixture; sed -i 's|/dev/nerves-app:|/dev/mmcblk0p9:|' "$S/rootfs_overlay/etc/erlinit.config"
expect "erlinit mounting another partition than fwup names fails" 1 "FAIL erlinit: mounts the application partition"

fixture; printf '/dev/nerves-userdata 0x2000 0x2000\n' > "$S/rootfs_overlay/etc/fw_env.config"
expect "fw_env.config pointing elsewhere than the env fails" 1 "FAIL fw_env.config"

fixture; mkdir -p "$S/rootfs_overlay/etc/init.d"; echo '#!/bin/sh' > "$S/rootfs_overlay/etc/init.d/S40wifi"
expect "an init script in the overlay fails" 1 "FAIL overlay: no init scripts"

fixture; sed -i '/^task revert/d' "$S/fwup-ops.conf"
expect "fwup-ops without revert fails" 1 "FAIL fwup-ops: task revert"

rm -rf "$T"
exit $fail
