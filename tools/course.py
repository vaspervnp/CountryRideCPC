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


# The race: five stages, one after the other - the first, then at each
# stage's end a fork: the stage on the left or the one on the right, as the
# car is left or right of the road's middle when the track ahead is worked
# out past the stage's end (course.asm course_entry, COURSE_AHEAD entries
# before its checkpoint). Stage 2 l + 1 + side follows a stage of level l
# (next_stage): the left ones are the first race's, the right ones others.
# Each its colours (pen: firmware colour) - the sky, the haze, the far
# mountains, the grass and the bushes - and its trees; its name for the
# fork's message; its traffic: the pictures at least between two cars
# coming (src/traffic.asm tr_pauses, and 0-31 more at random), fewer the
# further on - and on a fork's right than on its left. Measured (the
# autopilot, the ROSSO GT), the cars on the road on average for a pause:
# 0.9 for 64, 1.2 for 48, 1.55 for 32, 1.8 for 20, 2 (all there can be)
# from 10 down; a slower car has more about it.
STAGES = [
    dict(name="COUNTRYSIDE", traffic=64, pens={}, trees=["dead"],
         segs=stage([F(12), C(24, 3), F(12), H(28, 70), F(6), C(30, -4),
                     F(4), C(24, 4), F(12), H(32, -60), F(6), C(32, 5),
                     F(12), H(24, 80), F(6), C(28, -5), F(12), H(30, -70),
                     F(6), C(30, 3)])),
    dict(name="DESERT", traffic=48,             # long straights, big crests
         pens=dict(HAZE=25, GRASS_A=25, GRASS_B=24, BUSH=12, MAUVE=3),
         trees=["palm", "dead", "stump"],
         segs=stage([F(30), H(40, 95), F(20), C(30, 7), F(24), H(36, -90),
                     F(16), C(26, -7), F(30), H(40, 95), F(20), C(30, 6),
                     F(16)])),
    dict(name="RIVIERA", traffic=40,            # the coast: sweeping, gentle
         pens=dict(HAZE=20, GRASS_A=22, GRASS_B=19, BUSH=9, MAUVE=2),
         trees=["palm"],
         segs=stage([F(12), C(40, 4), F(10), C(36, -5), F(12), H(28, 60),
                     F(8), C(44, 5), F(8), C(30, -3), F(12), H(32, -70),
                     F(8), C(40, -6), F(10), C(36, 4), F(10)])),
    dict(name="SUMMIT", traffic=32,             # hill after hill
         pens=dict(HAZE=26, GRASS_A=23, GRASS_B=26, BUSH=9, MAUVE=11),
         trees=["dead"],
         segs=stage([F(8), H(30, 90), F(4), H(28, -90), F(6), C(24, -5),
                     F(12), H(26, 95), F(4), H(32, -80), F(6), C(30, 6),
                     F(12), H(24, 85), F(4), H(30, -90), F(6), C(22, -6),
                     F(12), H(28, 90)])),
    dict(name="MESA", traffic=28,               # canyons: deep dips, sharp
         pens=dict(HAZE=16, GRASS_A=15, GRASS_B=12, BUSH=3, MAUVE=3),
         trees=["dead", "stump"],
         segs=stage([F(14), H(36, -95), F(10), H(30, 85), F(12), C(26, 7),
                     F(8), C(26, -6), F(14), H(40, -90), F(10), C(30, 6),
                     F(12), H(28, 95), F(6), H(26, -80), F(12), C(24, -7),
                     F(12)])),
    dict(name="SUNSET", traffic=20,             # long sweeping curves
         pens=dict(BLUE=4, SKY=16, PASTEL=15, HAZE=25, GRASS_A=9, GRASS_B=19,
                   BUSH=0, MAUVE=7),
         trees=["palm", "stump"],
         segs=stage([F(8), C(60, 5), F(6), C(56, -6), F(12), H(32, 70),
                     F(6), C(48, 6), F(6), C(44, -4), F(12), H(30, -80),
                     F(6), C(40, 7)])),
    dict(name="AUTUMN", traffic=16,             # winding, over hills
         pens=dict(HAZE=25, GRASS_A=12, GRASS_B=9, BUSH=15, MAUVE=7),
         trees=["dead", "stump"],
         segs=stage([F(10), C(28, 5), F(6), C(28, -5), F(12), H(30, 75),
                     F(6), C(24, 6), C(24, -6), F(12), H(26, -85), F(8),
                     C(32, 4), F(6), C(26, -7), F(12), H(30, 80), F(8),
                     C(28, 5)])),
    dict(name="NIGHT", traffic=10,              # winding
         pens=dict(BLUE=1, SKY=1, PASTEL=2, HAZE=7, GRASS_A=9, GRASS_B=1,
                   BUSH=0, MAUVE=4),
         trees=["palm"],
         segs=stage([F(8), C(22, 6), C(22, -6), F(4), C(24, 7), F(12),
                     H(28, 80), F(4), C(20, -7), C(20, 7), F(12), H(30, -90),
                     F(4), C(24, -6), C(24, 6), F(12), H(26, 95), F(4),
                     C(28, -7)])),
    dict(name="STORM", traffic=4,               # grey skies, hard curves
         pens=dict(BLUE=1, SKY=13, PASTEL=14, HAZE=13, GRASS_A=9, GRASS_B=13,
                   BUSH=0, MAUVE=1),
         trees=["dead"],
         segs=stage([F(20), H(36, 90), F(12), C(30, -7), F(10), C(30, 7),
                     F(14), H(32, -95), F(12), H(28, 70), F(6), C(26, -6),
                     F(8), C(22, 6), F(14), H(30, -80), F(6), C(30, 5),
                     F(10)])),
]
LEVELS = 5                      # stages a race
FORK_AHEAD = 64                 # entries before a stage's end its fork's
                                # message is shown from (game.asm)
