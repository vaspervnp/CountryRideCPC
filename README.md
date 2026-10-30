# Country Ride

A racing game for the Amstrad CPC 6128, written in Z80 assembly.

![The road on the flat](docs/screen-flat.png)

A four-lane road runs over crests, dips and curves - never a curve on a
hill - with bushes of different sizes beside it at random intervals, now
and then a palm, a dead tree or a road sign, and cars on it, at 25 frames
a second. A demo drives a loop of it until you
press fire; then you race the clock over five stages, each in its own
colours (The race, below), to music, the engine's note rising with the
speed. You steer: the
road moves under the car, and a curve carries the car out of it unless
you steer against it.

| Crest ahead | In a dip | The sharpest curve |
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

Pick a car (below). The demo drives until you press fire (or space,
cursor up, Q, joystick up). Then steer with the cursor keys, O and P, or a
joystick: left and right.
Faster: cursor up, Q, space, joystick up or fire; slower: cursor down, A,
joystick down. With neither held the car slows down a little; with a
wheel on the grass (the road 20 pairs or more to one side) it goes no
faster than half its top speed. ESC pauses the race, and goes on with it.

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
| 0–63 | ~1/4 | HUD on navy: TIME, SPEED gauge with the gear (N–6), TOTAL TIME, CHECKPOINT gauge; a line of messages |
| 64–135 | ~1/4 | navy, the HUD's colour |
| 136–179 | ~1/6 | dithered sky fading into the navy, snowy mountains up to 28 lines high |
| 180–187 | | a band of ground |
| 188–267 | 3/10 … 1/4 | the road: 80 lines on the flat, 66 behind a crest |
| 268–271 | | black: a monitor's edge hides these, and drawing them took ~0.7 ms a picture |

The sky, the mountains and the road take the screen's bottom half. (Until
2026-10-26 the horizon was higher: the sky from line 64, the mountains up to
44 lines, the road from line 163 - 105 lines. Lowering it made every picture
~4.5 ms cheaper.) The road's top rises and falls between 3/10 and 1/4 of
the screen, and the horizon goes with it. When a crest hides the far road,
the sky and the mountains move down, twice as fast as the road's top at
first, and the lines above them fill with the HUD's navy. The band of
ground between the mountains and the road - what the crest does not hide of
the far side - goes from 8 lines on the flat to 3-7 behind a crest. It cannot go to none: the
road part has to start at a character row, so the mountains can come no
nearer to the road's top than the row it is in (*Horizon drop* below), and
they move at most 2 lines a step, never in jumps.

The road bends left and right, from nothing at the bottom, where the car
is, to the most at the horizon; in the sharpest curves the far road
leaves the screen. The sky and the mountains turn sideways as the road
bends, by hardware scrolling.

The road has four lanes, each a little wider than the car. It
has thick red and white kerbs. The asphalt is plain grey and the grass plain
green: the stripes are in the kerbs and the lane dashes, which move all the
way to the horizon; past the striped zone their dashes get longer with
distance, so they don't flicker. The road never narrows to a point: far away
it is still 10 pixels wide, kerb to kerb.

Bushes stand on the grass on either side, at random intervals, in three
sizes and at different distances from the road. They grow as they come
nearer, from 5 to 16 lines, and leave by the sides of the screen.

Up to two cars of traffic drive ahead in the lanes, slower than the player,
who catches up with them and drives by - or bumps into them. Each
has a closed or an open top - a coupé's cabin, or a windscreen with a driver
behind it - on a sports car's, a saloon's or a GT's tail, and a colour for
its top and one for its tail, out of sixteen: hundreds of different cars.

### The race

Fire pressed while the demo drives, GET READY: the road ahead flattens
out and straightens, the car brakes to a standstill in the third lane from
the left, the count goes 3, 2, 1 in the gear's place, and GO! - the player
drives, from a standstill. TIME starts at 70 seconds and counts down; TOTAL
TIME counts up.

The course is five stages of 12288 depth units each (about 40-50 seconds),
each with its own track and colours - the sky near the horizon, the haze,
the far mountains, the grass and the bushes:

| Stage | Track | Colours |
|---|---|---|
| 1 COUNTRYSIDE | curves and hills by turns | green and lime |
| 2 DESERT | long straights, big crests, sharp curves | sand, dark red rock |
| 3 ALPS | hill after hill | snow and ice |
| 4 SUNSET | long sweeping curves | an orange and pink sky, dark grass |
| 5 NIGHT | winding | a dark sky, dark grass and navy |

| ![COUNTRYSIDE](docs/screen-stage1.png) | ![DESERT](docs/screen-stage2.png) | ![ALPS](docs/screen-stage3.png) |
|---|---|---|
| ![SUNSET](docs/screen-stage4.png) | ![NIGHT](docs/screen-stage5.png) | |

Beside the road, few and far between, stand each stage's trees - dead
trees in the countryside and the Alps; tall thin palms, short thick ones
and dead trees in the desert; both palms at sunset; tall palms at night -
and before every sharp curve its signs (Props, below).

The CHECKPOINT gauge fills on the way to each stage's end. There TIME gets
50 more seconds (EXTENDED TIME), 2 fewer at each next one, down to 36, and
never over 99; then the next stage's number shows, and its colours are
there at once. Past the fifth, FINISH: the car brakes to a standstill on
the straight that follows, and TOTAL TIME is the race's. At 0, TIME UP:
the car brakes to a standstill, still steered, GAME OVER. Either way the
demo then drives on from there, its loop and its colours back after the
road has flattened out. (`rules_vbl` in `src/game.asm`; the numbers are
its `START_TIME`, `EXT_FIRST`, `EXT_DROP`, `EXT_MIN`; the stages are
`tools/course.py`.) The autopilot used for testing - keeping to a lane,
out of the traffic's way, often bumping it - finishes with 41 seconds left
in the ROSSO GT, 30 in the BERLINETTA and 10 in the TOURING, and runs out
of time in the last stage in the WEDGE TURBO.

The messages - PRESS FIRE (blinking in the demo), GET READY, GO!, STAGE 1-5,
EXTENDED TIME, TIME UP, FINISH, GAME OVER, PAUSE - are the HUD's last line
(The HUD, below).

ESC holds the race - or the count before it, or the braking after it -
where it is: the picture stays, the sound stops, PAUSE shows; ESC again
and it goes on.

The five best times to the finish are kept as long as the machine is on:
in the demo the message line shows PRESS FIRE (5 seconds), then TOP TIMES
and each of the five - its place and its TOTAL TIME, 3'30"00 to 4'10"00
before any race has beaten them - 1.3 seconds each. A race that finishes
faster than one of them takes its place, the slower ones moving down; the
demo then starts with them, and its own blinks (`src/race.asm`).

The race has music - an original tune, 16 bars in C major, the lead and
the bass - and the car its engine, from GET READY to GAME OVER: a note
from 65 Hz standing still to ~190 Hz at the top speed, humming, with a
rumble on the grass. The count beeps, GO! and a checkpoint ring, a bump
and a crash have their noise, TIME UP and FINISH their own few notes. The
demo is silent (Sound, below).

