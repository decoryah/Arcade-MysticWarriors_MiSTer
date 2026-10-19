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
  compared with the image (0 wrong) and no renderer overrun. With scripted inputs: coin, start, SELECT NINJA, the
  story scene in the dojo and the start of stage 1 (the BMR street, the player blinking in, shuriken and a crate
  broken; 1,300 frames, no overrun). The service menu's **MASK ROM CHECK passes all twelve ROMs**: the tile ROMs 1H, 1K,
  3H, the sprite ROMs 10K, 12K, 17K, 19K, 20K, 22K and the PCM ROMs 1D, 2D, each read back through the board's ROM
  windows against the checksums in the game's program (3,300 frames).
- **The MiSTer top level end to end** (`sim/emu/run_emu.sh`, the framework's own video path): the fast load replayed from
  the DDR3 in 0.65 s and every one of the 7.47 M SDRAM words compared with the image (0 wrong), the frame period exactly
  1,622,016 clocks (59.1856 Hz), 224 rows of 288 pixels, the EEPROM read back through the save path; every Scale mode
  at 1080p and 4K and with Full Screen (the size asked of the scaler equal to the framework's rule), HQ2x, CRT 25 % and
  forced_scandoubler (448 rows in 528 lines a frame, so the scandoubler's output has frames), CRT Adjust at zero
  identical to CRT Adjust off and with amounts a whole frame period.
- **The picture against MAME 0.289, frame for frame:** 678 of 678 frames pixel-identical to MAME's snapshots of the same
  frames (MAME's chip state dumped by a Lua probe and rendered by the core's video pipeline): the attract mode with its
  four demo cycles, scripted play through stages 1 and 2 with their bosses and the continue screen, and sampled frames
  of the other six stages. The whole machine's chip state equals MAME's at the same frame in every register and RAM
  word (lag 0) at attract frames 60, 120 ... 900. The comparison found one bug, fixed in this build: a sprite zoom
  register of 0 (cells 2,048 pixels across, the full-screen haze over the castle at dusk) overflowed the sprite drawer.
- **Quartus 17.0.2:** 45 % of the ALMs (19,065), 519 of 553 M10K, 65 DSPs; every clock's slack positive (the 96 MHz
  core clock +0.696 ns setup, +0.245 ns hold; the tightest, +0.392 ns, is in the framework's HDMI scaler).
  `releases/mysticwarriors_20261019.fit.summary` / `.sta.summary`.

### Controls

Two buttons, **Shoot** and **Jump** (A and B on a gamepad by default), Start and Coin, up to four players: the game's
own I/O CHECK lists LEFT, RIGHT, UP, DOWN, SHOOT, JUMP and START for each player. The board's third button input is read
by nothing, so the core and the MRAs do not offer it. Keyboard: 1-4 start, 5-8 coin, F2 the test switch.

### OSD

Aspect ratio, Scale, Flip Screen, Scandoubler Fx, CRT Adjust (rmonic79's module: H-Size, H-Position, V-Shift), Number of
Players (2 or 4), Coin Mechanism, Audio (stereo / mono), Test Mode, Diagnostic overlay, SDRAM read capture, Reset. See the
README.

### Known differences / open points

- The comparison with MAME covers what scripted inputs reach: one player, the bosses of stages 1 and 2, sampled
  frames of every stage. Later bosses, the ending and play with two to four players are not in it.
- Tile blending follows the current MAME (each tile with its own mix code), not MAME 0.289's rule; the game uses tile mix
  code 1 only and no sprite or additive mix codes, so the two rules give the same picture everywhere the comparison
  reached.
- SHDPRISEL's shadow conditions 1 and 2 are not modelled; the game does not use them (SHDPRISEL is 0x3F in every
  compared frame with shadows).

### Credits

plasticbugs' Gaiapolis core for the Analogue Pocket (the machine the Monster Maulers, Metamorphic Force and Violent Storm
cores, and so this one, are built on), MAME, TG68K.C, tv80, rmonic79's CRT Adjust, furrtek's SiliconRE, Jose Tejada's
JTFRAME SDRAM timing notes, jlrh's konami-fpga as a reference, and the MiSTer framework.
