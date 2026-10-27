#!/usr/bin/env python3
"""Boot build/countryride.dsk on an emulated CPC 6128 and look at it.

    tools/run.py shots     screenshots into docs/
    tools/run.py check     frame rate; the buffers and the split screen vs scene.py
    tools/run.py watch N   N seconds, a screenshot every second, in build/

The emulator is floooh/chips' CPC (Z80, gate array, CRTC, PPI, FDC with
.DSK) with the real 6128 ROMs, driven headless through ~/repos/CPCTools/cpcemu.
It boots BASIC, RUN"COUNTRY loads the disc like a real machine would, and the
screenshots are what the gate array actually put out.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMU = os.path.expanduser("~/repos/CPCTools/cpcemu")
sys.path.insert(0, EMU)
sys.path.insert(0, os.path.join(ROOT, "tools"))

DSK = os.path.join(ROOT, "build", "countryride.dsk")
SYM = os.path.join(ROOT, "build", "countryride.sym")


def symbols():
    out = {}
    for line in open(SYM):
        m = re.match(r"^(\S+)\s+#([0-9A-Fa-f]+)\s", line)
        if m:
            out[m.group(1).upper()] = int(m.group(2), 16)
    return out


def load_emulator():
    """The emulator module, using build/libcpcdebug.so (registers, steps)
    when tools/emu/build.sh has been run, the stock library otherwise."""
    import ctypes
    import cpc
    dbg = os.path.join(ROOT, "build", "libcpcdebug.so")
    if os.path.exists(dbg) and not hasattr(cpc, "_debug"):
        lib = cpc._bind(ctypes.CDLL(dbg))
        lib.cpcemu_regs.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint16)]
        lib.cpcemu_run_to.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_uint32]
        lib.cpcemu_run_to.restype = ctypes.c_int
        lib.cpcemu_trace.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                     ctypes.POINTER(ctypes.c_uint16)]
        lib.cpcemu_ticks.argtypes = [ctypes.c_void_p]
        lib.cpcemu_ticks.restype = ctypes.c_uint64
        lib.cpcemu_crtc.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint8)]
        lib.cpcemu_set_adj_mode.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.cpcemu_fb_ptr.argtypes = [ctypes.c_void_p]
        lib.cpcemu_fb_ptr.restype = ctypes.c_void_p
        cpc._lib = lib
        cpc._debug = True
    return cpc


REG_NAMES = ["AF", "BC", "DE", "HL", "IX", "IY", "SP", "PC",
             "AF'", "BC'", "DE'", "HL'", "IR", "IM", "IFF", "RAM"]


def regs(c):
    import ctypes
    import cpc
    buf = (ctypes.c_uint16 * 16)()
    cpc._lib.cpcemu_regs(c._h, buf)
    return dict(zip(REG_NAMES, list(buf)))


def run_to(c, pc, max_instr=10000000):
    import cpc
    return cpc._lib.cpcemu_run_to(c._h, pc, max_instr)


def crtc(c):
    """The CRTC's VCC, RA, R5 line (None outside the R5 lines), display on."""
    import ctypes
    import cpc
    buf = (ctypes.c_uint8 * 4)()
    cpc._lib.cpcemu_crtc(c._h, buf)
    return buf[0], buf[1], None if buf[2] == 0xFF else buf[2], bool(buf[3])


def us(c):
    """Microseconds of emulated time spent in run_to/trace so far."""
    import cpc
    return cpc._lib.cpcemu_ticks(c._h) / 4.0


def trace(c, n):
    import ctypes
    import cpc
    buf = (ctypes.c_uint16 * n)()
    cpc._lib.cpcemu_trace(c._h, n, buf)
    return list(buf)


