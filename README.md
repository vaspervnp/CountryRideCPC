# Country Ride

A racing game for the Amstrad CPC 6128, written in Z80 assembly.

![The road on the flat](docs/screen-flat.png)

This is the first milestone: the screen layout and the road engine. There is
no car or player input yet. A demo drive runs a four-lane road over a looping
run of crests and dips at 25 frames a second, and fills the HUD with
plausible numbers.

| Crest ahead | In a dip |
|---|---|
| ![Behind a crest](docs/screen-crest.png) | ![In a dip](docs/screen-dip.png) |

## Building

You need:

- [rasm](https://github.com/EdouardBERGE/rasm), the assembler;
- [iDSK](https://github.com/cpcsdk/idsk), to put the BASIC loader on the disc;
- `python3`, but only to regenerate the sources in `src/gen/` (which are
  committed), and Pillow for the pictures.

Then run:

```bash
make
```

This writes `build/countryride.dsk`.

## Running

Insert `build/countryride.dsk` in a CPC 6128, or any emulator of one, and type:

```
RUN"COUNTRY
```

The game needs the 6128's second 64K: it uses banks 4 to 7. So far it has
only been tested in an emulator (see [Testing](#testing)). The split screen
(raster ruptures, below) follows CRTC types 0 and 1; it has not been tried on
real hardware yet.

## Make targets

| Target | What it does |
|---|---|
| `make` | builds `build/countryride.dsk` |
| `make gen` | regenerates `src/gen/*.asm` from `tools/` and `assets/` |
| `make check` | boots the disc in an emulator, measures the frame rate, and compares the screen with the Python model |
| `make shots` | boots the disc and writes the screenshots in `docs/` |
| `make mockup` | writes `build/mockup.png`, the screen as worked out in Python |
| `make clean` | empties `build/` |

## The screen

The screen uses overscan in mode 0: 192 × 272 pixels (96 bytes a line), 16 colours.
On the flat it is:

| Lines | Share | What |
|---|---|---|
| 0–63 | ~1/4 | HUD on navy: TIME, SPEED gauge with the gear (N–6), TOTAL TIME, FUEL gauge |
| 64–151 | ~1/3 | dithered sky fading into the HUD colour, snowy mountains |
| 152–162 | | a band of ground |
| 163–271 | 2/5 … 1/3 | the road: 109 lines on the flat, 91 behind a crest |

The road's top rises and falls between 2/5 and 1/3 of the screen, and the
horizon goes with it. When a crest hides the far road, the sky and the
mountains move down as far as the road's top does, and the lines above them
fill with the HUD's navy. The band of ground between the mountains and the
road keeps its 11 lines.

The road has four lanes, each a little wider than the future 45-pixel car. It
has thick red and white kerbs. The grass and the asphalt alternate in
stripes of close colours. Kerbs and lane dashes move all the way to the
horizon: past the striped zone their dashes get longer with distance, so
they don't flicker. The road never narrows to a point: far away it is still
10 pixels wide, kerb to kerb.

## How it works

### Frames

There are two screen buffers. The game draws into the one not on screen. The
interrupt handler (IM 2) shows the new buffer at a VSYNC at least two frames
after the last flip, which gives a steady 25 Hz. The game logic steps at
50 Hz. If a picture is late, it catches up by up to four steps.

### The split screen

Moving the sky and the mountains would mean redrawing 46 lines of dithered
sky and 46 of mountains each time, ~19 ms. The CRTC does it instead.

Each buffer always holds the same picture, as in the table above. The
interrupt handler reprograms the CRTC three times a frame (raster ruptures),
so every frame is three CRTC frames with their own start address:

- the HUD part: rows 0–7, then *d* lines of border in navy (R5);
- the sky part: rows 8–18 (sky and mountains), then 8*q* − *d* lines of
  border in the ground's green, where *q* = *d*/8 rounded up;
- the road part: from row 19 + *q*, with the VSYNC at line 272 as always.

For a drop of *d* lines, the sky and the mountains show *d* lines lower. The
R5 lines bring the road part back onto a character row, so the road lines are
where they always are in the buffer, and the road renderer knows nothing
about it.

The Gate Array interrupts at fixed lines: 2 after the VSYNC, then every 52.
Each interrupt writes the registers for the parts to come, with ten lines or
more to spare. If the frame is ever out of step, the handler falls back to a
plain full frame until the next VSYNC.

### Memory

The CRTC always reads the base 64K. Each buffer is 32K, split between two
16K pages so that its top half can be reached at `#4000` through a RAM
configuration:

| Buffer | Top half (lines 0–159) | Bottom half |
|---|---|---|
| 0 | page 1 | page 2 |
| 1 | page 3 | wraps into page 0 |

The banks hold the rest:

| Bank | Contents | Seen at |
|---|---|---|
| 4 | road code for stripe band A | `#4000` (C4) |
| 5 | road code for stripe band B | `#4000` (C5) |
| 6 | the road's row tables and the precomputed hill tables | `#4000` (C6) |
| 7 | the game (main loop, HUD, graphics) | `#C000` (C1/C3) |

Some code and data must be reachable from every RAM configuration: the
variables they share, the interrupt handler, the stack, the line lists and
the part of the renderer that switches banks. These live in 704-byte
fragments at `#x540–#x7FF` of pages 0 and 2, which no buffer covers.
`src/hw.asm` has the whole map.

### The road

The road is made of 109 rows. Each row has a depth, and its stripe band is a
bit of (depth + camera position). For every row width, band and pixel parity,
`tools/mkroad.py` generates straight-line code that draws the row with
`PUSH` instructions:

- the asphalt and the kerbs come from registers;
- everything else comes from `LD BC,nn / PUSH BC`;
- the grass is shared blocks of 48 pushes, entered part-way.

Each frame:

1. `road_project` writes, for every road line, an 8-byte template into a
   line list.
2. `road_draw` walks the list with the stack pointer, jumping into the
   generated code for each line.
3. Lines that cannot have changed are skipped: the ground behind a crest,
   and far lines whose dash has not moved.

Hills move row *r* down (on a crest) or up (in a dip) by *h / r* lines, with
occlusion behind a crest. The line-to-row mapping is precomputed for 128 hill
levels, so a hill costs nothing extra per frame.

### The HUD

The HUD shows a copy of the game's values, taken every 4 pictures (6.25 times
a second). The gauges have 8 segments. Each buffer remembers what it shows. Only what changed is
redrawn, at most one big item a picture. Text and gauges sit on the HUD's
plain background, so drawing is plain copying, never masking.

### Timing

Measured in the emulator at full demo speed, a picture takes about 34.5 ms of
its 40 ms budget (38.4 ms at worst):

- road drawing: ~27.7 ms;
- road projection: ~5 ms;
- HUD: ~1 ms on average, 3.5 ms at most;
- the horizon: nothing (the ruptures cost a few register writes per
  interrupt).

Not one picture was late in two minutes of driving.

## Testing

`tools/run.py` drives a headless CPC 6128 emulator based on
[floooh/chips](https://github.com/floooh/chips), with the real ROMs. It boots
BASIC and types `RUN"COUNTRY`, the way a person would.

`make check` then:

- measures the frame rate;
- compares 240 freshly drawn road pictures, line by line, with what
  `tools/scene.py` (the Python reference model) says they should be;
- does the same for 20 pictures of the HUD and horizon;
- compares 300 frames of what the emulator actually displayed with the
  buffer on screen, split the way the model says for that frame's drop.

The emulator harness expects the headless emulator in
`~/repos/CPCTools/cpcemu`. `tools/emu/build.sh` builds a debug library from
it into `build/libcpcdebug.so`, with register access and run-to-address. Set
`CPCEMU` to point the build script elsewhere.

The library is built with a patched copy of chips' CRTC
(`tools/emu/crtc_patch.py`; the original is not touched). Stock chips makes
R5 lengthen the last row, and ends a frame on VCC ≥ R4, which would hide a
late register write. The patched copy follows a real CRTC: the R5 lines come
after the last row, and a frame ends only on VCC = R4 at the end of a row.

## Layout

```
src/            the game
  main.asm      the build: banks, files on the disc
  hw.asm        ports, CRTC values, memory map
  boot.asm      takes the machine over, copies the common fragments
  common.asm    the fragments: variables, interrupts and ruptures, road_draw
  road.asm      road_init, road_project
  game.asm      main loop, demo drive
  hud.asm       HUD updates
  horizon.asm   how far the horizon drops
  screen.asm    buffers, blitting, the static picture
  gen/          generated by tools/ (committed)
tools/
  cpcgfx.py     palette, mode 0 encoding, road geometry
  scene.py      the reference model of the whole screen
  mkgfx.py      HUD, sky and mountain graphics -> src/gen/
  mkroad.py     the generated road code and tables -> src/gen/
  run.py        emulator harness: check, shots, watch
  emu/          the emulator debug library and the CRTC patch
assets/         fonts
disc/           BASIC loader
docs/           screenshots
```

## Next

- the car, always at the bottom centre;
- curves, with the mountains scrolling sideways (the sky part's start
  address can do that too);
- 3- and 2-lane roads (the generator already has the `LANES` parameter).
