#!/usr/bin/env python3
"""The driving's model: Out Run's physics (Sega's SMS game) as the user's
OutrunOutrunCPC runs them - its own code written to the SMS's
(OutrunOutrunCPC tools/native/LOGIC.md, steps 1.10a and 1.10b: the engine
L2F6B and the steering L264D) - and what Country Ride makes of them
(src/game.asm steer and speed_player, scene.py's car stats).

Out Run's car (OutrunOutrunCPC: 12 race loops a second; the steering a
loop, the engine twice):
- the engine: revs pulled up by a torque curve through the gear's ratio,
  the speed (km/h) following the revs by 2 at most an engine step (8
  braking), two gears the player picks - LOW to 193, HIGH to 293 - and in
  either the ratio stepping on towards its own. In LOW from a standstill
  100 km/h at 3.6 s, 160 at 5.4, 193 at 11.3; in HIGH 100 at 4.7 s (T_LOW,
  T_HIGH); with the gear changed at its best, 160 (ENGINE_SHIFT: the demo's
  drive changes there), 193 at 6.6, 250 at 9.0, 280 at 13.7 and 293 at 23.6.
  Lifting off it loses 2 a step (48 km/h a second), braking ~164 a second;
  off the road the pedal gives less: on the sand the high gear no more than
  221, past it the low gear 117 and the high one 88 (CAPS);
- the wheel: towards +-127 by 64 a loop; the car across the road its turn
  / 8 + / 32 units a loop (18 at the full lock), times the speed / 128
  below 128 on the road, less in a bend sharper than 64 above 147 (f =
  1 - (v - 147)(64 - r) / 9408); the road's edge (the sand) at 108 units
  from its middle, the sand 40 wide;
- a bend of radius r carries the car out by v (min(1091 / min(r, 127),
  127) - 1) / 220 units a loop, this pull moving towards that by 5 a
  loop. The game's bends are r 45-90, mostly 50-63 (k 16-20).

Ours (25 pictures a second, the steering once a picture, the speed a
VSYNC): a speed of SPEED_TOP (8.8 depth units a VSYNC, the first car's top)
is 293 km/h; Out Run's 108 units are OFFROAD_X (20) pairs, so a unit is
UNIT pairs and a loop's move U pairs a picture times 12 / 25; a curve level
L is a radius 45 x 7 / L (curvature with the level, level 7 Out Run's
sharpest). The first car (ROSSO) is Out Run's; the others are as far from
it as their bars (scene.py CAR_LEVELS): the speed curve scaled to their top
and each acceleration bar 15% quicker or slower, each grip bar 10% more
steering and 10% less pull.

    python3 tools/outrun.py           the numbers ours come to
    python3 tools/outrun.py --check   T_LOW, T_HIGH again from the model (needs
                                      ../OutrunOutrunCPC: its engine's
                                      tables are the ROM's)
"""

import os
import re
import sys

LOOPS = 12                      # OutrunOutrunCPC's race loops a second
ENGINE_STEPS = 2 * LOOPS        # ... the engine's steps
PICTURES = 25                   # ours a second
VSYNCS = 50
V_TOP = 293                     # Out Run's top speed (the high gear's)
ENGINE_SHIFT = 160              # the best speed to change up
GEAR_TOP = (193, 293)           # LOW's top speed, HIGH's
SAND_EDGE, SAND_W = 108, 40     # Out Run's road edge and sand (shape 0)
# the most the pedal gives, LOW and HIGH: on the road, on the sand (HIGH:
# #BE of the revs), on the grass past it (#99, #4C)
CAPS = dict(road=(193, 293), sand=(193, 221), grass=(117, 88))
BRAKE_STEPS = 43                # engine steps braking from 293 to a standstill
                                # (--check)
OFFROAD_X = 20                  # ours: a wheel off a 4-lane road (player.asm)
UNIT = OFFROAD_X / SAND_EDGE    # an Out Run unit, pairs
LOOP_TO_PIC = UNIT * LOOPS / PICTURES   # units a loop -> pairs a picture
R7 = 45                         # the radius of our sharpest curve level

