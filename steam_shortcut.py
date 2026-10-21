#!/usr/bin/env python3
"""Add or remove a non-Steam shortcut in every Steam user's shortcuts.vdf.

Steam must be closed, or it overwrites the file. The other shortcuts stay
as they are. Each changed file gets a backup next to it.
"""

import argparse
import glob
import os
import shutil
import struct
import sys
import time
import zlib

T_MAP, T_STR, T_INT, T_FLOAT, T_PTR, T_WSTR, T_COLOR, T_UINT64, T_END = range(9)
FIXED_SIZES = {T_INT: 4, T_FLOAT: 4, T_PTR: 4, T_COLOR: 4, T_UINT64: 8}


def read_cstr(buf, i):
    end = buf.index(b"\x00", i)
    return buf[i:end], end + 1


def parse_map(buf, i):
    """Return ([(type, key, value)], next index). Values stay as raw bytes."""
    items = []
    while True:
        kind = buf[i]
        i += 1
        if kind == T_END:
            return items, i
        key, i = read_cstr(buf, i)
        if kind == T_MAP:
            value, i = parse_map(buf, i)
        elif kind == T_STR:
            value, i = read_cstr(buf, i)
        elif kind in FIXED_SIZES:
            size = FIXED_SIZES[kind]
            value, i = buf[i:i + size], i + size
        else:
            raise ValueError(f"unsupported VDF type {kind} at byte {i - 1}")
        items.append((kind, key, value))


def dump_map(items):
    out = bytearray()
    for kind, key, value in items:
        out += bytes([kind]) + key + b"\x00"
        if kind == T_MAP:
            out += dump_map(value)
        elif kind == T_STR:
            out += value + b"\x00"
        else:
            out += value
    out.append(T_END)
    return bytes(out)


def load(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return [(T_MAP, b"shortcuts", [])]
    with open(path, "rb") as f:
        buf = f.read()
    root, _ = parse_map(buf, 0)
    if not root or root[0][1].lower() != b"shortcuts":
        raise ValueError(f"{path} does not start with a shortcuts map")
    return root


def field(entry, name):
    for kind, key, value in entry:
        if key.lower() == name.lower():
            return value
    return None


def make_entry(name, exe, start_dir, icon):
    quoted_exe = f'"{exe}"'
    appid = zlib.crc32((quoted_exe + name).encode()) | 0x80000000

    def s(key, value):
        return (T_STR, key.encode(), value.encode())

    def n(key, value):
        return (T_INT, key.encode(), struct.pack("<I", value))

    return [
        n("appid", appid), s("AppName", name), s("Exe", quoted_exe),
        s("StartDir", f'"{start_dir}"'), s("icon", icon), s("ShortcutPath", ""),
        s("LaunchOptions", ""), n("IsHidden", 0), n("AllowDesktopConfig", 1),
        n("AllowOverlay", 1), n("OpenVR", 0), n("Devkit", 0), s("DevkitGameID", ""),
        n("DevkitOverrideAppID", 0), n("LastPlayTime", 0), s("FlatpakAppID", ""),
        (T_MAP, b"tags", []),
    ]


def matches(entry, exe):
    value = field(entry, b"Exe") or b""
    return value.decode(errors="replace").strip('"') == exe


def update(path, args):
    root = load(path)
    shortcuts = root[0][2]
    kept = [item for item in shortcuts if not (item[0] == T_MAP and matches(item[2], args.exe))]
    if args.action == "add":
        if len(kept) != len(shortcuts):
            print(f"  already present: {path}")
            return
        kept.append((T_MAP, b"", make_entry(args.name, args.exe, args.start_dir, args.icon)))
    elif len(kept) == len(shortcuts):
        print(f"  not present: {path}")
        return
    # Steam numbers the entries 0, 1, 2, ... with no gaps.
    root[0] = (T_MAP, root[0][1], [(k, str(n).encode(), v) for n, (k, _, v) in enumerate(kept)])
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "wb") as f:
        f.write(dump_map(root))
    os.replace(temporary, path)
    print(f"  {'added to' if args.action == 'add' else 'removed from'}: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["add", "remove"])
    parser.add_argument("--exe", required=True)
    parser.add_argument("--name", default="Xodus Nexus")
    parser.add_argument("--start-dir", default="")
    parser.add_argument("--icon", default="")
    parser.add_argument("--steam-root", default=os.path.expanduser("~/.local/share/Steam"))
    args = parser.parse_args()
    args.start_dir = args.start_dir or os.path.dirname(args.exe)

    users = [d for d in glob.glob(os.path.join(args.steam_root, "userdata", "*"))
             if os.path.basename(d).isdigit() and os.path.basename(d) != "0"]
    if not users:
        print("No Steam user found. Sign in to Steam one time, then run this again.", file=sys.stderr)
        return 1
    for user in users:
        update(os.path.join(user, "config", "shortcuts.vdf"), args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