FIRST_ROUTE = (0, 1, 3, 5, 7)   # the left at every fork


def next_stage(level, right):
    """The stage after one of level `level` (0..LEVELS-2): its fork's left
    (right = 0) or right one."""
    return 2 * level + 1 + right


def routes():
    out = [(0,)]
    for level in range(LEVELS - 1):
        out = [r + (next_stage(level, side),) for r in out for side in (0, 1)]
    return out


# The props beside the road (tools/mkprops.py has their sprites, src/props.asm
# stands and draws them): a curve sign at the start of every curve of level
# 3 or more, on its outside, its chevrons pointing the way it bends; a speed
# limit sign before every curve of level 6 or more, on the right; and each
# stage's trees, by turns, wherever there is room for them - on a segment
# TREE_SEG entries long or longer (a straight, a hill, a curve's outside),
# about TREE_EVERY apart. Never two in sight at once (PROP_GAP).
PROP_KINDS = ["palm", "stump", "dead", "limit", "curve", "curve_r"]
PROP_ZVIS = 800                 # depth units ahead a prop is first drawn from
PROP_GAP = 760                  # ... and from one to the next, at least: one
                                # in sight at a time (PROP_ZVIS - BUSH_ZNEAR)
PROP_ROOM = dict(palm=1, stump=1, dead=1, limit=1, curve=1, curve_r=1)
                                # bushes in reach at most while one is in
                                # sight (src/props.asm: for the time)
SIGN_LAT, TREE_LATS = 1, (1, 2)  # bush lateral classes (cpcgfx.BUSH_LATS)
TREE_EVERY = 1200               # depth units between trees, about - on a
TREE_SEG = 8                    # segment this long or longer


def prop_code(kind, side, lat):
    """A prop's byte in the lists: kind, lateral class, side (bit 7: left)."""
    return PROP_KINDS.index(kind) | lat << 4 | (0x80 if side < 0 else 0)