# T_LOW[v], T_HIGH[v]: the time Out Run's car takes from a standstill, the
# pedal down, in that gear, to v km/h (to its top): tenths of an engine step
# (1/240 s), between the steps' speeds (--check)
T_LOW = [
    0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85,
    90, 95, 100, 105, 110, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160,
    165, 170, 175, 180, 190, 195, 200, 220, 230, 240, 260, 265, 270, 280,
    300, 310, 320, 335, 340, 350, 370, 380, 390, 400, 410, 420, 430, 445,
    450, 460, 480, 490, 500, 510, 520, 530, 540, 560, 565, 570, 590, 600,
    610, 620, 630, 640, 650, 660, 670, 680, 700, 705, 710, 730, 740, 745,
    750, 770, 775, 780, 800, 805, 810, 830, 835, 840, 850, 865, 870, 880,
    895, 900, 910, 920, 930, 940, 950, 960, 965, 970, 985, 990, 1000, 1010,
    1015, 1020, 1030, 1040, 1045, 1050, 1060, 1065, 1070, 1080, 1085, 1090,
    1100, 1105, 1110, 1120, 1125, 1130, 1140, 1145, 1150, 1160, 1165, 1170,
    1175, 1180, 1185, 1190, 1200, 1205, 1210, 1220, 1225, 1230, 1235, 1240,
    1245, 1250, 1260, 1270, 1275, 1280, 1290, 1295, 1300, 1310, 1320, 1325,
    1330, 1345, 1350, 1360, 1375, 1380, 1390, 1410, 1420, 1430, 1450, 1480,
    1500, 1520, 1570, 1600, 1630, 1690, 1730, 1760, 1810, 1900, 1950, 2020,
    2170, 2260, 2350, 2610, 2740
]
T_HIGH = [
    0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85,
    90, 95, 100, 105, 110, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160,
    165, 170, 175, 180, 185, 190, 195, 200, 205, 210, 215, 220, 225, 230,
    250, 260, 280, 290, 300, 320, 340, 360, 380, 400, 415, 420, 440, 460,
    480, 500, 520, 535, 540, 560, 580, 600, 620, 640, 655, 660, 680, 700,
    720, 740, 760, 775, 780, 800, 820, 840, 860, 880, 895, 900, 920, 940,
    960, 980, 1000, 1015, 1020, 1040, 1060, 1080, 1100, 1120, 1135, 1140,
    1160, 1180, 1200, 1220, 1240, 1260, 1275, 1280, 1300, 1320, 1340, 1360,
    1380, 1395, 1400, 1420, 1440, 1460, 1470, 1490, 1505, 1510, 1530, 1550,
    1570, 1590, 1610, 1625, 1630, 1650, 1660, 1680, 1700, 1720, 1735, 1740,
    1750, 1770, 1790, 1810, 1830, 1835, 1840, 1860, 1880, 1890, 1910, 1930,
    1945, 1950, 1960, 1980, 2000, 2010, 2030, 2050, 2055, 2060, 2080, 2100,
    2110, 2130, 2145, 2150, 2160, 2180, 2190, 2210, 2220, 2240, 2245, 2250,
    2270, 2280, 2300, 2310, 2320, 2335, 2340, 2350, 2360, 2380, 2390, 2400,
    2415, 2420, 2430, 2440, 2450, 2460, 2480, 2485, 2490, 2500, 2510, 2520,
    2530, 2550, 2555, 2560, 2570, 2580, 2590, 2600, 2610, 2615, 2620, 2630,
    2640, 2650, 2660, 2680, 2685, 2690, 2700, 2710, 2720, 2730, 2740, 2750,
    2755, 2760, 2770, 2780, 2790, 2800, 2820, 2825, 2830, 2840, 2850, 2860,
    2870, 2880, 2885, 2890, 2910, 2920, 2930, 2940, 2960, 2965, 2970, 2980,
    3000, 3010, 3020, 3040, 3045, 3050, 3070, 3090, 3100, 3120, 3140, 3155,
    3160, 3180, 3200, 3220, 3240, 3260, 3285, 3290, 3320, 3350, 3390, 3440,
    3490, 3545, 3550, 3600, 3670, 3730, 3810, 3890, 3990, 4085, 4090, 4190,
    4290, 4390, 4520, 4660, 4785, 4790, 4980, 5180, 5380, 5770, 6170, 6565,
    6570
]
assert len(T_LOW) == GEAR_TOP[0] + 1 and len(T_HIGH) == GEAR_TOP[1] + 1