### The cars

Before the race the player picks one of four sports cars, seen from the
side on the screen the loader shows while the game loads - the title
screen too, COUNTRY RIDE above the cars and the credits below them
(`tools/mkselect.py`):

![The title and the cars](docs/screen-select.png)

They are a red one with a
rear wing (ROSSO GT), a wide red one with a grille of black slats right
across its tail (BERLINETTA, after a Ferrari Testarossa), a low yellow
wedge with a louvred engine cover (WEDGE TURBO, after a Lotus Esprit) and a
white saloon with a wing on its boot and stripes in light blue, dark blue
and red (TOURING, after a BMW M3 of the eighties). 1-4 picks one and
starts; the arrow keys, O and P or the joystick move the flashing frame,
and fire, space or return start.

They drive differently - speed, acceleration and grip, shown as bars of
five (`scene.py` `CAR_LEVELS`; `car_setup` puts them into the code that
drives the car):

| | Speed | Acceleration | Grip |
|---|---|---|---|
| ROSSO GT | 5 | 4 | 3 |
| BERLINETTA | 5 | 5 | 2 |
| WEDGE TURBO | 4 | 3 | 5 |
| TOURING | 3 | 5 | 4 |

Speed 5 is the top speed of 6.6 depth units a VSYNC - the most the
pictures keep up with - 4 is 6.1, 3 is 5.7; on the grass, half. Acceleration
3 to 5 is 4 to 6 (1/256 depth units a VSYNC, every VSYNC): full speed in 8.4
to 5.6 seconds. Grip is how fast the car is steered across - a pair a
picture at the full lock, 1 1/3 with grip 4 or 5 - and how little a curve
carries it out of it: on a level 7 curve at its top speed 0.86, 0.72, 0.53
or 0.50 pairs a picture with grip 2, 3, 4 or 5 (Steering, below).

![Picking a car](docs/screen-select.png)

In the race the car is seen from behind, low down, 40 or 44 pixels wide
and up to 27 lines high, a little above the bottom of the screen. Steering,
it is seen turning, OutRun's way: turning left, it turns about its rear
axle, its nose going left, the left flank and the hubs of its tyres in
view.

