#!/usr/bin/env python3
"""Tell whether lk2nd will find a device tree in a boot image, before sending it.

Usage: lk2nd_dtb_check.py <boot.img> [--log <lk2nd oem log>] [--ids <chip/soc_rev/platform/subtype>]

lk2nd takes the DTB appended to the kernel, or a QCDT entry matching its SMEM ids. It prints those
ids as "Device info 0x000000dd/00020000/0x00000008/0" (chip/soc_rev/platform/subtype, after a failed
boot) or "suitable device tree for device (221/0x00020000/0x00000008/0)". --ids takes the same form.
Exit status: 0 bootable, 1 lk2nd will refuse it, 2 cannot tell.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bootimg_info import parse  # noqa: E402

LOG_PATTERNS = [
    re.compile(r"Device info 0x([0-9a-fA-F]+)/(?:0x)?([0-9a-fA-F]+)/0x([0-9a-fA-F]+)/(\d+)"),
    re.compile(r"suitable device tree for device \((\d+)/0x([0-9a-fA-F]+)/0x([0-9a-fA-F]+)/(\d+)\)"),
]


def ids_from_log(text):
    found = None
    for i, pat in enumerate(LOG_PATTERNS):
        for m in pat.finditer(text):
            chip = int(m.group(1), 16 if i == 0 else 10)
            found = (chip, int(m.group(2), 16), int(m.group(3), 16), int(m.group(4)))
    return found


def ids_from_arg(s):
    chip, rev, plat, sub = s.split("/")
    return (int(chip, 0), int(rev, 16) if not rev.startswith("0x") else int(rev, 0), int(plat, 0), int(sub, 0))


def matches(e, ids):
    chip, _rev, plat, sub = ids
    # Same masks as LK's dev_tree.c: msm id in the low 16 bits (upper bits: foundry),
    # hardware platform and subtype in the low byte
    if e["platform_id"] & 0xFFFF != chip or e["variant_id"] & 0xFF != plat:
        return False
    return e["subtype_id"] is None or e["subtype_id"] & 0xFF == sub


def fmt(e):
    sub = "-" if e["subtype_id"] is None else e["subtype_id"]
    return "<0x%x %d %s rev 0x%x>" % (e["platform_id"], e["variant_id"], sub, e["soc_rev"])


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    log = ids = None
    if "--log" in argv:
        with open(argv[argv.index("--log") + 1], errors="replace") as f:
            log = ids_from_log(f.read())
    if "--ids" in argv:
        ids = ids_from_arg(argv[argv.index("--ids") + 1])
    ids = log or ids
    with open(argv[1], "rb") as f:
        info = parse(f.read())
    if info.get("appended_dtbs"):
        print("ok: DTB appended to the kernel (%d found); lk2nd uses it" % len(info["appended_dtbs"]))
        return 0
    entries = (info.get("qcdt") or {}).get("entries") or []
    if not entries:
        if info.get("dtb_size"):
            print("unknown: boot image v2 with a header DTB; check that this lk2nd build reads it")
            return 2
        print("refuse: no appended DTB and no QCDT table: lk2nd has no device tree to pass")
        return 1
    listing = ", ".join(fmt(e) for e in entries)
    if ids is None:
        print("unknown: QCDT %s, but lk2nd's SMEM ids are unknown (set device.qcom_ids from a "
              "'Device info' line of 'fastboot oem log')" % listing)
        return 2
    idstr = "<%d/0x%x/%d/%d>" % ids
    hits = [e for e in entries if matches(e, ids)]
    if hits:
        print("ok: QCDT entry %s matches lk2nd's SMEM ids %s" % (fmt(hits[0]), idstr))
        return 0
    print("refuse: lk2nd will refuse this image (dtb not found): its QCDT ids %s don't match "
          "lk2nd's SMEM ids %s (chip/rev/platform/subtype), and there is no appended DTB"
          % (listing, idstr))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
