#!/usr/bin/env python3
"""The race's music, as src/sound.asm plays it: src/gen/music.asm.

An original tune, 16 bars in A minor at 150 beats a minute, for action:
a riff over a pedal note (i-VI-VII-V, twice), then a chorus in a 3-3-2
rhythm climbing the chords' notes (VI-VII-III-V, VI-VII-i-V); the bass
drives in eighths, an octave up on the second and fourth beats (where a
snare would be). The lead is on the PSG's channel A, the bass on B -
channel C is the engine's and the effects'. A row is an eighth note,
ROW_TICKS of the player's updates (25 a second); a pattern is a bar, 8
rows, a byte a row:

    0           hold (the note goes on, its volume decaying)
    1           off
    2 + 2i      note i of the tune's, lowest first: its period is
                snd_periods' i-th (the PSG's clock 1 MHz: 62500 / f) -
                2i, its offset there (the table in one 256-byte page)

Each channel has an order list of its bars' patterns (defw), #FFFF at the
end: round again.

The patterns and lists go into the pieces of SOUND.BIN the code leaves
(DATA_PIECES: hw.asm SND_P..., a line each), as records - sound.asm's.
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ROW_TICKS = 5
NOTES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
         "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10,
         "B": 11}

LEAD = [
    "A4  A4  E5  A4  D5  A4  C5  A4 ",     # Am   the riff, over A4
    "A4  A4  F5  A4  E5  A4  C5  A4 ",     # F
    "G4  G4  D5  G4  C5  G4  B4  G4 ",     # G    ... over G4
    "G#4 B4  E5  G#5 B5  G#5 E5  B4 ",     # E    up and down its notes
    "A4  A4  E5  A4  D5  A4  C5  A4 ",     # Am
    "A4  A4  F5  A4  E5  A4  C5  A4 ",     # F
    "G4  G4  D5  G4  C5  G4  B4  G4 ",     # G
    "E5  .   G#5 .   B5  .   E6  -  ",     # E    up into the chorus
    "C6  .   .   A5  .   .   F5  .  ",     # F    the chorus: 3-3-2
    "D6  .   .   B5  .   .   G5  .  ",     # G
    "E6  .   .   C6  .   .   G5  .  ",     # C
    "B5  .   .   G#5 .   .   E5  .  ",     # E
    "A5  C6  F5  A5  C6  .   A5  .  ",     # F
    "B5  D6  G5  B5  D6  .   B5  .  ",     # G
    "C6  B5  A5  G5  A5  .   E5  .  ",     # Am
    "G#5 .   B5  .   E6  .   -   .  ",     # E    and back to the riff
]
CHORDS = ["A", "F", "G", "E", "A", "F", "G", "E",
          "F", "G", "C", "E", "F", "G", "A", "E"]
# the bass: the chord's root in eighths, an octave up on beats 2 and 4
BASS = {c: " ".join("%s%d" % (c, 3 if i in (2, 6) else 2) for i in range(8))
        for c in set(CHORDS)}

# instruments: volume at a note, its fall an update, the volume it stays at
LEAD_ENV = (14, 2, 9)
BASS_ENV = (13, 3, 5)

PIECE = 96


def semitone(tok):
    """A note's semitones above C2; None for a hold or an off."""
    if tok in ".-":
        return None
    name, octave = tok[:-1], int(tok[-1])
    n = NOTES[name] + 12 * (octave - 2)
    assert 0 <= n < 72, tok
    return n


def used():
    """The tune's notes, lowest first (semitones above C2)."""
    return sorted({semitone(t) for text in LEAD + list(BASS.values())
                   for t in text.split()} - {None})


def note(tok):
    if tok == ".":
        return 0
    if tok == "-":
        return 1
    return 2 + 2 * used().index(semitone(tok))


def pattern(text):
    row = [note(t) for t in text.split()]
    assert len(row) == 8, text
    return row


def periods():
    """The tune's notes' periods (the PSG: 1 MHz / 16 / f)."""
    return [round(62500 / (440 * 2 ** ((n - 33) / 12))) for n in used()]


def main(pieces):
    """pieces: the free pieces' addresses (hw.asm SND_Pn), each PIECE
    bytes. Lays the data out in them; writes src/gen/music.asm."""
    pats, lead_order, bass_order = [], [], []
    for text in LEAD:
        p = pattern(text)
        if p not in pats:
            pats.append(p)
        lead_order.append(pats.index(p))
    for c in CHORDS:
        p = pattern(BASS[c])
        if p not in pats:
            pats.append(p)
        bass_order.append(pats.index(p))
    per = periods()
    blocks = [("snd_periods", "the tune's notes' periods, lowest first",
               ["    defw " + ",".join(str(v) for v in per[j:j + 12])
                for j in range(0, len(per), 12)]
               + ["    ASSERT hi(snd_periods) == hi(snd_periods+%d)" % (2 * len(per) - 1)],
               2 * len(per)),
              ("mus_lead", "the lead's bars (channel A)",
               ["    defw " + ",".join("mus_p%d" % i for i in lead_order[j:j + 8])
                for j in range(0, len(lead_order), 8)] + ["    defw #FFFF"],
               2 * len(lead_order) + 2),
              ("mus_bass", "the bass's bars (channel B)",
               ["    defw " + ",".join("mus_p%d" % i for i in bass_order[j:j + 8])
                for j in range(0, len(bass_order), 8)] + ["    defw #FFFF"],
               2 * len(bass_order) + 2)]
    blocks += [("mus_p%d" % i, None, ["    defb " + ",".join(str(v) for v in p)], 8)
               for i, p in enumerate(pats)]
    room = [[a, PIECE, []] for a in pieces]
    for label, comment, lines, size in blocks:
        r = next((r for r in room if r[1] >= size), None)
        if r is None:
            raise SystemExit("sound: no room left in the pieces for " + label)
        r[2] += [label + ("   ; " + comment if comment else "")] + lines
        r[1] -= size
    out = [";; Generated by tools/mksound.py - do not edit.",
           ";; The race's music (see mksound.py), in SOUND.BIN's pieces after the",
           ";; code: records as sound.asm's.", "",
           "ROW_TICKS   EQU %d   ; the player's updates a row (an eighth note)" % ROW_TICKS,
           "LEAD_V0     EQU %d" % LEAD_ENV[0], "LEAD_DEC    EQU %d" % LEAD_ENV[1],
           "LEAD_SUS    EQU %d" % LEAD_ENV[2], "BASS_V0     EQU %d" % BASS_ENV[0],
           "BASS_DEC    EQU %d" % BASS_ENV[1], "BASS_SUS    EQU %d" % BASS_ENV[2], ""]
    for i, (a, left, lines) in enumerate(room):
        if not lines:
            continue
        p = "mus_d%d" % i
        out += ["    defw %s,%s_end-%s" % (a, p, a), "%s_ph" % p,
                "    ORG %s,%s_ph" % (a, p)] + lines + [
               "%s_end" % p, "    ASSERT %s_end <= %s+SND_PIECE" % (p, a),
               "    ORG %s_ph+%s_end-%s" % (p, p, a)]
    open(os.path.join(ROOT, "src", "gen", "music.asm"), "w").write("\n".join(out) + "\n")
    used = sum(PIECE - r[1] for r in room)
    print("music: %d patterns, %d bytes; %d bytes left in its pieces"
          % (len(pats), used, sum(r[1] for r in room)))


DATA_PIECES = ["SND_P%d" % i for i in range(7, 10)]   # (sound.asm has P0-P6, P10)

if __name__ == "__main__":
    main(DATA_PIECES)
