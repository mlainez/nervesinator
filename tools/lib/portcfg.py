#!/usr/bin/env python3
"""Read values from a port.yaml without a YAML library (the subset the kit writes).

Usage: portcfg.py <port.yaml> <dotted.key>      e.g. portcfg.py ports/x/port.yaml device.serial
Lists print one item per line. Missing keys print nothing and exit 1.
"""
import re
import sys


def parse(path):
    root, stack = {}, [(-1, None)]
    stack = [(-1, root)]
    with open(path) as f:
        for raw in f:
            line = raw.split(" #", 1)[0].rstrip() if not raw.lstrip().startswith("#") else ""
            if not line.strip():
                continue
            indent = len(line) - len(line.lstrip())
            m = re.match(r"^\s*([A-Za-z0-9_.-]+):\s*(.*)$", line)
            if not m:
                continue
            key, val = m.group(1), m.group(2).strip()
            while stack and stack[-1][0] >= indent:
                stack.pop()
            parent = stack[-1][1]
            if val == "":
                parent[key] = {}
                stack.append((indent, parent[key]))
            else:
                parent[key] = scalar(val)
    return root


def scalar(v):
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [scalar(x.strip()) for x in inner.split(",")] if inner else []
    if v in ("{}",):
        return {}
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def main():
    data = parse(sys.argv[1])
    cur = data
    for part in sys.argv[2].split("."):
        if not isinstance(cur, dict) or part not in cur:
            return 1
        cur = cur[part]
    if isinstance(cur, list):
        if cur:
            print("\n".join(str(x) for x in cur))
    elif isinstance(cur, dict):
        for k, v in cur.items():
            print("%s=%s" % (k, v))
    else:
        print(cur)
    return 0


if __name__ == "__main__":
    sys.exit(main())