class Game:
    """The game booted from the disc, with car CAR (env, 0-3: the loader's
    screen picks it by its number) - scene.py set to it too."""

    def __init__(self, car=None):
        CPC = load_emulator().CPC
        self.sym = symbols()
        self.car = int(os.environ.get("CAR", "0")) if car is None else car
        import scene
        scene.set_car(self.car)
        self.c = CPC()
        self.c.run_frames(150)                  # to the BASIC prompt
        self.c.insert_disc(DSK)
        blob, magic = self.sym["CAR_BLOB"], self.sym["CAR_MAGIC"]
        self.c.write_ram(blob, bytes(2))
        self.c.type_text('RUN"COUNTRY\n')
        # load; the car's number now and then until the loader has loaded
        # its CARn.BIN (the magic word at CAR_BLOB), BOOT.BIN has taken it
        # (its high byte 0) and the game has drawn its first pictures (the
        # count is BASIC's memory till then)
        phase = 0
        for i in range(2000):
            self.c.run_frames(1)
            w = self.word("CAR_BLOB")
            if phase == 0:
                if w == magic:
                    phase = 1
                elif i % 100 == 50:
                    self.c.type_text(str(self.car + 1))
            elif phase == 1 and not w >> 8:
                phase = 2
            elif phase == 2 and 2 <= self.word("FRAMES_DRAWN") < 50:
                break                           # (BASIC's till the fragments
                                                # are in place)
        else:
            raise SystemExit("the game never drew a picture (PC #%04X)"
                             % self.c.pc)
        assert self.game_byte("CAR_ID") == self.car, (self.game_byte("CAR_ID"), self.car)

    def byte(self, name, off=0):
        return self.c.read_ram(self.sym[name] + off, 1)[0]

    def word(self, name):
        b = self.c.read_ram(self.sym[name], 2)
        return b[0] | (b[1] << 8)

    def bank(self, n, addr, size):
        """Read extra RAM bank n (4-7) as the Z80 sees it at addr."""
        import ctypes
        import cpc
        p = cpc._lib.cpcemu_ram_ptr(self.c._h, n)
        return ctypes.string_at(ctypes.addressof(p.contents) + (addr & 0x3FFF), size)

    def game_byte(self, name, off=0):
        """A variable of the game code, which lives in bank 7 at #C000."""
        return self.bank(7, self.sym[name] + off, 1)[0]

    def game_poke(self, name, value, off=0):
        """Set a byte variable of the game code (bank 7)."""
        import ctypes
        import cpc
        p = cpc._lib.cpcemu_ram_ptr(self.c._h, 7)
        a = ctypes.addressof(p.contents) + ((self.sym[name] + off) & 0x3FFF)
        ctypes.memmove(a, bytes([value & 0xFF]), 1)

    def shot(self, path):
        self.c.screenshot(path, aspect=True)

def fps(g, seconds=10):
    v0 = g.byte("VBL_COUNT")
    f0 = g.word("FRAMES_DRAWN")
    late0 = g.word("FRAMES_LATE")
    vbls = 0
    last = v0
    for _ in range(seconds * 50):
        g.c.run_frames(1)
        v = g.byte("VBL_COUNT")
        vbls += (v - last) & 0xFF
        last = v
    frames = g.word("FRAMES_DRAWN") - f0
    late = g.word("FRAMES_LATE") - late0
    return frames, vbls, late


def cmd_shots():
    """Screenshots of the road's shapes, taken at a VSYNC so the picture is
    whole: flat and straight, behind the top of a crest (road down to 1/3 of
    the screen, ground showing), in a dip (road up to 2/5), and the sharpest
    curve - the demo track never bends on a hill. A shape counts once the
    curve level has held for 8 VSYNCs, so both buffers were drawn with it.
    And the screen the car is picked on, the game loaded, the third car
    picked (its frame moved twice to the right)."""
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    c = load_emulator().CPC()
    c.run_frames(150)
    c.insert_disc(DSK)
    c.type_text('RUN"COUNTRY\n')
    c.run_frames(1000)                          # (all loaded by then)
    for _ in range(2):
        c.tap_key("p", 10, 20)
    c.run_frames(13)                            # (the frame's ink: yellow)
    path = os.path.join(docs, "screen-select.png")
    c.screenshot(path, aspect=True)
    print("wrote", path)
    del c
    g = Game()
    want = {"flat": lambda h, k: h == 0 and k == 0,
            "crest": lambda h, k: 90 <= h <= 127 and k == 0,
            "dip": lambda h, k: -128 <= h <= -86 and k == 0,
            "curve": lambda h, k: k == 7}
    taken = {}
    last, held = None, 0
    for _ in range(50 * 180):
        g.c.run_frames(1)
        h = g.byte("HILL")
        h = h - 256 if h > 127 else h
        k = g.byte("ROAD_CURVE")
        k = k - 256 if k > 127 else k
        held = held + 1 if k == last else 0
        last = k
        if held < 8:
            continue
        for name, test in want.items():
            if name in taken or not test(h, k):
                continue
            path = os.path.join(docs, "screen-%s.png" % name)
            at_vsync(g)
            g.shot(path)
            taken[name] = h
            print("wrote %s (hill %d, curve %d)" % (path, h, k))
        if len(taken) == len(want):
            break


def _pens(data):
    from cpcgfx import m0_decode
    pens = []
    for b in data:
        pens += m0_decode(b)
    return pens


