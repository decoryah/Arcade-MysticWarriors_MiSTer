## Mystic Warriors for MiSTer - 20261019

Konami's **Mystic Warriors** (1993, GX128 "pre-GX" hardware), the four-player ninja beat-'em-up, with five MRAs: World
(EAA), USA (UAA), Japan (JAA) and Asia (AAB, AAA).

**First build. Not yet tested on a real MiSTer.** It was compiled with Quartus 17.0.2 and checked in simulation (below);
please treat it as a test build until it has been run on a board.

### Install

1. Copy `releases/mysticwarriors_20261019.rbf` to `_Arcade/cores/` and the five `.mra` files from `mra/` to `_Arcade/` on
   the SD card.
2. Put your own MAME 0.289 romset `mystwarr.zip` in `games/mame/`. The merged set holds all versions; the clone zips
   (`mystwarru.zip`, `mystwarrj.zip`, `mystwarra.zip`, `mystwarraa.zip`) work next to the parent. No ROMs are included.
3. Start the game from the Arcade menu. The ROM image is about 15 MB: with a recent Main_MiSTer it is copied to the DDR3
   in one go (the MRAs' `address=` attribute), with an older one it is streamed. The game's own power-on RAM / ROM check
   then runs, as on the board.

### Checked

- **ROM path:** `tools/mw_rom.py` rebuilds MAME's memory regions from the zip by MAME's own loading rules
  (`ROM_LOADTILE_WORD`, `ROM_LOAD64_WORD`, ...) and compares them with the image each MRA builds: all five sets
  identical in every region.
- **The whole machine in Verilator** (`sim/run_mw.sh`), the real 68000 and Z80 programs from reset behind the MiSTer
  memory subsystem: the game's own power-on **ROM RAM CHECK passes every item** (RAMs, program and sound ROMs, EEPROM);
  the intro ("Beware of 'SKULL' enterprise on!", the red flash and the fade, the dusk city and the Skull castle with its
  parallax); a coin and the title screen with the five ninjas, whose text rows and HUD frames sit at exactly the pixels
  of MAME's snapshots of the game; the interrupts (IRQ2 / IRQ4 enabled by the game through the IRQ control byte, taken
  every frame); the music in stereo from the first second; over 900 frames, 1.68 M tile and 27,280 sprite ROM reads
  compared with the image (0 wrong) and no renderer overrun.
- **The MiSTer top level end to end** (`sim/emu/run_emu.sh`, the framework's own video path): the fast load replayed from
  the DDR3 and every one of the 7.47 M SDRAM words compared with the image (0 wrong), the frame period exactly
  1,622,016 clocks (59.1856 Hz), 224 rows of 288 pixels, the EEPROM read back through the save path.
- **Quartus 17.0.2:** 46 % of the ALMs (19,118), 519 of 553 M10K, 65 DSPs; every clock's slack positive (the 96 MHz
  core clock +0.629 ns setup, +0.245 ns hold; the tightest, +0.274 ns, is in the framework's HDMI scaler).
  `releases/mysticwarriors_20261019.fit.summary` / `.sta.summary`.

### OSD

Aspect ratio, Scale, Flip Screen, Scandoubler Fx, CRT Adjust (rmonic79's module: H-Size, H-Position, V-Shift), Number of
Players (2 or 4), Coin Mechanism, Audio (stereo / mono), Test Mode, Diagnostic overlay, SDRAM read capture, Reset. See the
README.

### Known differences / open points

- No frame-for-frame comparison with MAME yet (no MAME was at hand for this build).
- Tile blending follows the current MAME (each tile with its own mix code), not MAME 0.289's rule.
- SHDPRISEL's shadow conditions 1 and 2 are not modelled.

### Credits

plasticbugs' Gaiapolis core for the Analogue Pocket (the machine the Monster Maulers, Metamorphic Force and Violent Storm
cores, and so this one, are built on), MAME, TG68K.C, tv80, rmonic79's CRT Adjust, furrtek's SiliconRE, Jose Tejada's
JTFRAME SDRAM timing notes, jlrh's konami-fpga as a reference, and the MiSTer framework.
