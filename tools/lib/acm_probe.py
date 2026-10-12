#!/usr/bin/env python3
"""Talk to a kit test image over its ACM console (/dev/ttyACM*), with the standard library only.

Usage: acm_probe.py <tty> [--timeout S] [--return]

Reads the banner the image prints when the port opens (it ends with a "KIT-READY ..." line), then
runs a few read-only commands in the image's shell. With --return, it then asks the image to go
back to the flash mode (reboot-mode $KIT_RETURN_MODE, else reboot -f).
Prints the transcript. Exit status: 0 when KIT-READY was seen, 1 otherwise.
"""
import os
import select
import sys
import termios
import time
import tty

# The shell echoes what we type: split the markers so the echo never matches them
PROBE = 'echo KIT-""PROBE; uname -a; cat /proc/cmdline; ip addr show usb0; echo KIT-""END\n'
RETURN = '. /etc/kit-image; sync; reboot-mode "$KIT_RETURN_MODE"; reboot -f\n'


def read_until(fd, needles, timeout):
    buf, end = b"", time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            if any(n in buf for n in needles):
                break
    return buf


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    timeout = float(argv[argv.index("--timeout") + 1]) if "--timeout" in argv else 20
    fd = os.open(argv[1], os.O_RDWR | os.O_NOCTTY)
    try:
        # TCSANOW: the default TCSAFLUSH would drop a banner that already arrived
        tty.setraw(fd, termios.TCSANOW)
        out = read_until(fd, [b"--- shell ---"], timeout)
        os.write(fd, b"\n" + PROBE.encode())
        out += read_until(fd, [b"KIT-END"], timeout)
        if "--return" in argv:
            os.write(fd, RETURN.encode())
            out += read_until(fd, [], 3)
    finally:
        os.close(fd)
    text = out.decode(errors="replace").replace("\r", "")
    print(text)
    return 0 if "KIT-READY" in text else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