The cars are photorealistic renders of 3D models (`tools/cars3d.py`, in
Blender with Cycles: paint under a clear coat, glass that mirrors the sky,
rubber, alloy rims, lenses lit from within, a sun behind and a sky). Their
bodies are curved: each is lofted along the car through rounded sections
(superellipses, from nearly square to round) whose width, height and
roundness follow smooth curves from the tail to the nose (`tools/car3d.py`
`Shape`, `loft`) - a rear face with rounded shoulders, hips over the rear
wheels and a waist at the doors, a bubble of a cabin with a painted roof,
sails, a nose rounded in plan and in profile - with the wheel arches cut
into them and fenders swelling over the wheels. They are brought
to mode 0 by `tools/dither.py`: each mode 0 pixel takes the mean colour of
the 128 render pixels under it, over the asphalt's grey, made more
saturated and its darks darker, and then the nearest pen - or, where two
neighbouring pens of a ramp (dark red, red, orange, yellow, white; black,
navy, blue, sky, pastel, white; the greys) mixed in a checkerboard come
clearly nearer, that checkerboard: CPC dithering, flat where the paint is
flat. The asphalt's grey only in a checkerboard, never alone: a grey pixel
would look like a hole. Each car has nine views - on the level, going
uphill and going downhill (pitched 8 degrees before the car is squashed as
low as the game draws it), each straight, turning left and turning right
(the left view mirrored) - and two for a crash: spun 30 degrees about its
middle, its tail swung out (rendered in a frame 80 pixels wide, moved 4
pixels left to keep its box near the others'), with dust at its rear
wheels (white at the clouds' hearts, thinning out under the car), and spun
the other way mirrored - in `tools/carsart.py` (`tools/mkcars.py`, which
also draws `build/cars-sheet.png`). In the race the car is seen uphill
where the road ahead climbs - the hill 20 or more into a dip - and
downhill where it falls away, over a crest (`car_lines`). The side views have the select screen's own sixteen pens (pink
for the red paint's highlights, pastel cyan for the white car's and the
glass's: `tools/mkselect.py`).

## How it works

### Frames

There are two screen buffers. The game draws into the one not on screen. The
interrupt handler (IM 1) shows the new buffer at a VSYNC at least two frames
after the last flip, which gives a steady 25 Hz. The game logic steps at
50 Hz. If a picture is late, it catches up by up to four steps.

### The split screen

The picture is three parts, each in its own memory:

| Part | Lines on the flat | Memory |
|---|---|---|
| HUD | 0–63, then navy border to 131 | page 1, one copy per buffer |
| sky and mountains | 132–179 (navy to 135) | page 3, one copy for both buffers, in a ring |
| road | 184–271 (180–183 are border) | page 2 (buffer 0) or page 0 (buffer 1), from line 160: 160–183 never shown |

The interrupt handler reprograms the CRTC three times a frame (raster
ruptures), so every frame is three CRTC frames with their own start address,
row count and R5 lines.

- **Horizon drop.** When the road's top is *d* lines down, the sky goes
  *s* lines down: twice *d*, but no further than the road part's first line
  less one, and at most 2 more than for *d* − 1 (`scene.sky_drop`, a table
  in the interrupt handler, with the 68 lines from the HUD to the sky part
  added). The HUD part ends in navy border: its last row (navy anyway),
  (68 + *s*)/8 more rows, all hidden by R6, then (68 + *s*) mod 8 R5 lines -
  4 on the flat. So the sky starts at line 132 + *s*.
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
  characters (2K). The sky part is 6 rows of 48 characters in that ring.
  Moving its start address one character scrolls it a word (4 pixels)
  sideways for good; only the column that comes in has to be written, from
  the panorama (384 pixels in bank 7: per column of a word, its four
  character rows' addresses, each row - 16 bytes, two a line - kept once:
  150 different ones of 384, the sky and the mountains' bodies being many
  columns'; 3.2K instead of 6K). That takes
  ~1.4 ms, done at the flip, before the sky part is on screen, so it never
  tears. The dithered sky repeats every word, so only the mountains seem to
  move.
- **Timing.** The Gate Array interrupts come at fixed lines (~274, 14, 66,
  118, 170, 222), and each handler sets up the next one's, so none has to
  work out where the frame is. Each register is written with more than five
  lines to spare. The HUD part's rows run on to line 131 or further, so the
  sky part's size waits for the interrupt at ~170, in the sky part. The VSYNC's handler checks that it is in VSYNC; if a frame
  is ever out of step, the handler falls back to a plain frame until the
  next VSYNC.

### Memory

The CRTC always reads the base 64K:

| Page | Holds |
|---|---|
| 0 | buffer 1's road part, common fragments; the sound in hidden lines |
| 1 | both HUDs (`#4000` with RAM C1), the bush sprites' code and the props' sprites beside them |
| 2 | buffer 0's road part, common fragments; the sound in hidden lines |
| 3 | the sky ring (`#4000` with RAM C3) |

The banks hold the rest:

| Bank | Contents | Seen at |
|---|---|---|
| 4 | road templates (`#4000–#5FFF`), code (`#6000`) and the next step's staging set (`#7E00`) for stripe band A; traffic sprite code | `#4000` (C4) |
| 5 | road code (`#4000`), the next step's staging set (`#5E00`) and templates (`#6000–#7FFF`) for stripe band B | `#4000` (C5) |
| 6 | the road's row tables and the precomputed hill tables; the traffic: its code, tables and most of its sprites' code | `#4000` (C6) |
| 7 | the game (main loop, HUD, graphics, the panorama, the track's rings and the props' size table at `#F000`, over what runs once at the start) | `#C000` (C1/C3) |

Some code and data must be reachable from every RAM configuration: the
variables they share, the interrupt handler, the stack, the line lists and
the part of the renderer that switches banks. These live in 704-byte
fragments at `#x540–#x7FF` of pages 0 and 2, beside the road parts: the
eight in page 0 (the first also has the props' drawing, cut to fit the
screen: there was the IM 2 table, 263 bytes - IM 1's `JP` is at `#0038`,
in a hidden line), and the eight in page 2 hold the bushes' tables and
their sprites as data (and, in what is left, some of the car's and the
traffic's code). `src/hw.asm` has the whole map. Bank 7's code that runs
only once, as the game starts (`src/init.asm`: the car's figures, the
parts of the screen that never change), is at `#F000`, where the track's
rings and the props' table are worked out after it.

The car's code - a compiled sprite for each of its eleven views - has the
same places for every car, as big as the biggest car's needs
(`tools/mkbush.py`): the three on the level in page 1 beside the bushes'
and in what is left of the page 2 fragments (with the smallest bush's code
when page 1 is short), the six on hills and the two spun (6.4K) in what
the CRTC never shows and nothing else writes: the HUDs' eighth character
rows (the HUD part shows seven: `R6`), bank 7 from `#F100`, after the game, and the road
parts' lines 160-172 - buffer 0's, and buffer 1's first four 2K blocks (a
bush reaches line 173 at most, the line lists start at 188, and
`draw_static` fills only from 184). BOOT.BIN has the first car's views on
the level in place. The loader loads the picked car's own `CARn.BIN` at
`#1900` (just past buffer 1's hidden lines in its fourth 2K block, which
take code) - records of where they go and the bytes: its code, `car_views`
(where each view's first line ends, and its code), `car_id` - and, the
same in every one, the traffic's code and the props' sprites that have no
room elsewhere. BOOT.BIN
first puts the fragments in place - but 3-6, whose places the file lies
on - then copies the records into place, with bank 7 switched in, and then
fragments 3-6. The race takes no more memory for four cars than for one.

The sound (`SOUND.BIN`, records like a car's file, loaded at `#98C0` - in
buffer 0's fourth block, past what the car's records write - and put in
place after them) is where nothing else goes: what the interrupt runs and
reads in the road parts' lines 173-178, both buffers' (twelve 96-byte
pieces, in pages 0 and 2: whatever the RAM configuration; a bush's top is
on line 183 at the highest, a prop's on 179, both checked by
`tools/mkbush.py`), and what the main loop runs in three HUD eighth rows
(`#4AA0`, `#52A0`, `#5AA0`), where fragments 2-7 were stored until then.
`boot_blob` (`src/boot.asm`) copies both files' records. `RACE.BIN` (the
pause and the best times, and the start of a race, which bank 7 had no
room left for: `src/race.asm`) is records too, loaded at `#A0C0` and put
in place after the sound: in buffer 1's hidden lines 164 and 172 (which
the traffic's code leaves), 167, and 178.

Page 1 has the HUDs in the first `#600` bytes of each 2K block - but the
eighth character row of each, never shown, holds code of the car's views
on hills: 12 runs of 96 bytes, those BOOT.BIN's own fragments have left
by then (`tools/mkbush.py` `HUD_ROW7`); the other
512 bytes of each block hold the bush sprites and the car as code, and most
of the props' sprites as data - the
seventh block's first half, at `#7600`, the keys and the player's speed
(`src/player.asm`), and the last block's first half, at `#7E00`, the part
of the road cache's work that runs with RAM C1.
`BOOT.BIN` is loaded at `#4000`, so it carries that code where it runs, and
the fragments, which it copies out, two to a block where the HUDs go later.

### The road

The road is made of 80 rows (its shape is laid out over 84, as if it went
on to the screen's last line). Each row has a depth, and its stripe band is a
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
4. The grass never changes colour, so a line that shows the same row at the
   same curve level as when its buffer was last drawn gets only its road
   drawn, kerb to kerb, and its grass is left alone. Bit 0 of the template
   pointer says so (templates sit at even addresses). If the hill has moved,
   `road_project` compares each line's row with the old hill level's; on a
   straight road a line that now shows a nearer row needs only its road
   too, as the old, narrower road lies under the new one. A line that
   shows the row it did, in the stripe it was in, is already right and is
   skipped - with the hill alone having moved, as when nothing has (on a
   crest or in a dip most near lines show the row they did).

Hills move row *r* down (on a crest) or up (in a dip) by *h / r* lines, with
occlusion behind a crest. The line-to-row mapping is precomputed for 128 hill
levels, so a hill costs nothing extra per frame.

### The track

The game reads the track an entry - 32 depth units - at a time: the hill
and the curve level under the camera, and a few entries on (whether a hill
is near, the next curve level to work out). Those come from two rings of
64 entries in bank 7 (`#F000`), which `course_fill` keeps worked out 8
entries ahead of the camera from a list of segments: n entries straight,
a curve to level v and back, one level an entry, or a hill of height v,
a sine from a quarter-sine table. Two bytes a segment: the demo's loop is
16 of them (`course_demo`), the race's five stages 92 (`course_race`).
Any list can follow from the next entry on, after the road is first
brought to the flat - a curve level and 12 of hill an entry - so the race
starts on a straight wherever the demo was, and the demo takes its loop up
again wherever the race ended. `tools/course.py` has the lists and the
model of all this, to the bit, and makes sure the road never bends on a
hill - and, in the race, that a hill comes 12 entries or more after a
curve: the road can still be a level or two into the curve there, and a
picture with the road bent on a hill that moves is the heaviest there is
(with 6 entries, 39.9 ms).

### Curves

A curve has a level from −7 (sharp left) to +7 (sharp right). At level *k*,
row *r* moves sideways by *k*/7 × 64 × ((84 − *r*)/83)² bytes: a parabola,
nothing at the screen's bottom and 128 pixels at the horizon at the
sharpest. Moving
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

A buffer's level moves at most one level a picture. When it moves, the road
has moved sideways by at most 5 pairs of bytes on any line, so each line is
drawn with its road and 5 pairs of grass either side of it, not whole. That
picture has a smaller HUD share and leaves the sky's turn to the next one,
and a picture that starts with the sky turning keeps its buffer's level for
one more picture, so the two never fall on the same picture.

### Steering

The car is driven as Out Run's (the SMS's `L264D`, which
OutrunOutrunCPC runs as it is) - measured there: its steering, the push of
its curves and how they come and go, in proportion to its road's width.
Left or right turns the wheel (`steer_s`) towards the full lock, neither
brings it back, 28 of 127 a picture at most: 0.2 s to the full lock, 0.4
s from one to the other (Out Run: 64 a step, ~10.9 steps a second). At
the full lock the car moves a pair (4 pixels) a picture - 1 1/3 with grip
4 or 5 - from a speed of 4 depth units a VSYNC on (Out Run: 128 of its
193), less as much as it is slower, not at all standing still. A curve
carries it out of it, in proportion to the curve level and the speed: on
a level 7 curve at full speed 72% of the full lock (Out Run's common sharp
curves, radius 60-66: 71-75%; its gentlest 31%, a level 3 curve here);
the push comes and goes, 0.11 pairs a picture each picture at most (Out
Run: 5 a step). The two moves add up in `car_x` and its fraction `car_xf`
(`steer` in `src/game.asm`). The car moves across the screen at once, and
the road - the camera - follows
it as fast as its steps go: the car is drawn `road_x` - `car_x` pairs right
of the middle of the screen, 16 at most (`CAR_LEAD`; the road at most 16
pairs behind). The road moves under it in perspective: `road_x` is how many
pairs (4 pixels) right of the middle the road is on the bottom row, and a row of half-width *h* bytes moves `road_x`
× 10*h*/256 bytes - the far road hardly moves, and the road turns about the
horizon. In the middle the curve levels' own template sets are drawn; off
it, `road_project` takes its templates from one more set in each bank, the
cache, made for the curve level and `road_x` (`src/cache.asm`).

- **Smooth edges.** Each group of rows keeps one sum - its curve level's
  shift and its share of `road_x`, in 1/256 bytes - and is drawn at the
  byte that sum rounds to (`cpcgfx.road_shift`). Rounded as it is,
  neighbouring groups would step at different moments and the kerbs and
  lane lines would zig-zag; so a small bias, at most a quarter of a byte,
  turned round from one group to the next and following the edge's slope,
  moves where each one rounds, and the edges come out as even staircases.
  The lane lines sit at an even number of pixels from the centre.
- **A step sideways** (`cache_step`) moves every group's sum two or four
  pairs' worth (8 or 16 pixels: `road_x` is always even, and with the road
  to go a pair it waits), between two pictures, so none shows the road half moved. The groups whose byte changes - about 40 of 51 - get their
  templates made afresh: band B's in bank 5 there and then, band A's and
  the far rows' band 2 in bank 4 after, from a list of the groups that
  moved. A core all on the screen takes its template straight from per
  group tables; one cut short by a side of the screen has the pair it is
  entered at or left by looked up in its entry table (every core variant
  sits in one 256-byte page, so that is all low bytes). Made there and
  then, a step takes ~12.5 ms (up to ~15 ms with the road 8 pairs or more
  to the side a sharp curve bends to).
- **Worked out ahead.** So the next step - up to four pairs towards where
  the road is to go (`cp_pend`) - is worked out in the time left before each flip, a
  piece at a time (`cache_pre`: up to 12 groups or 7 band A templates,
  ~2.4 ms, up to ~2.8 ms), when no new curve level is to be worked out
  first (below).
  Its templates go into a staging set in each bank, laid out as the cache
  set, and the bushes' shares into a staging table; the groups' sums move
  there and then, and are put back if the step is dropped (the road to go
  the other way, or less far; a new curve level). The step itself only
  copies the staging sets into the cache sets: ~5 ms, so it can go after
  any picture done by the 10th interrupt. The staging sets are then the
  cache's, so the next one starts at once; after a step made there and
  then, or a new curve level in the middle, they are made the cache's
  again first (two pieces).
- **Only when it fits.** A step made there and then - when none is worked
  out ahead, and two pairs at most - is made after a picture only if it is
  sure to be done before
  the flip, by the interrupts counted since the last one: up to the 6th (the
  5th on the costly side of a sharp curve); one worked out ahead, whenever
  there is a step at all. Else the road waits a
  picture. After a step the next picture of each buffer draws every near
  line's road and a margin of grass, and the far lines too unless the step
  left every far group where it was. A step goes on a hill too: with the
  road 80 lines high, a picture whose hill moves and road moved sideways
  fits (37.4 ms at worst). With 105 lines it did not - a step on top of one
  made it late - so until 2026-10-26 nothing moved after a picture whose
  hill moved, nor while a hill was under the camera or two track entries
  ahead, and on each hill the road did not follow the steering for up to
  4 seconds.
- **A new curve level off the middle** is worked out ahead the same way,
  into the staging sets (`cache_want`, `prk5`): the level the track has
  next - a level towards the game's, or with that reached, the track's as
  far on as the car goes in 8 VSYNCs, about the time it takes - 3 groups a
  piece (each group moved a level, placed, and its share for the bushes
  worked out afresh: ~2 ms, up to ~3 ms). The road takes the level only
  once it is ready, and then all of it at once, copied into place like a
  step (~5 ms): no picture shows the road at two levels. A level dropped
  (a hill holds it back while the player wants a step) is put back a
  piece at a time, and wanted again before that is done, goes on from
  where it is (`cache_drop`): until 2026-10-30 the staging sets were made
  the cache's again first, which put the old level's templates back for
  groups whose sums were at the new one, and the far lines showed them
  for seconds. Until then no
  step goes - the level goes first; but once one has gone, a step the
  player wants is worked out before the next (`cp_turn`): on a winding
  road a level is nearly always wanted, and the road would not follow the
  steering for seconds. The next picture of each buffer draws
  all of the road moved, ~10 ms more than the last one, so the level only
  goes after a picture done by the 7th interrupt since its flip (~27 ms) -
  one later for each further level the road is behind the track. In the
  middle the curve levels' own
  sets are drawn, so the level moves there and then, and the cache
  follows a few groups at a time; the road leaves the middle only once it
  has. A level waits on a hill or just before one (the track has no curve
  on a hill: only a late level waits) - a picture whose hill moves
  compares every line's row with the old one's, and both together are too
  much. Meanwhile a step the player wants is worked out in its place.
- **Drift.** A curve carries the car out of it: the curve level times the
  speed adds up, and every 48 of it is a pair outwards. Steering against it,
  the two cancel; with neither, the car ends up on the grass, up to 32 pairs
  (128 pixels) either way.
- **The car** is three compiled sprites like the bushes' (below): straight,
  turning left and its mirror. Their lines' runs differ, and the car moves
  across the screen, so a buffer that last showed another view, or the car
  somewhere else, has the car's 20 lines drawn whole (`car_lines`; up to
  2 ms more). Seen turning, the car is
  bigger: 1.3 ms to draw instead of 1.1. The straight and the left one are
  in page 1, the right one in the page 2 fragments.

### Bushes

`tools/mkbush.py` places the bushes along the track, with a fixed random
seed, and makes a sprite for each of 7 heights; `tools/scene.py` has their
art and works out where they go, and `src/bush.asm` has to match it.

- **In reach.** A bush comes into reach when it is near enough for its size
  class to be drawn, and leaves it when it has gone by. The bushes in reach
  are kept in a short list, nearest first; a table of where each comes into
  reach, in that order, tells when one joins. The layout never has more than
  three in reach at once.
- **Projection.** A bush's depth ahead gives its row (a table), so its size
  class gives the sprite and its lateral class how far from the road's
  centre it stands, signed for its side; the road's centre at that row
  comes from a table per curve level (mirrored for left curves), and its
  line from *h / r* as for the road. Off the middle it moves exactly as far
  as its row's group does (`rd_gp`, kept by the cache), so it keeps its
  place beside the kerb; it stands a byte further out than its lateral
  class says, as at an odd byte a row's kerb is a byte wider (the core's
  parity). It is drawn while its centre is on the screen and its row is not
  behind a crest.