def hud_pens(g, buf):
    """Buffer `buf`'s HUD, lines 0..63: page 1, buffer 1's 768 bytes on."""
    return [_pens(g.c.read_ram(0x4000 + 768 * buf + (y & 7) * 0x800 + (y >> 3) * 96, 96))
            for y in range(64)]


def sky_pens(g):
    """The sky part as the CRTC shows it: its rows of the ring in page 3,
    from character ring_w0 (lines SKY_Y..BLOCK_BOTTOM-1)."""
    from cpcgfx import SKY_Y, BLOCK_BOTTOM
    w0 = g.word("RING_W0")
    out = []
    for i in range(BLOCK_BOTTOM - SKY_Y):
        r, ras = i >> 3, i & 7
        data = []
        for j in range(48):
            w = (w0 + 48 * r + j) & 1023
            data += g.c.read_ram(0xC000 + ras * 0x800 + 2 * w, 2)
        out.append(_pens(data))
    return out


def road_pens(g, buf, y0=160, y1=272):
    """Buffer `buf`'s road part, lines y0..y1-1 (160 and on)."""
    return [_pens(g.c.read_ram((0x8000 if buf == 0 else 0x0000) + (y & 7) * 0x800
                               + ((y >> 3) - 20) * 96, 96))
            for y in range(y0, y1)]


def _signed(v):
    return v - 256 if v > 127 else v


def road_model(g):
    """What scene.py says the road part should be for the engine's inputs
    now: lines ROAD_AREA_Y..271, the road, the bushes and the car."""
    import scene
    zcam = g.word("ZCAM")
    hill = _signed(g.byte("HILL"))
    hill = min(scene.level_hill(scene.hill_level(hill)), g.sym["HILL_MAX"])
    curve = _signed(g.byte("ROAD_CURVE"))
    x = _signed(g.byte("ROAD_X"))
    view = g.game_byte("CAR_VFULL")
    off = _signed(g.game_byte("CAR_OFF"))
    return (scene.road_area(hill, zcam, curve, x=x, view=view, car_off=off),
            hill, zcam, curve, x)


def road_partial(g):
    """At PICTURE_DONE: whether the picture was drawn with the cache (the
    road off the middle) while it was still catching up with the curve
    level - some groups of rows a level behind, as road_project allows for,
    but not as the model draws it. (road_x moves the whole cache at once.)"""
    return g.byte("RP_CACHE") and g.byte("RD_N2")


# Where line 0 of the picture is in the emulator's framebuffer (1024 x 312,
# a hardware colour per byte, four bytes to a mode 0 pixel). Its monitor
# shows 272 lines from 5 above ours, so the last 5 are off its screen.
FB_X0, FB_Y0 = 0, 5
FB_LINES = 272 - FB_Y0


def on_screen(g):
    """The picture the emulator last showed: FB_LINES lines of 192 hardware
    colours."""
    fb = g.c.framebuffer()
    return [[fb[(FB_Y0 + y) * 1024 + FB_X0 + 4 * x] for x in range(192)]
            for y in range(FB_LINES)]


def at_vsync(g):
    """Run to the interrupt inside VSYNC, before it starts the next frame:
    the framebuffer then holds a whole frame, and rup_base and rup_drop say
    how it was split."""
    run_to(g.c, g.sym["IRQ_VSYNC"])