def props_want(segs, trees=False, seed=1, z0=0):
    """The props a segment list would have: [(z, priority, kind, side, lat,
    lo, hi)], z in depth units from z0 at its first entry, a tree anywhere
    from lo to hi ("tree": its kind is given later, props_kept)."""
    import random
    rnd = random.Random(seed)
    want = []
    e = 0
    for n, v in segs:
        if v and abs(v) <= G.CURVE_K and abs(v) >= 3:
            side = -1 if v > 0 else 1
            z = (e + 3) * ENTRY
            want.append((z, 0, "curve_r" if v > 0 else "curve", side, SIGN_LAT, z, z))
            if abs(v) >= 6:
                z = (e - 28) * ENTRY
                want.append((z, 1, "limit", 1, SIGN_LAT, z, z))
        if trees and n >= TREE_SEG:
            m = max(1, n * ENTRY // TREE_EVERY)
            for k in range(m):
                side = rnd.choice((-1, 1))
                if v and abs(v) <= G.CURVE_K:
                    side = -1 if v > 0 else 1   # (a curve's outside)
                want.append(((e + n * (k + 1) // (m + 1)) * ENTRY, 2, "tree", side,
                             rnd.choice(TREE_LATS), (e + n * k // m) * ENTRY,
                             (e + n * (k + 1) // m - 1) * ENTRY))
        e += n
    return [(z0 + z, p, k, sd, lt, z0 + lo, z0 + hi) for z, p, k, sd, lt, lo, hi in want]


def props_kept(want, trees, loop=0, zmax=None):
    """Those of the props wanted kept, the curve signs first, then the limit
    signs, then the trees - each where it is wanted or, a tree, the nearest
    to it that it can be: none nearer another than PROP_GAP (round the loop
    too), a stage's (zmax) none nearer its ends than half that. The trees
    kept are the kinds in `trees` by turns (a function of the depth).
    [(z, kind, side, lat)], nearest first."""
    out = []
    zmin = 0 if zmax is None else PROP_GAP // 2

    def free(z):
        return (z >= zmin and (not loop or z < loop) and (zmax is None or z <= zmax)
                and all(abs(z - z2) >= PROP_GAP and (not loop or loop - abs(z - z2) >= PROP_GAP)
                        for z2, _, _, _ in out))
    for z, pri, kind, side, lat, lo, hi in sorted(want, key=lambda w: (w[1], w[0])):
        at = sorted(range(lo, hi + 1, ENTRY), key=lambda z2: abs(z2 - z))
        at = next((z2 for z2 in [z] + at if free(z2)), None)
        if at is not None:
            out.append((at, kind, side, lat))
    out.sort()
    turn = {}
    for i, (z, kind, side, lat) in enumerate(out):
        if kind == "tree":
            kinds = trees(z)
            n = turn[id(kinds)] = turn.get(id(kinds), -1) + 1
            out[i] = (z, kinds[n % len(kinds)], side, lat)
    return out


def demo_props():
    return props_kept(props_want(DEMO, True), lambda z: STAGES[0]["trees"],
                      len(entries(DEMO)) * ENTRY)


def stage_props(i):
    """Stage i's props, from its first entry: whatever stage comes before
    or after it, never two nearer than PROP_GAP."""
    st = STAGES[i]
    return props_kept(props_want(st["segs"], True, i + 1), lambda z: st["trees"],
                      zmax=STAGE_LEN * ENTRY - PROP_GAP // 2)


def race_props(route=FIRST_ROUTE):
    """A race's props along `route`, from its first stage's first entry."""
    return [(z + k * STAGE_LEN * ENTRY, kind, side, lat)
            for k, i in enumerate(route) for z, kind, side, lat in stage_props(i)]


def prop_list(props, loop=0):
    """Bytes of the list as the game has it: per prop the gap from the last
    (or the list's start) in 16 depth units, then its byte (prop_code); at
    the end the gap to the list's end and #FF (round again: `loop`, its
    length) or 0,#FE (no more)."""
    out, z0 = [], 0
    for z, kind, side, lat in props:
        gap = z - z0
        assert gap % 16 == 0 and 0 < gap < 256 * 16, (z, gap)
        out += [gap // 16, prop_code(kind, side, lat)]
        z0 = z
    if loop:
        gap = loop - z0
        assert gap % 16 == 0 and 0 < gap < 256 * 16
        out += [gap // 16, 0xFF]
    else:
        out += [0, 0xFE]
    return out


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


def race(route=FIRST_ROUTE):
    """A race's segments along `route` (its stages), then the finish."""
    return [s for i in route for s in STAGES[i]["segs"]] + FINISH


def fork_text(level, width):
    """The message at the end of a stage of level `level`: the next stage on
    the left, the left, and the one on the right, the right - `width` long."""
    left, right = (STAGES[next_stage(level, side)]["name"] for side in (0, 1))
    return left + " " * (width - len(left) - len(right)) + right


FORK_W = max(len(STAGES[next_stage(l, 0)]["name"]) + len(STAGES[next_stage(l, 1)]["name"]) + 2
             for l in range(LEVELS - 1))


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
    for route in routes():
        flat = None                     # (straight since the last curve)
        for n, v in race(route):
            if v == 0:
                flat = None if flat is None else flat + n
            elif abs(v) <= G.CURVE_K:
                flat = 0
            else:
                assert flat is None or flat >= CURVE_HILL, (route, n, v, flat)
                flat = None
    assert len(STAGES) == 2 * LEVELS - 1
    for st in STAGES:
        assert len(entries(st["segs"])) == STAGE_LEN
        assert all(p in STAGE_PENS for p in st["pens"])


check()
for _props, _loop in ([(demo_props(), len(entries(DEMO)) * ENTRY)]
                      + [(stage_props(i), 0) for i in range(len(STAGES))]):
    assert all(b[0] - a[0] >= PROP_GAP for a, b in zip(_props, _props[1:]))
    if _loop:
        assert _props[0][0] + _loop - _props[-1][0] >= PROP_GAP
    prop_list(_props, _loop)


if __name__ == "__main__":
    for st in STAGES:
        es = entries(st["segs"])
        print("%-12s %3d segments, hills %d entries, curves %d" % (
            st["name"], len(st["segs"]), sum(1 for h, k in es if h),
            sum(1 for h, k in es if k)))
    segs = sum(len(st["segs"]) for st in STAGES) + len(FINISH)
    print("stages: %d segments, %d bytes" % (segs, 2 * segs + 2 * len(STAGES) + 2))
    for name, props in [("demo", demo_props())] + [(st["name"], stage_props(i))
                                                   for i, st in enumerate(STAGES)]:
        kinds = {}
        for z, kind, side, lat in props:
            kinds[kind] = kinds.get(kind, 0) + 1
        print("%s props: %d (%s), %d bytes" % (name, len(props), kinds, len(prop_list(props, 8192 if name == "demo" else 0))))
    for l in range(LEVELS - 1):
        print("fork %d: [%s]" % (l, fork_text(l, FORK_W)))