- **Drawing.** The grass is plain, so a sprite is drawn as it is, with no
  mask: a run of whole pairs of bytes a line, the grass between its leaves
  already in. Each sprite is code (`src/gen/bushcode.asm`): for every line,
  the step to the next line's run, then `PUSH`es from the run's right end,
  its three most used pairs in registers. A bush cut by a side of the screen
  or the top of the road part is copied instead, from the same sprite as
  data, with its lines cut to fit.
- **Erasing.** Each buffer remembers the boxes its bushes were drawn in. At
  its next picture, before the road is drawn, they are filled with grass by
  `PUSH`es, a character row's lines at a time; the records are read with
  `POP`. A bush on the inside of a curve may stand in front of the far road;
  when one goes, the far lines are drawn even where their dash has not
  moved, to put that road back.
- **Interrupts.** While SP points into the screen, interrupts are off but get
  one instruction's chance a line, with SP at the right end of the run about
  to be pushed: the return address an interrupt leaves there is pushed
  over. The sprite code `CALL`s the step to the next character row there
  too.

The tables and the sprites as data are in the page 2 fragments, which are
mapped whatever the bank; the code in page 1 (RAM C1, as the game runs) -
the smallest sprite's in the fragments if page 1 has no room left; the
track and the drawing in bank 7.