def cmd_check():
    import scene
    from cpcgfx import SCR_H, pen_hw
    g = Game()
    frames, vbls, late = fps(g, 10)
    print("%d pictures in %d VSYNCs: %.2f pictures/s, %d late"
          % (frames, vbls, 50.0 * frames / max(vbls, 1), late))
    # Every line of a freshly drawn buffer's road part against the Python
    # model, the bushes on it - including the lines road_project decided had
    # not changed.
    # A picture drawn while the cache was catching up is passed over for
    # the next one.
    bad = 0
    seen = set()
    curves = set()
    xs = set()
    partial = 0
    y0 = scene.ROAD_AREA_Y
    for n in range(240):
        run_to(g.c, g.sym["PICTURE_DONE"])
        while road_partial(g):
            partial += 1
            run_to(g.c, g.sym["PICTURE_DONE"])
        buf = g.byte("ROAD_BUF")
        want, hill, zcam, curve, x = road_model(g)
        got = road_pens(g, buf, y0, SCR_H)
        wrong = [y0 + i for i in range(len(want))
                 if y0 + i >= scene.ROAD_SHOWN_Y and want[i] != got[i]]
        seen.add(hill)
        curves.add(curve)
        xs.add(x)
        if wrong:
            bad += 1
            if bad <= 5:
                print("picture %d (buffer %d, hill %d, zcam %d, curve %d, x %d): %d "
                      "lines differ, first %d" % (n, buf, hill, zcam, curve, x,
                                                  len(wrong), wrong[0]))
        for _ in range(37):              # skip ahead to vary hill and zcam
            run_to(g.c, g.sym["PICTURE_DONE"])
    print("road check: %d of 240 pictures differ from scene.py (%d passed over, "
          "the cache catching up); hills seen %s; curve levels seen %s; road_x "
          "from %d to %d" % (bad, partial, sorted(seen), sorted(curves), min(xs),
                             max(xs)))

    # The HUD, sky and mountains of a freshly drawn buffer.
    from cpcgfx import HUD_H, SKY_Y
    hud_bad = 0
    worst_lag = 0
    for n in range(20):
        for _ in range(23):
            run_to(g.c, g.sym["RENDER_END"])
        buf = g.byte("ROAD_BUF")
        # what this buffer's HUD says it shows: hud_update defers all but
        # one change a picture, so it may be a picture behind the game
        gear = g.game_byte("SHOWN_GEAR", buf)
        tt = [g.game_byte("SHOWN_TOTAL", 5 * buf + i) for i in range(5)]
        vals = dict(time_left=g.game_byte("SHOWN_TIME_HI", buf) * 10
                    + g.game_byte("SHOWN_TIME", buf),
                    speed_level=g.game_byte("SHOWN_SPEED", buf),
                    gear="N" if gear == 0 else str(gear),
                    total_centis=tt[0] * 6000 + (tt[1] * 10 + tt[2]) * 100
                    + tt[3] * 10 + tt[4],
                    fuel=g.game_byte("SHOWN_FUEL", buf))
        lag = abs(vals["speed_level"] - g.game_byte("SPEED_LEVEL"))
        worst_lag = max(worst_lag, lag)
        want = scene.hud(**vals)
        got = hud_pens(g, buf)
        wrong = [y for y in range(64) if want[y] != got[y]]
        sky_want = scene.sky_lines(g.byte("RING_HEAD"))
        wrong += [SKY_Y + i for i, row in enumerate(sky_pens(g)) if row != sky_want[i]]
        if wrong:
            hud_bad += 1
            if hud_bad <= 3:
                print("picture %d (buffer %d, %s): lines %s differ"
                      % (n, buf, vals, wrong[:8]))
    print("HUD and sky check: %d of 20 pictures differ from scene.py "
          "(speed gauge at most %d segments behind)" % (hud_bad, worst_lag))
    if worst_lag > 2:                   # the HUD keeps up, a picture or two late
        hud_bad += 1

    # What the CRTC made of the buffer on screen: the split frame, with the
    # horizon as far down as the buffer's road asked for - the same whatever
    # the CRTC does in the R5 lines (tools/emu/crtc_patch.py), 100 frames
    # with each of the three behaviours, a few frames apart so they spread
    # over a lap of the demo track.
    import cpc
    scr_bad = 0
    drops = set()
    heads = set()
    for n in range(300):
        if n % 100 == 0:
            cpc._lib.cpcemu_set_adj_mode(g.c._h, n // 100)
        at_vsync(g)
        buf = g.byte("RUP_BUF")
        drop = g.byte("RUP_DROP")
        drops.add(drop)
        heads.add(g.byte("RING_HEAD"))
        want = [[pen_hw(p) for p in row]
                for row in scene.shown(hud_pens(g, buf), sky_pens(g),
                                       road_pens(g, buf), drop)]
        got = on_screen(g)
        wrong = [y for y in range(FB_LINES) if want[y] != got[y]]
        if wrong:
            scr_bad += 1
            if scr_bad <= 3:
                print("frame %d (R5 model %d, buffer %d, drop %d): lines %s "
                      "differ" % (n, n // 100, buf, drop, wrong[:8]))
        g.c.run_frames(1 + n * 7 % 9)
    print("screen check: %d of 300 frames (3 R5 models) differ from the parts "
          "split as scene.py says; drops seen %s; %d headings"
          % (scr_bad, sorted(drops), len(heads)))
    return 1 if bad or hud_bad or scr_bad else 0


def cmd_watch(n):
    g = Game()
    for i in range(n):
        g.c.run_frames(50)
        path = os.path.join(ROOT, "build", "watch-%02d.png" % i)
        g.shot(path)
        print(path, "hill", g.byte("HILL"), "speed", g.word("SPEED"),
              "drawn", g.word("FRAMES_DRAWN"), "late", g.word("FRAMES_LATE"))


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if what == "shots":
        cmd_shots()
    elif what == "check":
        sys.exit(cmd_check())
    else:
        cmd_watch(int(sys.argv[2]) if len(sys.argv) > 2 else 5)
