#!/usr/bin/env python3
"""Checks the disc's packed files (src/pack.asm): each build/<name>.pk - the
word where it goes, then its bytes packed by rasm's ZX0 (LZX0) - unpacked
as src/dzx0.asm does, against build/<name>.raw, what src/main.asm made;
and that each fits where the loader loads it (FITS: src/discmap.asm's
names), which rasm cannot check (its labels past a packed section are the
unpacked ones in an ASSERT).

    python3 tools/zx0check.py

A ZX0 (version 2) decoder after the format's reference one (dzx0.c, Einar
Saukas): literals and copies, lengths in interlaced Elias gamma codes, an
offset's high part inverted, its low byte's last bit the length's first.
"""

import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Each file: where the loader loads it, and what it must end before - the
# unpacker for the banks (they unpack in #4000-#7FFF), the place it unpacks
# to for the sound and the race (the race's: the sound, already there), the
# memory's end for the car's file and BOOT.BIN (the screen black by then);
# SELECT.BIN, at #4000, its unpacker and code first (here only its data)
FITS = [("select", "#4000", "#8000"),
        ("roada", "PACK_LOW", "UNPACK"), ("roadb", "PACK_LOW", "UNPACK"),
        ("roadc", "PACK_LOW", "UNPACK"), ("game", "PACK_LOW", "UNPACK"),
        ("sound", "PACK_LOW", "SOUND_BLOB"), ("race", "PACK_LOW", "SOUND_BLOB"),
        ("car0", "PACK_HIGH", "#10000"), ("car1", "PACK_HIGH", "#10000"),
        ("car2", "PACK_HIGH", "#10000"), ("car3", "PACK_HIGH", "#10000"),
        ("boot", "PACK_HIGH", "#10000")]


def discmap():
    """src/discmap.asm's EQUs (numbers, or a name plus a number)."""
    out = {}
    for line in open(os.path.join(ROOT, "src", "discmap.asm")):
        m = re.match(r"(\w+)\s+EQU\s+([\w#]+)(?:\+(\d+))?", line)
        if m:
            v = m.group(2)
            v = int(v[1:], 16) if v.startswith("#") else out[v]
            out[m.group(1)] = v + int(m.group(3) or 0)
    return out


def unzx0(data):
    """The bytes ZX0 data unpacks to, and how many of it were read."""
    pos = 0
    out = bytearray()
    mask, value = 0, 0
    back, last = False, 0
    offset = 1

    def byte():
        nonlocal pos, last
        last = data[pos]
        pos += 1
        return last

    def bit():
        nonlocal mask, value, back
        if back:
            back = False
            return last & 1
        mask >>= 1
        if not mask:
            mask, value = 128, byte()
        return 1 if value & mask else 0

    def gamma(inverted=False):
        v = 1
        while not bit():
            v = v << 1 | (bit() ^ inverted)
        return v

    def copy(n):
        for _ in range(n):
            out.append(out[-offset])

    while True:
        out += bytes(byte() for _ in range(gamma()))      # literals
        if not bit():
            copy(gamma())                                   # the last offset
            if not bit():
                continue
        while True:                                         # a new offset
            hi = gamma(True)
            if hi == 256:
                return bytes(out), pos
            offset = hi * 128 - (byte() >> 1)
            back = True
            copy(gamma() + 1)
            if not bit():
                break


def check(name, at, end):
    pk = open(os.path.join(ROOT, "build", name + ".pk"), "rb").read()
    raw = open(os.path.join(ROOT, "build", name + ".raw"), "rb").read()
    out, n = unzx0(pk[2:])
    if out != raw or n != len(pk) - 2:
        raise SystemExit("%s: unpacks to %d bytes (read %d of %d), not its %d"
                         % (name, len(out), n, len(pk) - 2, len(raw)))
    if at + len(pk) > end:
        raise SystemExit("%s: #%04X-#%04X, past #%04X" % (name, at, at + len(pk), end))
    return len(raw), len(pk), int.from_bytes(pk[:2], "little")


def main():
    eq = discmap()
    num = (lambda v: int(v[1:], 16) if v.startswith("#") else eq[v])
    total = [0, 0]
    for name, at, end in FITS:
        raw, pk, to = check(name, num(at), num(end))
        total[0] += raw
        total[1] += pk
        print("  %-6s %5d -> %5d bytes (%2d%%), at #%04X, to #%04X"
              % (name, raw, pk, 100 * pk // raw, num(at), to))
    print("packed: %d -> %d bytes (%d%%)" % (total[0], total[1], 100 * total[1] // total[0]))


if __name__ == "__main__":
    main()