### Props

Now and then a prop stands beside the road, never two in sight at once:
each stage's trees, by turns, and its signs - at the start of every curve
of level 3 or more, on its outside, a yellow board with black chevrons
pointing the way it bends, and before one of level 6 or more, on the
right, a speed limit. The demo has dead trees and the signs.

| Palm | Short palm | Dead tree | Speed limit | Curve |
|---|---|---|---|---|
| ![A palm](docs/prop-palm.png) | ![A short palm](docs/prop-stump.png) | ![A dead tree](docs/prop-dead.png) | ![A speed limit](docs/prop-limit.png) | ![A curve sign](docs/prop-curve.png) |

- **Art.** The trees are 3D models rendered in Blender
  (`tools/props3d.py`), the signs drawn as pixels; `tools/mkprops.py` brings
  them to the pens as it does the cars, every byte whole or clear, into
  `tools/propsart.py` (and `build/props-sheet.png`, all of them on each
  stage's grass). All the kinds share one scale of eight sizes - the
  tallest palm 44 lines high close by, 8 far off - each its own heights;
  even the tallest palm's top stays below the horizon.
- **Layout.** `tools/course.py` lays them out along each course: the signs
  first, then the trees, about 1200 depth units apart, on any segment of 8
  entries or more (a straight, a hill, a curve's outside), each as near
  where it is wanted as it can be - but none nearer another than 760, so
  that one is gone by before the next is 800 ahead. The list
  (`src/gen/gfx.asm`) is two bytes a prop: its depth from the last in 16
  units, and its kind, side and lateral class (a bush's). `course_set`
  gives a course its list, which starts with the course's first entry.
- **In sight.** The nearest that has not gone by, from 800 depth units
  ahead (`src/props.asm`). As one comes nearest, its kind's eight sprites
  go into the bush sprite records 8-15, and a table gives each row the
  size the props take there, so `bush_one` stands it as it does a bush.
- **Drawing.** From its sprite's lines, before the bushes - the few nearer
  stand in front of it: the lines above its column as groups of the same
  line, each line's runs of bytes copied with `LDIR` (cut to fit when a
  side of the screen cuts it), then the column - the trunk or the post, its
  last lines, a byte or two a line, written straight down. Its erasing is
  two boxes: the lines above the column as wide as the sprite, and the
  column's pair of bytes.
- **Off the road.** Its boxes lie on no road where `bush_one` leaves it off
  the inside of a curve - but a far one's top can lie on the far road on a
  straight with the road well off the middle (the road's far rows hardly
  move with `road_x`, its row does), so then it counts as on the inside,
  and the road is put back there; `tools/mkbush.py` checks this over
  hills, curve levels and `road_x`.
- **Time.** A prop costs 0.9-1.8 ms to stand and draw (the tallest palm
  close by ~3.9 ms) and some to erase; while one is in sight at most one
  bush is in reach - one that would still be in reach then never comes -
  and if the picture is late already (10 interrupts since the flip) it is
  not drawn that time, as the traffic's far car.

The sprites (1.4K) are in page 1 beside the bushes' code and in the hidden
lines (CARn.BIN), the drawing in bank 7 and fragment 0.

### Traffic

Up to two cars drive ahead at 3 depth units a VSYNC; the player catches up
with them and passes. Their art is rendered in Blender
(`tools/traffic3d.py`): a common body, two tops (closed: a coupé's cabin;
open: a windscreen, headrests and a driver) and three tails (a sports car's
round lamps, a saloon's wide clusters, a GT's light bar), at eight sizes;
`tools/mktraffic.py` brings them to the pens (`tools/trafficart.py`). What
takes the car's colour is black in the art, so any top goes with any tail
and each has a colour of its own out of 16 (a pen, or two in a
checkerboard). The three nearest sizes come in two pieces, top and tail;
the five further ones in one, a closed or open top on the saloon's tail,
still in two colours. `tools/scene.py` says where a car goes and what it
looks like, and `src/traffic.asm` has to match it.

- **Coming and going.** A car comes 512 depth units ahead, at the horizon,
  in a lane, with a top, a tail and colours at random, no sooner than half
  a second to two after the last one and at least 160 units behind it; it
  goes when it has gone by or got away.
- **Projection.** As a bush's: its row from its depth, its size from its
  row, its line from *h / r*, and it is drawn only whole - on the screen,
  on the road (below its top) and over near lines. Its place is its lane's,
  centred between the lane lines, from the road's centre on its row: the
  curve level's shift for its template group (`tr_cs`, mirrored for left
  curves) and road_x's share of it (`rd_gp`). Its top lines stand on
  further rows, narrower and bent more: it is kept on the road its top
  line shows (`tr_edge`), so it never stands out over the grass.
- **Drawing.** Each piece is code (`tools/mktrafcode.py`), as a bush's,
  but its paint comes from registers. A byte is all paint or none, so a
  word of paint is `PUSH DE` on even lines and `PUSH IY` on odd ones (two
  pens in a checkerboard make a byte one way round on even lines, the other
  on odd ones), and a word half paint takes its paint byte from E or IYL: a
  painted car costs no more than a plain one. Pieces that end the same way
  share their last lines (~800 bytes less). A near size's top is drawn in
  its colour, then its tail in its own; a further size loads its tail's
  colour at the line its top ends.
- **Erasing.** Each buffer remembers the lines its cars stood on; at its
  next picture road_project draws the road on those it would skip
  (`rp_force`) - a car is always on the road.
- **Time.** A car costs ~0.5 ms a picture, two ~1.3 ms (2.5 ms at worst).
  The HUD, drawn last, has only the time left (below). And if a picture is
  late already when the cars are drawn - 9 interrupts since the flip, 10 ms
  at most left (a picture whose hill moves, as a rule) - only the nearer
  car is drawn that time; from 10, 6.7 ms, only a car at a near size: the
  nearer one, if it is at one, and neither if not (`tr_dropped`). A far car
  blinks; a near one never.
- **Memory.** The pieces (4K) go where there is room in a RAM configuration
  they can run in: bank 6 after the traffic's code and in the row tables'
  pages past their rows (`src/gen/rowhole*.asm`), bank 4's last free bytes,
  fragment 4, the fragments' free runs and, in every `CARn.BIN`, the road
  parts' hidden lines - buffer 1's blocks 4-6 too, which boot has read by
  the time it copies these there. `src/trafglue.asm` (fragment 3) switches
  to a piece's bank and back. Banks 4 and 5 look free past their code in
  the binary but are not: they hold the cache's sets and the staging sets.

### Collisions

As in Out Run (the SMS's `L2B84` and `L39D6`, measured in OutrunOutrunCPC):

- **What touches the car.** A traffic car or a bush whose base line is on
  the car's lower half (`HIT_Y`), the two overlapping by more than
  `HIT_TRIM` bytes in from either's side: what is seen touching it. The
  traffic's (`tr_one`) and the bushes' (`bush_one`) drawing tells, as it
  places them, into `coll` (common memory), with the side it was on;
  `car_lines` leaves the car's place for them in `car_offc`. A bush beside
  the road can touch the car only when it is on the grass.
- **A car: a bump.** For a second (`BUMP_T`) the car is shoved away from
  the one it hit, 0.94 pairs a picture (Out Run: 12 a step for 10 steps),
  wobbling - its turning views left and right - and no faster than
  `BUMP_SPEED`, just slower than the traffic, so that the car hit goes on
  ahead; meanwhile nothing else bumps it. The player steers on.
- **A bush: a crash.** For 1.8 s (`CRASH_T`) the car is shoved away from
  it, 1.9 pairs a picture (24 a step) - across the road - spinning and out
  of control, slowing to a standstill (`speed_player`: `CRASH_BRK` a
  VSYNC); then it is brought back to the middle of the road, 0.63 pairs a
  picture (8 a step), and the player drives off again from a standstill.
  The spin (`spin_views`) is a view each 2 pictures: turning, spun, spun,
  turning one way, then the other - first its nose swung towards the side
  that was hit, as the blow turns it. A spun view's box is wider (60 pixels, the white car's
  64), so further than `SPIN_OFF` (16 pairs) from the middle it would run
  off the screen: there `car_lines` shows the car turning instead. Spun,
  the car is seen on the level whatever the slope.

All of it is the game's (`coll_start`, `coll_step` in `src/game.asm`): the
road, the traffic and the bushes are drawn as ever, so the checks hold.

### The HUD

The HUD shows a copy of the game's values, taken every 4 pictures (6.25 times
a second). The gauges have 8 segments. Each buffer remembers what it shows.
Only what changed is redrawn, last in a picture, with the time left: a
share of about 1.1 ms a picture up to the 10th interrupt since the flip, a
third of it at the 10th (then, every other picture of each buffer, a gauge
segment goes before the total time), none from the 11th - its copy waiting
too, for a picture that has the time; the rest waits for the buffer's next
picture. Text and gauges sit on
the HUD's plain background, so drawing is plain copying, never masking.
The big digits (the speed, the countdown) are kept at half their height,
each of their lines drawn twice.

