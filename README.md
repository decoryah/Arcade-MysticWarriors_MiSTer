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

The game has two buttons, **Shoot** (the attack: thrown shuriken or daggers, the hand weapon up close) and **Jump**: the game's own I/O CHECK lists
LEFT, RIGHT, UP, DOWN, SHOOT, JUMP and START for each player, and the board's third button input is read by nothing, so
the core does not offer it. On a gamepad the default mapping is A for Shoot, B for Jump, Start for Start and Select for
Coin; up to four joysticks. From the keyboard: 1-4 start, 5-8 coin and F2 for the test switch.

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
| Video against MAME 0.289 | **678 of 678 frozen-state corpus frames pixel-identical** to MAME 0.289's snapshots of the same frames: the attract mode (the intro, the title, the castle at dusk with its full-screen haze, four demo cycles on the snow mountain and in the jungle), scripted play through stage 1, its boss, the continue screen and stage 2 (to frame 72,000), and the other six stages entered through the game's stage byte. MAME's chip state is dumped by `tools/lua/dump_state.lua` and rendered by the video pipeline in `sim/run_frames.sh` (`docs/hardware.md`, section 8). Also with the line budget enforced and the ROMs answering 34 / 48 clocks late: identical, no late line. The comparison found one bug, fixed: sprites at zoom register 0 (2,048-pixel cells, the haze) |
| Whole machine against MAME 0.289 | The system bench's chip state at raster line 249, pixel 144 (the instant of MAME's frame update) equals MAME's at the same frame in every register, palette, sprite RAM and tile RAM word, **frame for frame (lag 0)**, and its next picture equals MAME's snapshot: the attract mode at frames 60, 120 ... 900, and scripted play (coin, start, the ninja select, the story scene) from frame 300 to 1,130. The comparison moved IRQ2, IRQ4 and the sprite list's instant to MAME's raster lines (240, 0 and 249) |
| Whole machine | `sim/run_mw.sh`: the real 68000 and Z80 programs from reset through `mw_mem`, the SDRAM controller and a behavioural SDRAM. The game's own power-on **ROM RAM CHECK passes every item** (the RAMs, the program and sound ROMs, the EEPROM: "VER. EA A"), then the intro ("Beware of 'SKULL' enterprise on!", its red flash and fade, the dusk city and the Skull castle with its parallax scroll) and, with a coin from the scripted inputs, the title screen with the five ninjas. The title screen's text rows and the HUD (1UP / HIGH SCORE / 2UP frames and digits) sit at exactly the pixel rows and columns of MAME's snapshots of the game. Over 900 frames: 1.68 M tile and 27,280 sprite ROM reads by the renderers compared with the image, 0 wrong; no line overran; IRQ2 and IRQ4 in every frame once the game enables them; the music plays in stereo from the first second. With scripted inputs: coin, start, the SELECT NINJA screen, a ninja chosen, the story scene in the dojo that follows and the start of stage 1 (the BMR street with its START banner and the 1UP arrow, the player blinking in on alternate frames, shuriken thrown and a crate broken; 1,300 frames, no line overran). The service menu (test switch): the MAIN MENU, and its **MASK ROM CHECK reports all twelve ROMs OK**: the tile ROMs 1H, 1K and 3H read through the K056832's ROM window at `680000` (both its modes and the bank register), the sprite ROMs 10K, 12K, 17K, 19K, 20K and 22K through the K055673's window at `482000` (this board's 4 MB + 1 MB layout), and the PCM ROMs 1D and 2D, each against the checksums in the game's program (3,300 frames) |
| MiSTer top level | `sim/emu/run_emu.sh`: `MysticWarriors.sv` itself with the framework's video path: the fast load replayed from the DDR3 and all 7.47 M SDRAM words compared with the image (0 wrong), frame period exactly 1,622,016 clocks (59.1856 Hz), 224 rows of 288 pixels starting 79 pixels after the hsync pulse, the EEPROM read back through the save path. Every Scale mode asks the scaler for the size the framework's rule gives (at 1080p V-Integer 1194 x 896, HV-Integer and Narrower 1152 x 896, HV-Integer+ 1440 x 896; at 4K 2592 x 2016 and 2880 x 2016; HV-Integer with Full Screen 1728 x 896); with HQ2x, CRT 25 % and MiSTer.ini's forced_scandoubler the monitor gets 448 rows in 528 lines a frame (CRT 25 % and forced_scandoubler hand the scaler the plain picture unchanged, HQ2x its filtered one); CRT Adjust at zero gives the picture and raster of CRT Adjust off, byte for byte, and with amounts set the frame period stays whole |
| Quartus | Quartus Prime Lite 17.0.2 compiles the project for the 5CSEBA6U23I7: 46 % of the ALMs (19,131), 519 of 553 M10K, 65 DSPs; every clock's slack positive (the 96 MHz core clock +0.811 ns setup / +0.242 ns hold; `releases/*.summary`) |

