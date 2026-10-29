## Mystic Warriors for MiSTer - 20261029

Konami's **Mystic Warriors** (1993, GX128 "pre-GX" hardware), the four-player ninja beat-'em-up, with five MRAs: World
(EAA), USA (UAA), Japan (JAA) and Asia (AAB, AAA).

**New: the Colours option, the board's video DAC curve.** Tested on a real MiSTer by the repository owner: it works.

### Install

1. Unzip `MysticWarriors_MiSTer_20261029.zip` over the root of the SD card. It adds the five MRAs to `_Arcade/` and
   `_Arcade/cores/mysticwarriors_20261029.rbf`. The MRAs are the same as in 20261019; MiSTer starts the newest dated
   RBF, so the older one can stay or go.
2. Put your own MAME 0.289 romset `mystwarr.zip` in `games/mame/` (or the clone zips next to it). No ROMs are included.
3. Start the game from the Arcade menu.

The OSD's version line reads `v261029`.

### What's new

- **OSD → Colours: Board DAC (the default) or MAME.** A real board's picture has darker, richer mid tones than MAME's:
  the K054338 colour chip outputs straight 8-bit values, but the board's K054573 DAC modules are conductance dividers,
  not linear ladders. Board DAC puts R, G and B through that circuit's curve (the model of the Gaiapolis core, the same
  chips; 0x40 becomes 21, 0x80 60, 0xC0 123, 0xFF stays 255). Fitted against a recording of a Mystic Warriors PCB (100
  frames matched one for one with MAME, 32 colours): the circuit is 1.8-2.0 of 255 off, MAME's straight line 2.8-4.3.
- **Fades as on the board.** The board's brightness sets the DAC current, so it scales the colour after the curve. With
  Board DAC the mixer blends the colours unscaled and the top level applies the frontmost pixel's brightness after the
  table, so the intro's fades keep the detail they have on the board.
- **MAME** is the picture of 20261019 exactly (the palette as MAME shows it). Use it with your own MiSTer gamma file if
  you prefer.
- Switch MiSTer's own gamma correction (Video processing) **off** with Board DAC, or the curve is applied twice.
- The picture and all video timing leave the core one pixel later than before (the DAC stage); geometry and raster are
  otherwise unchanged.

### Checked

- **On a real MiSTer:** this RBF with these MRAs, Board DAC included, tested by the repository owner: it works.
- **MAME mode is the old picture:** the MiSTer top level's fast load into the intro (250 frames) gives the 20261019
  picture byte for byte; the plain picture, CRT Adjust, forced scandoubler and HV-Integer with Full Screen keep their
  geometry and raster; the 15 attract frames of the frame bench stay pixel-identical to MAME 0.289.
- **Board DAC:** every channel of the same intro picture is the table's value (`sim/emu/dac_check.py`, 5,403 lit
  values, 0 off); on the intro's fades (brightness 0x77 and 0xD4) every pixel's unscaled colour times its brightness is
  MAME's pixel, 64,512 of 64,512.
- **Quartus 17.0.2:** 46 % of the ALMs (19,145), 519 of 553 M10K, 68 DSPs; every clock's slack positive (the 96 MHz
  core clock +0.611 ns setup, +0.245 ns hold). `releases/mysticwarriors_20261029.fit.summary` / `.sta.summary`.

Everything else (the game, the MRAs, the frame-for-frame comparison with MAME, the controls and the other OSD items) is
as in 20261019; see its notes and the README.

### Known differences / open points

- The DAC model is a model, not a measurement: the resistor values are those of Ace's reproduction module (the
  originals are sealed), the current comes from footage of unknown levels, and the K054574 is assumed linear. An
  oscilloscope on a real board's RGB output would settle it.
- The open points of 20261019 still hold (the play timeline from stage 1 up to two frames ahead of MAME, sprite codes
  past the 4 MB ROM read as blank, SHDPRISEL conditions 1 and 2 not modelled).

### Credits

plasticbugs' Gaiapolis core for the Analogue Pocket (the base of this core, and of the DAC model), Ace's 054573 /
054574 reproductions, Franck78's Gaiapolis schematic, furrtek's SiliconRE, MAME, TG68K.C, tv80, rmonic79's CRT Adjust,
Jose Tejada's JTFRAME SDRAM timing notes, jlrh's konami-fpga as a reference, and the MiSTer framework.