The last line holds the game's message: 13 cells of the small font's
glyphs (the digits and the 19 letters the messages use, 24 bytes each),
each buffer redrawing the cells that differ from what it shows, left to
right, 4 at most a picture (~0.25 ms each, its 3 x 8 bytes copied by
`draw_cell`: the line is a character row's first) and only before the
9th interrupt since the flip - so a message comes and goes as a wipe over
a few pictures (`hud_msg`): ~1.5 ms in each of those, nothing in the
others (a buffer looks again only when the message changes).

### Sound

The PSG (AY-3-8912, through the PPI) plays three channels: A the tune's
lead, B its bass, C the engine or, for a while, an effect. The interrupt
plays it all (`src/sound.asm`): at line ~118 every other frame
(`irq_idle`), so 25 times a second, in step with the pictures:

- **The music** (`snd_tick`): a row - an eighth note at 125 beats a
  minute - every 6 updates, a pattern of 8 rows a bar, each channel's
  bars from its order list, round again at its end. A note's volume
  starts at 13 and falls an update to the level it holds (the lead 9, the
  bass 7). The tune is `tools/mksound.py`'s (`src/gen/music.asm`): note
  names, bar by bar, the bass the chord's root an octave apart on every
  other eighth; a byte a row (hold, off, or a note from C2), octave 2's
  twelve periods, higher octaves halved and rounded.
- **Channel C** (`snd_chan_c`): an effect is steps of updates, a volume
  falling an update, a tone's period or a noise's; with none, the
  engine as the main loop last had it.
- **The PSG's registers** (`snd_out`): kept in `snd_regs`, and only those
  that differ from what was written last (`snd_last`) are written.

Once a picture, after `steer`, the main loop's `snd_frame` tells it what
the game is doing: the music on in the race (from its start), off
otherwise; the engine's period (960 less 3/8 of the speed, every other
picture 1/16 longer: the hum) and volume (none in the demo), its noise
on the grass; and an effect when something begins - the count's digit
changing (a beep, GO!), the message (EXTENDED TIME, TIME UP, FINISH),
`coll_t` going up (a bump, a crash).

`read_keys` reads the keyboard through the PSG's port too, its
interrupts off meanwhile. An update takes ~0.3 ms in the demo and
~0.54 ms on average in the race (0.9 ms in one in ten, 1.1 ms at most: a
row's notes as a bar starts), measured in the emulator.

### Timing

Measured in the emulator over 3000 pictures (2 minutes) of the demo's
crests, dips and curves, from the flip that starts a picture to the next
flip being asked for, a picture takes about 22.5 ms of its 40 ms; 22.3 ms
with the player not steering, the curves carrying the car out (at the top
speed of 6.6 depth units a VSYNC; with the horizon higher, 27.1 and 26.7 ms,
and 26.3 and 25.7 ms at 5.25). Roughly (measured with the horizon higher,
at 5.25, before the road's last four lines were cut, which took off
~0.7 ms on average and up to ~1.5 ms):

- road drawing: ~21.5 ms (~22.7 ms when the hill moves, ~27.6 ms when the
  curve level changes);
- road projection: ~5 ms (~5.8 ms when the hill moves);
- bushes: ~1.7 ms (4.9 ms at worst), taking away and drawing;
- a prop in sight: 0.9-1.8 ms to stand and draw (~4 ms the tallest palm
  close by), a bush fewer in reach meanwhile (Props, above);
- HUD: ~1 ms, within its share;
- game logic: ~0.6 ms;
- interrupts: ~1.4 ms, the raster ruptures and the sky's turns (1.4 ms a
  turn, at the flip);