## Known differences / open points

* Not yet tested on a real MiSTer.
* In play, the whole machine stays frame-exact with MAME only until stage 1 starts: the game's five-frame unpacking of
  the stage takes the core's 68000 a frame less than MAME's, and from there the core is up to two frames ahead (its
  68000 otherwise runs within 2 % of MAME's speed; `docs/hardware.md`, section 8). The pictures of every state are
  identical to MAME's (the corpus above); it is the game's timeline that drifts.
* The frame-for-frame comparison with MAME 0.289 (above) covers what the scripted inputs and the stage byte reach: one
  player with the default ninja, the bosses of stages 1 and 2, sampled frames of every stage. Later bosses, the ending
  and play with two to four players are not in the corpus.
* The whole machine (the real 68000 and Z80 programs) has been simulated only into the start of stage 1; later play is
  covered by the frozen-state comparison of the video chips with MAME, not by the machine running it.
* The tile blending follows the current MAME (each tile with its own mix code), not 0.289's; the additive mode
  likewise (`docs/hardware.md`, section 4). Nothing the corpora and a per-frame watch of every stage reach tells the
  two apart: the game uses tile mix code 1 only, and no sprite mix codes or additive codes (`docs/hardware.md`,
  section 8).
* SHDPRISEL's shadow conditions 1 and 2 (the "topmost screen" comparison the current MAME added) are not modelled; the
  game does not use them (SHDPRISEL is 0x3F in every corpus frame with shadows).

## Repository layout

| Path | |
|---|---|
| `MysticWarriors.sv`, `MysticWarriors.q*`, `MysticWarriors.sdc`, `files.qip` | the MiSTer top level (`emu`), Quartus project, timing constraints |
| `rtl/` | the machine: `mw_core` (the board), `mw_main` (68000 map), `mw_video`, `mw_mixer`, `mw_sound`, renderers (`k056832_tilemap`, `k053247_*`), `k054539`, `k054321`, `er5911` (`rtl/data/` generated tables, `rtl/pll*` the clock PLL) |
| `target/mister/` | the memory subsystem (`mw_mem`, `rom_cache`, `ddr_arb`), SDRAM controller, memory test, Flip Screen |
| `modules/` | vendored TG68K.C, tv80 and CRT Adjust |
| `sys/` | the MiSTer framework (identical to Template_MiSTer) |
| `mra/` | the five MRAs, generated by `tools/make_mra.py` |
| `sim/` | Verilator benches: the whole machine (`run_mw.sh`), the frozen-state frame bench (`run_frames.sh`: the video pipeline from a MAME state, against MAME's snapshot), the MiSTer top level end to end (`emu/run_emu.sh`: loader check, fast load, raster, Scale, scandoubler, CRT Adjust, Flip Screen, EEPROM save path), lint |
| `tools/` | MRA generator, ROM image builder and checker (`mra_build.py`, `mw_rom.py`), the boot-skip patch for the benches, the MAME probes (`lua/`) and runners (`mame_run.ps1`, `make_corpus.ps1`), the comparisons (`cmp_frame.py`, `cmp_state.py`, `cmp_lag.py`, `mixcodes.py`), generators of `rtl/data` |
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

MAME 0.289 is run by `tools/mame_run.ps1` with the probes of `tools/lua/` (the paths of MAME, its ROMs and a work
directory are its parameters); `tools/make_corpus.ps1` makes a corpus of frozen states with MAME's snapshots, and
`sim/run_frames.sh` renders it and compares:

```
tools/make_corpus.ps1 -Dir C:\work\states_play -Frames 600,800,1000 -Schedule play
sim/run_frames.sh /mnt/c/work/states_play mystwarr.rom
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
