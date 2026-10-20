#!/bin/sh
# Build build/libcpcdebug.so from the headless emulator plus tools/emu/cpcdebug.c
set -e
EMU=${CPCEMU:-$HOME/repos/CPCTools/cpcemu}
ROOT=$(dirname "$0")/../..
mkdir -p "$ROOT/build"
cc -O2 -shared -fPIC -I"$EMU" -o "$ROOT/build/libcpcdebug.so" "$(dirname "$0")/cpcdebug.c"