- the sound: ~0.3 ms in the demo, ~0.54 ms in the race (Sound, above).

In 3000 pictures none runs past its flip in the demo, with the player not
steering or steering from side to side: the worst takes 38.2 ms, with the
traffic, the props and the sound (Steering in numbers, below). Over the
race's five stages, driven by the autopilot in each of the four cars and
zigzagging from side to side with the keys, with the music, none does
either: the worst takes 39.3 ms (a hill moving, a dead tree close by drawn
at the 9th interrupt, and the sound) - a prop is left out of 5 to 52 of
each race's ~6100 pictures (7 to 18 before the sound), which were late
already when it came to it.
(Before the curve levels were worked out ahead, 1, 0 and 0 did: a picture
while the cache caught up with a new level.) A sideways step (~5 ms copied
into place, or up to ~14 ms made there and then), a batch of the cache's
work in the middle (3 groups, up to ~3 ms) or a piece of the next step or
curve level worked out ahead (up to ~3.4 ms and ~5.4 ms: they stop when
the flip is 3.3 ms away) never runs past the flip.

### Steering in numbers

Measured in the emulator, 3000 pictures each: the demo; the player not
steering, the curves carrying the car out; and steering from side to side,
the tools setting `steer_x` to 32 pairs either way in turn - all with the
demo's speed, up to the top speed (6.6 depth units a VSYNC).

| | Demo | Not steering | Side to side |
|---|---|---|---|
| a picture, on average | 22.8 ms | 23.1 ms | 26.6 ms |
| the worst | 37.7 ms | 34.7 ms | 37.2 ms |
| past the flip | 0 | 0 | 0 |
| pairs the road moved a picture | 0.116 | 0.137 | 1.024 |
| curve levels the road is behind the track, off the middle | 0.44 | | 1.13 |

(The first car; with the cars seen on hills and the car's 27 lines drawn
whole when its view or place changes. The other three: 35.9 ms at worst in
the demo, 37.6 ms side to side. Driving with the keys, all four: 0 past
the flip in 3000, 38.3 ms at worst.)

With the traffic (up to two cars) and the car steered a third as fast
(2026-10-27) the same took 24.8 / 25.7 / 27.8 ms on average and 39.0 /
37.8 / 38.2 ms at worst, none past the flip, the road moving 0.116 / 0.139
/ 0.873 pairs a picture (driven as Out Run's car, bumping and crashing); the other three cars 37.7 / 36.9 / 37.5 ms at
worst in the demo and 37.6 / 38.4 / 39.2 side to side. Driving with the
keys, all four: 28.9-29.5 ms on average, 37.9 ms at worst, 0 past the flip
in 3000 - the HUD with a third of its share in ~6% of the pictures and
none in ~1%, and the far car left out of 28 to 49 (Traffic, above).

With the crash's spun views (2026-10-28): the same within the runs' spread
(side to side, four `steer_x` settings: 37.5-38.4 ms at worst, the build
before 37.7-39.2), none past the flip; keys 37.8-38.9 ms. Crashes forced at
the top speed - a bush hit on the road, the car spinning across it with
the traffic about - 37.1 ms at worst for the first car and 37.7 ms for
the white one (its spun views the biggest: 961 bytes of code, 1.82 ms,
against 1.25 ms turning), none past the flip.

With the props and the sound (2026-10-30): 24.5 / 25.3 / 27.8 ms on
average and 36.9 / 38.2 / 37.6 ms at worst, none past the flip.

Steering across the road (30 runs): 0.89 pairs a picture - 0.545 with
steps of two pairs only. With the keys (faster held, the car driven from
`car_x` -18 to 18 and back, 20 times): 56-64 pictures (2.2-2.6 s) a
crossing with grip 2 or 3, 46-48 (1.9 s) with grip 4 or 5 - from 33 to
104, as the curves carry the car with it or against it - the car on the
screen 9 to 10 pairs from the middle on average; 79-82 and 54-61 with the
traffic bumping it on the way. (Before it was driven as Out Run's,
42.1-42.9 and 36.4-37.3 pictures; steered three times as
fast, until 2026-10-27: 16.6 pictures, 0.67 s; 36.6 with steps of two pairs and
the car at most 12 pairs from the middle, and ~66 with the car kept in
the middle.) Driving with the
keys, left and right in turn every 40 pictures (every 12): 27.2 ms
(28.2 ms) a picture on average, 37.5 ms (38.0 ms) at worst, none past the
flip in 3000. Before steps went on hills, 22.6 / 22.1 / 23.8 ms on average, 33.0 / 32.5 / 34.9 at
worst, and 0.104 / 0.081 / 0.240 pairs a picture (0.248 across).

With the horizon higher (the road 105 lines instead of 80, until
2026-10-26) the same took 27.1 / 26.7 / 28.1 ms on average, 40.3 / 40.2 /
40.2 at worst - one past the flip in each, the second picture of a new
curve level or a step, with many bushes on the screen - and the road moved
0.066 / 0.055 / 0.145 pairs a picture, 1.53 / 1.69 levels behind the
track. Before that, at the top speed of 5.25 depth units a VSYNC, 0 / 0 /
1 were past the flip (40.7 ms), and at 6.6, before the hill pictures
skipped the lines that had not changed, 8 / 2 / 6.

The cache's work, each piece (the step worked out ahead and copied into
place, or made there and then when there is none):

| | Mean | Worst |
|---|---|---|
| a step copied into place (two or four pairs) | 5.0 ms | 5.2 ms |
| a step made there and then (two pairs) | 12.6 ms | 14.0 ms |
| a piece of the next step worked out ahead | 2.4 ms | 3.4 ms |
| a piece of the next curve level worked out ahead | 3.3 ms | 5.4 ms |
| the staging sets made the cache's again, a bank | 2.6 ms | 2.9 ms |
| a batch of a new curve level in the middle (3 groups) | 2.1 ms | 3.0 ms |

Working the levels out ahead has its price in steering: until a level the
track has next is ready and copied into place no step goes, and on a
curve's way in and out (a level every ~3 pictures at full speed) that is
most of the time - at the top speed of 6.6, a player holding a key could
see the road not move for 3 seconds. So after each level a step the
player wants goes first (`cp_turn`): steering across the road went from
0.118 pairs a picture to 0.149, and the road lagged the track's curve by
1.53 / 1.69 levels (demo / side to side) instead of 1.01 / 1.22 (with the
horizon higher; now 0.545, and 0.50 / 1.26). Letting the step go first
only with the road no more than a level behind gave 0.121 and 1.43 /
1.49. Before the levels were worked out ahead, the road
lagged by 1.06 / 1.19 levels and pictures showed it at two levels; now
never.

