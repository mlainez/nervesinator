#!/usr/bin/env python3
"""Check a Nerves system directory against the Nerves porting guide
(https://hexdocs.pm/nerves/porting-guide.html) and the kit's layout rule: boot A/B and rootfs
A/B, never a single boot slot. Static: it reads files, builds nothing.

Usage: nerves_check.py <nerves system dir>      exit 0 when nothing FAILs, 1 otherwise

FAIL is something the guide requires or the kit's rule forbids; WARN is something the guide or the
official systems do and this one does differently, to justify in dossier/nerves-config-review.md.
"""
import glob
import os
import re
import sys


class Report:
    def __init__(self):
        self.rows = []

    def add(self, level, what, detail=""):
        self.rows.append((level, what, detail))

    def need(self, ok, what, detail="", level="FAIL"):
        self.add("ok" if ok else level, what, "" if ok else detail)
        return ok

    def failed(self):
        return any(level == "FAIL" for level, _, _ in self.rows)

    def render(self):
        out = []
        for level, what, detail in self.rows:
            out.append("%-4s %s%s" % (level, what, (": " + detail) if detail else ""))
        fails = sum(level == "FAIL" for level, _, _ in self.rows)
        warns = sum(level == "WARN" for level, _, _ in self.rows)
        out.append("%d check(s), %d FAIL, %d WARN" % (len(self.rows), fails, warns))
        return "\n".join(out)


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def strip_comments(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def br2(defconfig):
    """BR2 options of a defconfig: name -> value ('y', a string, or None when 'is not set')."""
    opts = {}
    for line in defconfig.splitlines():
        m = re.match(r"^(BR2_\w+)=(.*)$", line.strip())
        if m:
            opts[m.group(1)] = m.group(2).strip().strip('"')
        m = re.match(r"^# (BR2_\w+) is not set", line.strip())
        if m:
            opts[m.group(1)] = None
    return opts


def kconfig(texts):
    """Kernel options over the config and its fragments, the later file winning."""
    opts = {}
    for text in texts:
        for line in text.splitlines():
            m = re.match(r"^(CONFIG_\w+)=(.*)$", line.strip())
            if m:
                opts[m.group(1)] = m.group(2)
            m = re.match(r"^# (CONFIG_\w+) is not set", line.strip())
            if m:
                opts[m.group(1)] = "n"
    return opts


def task_body(text, name):
    """The bodies of every fwup task whose name is `name` or starts with `name.`."""
    bodies = []
    for m in re.finditer(r"^\s*task\s+(%s(?:\.[\w.-]+)?)\s*\{" % re.escape(name), text, re.M):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        bodies.append((m.group(1), text[m.end():i]))
    return bodies


def check_files(d, r):
    for rel, level in (("mix.exs", "FAIL"), ("nerves_defconfig", "FAIL"), ("fwup.conf", "FAIL"),
                       ("fwup-ops.conf", "FAIL"), ("VERSION", "FAIL"),
                       ("rootfs_overlay/etc/erlinit.config", "FAIL"),
                       ("rootfs_overlay/etc/fw_env.config", "FAIL"),
                       ("post-build.sh", "WARN"), ("post-createfs.sh", "WARN"),
                       ("fwup_include/fwup-common.conf", "WARN"),
                       ("rootfs_overlay/etc/boardid.config", "WARN"),
                       ("Config.in", "WARN"), ("external.mk", "WARN")):
        r.need(os.path.isfile(os.path.join(d, rel)), "file " + rel, "missing (porting guide, anatomy of a system)", level)


def check_mix(d, r):
    mix = read(os.path.join(d, "mix.exs"))
    r.need(":nerves_package" in mix and "nerves_package" in mix, "mix.exs: the :nerves_package compiler and config")
    r.need(re.search(r"type:\s*:system", mix), "mix.exs: nerves_package type: :system")
    r.need(re.search(r"platform:\s*Nerves\.System\.BR", mix), "mix.exs: platform: Nerves.System.BR")
    r.need(re.search(r'defconfig:\s*"nerves_defconfig"', mix), "mix.exs: platform_config defconfig: \"nerves_defconfig\"")
    r.need("artifact_sites" in mix, "mix.exs: artifact_sites, so users download the system instead of building it",
           "missing", "WARN")
    r.need("checksum:" in mix, "mix.exs: checksum: the list of files that trigger a rebuild")
    for dep in (r"\{:nerves,", r"\{:nerves_system_br,", r"\{:nerves_toolchain_\w+"):
        r.need(re.search(dep, mix), "mix.exs: dependency %s" % dep.replace("\\", "").replace("w+", "…"))
    if "checksum:" in mix:
        listed = set(re.findall(r'"([\w./-]+)"', mix))
        for rel in ("nerves_defconfig", "rootfs_overlay", "fwup.conf", "fwup-ops.conf", "VERSION"):
            r.need(rel in listed, "mix.exs: checksum list names %s" % rel,
                   "a change to it would not rebuild the system", "WARN")
        for rel in ("fwup_include", "post-build.sh", "post-createfs.sh", "uboot", "patches", "packages"):
            if os.path.exists(os.path.join(d, rel)):
                r.need(rel in listed, "mix.exs: checksum list names %s" % rel,
                       "a change to it would not rebuild the system", "WARN")


def check_defconfig(d, r):
    opts = br2(read(os.path.join(d, "nerves_defconfig")))
    for name in ("BR2_TOOLCHAIN_EXTERNAL", "BR2_TOOLCHAIN_EXTERNAL_CUSTOM", "BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD",
                 "BR2_INIT_NONE", "BR2_ROOTFS_SKELETON_CUSTOM", "BR2_PACKAGE_NERVES_CONFIG"):
        r.need(opts.get(name) == "y", "nerves_defconfig: %s=y" % name)
    prefix = opts.get("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX") or ""
    want = "aarch64-nerves-linux-gnu" if opts.get("BR2_aarch64") == "y" else \
        ("arm" if opts.get("BR2_arm") == "y" else "")
    r.need("nerves" in prefix and (not want or prefix.startswith(want)),
           "nerves_defconfig: a Nerves toolchain whose prefix matches the architecture",
           "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX=%s" % (prefix or "unset"))
    r.need("nerves-common/skeleton" in (opts.get("BR2_ROOTFS_SKELETON_CUSTOM_PATH") or ""),
           "nerves_defconfig: the nerves-common skeleton")
    overlay = opts.get("BR2_ROOTFS_OVERLAY") or ""
    r.need("nerves-common/rootfs_overlay" in overlay and "${NERVES_DEFCONFIG_DIR}/rootfs_overlay" in overlay,
           "nerves_defconfig: BR2_ROOTFS_OVERLAY = the common overlay, then the system's")
    r.need("nerves-common/post-build.sh" in (opts.get("BR2_ROOTFS_POST_BUILD_SCRIPT") or ""),
           "nerves_defconfig: the nerves-common post-build script")
    busybox = (opts.get("BR2_PACKAGE_BUSYBOX_CONFIG") or "")
    r.need("nerves-common/busybox.config" in busybox, "nerves_defconfig: the nerves-common BusyBox config",
           "BR2_PACKAGE_BUSYBOX_CONFIG=%s (add device needs as a fragment instead)" % (busybox or "unset"), "WARN")
    r.need(opts.get("BR2_NERVES_SYSTEM_NAME"), "nerves_defconfig: BR2_NERVES_SYSTEM_NAME")
    r.need(opts.get("BR2_PACKAGE_NBTTY") == "y", "nerves_defconfig: BR2_PACKAGE_NBTTY=y (the IEx console)", "unset", "WARN")
    for name in ("BR2_TARGET_GENERIC_HOSTNAME", "BR2_SYSTEM_DHCP", "BR2_TARGET_GENERIC_GETTY",
                 "BR2_TARGET_GENERIC_GETTY_PORT", "BR2_TARGET_GENERIC_ROOT_PASSWD"):
        r.need(not opts.get(name), "nerves_defconfig: no %s (Nerves handles it)" % name,
               "left over from the Buildroot defconfig", "WARN")
    return opts


def check_kernel(d, defopts, r):
    ref = (defopts.get("BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE") or "").replace("${NERVES_DEFCONFIG_DIR}/", "")
    files = [os.path.join(d, ref)] if ref else []
    for frag in (defopts.get("BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES") or "").split():
        files.append(os.path.join(d, frag.replace("${NERVES_DEFCONFIG_DIR}/", "")))
    if not r.need(ref and os.path.isfile(files[0]),
                  "kernel: BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE names a config in the system",
                  ref or "unset"):
        return
    opts = kconfig(read(f) for f in files)
    for name, why in (("CONFIG_SQUASHFS", "the read-only root filesystem"),
                      ("CONFIG_F2FS_FS", "the application data partition"),
                      ("CONFIG_USB_GADGET", "USB networking"), ("CONFIG_USB_ETH", "USB networking")):
        r.need(opts.get(name) == "y", "kernel: %s=y, built in (%s)" % (name, why), "is %s" % (opts.get(name) or "unset"))
    # The guide asks for LZ4; `mix firmware` rebuilds the squashfs with gzip, as the official systems
    # run it. ZLIB defaults to y with SQUASHFS, so a saved defconfig omits it.
    r.need(opts.get("CONFIG_SQUASHFS_ZLIB") != "n", "kernel: squashfs gzip decompression (what mix firmware produces)",
           "CONFIG_SQUASHFS_ZLIB is not set")
    r.need(opts.get("CONFIG_SQUASHFS_LZ4") == "y", "kernel: CONFIG_SQUASHFS_LZ4=y (porting guide)",
           "unset: the system cannot mount an LZ4 root filesystem", "WARN")
    r.need(opts.get("CONFIG_CMDLINE_FORCE") != "y", "kernel: no CONFIG_CMDLINE_FORCE",
           "it ignores the bootloader's command line, so the slot's root= is never seen")


def check_fwup(d, r):
    text = strip_comments(read(os.path.join(d, "fwup.conf")))
    for path in sorted(glob.glob(os.path.join(d, "fwup_include", "*.conf"))):
        text += "\n" + strip_comments(read(path))
    defined = set(re.findall(r"define(?:-eval|!)?\(\s*(\w+)", text))
    for name in ("BOOT_A_PART_OFFSET", "BOOT_B_PART_OFFSET", "ROOTFS_A_PART_OFFSET", "ROOTFS_B_PART_OFFSET",
                 "APP_PART_OFFSET", "UBOOT_ENV_OFFSET"):
        r.need(name in defined, "fwup: %s defined" % name,
               "the layout is U-Boot env, boot A, boot B, rootfs A, rootfs B, application data")
    for name in ("NERVES_FW_DEVPATH", "NERVES_FW_APPLICATION_PART0_DEVPATH", "NERVES_FW_APPLICATION_PART0_FSTYPE",
                 "NERVES_FW_APPLICATION_PART0_TARGET"):
        r.need(name in defined, "fwup: %s defined" % name)
    r.need(task_body(text, "complete"), "fwup: task complete")
    for slot, other in (("a", "B"), ("b", "A")):
        bodies = task_body(text, "upgrade." + slot)
        if not r.need(bodies, "fwup: task upgrade.%s" % slot):
            continue
        body = "\n".join(b for _, b in bodies)
        up = slot.upper()
        r.need("ROOTFS_%s_PART_OFFSET" % up in body, "fwup: upgrade.%s writes rootfs %s" % (slot, up))
        r.need("BOOT_%s_PART_OFFSET" % up in body, "fwup: upgrade.%s writes boot %s" % (slot, up),
               "an upgrade that leaves the boot slot alone means a single boot slot: the kernel, DTB "
               "and initramfs must be updated and reverted together with the root filesystem")
        r.need(re.search(r"mbr_write|uboot_setenv\([^)]*nerves_fw_active", body),
               "fwup: upgrade.%s switches the active slot (MBR or nerves_fw_active)" % slot)
    complete = "\n".join(b for _, b in task_body(text, "complete"))
    r.need("BOOT_A_PART_OFFSET" in complete and "ROOTFS_A_PART_OFFSET" in complete,
           "fwup: complete writes boot A and rootfs A")
    r.need(len(re.findall(r"^\s*mbr\s+[\w-]+\s*\{", text, re.M)) >= 2 or "nerves_fw_active" in text,
           "fwup: two MBR definitions (slot a, slot b), or the slot kept in nerves_fw_active")
    r.need(re.search(r"^\s*uboot-environment\s", text, re.M), "fwup: a uboot-environment block for the firmware metadata")
    for key in ("nerves_fw_version", "nerves_fw_platform", "nerves_fw_architecture", "nerves_fw_application_part0_devpath"):
        r.need(key in text, "fwup: metadata a./b.%s" % key, "nerves_runtime reads it", "WARN")
    r.need("nerves_fw_validated" in text, "fwup: a./b.nerves_fw_validated (a new slot starts unvalidated)",
           "without it a bad update cannot be told from a good one", "WARN")
    ops = strip_comments(read(os.path.join(d, "fwup-ops.conf")))
    for name in ("factory-reset", "revert", "status", "validate", "prevent-revert"):
        r.need(task_body(ops, name), "fwup-ops: task %s" % name, "nerves_runtime calls it")
    return text


def define_value(text, name):
    m = re.search(r"define\(\s*%s\s*,\s*\"?([^\")]+)\"?\s*\)" % name, text)
    return m.group(1).strip() if m else ""


def check_overlay(d, fwup, r):
    erlinit = strip_comments(read(os.path.join(d, "rootfs_overlay/etc/erlinit.config")))
    app = define_value(fwup, "NERVES_FW_APPLICATION_PART0_DEVPATH")
    mounts = re.findall(r"^\s*(?:-m|--mount)\s+(\S+)", erlinit, re.M)
    r.need(app and any(m.split(":")[0] == app for m in mounts),
           "erlinit: mounts the application partition fwup names (%s)" % (app or "?"),
           "erlinit mounts %s" % (", ".join(m.split(":")[0] for m in mounts) or "nothing"))
    r.need(re.search(r"nbtty", erlinit), "erlinit: nbtty before the release (-s or --pre-run-exec)", "missing", "WARN")
    r.need(re.search(r"^\s*(?:-d|--uniqueid-exec)\s", erlinit, re.M) and
           re.search(r"^\s*(?:-n|--hostname-pattern)\s", erlinit, re.M),
           "erlinit: a hostname from the board id (-d boardid, -n nerves-%s)", "missing", "WARN")
    env_offset = define_value(fwup, "UBOOT_ENV_OFFSET")
    fw_env = [l.split() for l in strip_comments(read(os.path.join(d, "rootfs_overlay/etc/fw_env.config"))).splitlines() if l.split()]
    if env_offset.isdigit() and fw_env and len(fw_env[0]) >= 2:
        try:
            r.need(int(fw_env[0][1], 0) == int(env_offset) * 512,
                   "fw_env.config: the environment offset equals UBOOT_ENV_OFFSET",
                   "%s there, %d bytes in fwup" % (fw_env[0][1], int(env_offset) * 512))
        except ValueError:
            r.add("WARN", "fw_env.config: offset not readable", fw_env[0][1])
    overlay = os.path.join(d, "rootfs_overlay")
    scripts = glob.glob(os.path.join(overlay, "etc/init.d/*")) + glob.glob(os.path.join(overlay, "etc/inittab"))
    r.need(not scripts, "overlay: no init scripts (startup work belongs in the Elixir application)",
           ", ".join(os.path.relpath(s, d) for s in scripts[:4]))
    kit_net = []
    for root, _, files in os.walk(overlay):
        for name in files:
            if "10.0.42." in read(os.path.join(root, name)):
                kit_net.append(os.path.relpath(os.path.join(root, name), d))
    r.need(not kit_net, "overlay: networking left to nerves_pack (no rescue-image address)", ", ".join(kit_net[:4]))
    r.need(os.path.isfile(os.path.join(d, "uboot/boot.cmd")) or glob.glob(os.path.join(d, "**/extlinux.conf"), recursive=True),
           "boot: a checked-in boot script (uboot/boot.cmd or extlinux.conf)", "missing", "WARN")


def check(d):
    r = Report()
    check_files(d, r)
    check_mix(d, r)
    defopts = check_defconfig(d, r)
    check_kernel(d, defopts, r)
    fwup = check_fwup(d, r)
    check_overlay(d, fwup, r)
    return r


def main(argv):
    if len(argv) != 1 or not os.path.isdir(argv[0]):
        print(__doc__.strip().splitlines()[4])
        return 2
    report = check(argv[0])
    print(report.render())
    return 1 if report.failed() else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
