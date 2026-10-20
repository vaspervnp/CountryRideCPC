# COUNTRY RIDE - Amstrad CPC 6128
#
#   make          build/countryride.dsk  (RUN"COUNTRY on a 6128)
#   make gen      regenerate src/gen/*.asm from tools/ and assets/ (python3)
#   make shots    boot the disc in the emulator and take docs/ screenshots
#   make check    boot it, run it, compare the road with the Python model
#   make mockup   build/mockup.png, the picture worked out in Python
#   make clean
#
# Needs rasm and iDSK. The generated sources are committed, so python3 is only
# needed when the art or the road shape changes; Pillow for the pictures.

RASM   ?= rasm
IDSK   ?= iDSK
PYTHON ?= python3
BUILD  := build
DSK    := $(BUILD)/countryride.dsk

SRC := $(wildcard src/*.asm) $(wildcard src/gen/*.asm)

.PHONY: all gen shots check mockup clean

all: $(DSK)

$(DSK): $(SRC) disc/country.bas | $(BUILD)
	rm -f $@
	$(RASM) src/main.asm -o $(BUILD)/countryride -s -sa -os $(BUILD)/countryride.sym
	$(PYTHON) -c "import sys; open(sys.argv[2],'wb').write(open(sys.argv[1],'rb').read().replace(b'\n', b'\r\n'))" disc/country.bas $(BUILD)/country.bas
	$(IDSK) $@ -i $(BUILD)/country.bas -t 0 -f > /dev/null

gen:
	$(PYTHON) tools/mkgfx.py
	$(PYTHON) tools/mkroad.py

shots: $(DSK)
	$(PYTHON) tools/run.py shots

check: $(DSK)
	$(PYTHON) tools/run.py check

mockup:
	$(PYTHON) tools/scene.py $(BUILD)/mockup.png

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*