def brake_rate():
    """km/h a second braking, on average from the top."""
    return round(V_TOP * ENGINE_STEPS / BRAKE_STEPS)


def k_of_r(r):
    """Out Run's pull factor for a bend of radius r (L264D step 5)."""
    return min(0x443 // min(r, 127), 0x7F) - 1


def radius(level):
    """The radius our curve level stands for."""
    return round(R7 * 7 / level)


def pull_levels():
    """Per curve level 1-7: Out Run's k (game.asm push_levels)."""
    return [k_of_r(radius(L)) for L in range(1, 8)]


def sharp_levels():
    """Per curve level 1-7: the steering's cut in a sharp bend, 64 - r
    (0 for r 64 and up) times 13 (game.asm steer_sharp: (speed / 16 - 79)
    x this / 256 is the cut, /256 of the turn: 147 km/h is 79 x 16)."""
    return [13 * max(0, 64 - radius(L)) for L in range(1, 8)]


def time_to(v, gear):
    """Seconds from a standstill to v km/h in the gear (T_LOW, T_HIGH),
    between their speeds, to the gear's top."""
    t = (T_LOW, T_HIGH)[gear]
    v = max(0.0, min(float(len(t) - 1), v))
    i = min(int(v), len(t) - 2)
    return (t[i] + (t[i + 1] - t[i]) * (v - i)) / (10 * ENGINE_STEPS)


def acc_table(top, quick, bands, band, gear):
    """The speed gained a VSYNC in the gear, sixteenths of a speed unit (8.8
    depth units a VSYNC), per speed band (speed / band): Out Run's curve
    scaled to this car's top (its top speed Out Run's 293), quick times as
    quick; 0 past the gear's top."""
    gtop = top * GEAR_TOP[gear] / V_TOP         # the gear's top, ours
    out = []
    for i in range(bands):
        s0, s1 = band * i, min(band * (i + 1), gtop)
        if s0 >= gtop:
            out.append(0)
            continue
        s0 = min(s0, s1 - band)          # (the top's band, cut short: as a
        dt = time_to(V_TOP * s1 / top, gear) - time_to(V_TOP * s0 / top, gear)
        per_vsync = (s1 - s0) * quick / (dt * VSYNCS)   # whole one)
        out.append(max(1, min(255, round(16 * per_vsync))))
    return out


# ---------------------------------------------------------------------------
# The model (--check): OutrunOutrunCPC's specs of L2F6B, with the ROM's tables
# ---------------------------------------------------------------------------

def rom_tables():
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                     "OutrunOutrunCPC", "src", "native", "engine.asm")
    src = open(p).read()
    tq = src[src.index("en_torque:"):src.index("en_ratios:")]
    torque = [int(v, 16) for ln in tq.splitlines() if ln.strip().startswith("db")
              for v in re.findall(r"#([0-9A-F]{2})\b", ln)]
    rt = src[src.index("en_ratios:"):src.index("en_squares:")]
    ratios = [int(v, 16) for ln in rt.splitlines() if ln.strip().startswith("dw")
              for v in re.findall(r"#([0-9A-F]{4})\b", ln)]
    assert len(torque) == 256 and len(ratios) == 32
    return torque, ratios


