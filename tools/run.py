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
    def __init__(self):
        CPC = load_emulator().CPC
        self.sym = symbols()
        self.c = CPC()
        self.c.run_frames(150)                  # to the BASIC prompt
        self.c.insert_disc(DSK)
        self.c.type_text('RUN"COUNTRY\n')
        # load, then wait for the first pictures
        for _ in range(1500):
            self.c.run_frames(1)
            if self.word("FRAMES_DRAWN") >= 2:
                break
        else:
            raise SystemExit("the game never drew a picture (PC #%04X)"
                             % self.c.pc)

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

    def shot(self, path):
        self.c.screenshot(path, aspect=True)

    def screen_pens(self):
        """The displayed buffer decoded to pens, through the CRTC layout."""
        from cpcgfx import m0_decode
        front = self.byte("FRONT_BUF")
        rows = []
        for y in range(272):
            row, ras = y >> 3, y & 7
            if row < 20:
                base = 0x4000 if front == 0 else 0xC000
                a = base + 0x80 + ras * 0x800 + row * 96
            else:
                base = 0x8000 if front == 0 else 0x0000
                a = base + ras * 0x800 + (row - 20) * 96
            data = self.c.read_ram(a, 96)
            pens = []
            for b in data:
                pens += m0_decode(b)
            rows.append(pens)
        return rows


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
    """Screenshots of the three road shapes, taken at a VSYNC so the picture
    is whole: flat, behind the top of a crest (road down to 1/3 of the
    screen, ground showing) and in a dip (road up to 2/5)."""
    g = Game()
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    want = {"flat": lambda h: h == 0, "crest": lambda h: 90 <= h <= 127,
            "dip": lambda h: 0x80 <= h <= 0xAA}
    taken = {}
    for _ in range(50 * 120):
        g.c.run_frames(1)
        h = g.byte("HILL")
        speed = g.c.read_ram(g.sym["SPEED"], 2)      # bank 7 is not base RAM:
        for k, test in want.items():                 # read the gear instead
            if k in taken or not test(h):
                continue
            path = os.path.join(docs, "screen-%s.png" % k)
            g.shot(path)
            taken[k] = h
            print("wrote %s (hill %d)" % (path, h if h < 128 else h - 256))
        if len(taken) == len(want):
            break


def buffer_pens(g, buf, y0, y1):
    """Lines y0..y1-1 of buffer `buf`, decoded to pens."""
    from cpcgfx import m0_decode
    rows = []
    for y in range(y0, y1):
        row, ras = y >> 3, y & 7
        if row < 20:
            a = (0x4000 if buf == 0 else 0xC000) + 0x80 + ras * 0x800 + row * 96
        else:
            a = (0x8000 if buf == 0 else 0x0000) + ras * 0x800 + (row - 20) * 96
        pens = []
        for b in g.c.read_ram(a, 96):
            pens += m0_decode(b)
        rows.append(pens)
    return rows


def road_model(g):
    """What scene.py says the road should be for the engine's inputs now."""
    import scene
    zcam = g.word("ZCAM")
    hill = g.byte("HILL")
    hill = hill - 256 if hill > 127 else hill
    hill = min(scene.level_hill(scene.hill_level(hill)), g.sym["HILL_MAX"])
    return scene.road_lines(hill, zcam), hill, zcam


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
    while True:
        run_to(g.c, g.sym["ISR"])
        if g.byte("IRQ_PHASE") == 5:
            return


def cmd_check():
    import scene
    from cpcgfx import ROAD_Y, SCR_H, pen_hw
    g = Game()
    frames, vbls, late = fps(g, 10)
    print("%d pictures in %d VSYNCs: %.2f pictures/s, %d late"
          % (frames, vbls, 50.0 * frames / max(vbls, 1), late))
    # Every road line of a freshly drawn buffer against the Python model -
    # including the lines road_project decided had not changed.
    bad = 0
    seen = set()
    for n in range(240):
        run_to(g.c, g.sym["RENDER_END"])
        buf = g.byte("ROAD_BUF")
        want, hill, zcam = road_model(g)
        got = buffer_pens(g, buf, ROAD_Y, SCR_H)
        wrong = [ROAD_Y + i for i in range(len(want)) if want[i] != got[i]]
        seen.add(hill)
        if wrong:
            bad += 1
            if bad <= 5:
                print("picture %d (buffer %d, hill %d, zcam %d): %d lines differ, "
                      "first %d" % (n, buf, hill, zcam, len(wrong), wrong[0]))
        for _ in range(37):              # skip ahead to vary hill and zcam
            run_to(g.c, g.sym["RENDER_END"])
    print("road check: %d of 240 pictures differ from scene.py; hills seen %s"
          % (bad, sorted(seen)))

    # The HUD, sky and mountains of a freshly drawn buffer.
    from cpcgfx import HUD_H
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
        want = scene.memory(**vals)[:ROAD_Y]
        got = buffer_pens(g, buf, 0, ROAD_Y)
        wrong = [y for y in range(ROAD_Y) if want[y] != got[y]]
        if wrong:
            hud_bad += 1
            if hud_bad <= 3:
                print("picture %d (buffer %d, %s): lines %s differ"
                      % (n, buf, vals, wrong[:8]))
    print("HUD and horizon check: %d of 20 pictures differ from scene.py "
          "(speed gauge at most %d segments behind)" % (hud_bad, worst_lag))

    # What the CRTC made of the buffer on screen: the split frame, with the
    # horizon as far down as the buffer's road asked for.
    scr_bad = 0
    drops = set()
    for n in range(300):
        at_vsync(g)
        buf = 0 if g.byte("RUP_BASE") == g.sym["BUF0_R12"] else 1
        drop = g.byte("RUP_DROP")
        drops.add(drop)
        want = [[pen_hw(p) for p in row]
                for row in scene.shown(buffer_pens(g, buf, 0, SCR_H), drop)]
        got = on_screen(g)
        wrong = [y for y in range(FB_LINES) if want[y] != got[y]]
        if wrong:
            scr_bad += 1
            if scr_bad <= 3:
                print("frame %d (buffer %d, drop %d): lines %s differ"
                      % (n, buf, drop, wrong[:8]))
        g.c.run_frames(1)
    print("screen check: %d of 300 frames differ from the buffer split as "
          "scene.py says; drops seen %s" % (scr_bad, sorted(drops)))
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
