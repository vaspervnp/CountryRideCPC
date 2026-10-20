# Country Ride

A racing game for the Amstrad CPC 6128, written in Z80 assembly.

![The road on the flat](docs/screen-flat.png)

This is the first milestone: the screen layout and the road engine. There is
no car or player input yet. A demo drive runs a four-lane road over a looping
run of crests, dips and curves at 25 frames a second, and fills the HUD with
plausible numbers.

| Crest ahead, bending right | In a dip, bending left | The sharpest curve |
|---|---|---|
| ![Behind a crest](docs/screen-crest.png) | ![In a dip](docs/screen-dip.png) | ![A sharp right](docs/screen-curve.png) |

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
been tested in emulators: the harness below, and Retro Virtual Machine. The
split screen (raster ruptures, below) is built not to depend on what the CRTC
types do differently; it has not been tried on real hardware yet.

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

The road bends left and right, from nothing at the bottom, where the car
will be, to the most at the horizon; in the sharpest curves the far road
leaves the screen. The sky and the mountains turn sideways as the road
bends, by hardware scrolling.

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

The picture is three parts, each in its own memory:

| Part | Lines on the flat | Memory |
|---|---|---|
| HUD | 0–63 | page 1, one copy per buffer |
| sky and mountains | 64–151 | page 3, one copy for both buffers, in a ring |
| road | 160–271 (152–159 are border) | page 2 (buffer 0) or page 0 (buffer 1) |

The interrupt handler reprograms the CRTC three times a frame (raster
ruptures), so every frame is three CRTC frames with their own start address,
row count and R5 lines.

- **Horizon drop.** For a drop of *d* lines, the HUD part ends in navy
  border: its last row (navy anyway), *d*/8 more rows, all hidden by R6, then
  *d* mod 8 R5 lines. So the sky starts *d* lines lower.
- **Road start.** The road part starts at the character row the road's top
  is in. Between the two parts is green border (a row if needed, then R5
  lines), so the road lines are always where they are in memory, and the
  road renderer knows nothing about any of it.
- **R5 lines.** CRTCs differ in them: some make them border after the last
  row, others keep showing the next row (Retro Virtual Machine did, as dashes
  under the HUD and a black bar under the mountains). So they are fewer than
  8, the HUD part's come after a border row, and the ring row after the sky
  part's last is kept green, the colour of the border there.
- **When registers are written.** A part's start address is set in the part
  before it, never in a part's first row (type 1 rereads it on every line
  there); a part's size is set while it, or the R5 lines just before it, are
  on screen; R6 only well before or after the row it names.
- **Sky ring.** With MA10/MA11 at 0, the CRTC's address wraps every 1024
  characters (2K). The sky part is 11 rows of 48 characters in that ring.
  Moving its start address one character scrolls it a word (4 pixels)
  sideways for good; only the column that comes in has to be written, from
  the panorama (384 pixels, stored by columns in bank 7). That takes
  ~1.4 ms, done at the flip, before the sky part is on screen, so it never
  tears. The dithered sky repeats every word, so only the mountains seem to
  move.
- **Timing.** The Gate Array interrupts come at fixed lines (~274, 14, 66,
  118, 170, 222), and each handler sets up the next one's, so none has to
  work out where the frame is. Each register is written with more than five
  lines to spare. The VSYNC's handler checks that it is in VSYNC; if a frame
  is ever out of step, the handler falls back to a plain frame until the
  next VSYNC.

### Memory

The CRTC always reads the base 64K:

| Page | Holds |
|---|---|
| 0 | buffer 1's road part, common fragments |
| 1 | both HUDs (`#4000` with RAM C1), 4K free |
| 2 | buffer 0's road part, common fragments |
| 3 | the sky ring (`#4000` with RAM C3) |

The banks hold the rest:

| Bank | Contents | Seen at |
|---|---|---|
| 4 | road templates (`#4000–#5FFF`) and code (`#6000`) for stripe band A | `#4000` (C4) |
| 5 | road code (`#4000`) and templates (`#6000–#7FFF`) for stripe band B | `#4000` (C5) |
| 6 | the road's row tables and the precomputed hill tables | `#4000` (C6) |
| 7 | the game (main loop, HUD, graphics, the panorama) | `#C000` (C1/C3) |

Some code and data must be reachable from every RAM configuration: the
variables they share, the interrupt handler, the stack, the line lists and
the part of the renderer that switches banks. These live in 704-byte
fragments at `#x540–#x7FF` of pages 0 and 2, beside the road parts; nine
are used, seven are free. `src/hw.asm` has the whole map.

### The road

The road is made of 109 rows. Each row has a depth, and its stripe band is a
bit of (depth + camera position). For every row width, band and pixel parity,
`tools/mkroad.py` generates straight-line code that draws the row with
`PUSH` instructions:

- the asphalt and the kerbs come from registers;
- everything else comes from `LD BC,nn / PUSH BC`;
- the grass is shared blocks of 48 pushes, entered part-way.

A *template* says how to draw a row: where to enter the code, how much grass
goes on each side, and how to cut the code short where it leaves the screen.