class Engine:
    """L2F6B, an engine step, in a race (OutrunOutrunCPC LOGIC.md 1.10a)."""

    def __init__(self, torque, ratios):
        self.tq, self.rt = torque, ratios
        self.sq = [(r * r) >> 12 for r in ratios]
        self.v = 0
        self.revs = 0x001F
        self.ratio = 0x1000
        self.idx = 0x1F
        self.gear = self.gset = self.shift = 0
        self.last = self.fade = 0
        self.top = 0xC1
        self.under = 0

    def step(self, gear, pedal=0xFF, brake=False):
        s = self
        tq = lambda h: s.tq[min(h, 255)]          # noqa: E731
        s.gear = gear
        if not s.under:                             # the start: under way
            s.under = 1
            s.idx = (0x30 - tq(s.revs >> 16)) // 4
        elif s.shift == 0:
            if s.gear == 0:
                if s.gset:
                    s.gset, s.shift, s.top = 0, 4, 0xC1
                elif s.idx < 0x10:
                    s.idx += 1
                elif s.idx > 0x10:
                    s.idx = max(0x10, s.idx - 4)
            elif s.gset != 1:
                s.gset, s.shift, s.top = 1, 4, 0x125
            else:
                s.idx = min(0x1F, s.idx + 1)
        q = s.revs // s.ratio
        s.ratio = s.rt[s.idx]
        p = q * s.ratio
        ph = p >> 16
        if s.shift:
            s.shift -= 1
            if s.shift == 0 and ph > 0xE0 and pedal >= 0xE0:
                s.fade = (pedal - 0xE0) & 0xFF
            d = s.last - (s.last >> 4)
        elif pedal == ph:
            d = 0
        elif pedal > ph:
            d = tq(ph) * (2 if s.v < 0x14 else 1) * 2 * s.sq[s.idx]
        else:
            d = -68 * s.ratio
        if s.fade:
            d = s.last - (s.last >> 4)
            s.fade -= 1
        if brake:
            d -= 0x44000
        s.last = d
        s.revs = max(0, min(0x13C0000, p + d))
        vv = (((s.revs >> 16) * 425) & ~15) * 256 // s.ratio * 9 >> 9
        vv = min(vv, s.top)
        if s.v < vv:
            s.v = min(vv, s.v + 2)
        elif s.v > vv:
            s.v = max(vv, s.v - (8 if brake else 2))
        return s.v


def model_t(gear):
    """T_LOW or T_HIGH: the speed after each engine step in the gear, the
    time it passes each v worked out between the steps (tenths of a step)."""
    e = Engine(*rom_tables())
    vs = [0]
    for i in range(60 * ENGINE_STEPS):
        vs.append(e.step(gear))
    out, n = [], 1
    for v in range(GEAR_TOP[gear] + 1):
        while vs[n] < v:
            n += 1
        a, b = vs[n - 1], vs[n]
        t = n - 1 + (v - a) / (b - a) if b > a else n
        out.append(round(10 * t))
    return out


def main():
    if "--check" in sys.argv:
        for gear, name in ((0, "T_LOW"), (1, "T_HIGH")):
            got = model_t(gear)
            if got != globals()[name]:
                print(name, "differs from the model:\n", got)
                raise SystemExit(1)
        e = Engine(*rom_tables())
        for i in range(40 * ENGINE_STEPS):
            e.step(0 if (e.v < ENGINE_SHIFT and e.gear == 0) else 1)
        n = 0
        while e.v:
            e.step(1, pedal=0, brake=True)
            n += 1
        if n != BRAKE_STEPS:
            print("BRAKE_STEPS: the model's is", n)
            raise SystemExit(1)
        print("T_LOW, T_HIGH and BRAKE_STEPS as the model has them")
        return
    print("full lock: %.3f pairs a picture" % (18 * LOOP_TO_PIC))
    print("pull per level (k):", pull_levels())
    print("sharp cut per level:", sharp_levels())
    for v in (100, 160, 193, 250, 280, 290, 293):
        print("  %3d km/h at %s s" % (v, " / ".join("%.1f" % time_to(v, g)
                                                for g in (0, 1) if v <= GEAR_TOP[g])))


if __name__ == "__main__":
    main()