Steering across the road (30 runs from one side to the other), at the top
speed of 5.25: 0.164 pairs
a picture (0.185 before the curve levels were worked out ahead, 0.165
before the road's last four lines were cut); 0.110 with
every step made there and then (10 runs, measured before the steps were
always two pairs). The first run, from the flat start, went 0.62
pairs a picture; the most there could be was one, two pairs every other
picture (now two: four pairs every other picture). Holding a key (the road at most two pairs behind): 0.149 pairs a
picture, changing direction every 20 pictures; 0.156 every 60. The demo
track is mostly hills and curves.

What holds it back is the pictures, not the steps: a step makes the next
picture of each buffer draw every line's road, and on hilly track there is
rarely the room. Road drawing alone, steering from side to side (with
steps on hills allowed, for the last):

| The picture | Drawing |
|---|---|
| nothing moved (most lines skipped) | 12.7 ms |
| the hill moved | 16.5 ms |
| the road moved sideways | 23 ms |
| both | 24.1 ms (28 ms at worst) |

Steps sideways on hills, tried (pictures past the flip, demo / not steering
/ side to side, and pairs a picture side to side):

| A step sideways waits for a hill | Past the flip | Pairs |
|---|---|---|
| under the camera or 3 track entries ahead (*) | 2 / 2 / 1-3 | 0.175 |
| ... 2 entries ahead (now) | 2 / 1 / 3 | 0.179 |
| ... 1 entry ahead | 4 / 3 / 4 | 0.185 |
| ... under the camera only (*) | 4 / 1 / 7 | 0.199 |
| never: steps on a moving hill too (*) | 8-16 / 10-16 / 45-56 | 0.36 |

(*) Measured while a step could still be one pair or two.

Steps on a moving hill would double steering on hilly track, but the
picture after one was up to ~3.5 ms too long; drawing the lines that show
another row with the road and both margins instead of whole saved only
0.6 ms on average, and letting a step go only after a light picture still
left many late. (All of the above with the horizon higher, the road 105
lines high. With 80 lines steps go on hills: see the top of this section.)

Not drawing the lines of the groups a step left where they were saves
little: the first group a step moves is nearly always a far one (0-9), and
the ~7 it leaves are scattered. Sending the near lines through the
skip-checking loop for them cost 1.1 ms more than it saved; only the far
lines are left out, when no far group moved (about one step in five): the
picture after a step on flat road 0.25 ms shorter on average, 38.7 ms at
worst instead of 39.3, steering as it was.

## Testing

`tools/run.py` drives a headless CPC 6128 emulator based on
[floooh/chips](https://github.com/floooh/chips), with the real ROMs. It boots
BASIC and types `RUN"COUNTRY`, the way a person would, and on the loader's
screen the car's number: the first car, or `CAR` (0-3) - the reference
model then draws that one.

`make check` then:

- measures the frame rate;
- compares 240 freshly drawn road parts, line by line, props, bushes and
  traffic and all, with what `tools/scene.py` (the Python reference model) says
  they should be, over hills and curve levels - the lines the CRTC shows:
  above them is the car's code;
- does the same for 20 pictures of the HUD and horizon;
- compares 300 frames of what the emulator actually displayed with the
  buffer on screen, split the way the model says for that frame's drop: 100
  with each of the CRTC behaviours below, spread over a lap of the track.

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
  boot.asm      takes the machine over, puts the picked car's code in
                place, copies the common fragments
  common.asm    the fragments: variables, interrupts and ruptures, road_draw
  road.asm      road_init, road_project
  road6.asm     road_project's part in bank 6: how lines are drawn
  road15.asm    road_project's part in fragment 15, the curve level's jobs
  cache.asm     the road off the middle: the cache set, steps (also
                worked out ahead), jobs
  cache4.asm    ... its part in bank 4 (band A)
  cache5.asm    ... and in bank 5 (band B)
  cachemac.asm  making a cache template (both banks)
  game.asm      main loop, the race's rules, demo drive, steering
  course.asm    the track worked out a few entries ahead, the stages'
                colours
  bush.asm      the bushes: projected, drawn, taken away
  props.asm     the props: the nearest along the course, stood as a bush,
                drawn from its sprite's lines
  propdraw.asm  ... their drawing cut to fit the screen, their boxes
                (fragment 0)
  init.asm      what runs once as the game starts (over the track's rings)
  sound.asm     the sound: the interrupt's player (music, engine, effects),
                what the main loop tells it (SOUND.BIN)
  race.asm      the pause, the best times, the start of a race (RACE.BIN)
  traffic.asm   the traffic: cars coming and going, projected, drawn
  trafglue.asm  into a traffic sprite piece's bank and back, its steps
  hud.asm       HUD updates
  horizon.asm   how far the horizon drops, the sky ring
  screen.asm    buffers, blitting, the static picture
  gen/          generated by tools/ (committed)
tools/
  cpcgfx.py     palette, mode 0 encoding, road geometry
  scene.py      the reference model of the whole screen
  mkgfx.py      HUD, sky and mountain graphics, the track's lists -> src/gen/
  course.py     the demo's loop and the race's stages, and the model of
                how the game works them out
  mkroad.py     the generated road code, templates and tables -> src/gen/
  car3d.py      the first car as a 3D model, the game's camera, curved
                shapes (lofts, arches, fenders) for all the cars (Blender)
  cars3d.py     all four cars' models, rendered photorealistic in Blender:
                nine views each from behind, one spun (SPIN), one from the
                side -> assets/cars/
  dither.py     renders to mode 0: mean colours, the CPC's checkerboards
  mkcar.py      sprite art from renders: lone pixels, whole pairs, the box
  mkcars.py     the cars' views as the game's pens -> tools/carsart.py
  mkselect.py   the title and the screen the car is picked on
                -> src/gen/select.scr
  traffic3d.py  the traffic's tops and tails at eight sizes (Blender)
                -> assets/traffic/
  mktraffic.py  the traffic's art as the game's pens -> tools/trafficart.py
  mktrafcode.py the traffic's sprites as code, where they go, the tables
                -> src/gen/ (and src/gen/trafleft.py for mkbush.py)
  props3d.py    the trees as 3D models, rendered at each of their sizes
                (Blender) -> assets/props/
  mkprops.py    the props' art as the game's pens, the signs drawn
                -> tools/propsart.py
  mksound.py    the race's music -> src/gen/music.asm
  mkbush.py     the bushes along the track, their sprites (as code and as
                data), each car as code (CARn.BIN), what is left of the
                traffic's code, the props' sprites, and tables -> src/gen/
  run.py        emulator harness: check, shots, watch
  emu/          the emulator debug library and the CRTC patch
assets/         fonts, the cars', the traffic's and the trees' renders
disc/           BASIC loader: the car picked as the game loads
docs/           screenshots
```

## Next

- a crash at full speed as the arcade's: the car flipping (it spins now,
  between its turning views and two spun 30 degrees);
- curves that come from the horizon (the whole road bends at one level now);
- 3- and 2-lane roads (the generator already has the `LANES` parameter).
