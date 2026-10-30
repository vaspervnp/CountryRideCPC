#!/usr/bin/env python3
"""The track: the demo's loop and the race's course of stages, as runs of
straight road, curves and hills (segments), and how the game turns them
into track entries - 32 depth units each - a few ahead of the camera
(game.asm, course_fill). This is the model of that, to the bit.

A segment is (n, v): n entries of
  v = 0         straight and flat road;
  0 < |v| <= 7  a curve, one level an entry towards level v and back (it
                ends at 0);
  |v| >= 16     a hill, v * sin(pi t / n) at entry t (a crest ahead is
                positive, a dip negative), from a quarter sine table.
The road never bends on a hill: one at a time.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcgfx as G

ENTRY = 32                      # depth units a track entry
STAGE_LEN = 384                 # entries a stage (12288 depth units)
HILL_RAMP = 12                  # a hill's move an entry towards flat, when
                                # the game switches from one list to another
SINE_Q = [round(255 * math.sin(math.pi * i / 128)) for i in range(65)]


def F(n):
    return (n, 0)


def C(n, k):
    assert 0 < abs(k) <= G.CURVE_K
    return (n, k)


def H(n, a):
    assert 16 <= abs(a) <= 127 and n <= 128      # (course_entry: 8 bits)
    return (n, a)


def segment_entries(n, v):
    """The (hill, curve) of each of a segment's entries, as course_entry
    works them out."""
    out = []
    p = q = 0
    for t in range(n):
        h = k = 0
        if v and abs(v) <= G.CURVE_K:
            k = min(abs(v), t, n - 1 - t) * (1 if v > 0 else -1)
        elif v:
            s = SINE_Q[p if p <= 64 else 128 - p]
            h = (abs(v) * s + 128) >> 8
            if v < 0:
                h = -h
            q += 128                            # p = 128 t / n, rounded down
            while q >= n:
                q -= n
                p += 1
        out.append((h, k))
    return out


def entries(segs):
    return [e for n, v in segs for e in segment_entries(n, v)]


def ramp(h, k):
    """The entries from (h, k) to the flat, as course_entry makes them when
    the game switches lists (the first one is the entry after (h, k))."""
    out = []
    while h or k:
        k -= (k > 0) - (k < 0)
        h = max(0, h - HILL_RAMP) if h > 0 else min(0, h + HILL_RAMP)
        out.append((h, k))
    return out


# The demo's loop: 256 entries, round and round.
DEMO = [F(6), H(32, 95), F(4), C(30, 5), F(4), H(32, -90), F(4), C(30, -7),
        F(4), H(26, 60), F(4), C(20, -3), F(4), H(24, 95), F(4), C(28, 7)]


def stage(segs):
    """A stage's segments, a straight to the checkpoint making it
    STAGE_LEN entries."""
    n = sum(n for n, v in segs)
    assert n <= STAGE_LEN - 8, n
    return segs + [F(STAGE_LEN - n)]


# The race: five stages, each its colours (pen: firmware colour) - the sky,
# the haze, the far mountains, the grass and the bushes.
STAGES = [
    dict(name="COUNTRYSIDE", pens={},
         segs=stage([F(12), C(24, 3), F(12), H(28, 70), F(6), C(30, -4),
                     F(4), C(24, 4), F(12), H(32, -60), F(6), C(32, 5),
                     F(12), H(24, 80), F(6), C(28, -5), F(12), H(30, -70),
                     F(6), C(30, 3)])),
    dict(name="DESERT",                         # long straights, big crests
         pens=dict(HAZE=25, GRASS_A=25, GRASS_B=24, BUSH=12, MAUVE=3),
         segs=stage([F(30), H(40, 95), F(20), C(30, 7), F(24), H(36, -90),
                     F(16), C(26, -7), F(30), H(40, 95), F(20), C(30, 6),
                     F(16)])),
    dict(name="ALPS",                           # hill after hill
         pens=dict(HAZE=26, GRASS_A=23, GRASS_B=26, BUSH=9, MAUVE=11),
         segs=stage([F(8), H(30, 90), F(4), H(28, -90), F(6), C(24, -5),
                     F(12), H(26, 95), F(4), H(32, -80), F(6), C(30, 6),
                     F(12), H(24, 85), F(4), H(30, -90), F(6), C(22, -6),
                     F(12), H(28, 90)])),
    dict(name="SUNSET",                         # long sweeping curves
         pens=dict(BLUE=4, SKY=16, PASTEL=15, HAZE=25, GRASS_A=9, GRASS_B=19,
                   BUSH=0, MAUVE=7),
         segs=stage([F(8), C(60, 5), F(6), C(56, -6), F(12), H(32, 70),
                     F(6), C(48, 6), F(6), C(44, -4), F(12), H(30, -80),
                     F(6), C(40, 7)])),
    dict(name="NIGHT",                          # winding
         pens=dict(BLUE=1, SKY=1, PASTEL=2, HAZE=7, GRASS_A=9, GRASS_B=1,
                   BUSH=0, MAUVE=4),
         segs=stage([F(8), C(22, 6), C(22, -6), F(4), C(24, 7), F(12),
                     H(28, 80), F(4), C(20, -7), C(20, 7), F(12), H(30, -90),
                     F(4), C(24, -6), C(24, 6), F(12), H(26, 95), F(4),
                     C(28, -7)])),
]

# What a stage's colours may change: the rest are the HUD's, the road's,
# the car's.
STAGE_PENS = ["BLUE", "SKY", "PASTEL", "HAZE", "GRASS_A", "BUSH", "GRASS_B",
              "MAUVE"]

FINISH = [F(64)]                # past the last checkpoint, then straight on
CURVE_HILL = 12                 # straight entries at least from a curve to a
                                # hill in the race: the road can be levels
                                # behind the track, and a level off the
                                # middle on a hill that moves makes a picture
                                # late (~39.9 ms with 6)


def race():
    return [s for st in STAGES for s in st["segs"]] + FINISH


def stage_fw(i):
    """Stage i's firmware colour for each of STAGE_PENS."""
    base = dict(G.PENS)
    return [STAGES[i]["pens"].get(p, base[p]) for p in STAGE_PENS]


def check():
    for segs in [DEMO] + [st["segs"] for st in STAGES] + [FINISH]:
        es = entries(segs)
        assert all(h == 0 or k == 0 for h, k in es)
        assert all(abs(a[1] - b[1]) <= 1 for a, b in zip(es, es[1:]))
        assert all(n > 0 for n, v in segs)
    assert len(entries(DEMO)) == 256
    flat = None                         # (straight since the last curve)
    for n, v in race():
        if v == 0:
            flat = None if flat is None else flat + n
        elif abs(v) <= G.CURVE_K:
            flat = 0
        else:
            assert flat is None or flat >= CURVE_HILL, (n, v, flat)
            flat = None
    for st in STAGES:
        assert len(entries(st["segs"])) == STAGE_LEN
        assert all(p in STAGE_PENS for p in st["pens"])


check()


if __name__ == "__main__":
    for st in STAGES:
        es = entries(st["segs"])
        print("%-12s %3d segments, hills %d entries, curves %d" % (
            st["name"], len(st["segs"]), sum(1 for h, k in es if h),
            sum(1 for h, k in es if k)))
    print("race: %d segments, %d bytes" % (len(race()), 2 * len(race()) + 2))
