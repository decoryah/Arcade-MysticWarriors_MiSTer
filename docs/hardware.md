# Mystic Warriors -- Konami "pre-GX" hardware (GX128)

Source of truth: MAME `src/mame/konami/mystwarr.cpp` (machine `mystwarr`, sets `mystwarr`, `mystwarru`, `mystwarrj`,
`mystwarra`, `mystwarraa`), `mystwarr_v.cpp`, `konamigx_v.cpp` and the device files named below, read at MAME 0.289
and at the current master (which changed the tile blending this game needs, section 4); SiliconRE (furrtek) for the
K053252's timing and the K054338 / K055555 notes, through the Monster Maulers and Violent Storm cores that were built
on them. The 68000 program was read for the K053252 values and the interrupt vectors. The machine is the Violent Storm
core's (itself Metamorphic Force's, Monster Maulers', the Gaiapolis core's) with Monster Maulers' 5bpp graphics and
6 MHz raster, and this game's map, interrupts and tile blending.

## 1. Board

| | |
|---|---|
| Game | Mystic Warriors (EAA / UAA / JAA / AAB / AAA), Konami 1993 |
| Board | GX128 PWB353366A/B, the "pre-GX" family it shares with Violent Storm, Monster Maulers, Metamorphic Force, Martial Champion, Gaiapolis |
| Main CPU | MC68000 @ 16.000 MHz (32 MHz / 2) |
| Sound CPU | Z80 @ 8.000 MHz (32 MHz / 4) |
| Sound | 2 x K054539 @ 18.432 MHz, stereo (+ K054321 latch / master volume, in the 054986A module) |
| EEPROM | ER5911, 128 x 8 |
| Display | 288 x 224 visible, ROT0, 6 MHz pixel clock (K053252 fed 24 MHz, /4), 384 x 264 -> 15.625 kHz, 59.1856 Hz |
| Palette | 2048 entries, xRGB_888, shadows + highlights |
| ROM | 1.5 MB program (0.5 MB + 1 MB), 128 KB sound program, 2.5 MB tiles (5bpp), 5 MB sprites (5bpp), 4 MB PCM |

MAME's PCB notes give the measured syncs as 15.2042 kHz and 59.1879 Hz; the chip's programming (below) gives
15.625 kHz and 59.1856 Hz, which is also MAME's frame rate.

### Raster

