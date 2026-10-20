#!/bin/sh
# Build build/libcpcdebug.so from the headless emulator plus tools/emu/cpcdebug.c.
#
# The emulator is compiled from a mirror of its sources in build/emu-src, in
# which chips' CRTC (mc6845.h) is replaced by the copy tools/emu/crtc_patch.py
# makes - with the R5 lines and the end-of-frame test of a real CRTC, which
# the game's raster ruptures depend on. The original sources are untouched.
set -e
EMU=${CPCEMU:-$HOME/repos/CPCTools/cpcemu}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OV="$ROOT/build/emu-src"
rm -rf "$OV"
mkdir -p "$OV/chips/chips"
cp "$EMU/cpcheadless.c" "$OV/"
for f in "$EMU"/chips/chips/*.h; do
    ln -s "$f" "$OV/chips/chips/"
done
ln -s "$EMU/chips/systems" "$OV/chips/systems"
rm "$OV/chips/chips/mc6845.h"
python3 "$HERE/crtc_patch.py" "$EMU/chips/chips/mc6845.h" "$OV/chips/chips/mc6845.h"
cc -O2 -shared -fPIC -I"$OV" -o "$ROOT/build/libcpcdebug.so" "$HERE/cpcdebug.c"
