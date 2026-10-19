# Mystic Warriors for MiSTer

A MiSTer FPGA core for **Mystic Warriors** (Konami, 1993; *Mystic Warriors: Wrath of the Ninjas*), the four-player
ninja beat-'em-up on the "pre-GX" GX128 board. It is built on the Violent Storm, Metamorphic Force and Monster Maulers
cores (which come from plasticbugs' Gaiapolis core for the Analogue Pocket): the same 68000 / Z80 / K056832 / K055673 /
K055555 / K054338 / K054539 board family, with this game's map, 5bpp tiles and sprites, per-tile blending and a 288 x 224
picture at a 6 MHz pixel clock.

No ROMs or other copyrighted data are in this repository; you supply your own MAME `mystwarr.zip`.

**Status.** New core: built, simulated with the real game programs, **not yet tested on a MiSTer**. See "What is
verified" for exactly what has been checked and how, and "Known differences / open points" for what has not.

## Install

1. Copy the RBF from `releases/` to `/media/fat/_Arcade/cores/` and the `.mra` files from `mra/` to `/media/fat/_Arcade/`.
   Keep the RBF's `mysticwarriors_` name and date: MiSTer finds the core by the MRA's `<rbf>` name plus the date.
2. Put your MAME 0.289 `mystwarr.zip` in `/media/fat/games/mame/` (the merged set holds all five versions, or the clone
   zips `mystwarru.zip`, `mystwarrj.zip` ... next to it). No ROMs are distributed.
3. Start `Mystic Warriors (World ver EAA)` (or the USA / Japan / Asia version) from the Arcade menu. The ROM image is
   15.25 MB; with a recent Main_MiSTer (one that knows the MRA's `address=` attribute) it is copied to the DDR3 in one go
   and loaded in about a second, an older one streams it through the HPS port. The game's power-on RAM / ROM check runs
   first, as on the board.

| Set | MRA |
|---|---|
| `mystwarr` | Mystic Warriors (World ver EAA) |
| `mystwarru` | Mystic Warriors (USA ver UAA) |
| `mystwarrj` | Mystic Warriors (Japan ver JAA) |
| `mystwarra` | Mystic Warriors (Asia ver AAB) |
| `mystwarraa` | Mystic Warriors (Asia ver AAA) |

## OSD options

| Option | Values | |
|---|---|---|
| Aspect ratio | Original, Full Screen, [ARC1], [ARC2] | Original is 4:3 |
| Scale | Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+ | Integer scaling for the HDMI scaler (the framework's `video_freak`) |
| Flip Screen | Off, On | The picture turned 180 degrees on every output (a frame buffer in the DDR3: one frame of delay while on) |
| Scandoubler Fx | None, HQ2x, CRT 25%, CRT 50%, CRT 75% | |
| CRT Adjust | submenu: Off, On; H-Size 0..+3 / -16..-1, H-Position -48..+16, V-Shift -16..+15 | Fits the picture to a 15 kHz analog output. Does nothing while the scandoubler is in use |
| Number of Players | 2, 4 | The board's DIP |
| Coin Mechanism | Common, Independent | The board's DIP |
| Audio | Stereo, Mono | The board's DIP; Mono puts the left mix on both channels |
| Test Mode | Off, On | The board's test switch: the game's service menu |
| Diagnostic overlay | Off, On | Three rows of 32 squares along the bottom of the picture, and the built-in memory test after each ROM load |
| SDRAM read capture | Normal, Late | For a module that answers slowly |
| Reset | | Restarts the machine |

On a gamepad the default mapping is A / B / R for buttons 1 / 2 / 3, Start for Start and Select for Coin; up to four
joysticks. From the keyboard: 1-4 start, 5-8 coin and F2 for the test switch.

## What differs from the cores it is built on

| | Violent Storm | Monster Maulers | Mystic Warriors |
|---|---|---|---|
| picture | 384 x 224, 8 MHz | 288 x 224, 6 MHz | **288 x 224, 6 MHz**, 384 x 264, 59.1856 Hz |
| tiles / sprites | 4bpp / 4bpp | 5bpp / 5bpp | **5bpp / 5bpp** |
| sprite z codes | kept | suppressed | **kept** |
| tile blending | MAME 0.289's "last mix code" | none | **per tile** (current MAME's rule) |
| interrupts | IRQ6 / IRQ5 by scanline | IRQ5 at vblank | **IRQ2 / IRQ4 by scanline, gated by the IRQ control byte** |
| helper chip | K055550 | K055550 | **none** |
| rotating plane | none | K053936 | **none** |
| players | 3 | 2 | **4** |

## What is verified

| | |
|---|---|
| ROM path | `tools/mw_rom.py` rebuilds MAME's regions from `mystwarr.zip` by MAME's own loading rules and compares them with the image built from each MRA: all five sets identical in every region |
| Lint | Verilator `-Wall` over the machine and the memory subsystem (`sim/lint.sh`) |
| Whole machine | `sim/run_mw.sh`: the real 68000 and Z80 programs from reset through `mw_mem`, the SDRAM controller and a behavioural SDRAM. The game's own power-on **ROM RAM CHECK passes every item** (the RAMs, the program and sound ROMs, the EEPROM: "VER. EA A"), then the intro ("Beware of 'SKULL' enterprise on!", its red flash and fade, the dusk city and the Skull castle with its parallax scroll) and, with a coin from the scripted inputs, the title screen with the five ninjas. The title screen's text rows and the HUD (1UP / HIGH SCORE / 2UP frames and digits) sit at exactly the pixel rows and columns of MAME's snapshots of the game. Over 900 frames: 1.68 M tile and 27,280 sprite ROM reads by the renderers compared with the image, 0 wrong; no line overran; IRQ2 and IRQ4 in every frame once the game enables them; the music plays in stereo from the first second. With scripted inputs: coin, start, the SELECT NINJA screen, a ninja chosen and the story scene in the dojo that follows (1,000 frames, no line overran). The service menu (test switch): the MAIN MENU, and its **MASK ROM CHECK reports 1H, 1K and 3H (the tile ROMs) OK**, read through the K056832's ROM window at `680000` (both its modes and the bank register) against the checksums in the game's program |
| MiSTer top level | `sim/emu/run_emu.sh`: `MysticWarriors.sv` itself with the framework's video path: the fast load replayed from the DDR3 and all 7.47 M SDRAM words compared with the image (0 wrong), frame period exactly 1,622,016 clocks (59.1856 Hz), 224 rows of 288 pixels starting 79 pixels after the hsync pulse, the EEPROM read back through the save path |
| Quartus | Quartus Prime Lite 17.0.2 compiles the project for the 5CSEBA6U23I7: 46 % of the ALMs (19,118), 519 of 553 M10K, 65 DSPs; every clock's slack positive (the 96 MHz core clock +0.629 ns setup / +0.245 ns hold; `releases/*.summary`) |

## Known differences / open points

* Not yet tested on a real MiSTer.
* No frame-for-frame comparison with MAME has been made for this core yet (the other cores' frozen-state corpus and
  MAME Lua probes need a MAME installation; the benches are in place). The comparisons so far are against MAME's
  published snapshots of the game (positions of the text and HUD), not against MAME frames of the same game moment.
* Gameplay beyond the first story scene has not been simulated for this build yet, and the MASK ROM CHECK's sprite
  (10K-22K) and PCM (1D, 2D) results were still running in the bench when this was written (the sprite ROM window at
  `482000` is Monster Maulers' with this board's 4 MB + 1 MB layout).
* The tile blending follows the current MAME (each tile with its own mix code), not 0.289's; the additive mode
  likewise (`docs/hardware.md`, section 4).
* SHDPRISEL's shadow conditions 1 and 2 (the "topmost screen" comparison the current MAME added) are not modelled.

## Repository layout

| Path | |
|---|---|
| `MysticWarriors.sv`, `MysticWarriors.q*`, `MysticWarriors.sdc`, `files.qip` | the MiSTer top level (`emu`), Quartus project, timing constraints |
| `rtl/` | the machine: `mw_core` (the board), `mw_main` (68000 map), `mw_video`, `mw_mixer`, `mw_sound`, renderers (`k056832_tilemap`, `k053247_*`), `k054539`, `k054321`, `er5911` (`rtl/data/` generated tables, `rtl/pll*` the clock PLL) |
| `target/mister/` | the memory subsystem (`mw_mem`, `rom_cache`, `ddr_arb`), SDRAM controller, memory test, Flip Screen |
| `modules/` | vendored TG68K.C, tv80 and CRT Adjust |
| `sys/` | the MiSTer framework (identical to Template_MiSTer) |
| `mra/` | the five MRAs, generated by `tools/make_mra.py` |
| `sim/` | Verilator benches: the whole machine (`run_mw.sh`), the MiSTer top level end to end (`emu/run_emu.sh`: loader check, fast load, raster, Scale, scandoubler, CRT Adjust, Flip Screen, EEPROM save path), lint |
| `tools/` | MRA generator, ROM image builder and checker (`mra_build.py`, `mw_rom.py`), the boot-skip patch for the benches, generators of `rtl/data` |
| `docs/` | `hardware.md`, `mister-memory.md` |

## Building

Quartus Prime Lite 17.0.2 (the version MiSTer's framework is built with):

```
quartus_sh --flow compile MysticWarriors
```

`python3 tools/make_mra.py mystwarr.zip` regenerates the MRAs. The simulation bench needs Verilator 5 and a C++ compiler,
and a ROM image you build yourself from your own romset (it checks every part's CRC):

```
python3 tools/mra_build.py "mra/Mystic Warriors (World ver EAA).mra" mystwarr.zip mystwarr.rom   # 15,990,784 bytes
python3 tools/mw_rom.py mystwarr.zip mystwarr.rom mystwarr                                       # against MAME's regions
BACKDOOR=1 SKIPBOOT=1 TRACE=1 SNAPEVERY=50 sim/run_mw.sh mystwarr.rom mystwarr.nv 600 out/mw
python3 tools/rgb2png.py out/mw.f600.rgb f600.png 2
```

## Credits

* **plasticbugs** -- the Gaiapolis core for the Analogue Pocket, the machine this one descends from (`rtl/`, the SDRAM
  controller `target/mister/sdram_ctrl.sv` and the memory test `mem_test.sv`, adapted; `tools/mra_build.py`), and through
  it the MAME team's work as the reference, **Tobias Gubener**'s TG68K.C (LGPL-3.0) and **Guy Hutchison**'s tv80 (MIT),
  vendored under `modules/`.
* **decoryah** -- the Violent Storm, Metamorphic Force and Monster Maulers cores for MiSTer this one is assembled from.
* **Claude** (Anthropic's AI model, used through Claude Code) -- the Mystic Warriors machine and MiSTer layer, written
  for the repository owner: the map and interrupts, the 5bpp renderers with z codes, the per-tile blending mixer, the ROM
  path and MRAs, the benches and this documentation.
* **The MAME team** -- `mystwarr.cpp` and the Konami device files: the reference for everything here.
* **Sorgelig** and the MiSTer team -- the framework (`sys/`, GPL).
* **rmonic79** (Umberto Parisi), with help from **Andrea Bogazzi** (asturur) --
  [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust), the module behind the CRT Adjust options
  (`modules/crt-adjust/crt_adjust.sv`; GPL-3.0 or later).
* **furrtek** -- [SiliconRE](https://github.com/furrtek/SiliconRE/tree/master/Konami)'s silicon-traced models and notes of
  the K053252 timing chip, the K054338 and K055555, through the cores above.
* **Jose Tejada (jotego)** -- JTFRAME's MiSTer SDRAM clock phase and read-capture timing, which this core's PLL and
  controller settings follow; and, with the other authors of the independent Konami cores read as references (jlrh's
  `konami-fpga`, which also has a Mystic Warriors core), the cross-checks of the Konami chips.

## Licence

Copyright (C) 2026 decoryah. GPL-3.0, as the cores this is built on (see `LICENSE`). The vendored TG68K.C (LGPL-3.0),
CRT Adjust (GPL-3.0 or later) and tv80 (MIT) in `modules/` keep their own licences, and the MiSTer framework in `sys/` is
GPL (see the headers of its files).
