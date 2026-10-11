#!/usr/bin/env python3
"""Describe an Android boot image: header version, offsets, cmdline, kernel format, DTB placement.

Usage: bootimg_info.py <boot.img> [--json]

The output gives the mkbootimg arguments needed to build a compatible image.
Supports header v0-v4, appended DTBs, QCDT dt.img (v0 "dt_size" variant) and Samsung footers.
"""
import json
import struct
import sys

FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def pages(n, page):
    return (n + page - 1) // page * page


def kernel_format(blob):
    if len(blob) > 0x40 and struct.unpack_from("<I", blob, 0x24)[0] == 0x016F2818:
        return "zImage (arm32)"
    if len(blob) > 0x40 and blob[0x38:0x3C] == b"ARM\x64":
        return "Image (arm64, uncompressed)"
    if blob[:2] == b"\x1f\x8b":
        return "gzip (likely Image.gz, arm64)"
    if blob[:4] == b"\x02\x21\x4c\x18":
        return "lz4 legacy"
    if blob[:4] == b"UNCO":
        return "Samsung/vendor wrapped"
    return "unknown"


def appended_dtbs(kernel):
    found, i = [], kernel.find(FDT_MAGIC, 0x40)
    while i != -1:
        if i + 8 <= len(kernel):
            size = struct.unpack_from(">I", kernel, i + 4)[0]
            if 0x100 < size < 0x400000:
                found.append({"offset": i, "size": size})
                i = kernel.find(FDT_MAGIC, i + size)
                continue
        i = kernel.find(FDT_MAGIC, i + 4)
    return found


def parse(data):
    if data[:8] != b"ANDROID!":
        raise ValueError("no ANDROID! magic: not an Android boot image (or wrapped/compressed)")
    info = {}
    hv_v3 = struct.unpack_from("<I", data, 40)[0]
    if hv_v3 in (3, 4):
        kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<4I", data, 8)
        info.update(header_version=hv_v3, page_size=4096, kernel_size=kernel_size,
                    ramdisk_size=ramdisk_size, header_size=header_size,
                    cmdline=data[44:44 + 1536].split(b"\0")[0].decode(errors="replace"))
        page = 4096
        k_off = page
        info["kernel"] = kernel_format(data[k_off:k_off + kernel_size])
        info["appended_dtbs"] = appended_dtbs(data[k_off:k_off + kernel_size])
        info["note"] = "v3/v4: offsets come from the bootloader/vendor_boot; dtb lives in vendor_boot"
    else:
        (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr,
         tags_addr, page, field9, os_version) = struct.unpack_from("<10I", data, 8)
        name = data[48:64].split(b"\0")[0].decode(errors="replace")
        cmdline = data[64:64 + 512].split(b"\0")[0] + data[608:608 + 1024].split(b"\0")[0]
        base = kernel_addr - 0x8000
        info.update(page_size=page, kernel_size=kernel_size, ramdisk_size=ramdisk_size,
                    second_size=second_size, name=name,
                    cmdline=cmdline.decode(errors="replace"),
                    base=hex(base), kernel_offset=hex(kernel_addr - base),
                    ramdisk_offset=hex(ramdisk_addr - base), second_offset=hex(second_addr - base),
                    tags_offset=hex(tags_addr - base))
        k_off = page
        r_off = k_off + pages(kernel_size, page)
        s_off = r_off + pages(ramdisk_size, page)
        after_second = s_off + pages(second_size, page)
        kernel = data[k_off:k_off + kernel_size]
        info["kernel"] = kernel_format(kernel)
        info["appended_dtbs"] = appended_dtbs(kernel)
        if field9 in (1, 2):
            info["header_version"] = field9
            if field9 == 2:
                dtb_size = struct.unpack_from("<I", data, 1648)[0]
                info["dtb_size"] = dtb_size
        elif field9 and data[after_second:after_second + 4] == b"QCDT":
            info["header_version"] = 0
            info["qcdt"] = {"offset": after_second, "size": field9}
        else:
            info["header_version"] = 0
            if field9:
                info["field9_unknown"] = field9
        info["mkbootimg_args"] = (
            "--base %s --pagesize %d --kernel_offset %s --ramdisk_offset %s --second_offset %s "
            "--tags_offset %s --header_version %d" % (
                info["base"], page, info["kernel_offset"], info["ramdisk_offset"],
                info["second_offset"], info["tags_offset"], info["header_version"]))
    tail = data[-4096:]
    if b"SEANDROIDENFORCE" in tail:
        info["samsung_footer"] = "SEANDROIDENFORCE"
    if b"AVB0" in data[-65536:]:
        info["avb_footer"] = True
    return info


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    try:
        info = parse(data)
    except ValueError as e:
        print("error:", e)
        return 1
    if "--json" in sys.argv:
        print(json.dumps(info, indent=2))
    else:
        for k, v in info.items():
            print("%-16s %s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