The K053252 is programmed once at boot, by the reset code at `$001036`: registers 0/1 = `0x017F` (H max),
2/3 = `0x0012` (HFP), 4/5 = `0x002E` (HBP), 8/9 = `0x0107` (V max), 10 = `0x11` (VFP), 11 = `0x0E` (VBP),
12 = `0x73` (sync widths). With the relations the Monster Maulers and Violent Storm cores took from SiliconRE's model
of the chip (both games' values reproduce their numbers):

* 384 pixels x 264 lines, 15.625 kHz, 59.1856 Hz;
* hblank 96 pixels (HFP + HBP + hsync), hsync 32 pixels (8 x (HSW + 1)) starting 17 pixels (HFP - 1) after the
  picture ends;
* vblank 40 lines (16 before the picture, 24 after it), vsync 8 lines (VSW + 1) starting 17 lines (VFP) after
  vblank starts, so it wraps over the frame's end.

That is Monster Maulers' horizontal timing with the sync 7 pixels earlier, and Violent Storm's vertical timing. The
picture is at x 24, y 16 of the raster (MAME's visible area is (24, 16) - (311, 239), `set_offsets(24, 16)`).

MAME's raster is the chip's. The driver sets `set_raw(6 MHz, 384, ..., 264)` and then `set_size(512, 256)`, but that
256-line frame lasts only until the game programs the K053252 at boot: `k053252_device::res_change` then sets the
screen to the chip's 384 x 264 raster with the picture at (24, 16). From there MAME's scanline N is raster line N here,
which measurements in MAME 0.289 confirm (`tools/lua/input_reads.lua`: the IRQ4 vector fetched 3 us into the frame, the
IRQ2 vector 15,363 us = line 240, the frame update 15,960 us). So IRQ2 is at raster line 240, IRQ4 at raster line 0, and
the frame update (vblank end: `set_vblank_time(600 us)` after vblank start, 3,600 pixel periods) at line 249, pixel 144
(`mw_core` parameters). (Until 2026-10-19 the core assumed the 256-line frame and put them at lines 247, 263 + half a
line and 261: section 8.)

## 2. Custom chips

| Chip | Function | Here |
|---|---|---|
| K056832 (+ K054156) | tilemap generator, 4 layers over a 4 x 4 grid of 64 x 32 tile pages | `K056832_BPP_5`; `mystwarr_tile_callback`; layer offsets (-5, -3, -1, 0) |
| K055673 (+ K053246A) | sprite generator (K053246/7 family) | `K055673_LAYOUT_GX` (5bpp), offsets (-48, -24), z codes honoured; `mystwarr_sprite_callback` |
| K055555 | priority encoder / layer mixer | 4 tile layers + OBJ (there is no SUB1 plane) |
| K054338 | alpha / shadow / brightness colour stage | backdrop, 3 shadow tables, 3 brightness codes, 3 mix levels; alpha inverted |
| K053252 | CRTC | timing above |
| K054321 | main <-> sound latches, master volume | as Gaiapolis |
| ER5911 | serial EEPROM | as Gaiapolis, on the high byte |

There is no protection or helper chip (no K055550, K054000 or K053990), no K053936 and no K053250.

## 3. Main CPU memory map (`mystwarr_map`)

| Range | | Function |
|---|---|---|
| `000000-1FFFFF` | R | program ROM: `000000-07FFFF` the 01/02 pair (version-specific), `080000-0FFFFF` empty (reads 0), `100000-1FFFFF` the 03/04 pair |
| `200000-20FFFF` | RW | work RAM |
| `400000-40FFFF` | RW | sprite RAM through the K053247's scattered window (as Gaiapolis / Monster Maulers: word w of the chip at `400000 + ((w & 0x7f8) << 5) + (w & 7) * 2`, the rest plain RAM) |
| `480000-4800FF` | W | K055555 |
| `482000-48200F` | R | K055673 ROM read-back (5bpp, `k055673_5bpp_rom_word_r`) |
| `482010-48201F` | W | K055673 registers |
| `484000-484007` | W | K053246 registers |
| `48A000-48A01F` | W | K054338 |
| `48C000-48C03F` | W | K056832 VACSET |
| `490000` | W | EEPROM: DI / CS / CLK on bits 8 / 9 / 10 (the high byte) |
| `492000` | W | watchdog |
| `494000`, `494002` | R | `P1_P2`, `P3_P4` (player 1 / 3 in the low byte, 2 / 4 in the high) |
| `496000` | R | `IN0`: coins 1-4 (bits 3:0) |
| `496002` | R | `IN1` (low byte; a high-byte-only read gives 0): EEPROM DO (bit 0) / READY (bit 1), test (bit 2, low = on), bit 3 must read 0, SW1 (bits 7:4) |
| `498000-49801F` | RW | K054321 (low byte) |
| `49A000` | W | sound IRQ (Z80 IRQ0) |
| `49C000-49C01F` | RW | K053252 (low byte) |
| `49E000-49E007` | W | K056832 VSCCS; the low byte of `49E006` is also the IRQ control byte |
| `600000-601FFF` | RW | K056832 tile RAM window (8 KB; 16 pages behind regs[0x19]); `602000-603FFF` the same again |
| `680000-683FFF` | R | K056832 ROM read-back (`mw_rom_word_r`, 16 KB: two 2048-group banks; bank `regs[0x1a] | regs[0x1b] << 16` mod 640, the first 256 hold the ROM) |
| `700000-701FFF` | RW | palette, 2048 x 32 bit (00RR GGBB) |

### Interrupts (`mystwarr_interrupt`)

Two autovectored levels, both `HOLD_LINE`, raised only while bit 0 of the IRQ control byte (`49E007`) is set (the reset
code writes `0xD0` there, with the bit clear, and the game sets it once it is ready): IRQ2 at line 240 (vblank start,
handler `$002812`; it reads the controls about 136 us in) and IRQ4 at line 0 (handler `$00346A`). A raised level is held until the 68000 acknowledges that
level. The level 6 vector (`$003488`) exists but MAME does not raise it ("almost likely not really necessary").

### Inputs

`P1_P2` / `P3_P4`: each byte a player: bit 0 left, 1 right, 2 up, 3 down, 4-6 buttons 1-3, 7 start (active low).
The game uses buttons 1 and 2 only: its I/O CHECK (the strings at `$056400`) lists LEFT, RIGHT, UP, DOWN, SHOOT, JUMP,
START and SERVICE per player. MAME wires three buttons (`KONAMI16_LSB(n, IPT_BUTTON3, ...)`), the harness's generic
layout; the core offers Shoot and Jump and holds bit 6 released.
`IN1` SW1: bit 4 sound output (1 = mono), bit 5 coin mechanism (1 = common), bit 6 number of players (1 = 2, 0 = 4),
bit 7 unused.

## 4. Video

### Tiles (K056832, 5bpp)
Pages are 64 x 32 tiles of 8 x 8; a layer takes a rectangle of pages from the 4 x 4 grid (regs 8-15: start page and
span - 1, in pages).

ROM: `ROM_LOADTILE_WORD x2` + `ROM_LOADTILE_BYTE` give 5-byte groups per 8-pixel row: bytes 0-3 are packed chunky
(byte k = pixels 2k, 2k+1, high nibble first) and byte 4 is bit 4 of each of the 8 pixels (pixel 0 in bit 7). Pixel
value = `{plane5, nibble}`. The same ROM sizes and loading as Monster Maulers.

`mystwarr_tile_callback`: `color = layer_colorbase | (color >> 1 & 0x0f)`, `priority = attr >> 2 & 3` (the tile's
category). The gfx granularity is 16, so the palette entry is `(color * 16 + pixel) mod 2048`: a 5-bit pixel reaches
into the next colour unit. Per-layer x offsets (VIDEO_START mystwarr): -5, -3, -1, 0.

**Tile blending.** "Mystic Warriors requires tile based blending" (MAME). The tile's mix code (attribute bits 3:2) is
its category, and the current MAME (`gx_draw_basic_tilemaps`, after 0.289) draws each category with the K054338 level
of the code `(category & ~V_INMIX_ON) | (V_INMIX & V_INMIX_ON)`: every tile blends with its own code, and with
V_INMIX_ON all set every tile takes V_INMIX's. MAME 0.289 instead drew every tile with a non-zero code at the level of
the *last* such code the callback had seen in the frame, which the Violent Storm core reproduces; this core follows the
newer, per-tile rule. Each pixel carries its tile's code from the tilemap to the mixer.

### Sprites (K055673 GX layout, 5bpp)
Entry format as Gaiapolis (8 words, 256 entries). `mystwarr_sprite_callback`: `priority_mask = color & 0xe0`,
`color = (K055555 palette index(4) << 5) | (color & 0x1f)`, mix code = attribute bits 9:8. 5bpp layout: the four
low planes are the first 4 MB of the ROM (one 64-bit word a 16-pixel row, left 8 pixels in bytes 0-3, right 8 in
bytes 4-7) and the fifth plane is the 1 MB after it (a 16-bit word a row: high byte left 8 pixels, low byte right 8).
Colour unit 32 entries, so the entry is `{color[5:0], pen[4:0]}`; the shadow pen is 31 (1 for a "full shadow"
object). `konamigx_mixer_primode` is not set: sprites keep their z codes (the Violent Storm drawer's Z buffer).

Zoom: `k053247_draw_single_sprite_gxcore` takes a zoom register `z` (10 bits) to the factor `(0x400000 + z / 2) / z`,
and `z = 0` to 0x800000, so a cell can be 2,048 pixels across (`zw = ((Z * (x + 1) + 2048) >> 12) - ((Z * x + 2048)
>> 12)`, up to 2,048) and a sprite of 8 cells 16,384. The game draws its full-screen hazes and fades that way (one
8 x 4 sprite at zoom 0 over the castle at dusk, attract frames ~2,700-2,900): the drawer's cell accumulators are
27 bits, the offsets into a cell 11, and a 2,048-pixel cell takes the stride 0x1000 directly (the reciprocal table
stops at 2,047).

### Mixer (`konamigx_mixer`, K055555 + K054338)
As Monster Maulers' (`docs/hardware.md` there) without the SUB1 plane, with the tile layers' mix code taken per pixel
(above) and the additive mode as the current MAME has it: an additive mix code's level is not inverted
(`k054338_device::set_alpha_level`), a sprite adds `s * a >> 8` and a tile `s * (a + 1) >> 8`, clamped.
Brightness, shadows and the tie order are Monster Maulers'.

### Sprite list timing
MAME takes the sprite list at its screen update (vblank end, `VIDEO_UPDATE_AFTER_VBLANK`); the core copies the sprite
RAM at that instant, raster line 249, pixel 144 (section 1), and builds the list from the copy, as the Violent Storm core
does.

## 5. Sound

As Gaiapolis (`docs/hardware.md` of that core): Z80 with ROM banks at `8000-BFFF` (regs `F800` bits 3:0), the
K054539s at `E000-E22F` and `E400-E62F`, K054321 at `F000-F003`, timer NMI gated by `F800` bit 4. The sound ROM is
128 KB, loaded twice (`ROM_RELOAD`) to fill the 256 KB bank space. `MACHINE_RESET mystwarr`: chip 1 channels 0-3
("chorus") x0.8, channels 4-7 ("voice") x2.0, chip 2 all channels ("percussion") x0.5.

## 6. ROM image and MRAs

`tools/make_mra.py` writes the five MRAs from MAME's `mystwarr.zip`; `tools/mra_build.py` builds the image an MRA
describes; `tools/mw_rom.py` rebuilds MAME's regions from the zip by MAME's own loading rules and compares them with
that image, region by region (all five sets: identical). Layout in the MRA header and `docs/mister-memory.md`.

## 7. Tools

| | |
|---|---|
| Quartus | 17.0.2 Lite |
| Verilator | 5 (oss-cad-suite in WSL) |
| Python | 3 (WSL), for the MRA and image tools and the comparisons |
| MAME | 0.289 (the official Windows build), run by `tools/mame_run.ps1` with the probes of `tools/lua/` |

## 8. Verification against MAME 0.289

### The probes and benches

* `tools/lua/dump_state.lua` freezes MAME frames: the write-only registers through write taps (K056832 `48C000`,
  VSCCS `49E000`, K053246 `484000`, K055673 `482010`, K055555 `480000`, K054338 `48A000`), the palette, the sprite
  RAM through the scattered window, all 16 tile RAM pages (after the snapshot: the bank register is cycled and put
  back), optionally the work RAM, and MAME's own snapshot of that frame (`tools/make_corpus.ps1`: `state_N.txt` +
  `snap_N.png`). `SKIPBOOT=1` applies `tools/skipboot.txt` (read taps), the system bench's shortcut over the power-on
  check; `SCHEDULE=play|survey` the system bench's scripted inputs, frame for frame.
* `sim/run_frames.sh` (`sim/tb_frame*`): the video pipeline as `mw_core` wires it (tilemap with its row cache, list
  builder, drawer with its scheduler and row cache, mixer) loaded with a frozen state and rendered line by line, then
  compared with the snapshot (`tools/cmp_frame.py`). Two passes, the second written (the mixer's brightness carries
  over from the frame before, as in the machine).
* The system bench (`sim/run_mw.sh`, the whole machine from reset) with `DUMPLINE=249:144` dumps the same state at
  raster line 249, pixel 144, the instant of MAME's frame update and of its frame notifier (MAME's screen is
  `VIDEO_UPDATE_AFTER_VBLANK`: the update, the notifier and the Lua dump are at vblank end, section 1), and
  `SCHEDLINE=249:144` applies the scripted inputs there, where the probe's notifier sets them; `RDLOG=n` logs where
  in the frame the game reads its controls. `tools/cmp_state.py` compares two states, `tools/cmp_lag.py` finds the
  frame lag between the bench and a range of MAME states, `tools/lua/input_reads.lua` times MAME's frame notifier and
  the game's control reads.
* `tools/mixcodes.py` and `tools/lua/watch_mix.lua` (every frame) list the blending features a run uses;
  `tools/lua/stage_poke.lua` starts a game in a later stage: the byte at `$200300` is the stage (0 the city, 1 the snow
  mountain, 2 the cave, 3 the river, 4 the jungle, 5 the mine, 6 the airliner, 7 the city at night), written from the
  start button to before the stage is set up.

### Frame alignment

With SKIPBOOT on both sides and the same EEPROM (MAME's own, initialised on a first run, given to both), the system
bench's state at raster line 249, pixel 144 after its N-th frame equals MAME's state at its N-th frame notifier in
every word (registers, palette, sprite RAM, all 16 tile RAM pages): **lag 0**. Frame 300 (a palette fade) matches
MAME's frame 300 and neither neighbour. The bench's picture N + 1, scanned out after that instant, equals MAME's
snapshot N.

Scripted inputs: a value the probe sets in its frame notifier reaches the game a frame later than the bench's
`SCHEDLINE` does (MAME's input ports take their new values in its own frame notifier, which runs before the
probe's), so a play run is compared with MAME run with `SCHEDLAG=-1` (the schedule a frame earlier); then it is lag 0
as well. Without it the bench's frame N equals MAME's N + 1. The game reads its controls in the IRQ2 handler, at
raster line 242 in both (MAME 15,499 us into the frame; the bench line 242, pixels 64-120), well before the inputs
change.

The interrupts. Timed in MAME (section 1), IRQ2 is at line 240 and IRQ4 at line 0 of the board's raster; the core
had them at lines 247 and 263 + half a line, and took the sprite list at line 261, from a 256-line reading of MAME's
screen that the K053252 replaces at boot. Corrected (`mw_core` parameters); the attract mode is lag 0 with either, the
corrected placement is MAME's.

### Results

| Corpus (MAME 0.289, `mystwarr`) | Frames | Pixel-identical |
|---|---|---|
| Attract mode, frames 60-6,000 every 60 (intro, title, castle at dusk with the zoom-0 haze, the first demo) | 100 | 100 |
| Attract mode, frames 6,000-40,000 every 250 (four demo cycles: the snow mountain and the jungle) | 137 | 137 |
| Scripted play, frames 600-20,000 every 200 (select, stage 1, its boss, the continue screen, stage 2) | 98 | 98 |
| Scripted play, frames 15,000-72,000 every 500 (stage 2 and its boss, later stage 1 again) | 115 | 115 |
| Stages 3-8 through `$200300` = 2-7, frames 1,500-20,000 every 500 each | 228 | 228 |

Before the zoom fix (section 4) attract frames 2,820 and 2,880 differed (the right half of the haze missing); every
other frame was identical with the build as it was. With the line budget enforced (`REALTIME=1`: each line gets the
6,144 clocks the raster gives it) and the memories answering late (`+LAT_TROM=34 +LAT_SROM=48 +LAT_VRAM=4`) all 678
frames are still identical, with no line late.

Whole machine (`sim/run_mw.sh`, SKIPBOOT, the backdoor load, the corrected interrupts): the attract mode to frame
905, the state at 60, 120 ... 900 equal to MAME's in every word and each following picture identical to MAME's
snapshot (15 of 15); IRQ2 and IRQ4 in every frame once the game enables them, no line overran. Scripted play to frame
1,505: coin, start, the ninja select and the story scene equal to MAME's at every compared frame from 300 to 1,130
(states and pictures). Then the core runs ahead: at the start of stage 1 the game unpacks data for about five frames
(the loop at `$25634`; MAME's 68000 is busy from frame 1,139 to 1,144) and the core finishes a frame earlier, so
from frame 1,140 its scroll and sprites are up to two frames ahead of MAME's and the play runs differ from there. The
68000's speed elsewhere agrees with MAME's: the idle loop (`$1BA4`) turns 4,319 / 6,678 times a frame in the core
where MAME's turns 4,261 / 6,648 (+0.5 to +1.7 %). An instruction-level comparison of that loop's timing (the core's
TG68K is paced at 16 clocks a bus step, 8 an internal one) is open.

### What the corpora cannot tell apart

MAME 0.289 and the current MAME (whose rules `mw_mixer` follows) differ where tiles of different non-zero mix codes are
in one layer (0.289 blends them all at the last code its tile callback saw), on additive mix codes (0.289 inverts their
level and blends instead of adding) and on sprites with mix codes. `tools/lua/watch_mix.lua` over 20,000 frames of
scripted play in each of the eight stages and 42,000 frames of the attract mode found none of the three: the game uses
tile mix code 1 only (fades; V_INMIX 0 and V_INMIX_ON 0xF3, 0x3F or 0) and no sprite mix codes, so the two rules
give the same picture everywhere the scripted inputs reach. SHDPRISEL's conditions 1 and 2 (current MAME) are unused
too: SHDPRISEL is 0x3F (condition 3 for all three shadows) in all 93 corpus frames with shadow sprites.