Each frame:

1. `road_project` writes, for every road line, a pointer to a template into
   a line list.
2. `road_draw` walks the list with the stack pointer, jumping into the
   generated code for each line.
3. Lines that cannot have changed are skipped: the ground behind a crest,
   and far lines whose dash has not moved - told from the bit of
   (depth + camera) the dash is, now and when the buffer was last drawn. The
   list ends after the last line that changed.

Hills move row *r* down (on a crest) or up (in a dip) by *h / r* lines, with
occlusion behind a crest. The line-to-row mapping is precomputed for 128 hill
levels, so a hill costs nothing extra per frame.

### Curves

A curve has a level from −7 (sharp left) to +7 (sharp right). At level *k*,
row *r* moves sideways by *k*/7 × 64 × ((109 − *r*)/108)² bytes: a parabola,
nothing at the bottom and 128 pixels at the horizon at the sharpest. Moving
a row only changes its template: the grass on each side, where the code is
entered or cut short, and, for an odd number of bytes, the code for the
other pixel parity.

So `tools/mkroad.py` makes the templates for every level, a 512-byte set per
level (15 levels, 7.5K a band). They sit in the banks next to the code they
point at, band A's in bank 4 and band B's at the same offsets in bank 5;
`road_draw` tells which bank a template is in from bit 13 of its address and
switches before reading it. `road_project` only adds the level's set to each
pointer, so a curve costs nothing per line.

Far away, a row moves a lot from row to row, so the 7 furthest rows have a
template each; nearer, the rows of one width share one.

When the level changes, every far line moves and is drawn again (~2.5 ms).
That picture leaves its HUD changes and the sky's turn to the next one, and
a picture that starts with the sky turning keeps its buffer's level for one
more picture, so the two never fall on the same picture.

### The HUD

The HUD shows a copy of the game's values, taken every 4 pictures (6.25 times
a second). The gauges have 8 segments. Each buffer remembers what it shows.
Only what changed is redrawn, within a share of about 1.1 ms a picture (a
third of that after a flip that turned the sky); the rest waits for the
buffer's next picture. Text and gauges sit on the HUD's
plain background, so drawing is plain copying, never masking.

### Timing

Measured in the emulator through the demo's crests, dips and curves, from
the flip that starts a picture to the picture being done, a picture takes
about 33.1 ms of its 40 ms (37.3 ms at worst):

- road drawing: ~26.6 ms (~29.6 ms when the curve level changes);
- road projection: ~4.6 ms;
- HUD: ~1 ms, within its share (less after a sky turn);
- game logic: ~0.6 ms;
- interrupts: ~1.4 ms, the raster ruptures and the sky's turns (1.4 ms a
  turn, at the flip).

Not one picture was late in two minutes of driving.

## Testing

`tools/run.py` drives a headless CPC 6128 emulator based on
[floooh/chips](https://github.com/floooh/chips), with the real ROMs. It boots
BASIC and types `RUN"COUNTRY`, the way a person would.

`make check` then:

- measures the frame rate;
- compares 240 freshly drawn road pictures, line by line, with what
  `tools/scene.py` (the Python reference model) says they should be, over
  hills and curve levels;
- does the same for 20 pictures of the HUD and horizon;
- compares 300 frames of what the emulator actually displayed with the
  buffer on screen, split the way the model says for that frame's drop: 100
  with each of the CRTC behaviours below.

The emulator harness expects the headless emulator in
`~/repos/CPCTools/cpcemu`. `tools/emu/build.sh` builds a debug library from
it into `build/libcpcdebug.so`, with register access and run-to-address. Set
`CPCEMU` to point the build script elsewhere.

The library is built with a patched copy of chips' CRTC
(`tools/emu/crtc_patch.py`; the original is not touched). Stock chips makes
R5 lengthen the last row, and ends a frame on VCC ≥ R4, which would hide a
late register write. The patched copy follows a real CRTC: the R5 lines come
after the last row, and a frame ends only on VCC = R4 at the end of a row.
What a CRTC does in the R5 lines can be switched between three behaviours:
border when the row counter, one past R4, equals R6 (type 0); rows go on
counting; the display stays as the last row left it and shows the next row
(type 1, and Retro Virtual Machine). The picture must be the same with all
three.

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
  horizon.asm   how far the horizon drops, the sky ring
  screen.asm    buffers, blitting, the static picture
  gen/          generated by tools/ (committed)
tools/
  cpcgfx.py     palette, mode 0 encoding, road geometry
  scene.py      the reference model of the whole screen
  mkgfx.py      HUD, sky and mountain graphics -> src/gen/
  mkroad.py     the generated road code, templates and tables -> src/gen/
  run.py        emulator harness: check, shots, watch
  emu/          the emulator debug library and the CRTC patch
assets/         fonts
disc/           BASIC loader
docs/           screenshots
```

## Next

- the car, always at the bottom centre;
- curves that come from the horizon (the whole road bends at one level now);
- 3- and 2-lane roads (the generator already has the `LANES` parameter).
