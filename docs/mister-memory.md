# The MiSTer memory partition

The machine (`rtl/mw_core.sv`) sees five ROM ports and a tile RAM port, all level request / one-cycle ack. What sits behind
them is `target/mister/mw_mem.sv`, the Violent Storm core's memory system (itself Metamorphic Force's, Monster Maulers',
the Gaiapolis core's; `docs/mister-memory.md` of gaiapolis-mister has the reasoning for the partition and the caches,
which carries over unchanged) with Monster Maulers' fifth planes put back: this board's tiles and sprites are 5bpp, and a
row's fifth plane rides in the same SDRAM burst as its four other planes. There is no rotating plane, so nothing of the
machine lives in the DDR3.

| | MiSTer (DE10-Nano + SDRAM module) |
|---|---|
| SDRAM | 32 MB, 16 bit |
| DDR3 | the HPS's 1 GB, 64 bit, shared with Linux and the scaler: the fast load's copy of the image and Flip Screen's frame buffers |
| block RAM | 5.6 Mbit (553 M10K) |

## The partition

```
SDRAM   tiles         1.5 MB   3-word bursts   a tile row = 4 chunky bytes + the fifth plane's byte              K056832
        PCM           4 MB     single words    (2 x 2 MB of ROM)                                                   two K054539s
        sprites       5 MB     5-word bursts   a 16-pixel row = 4 words (the four low planes) + the fifth plane's word  K055673
        68000 program 2 MB     behind a 16 KB cache, 8-word line fills (1.5 MB of ROM, the rest zeros)
        Z80 program   256 KB   behind a  4 KB cache, 8-word line fills (the 128 KB ROM twice)
DDR3    fast load     the image as Main_MiSTer copied it (byte 0x32000000)
        Flip Screen   2 frame buffers (flip_buf.sv), the finished picture
block   K056832 tile RAM  64K x 16, byte enables
RAM     tile row cache    512 x 40 (tags 512 x 16), sprite row cache 512 x 80
        work RAM 64 KB, sprite RAM (+ the 64 KB window's plain RAM), palette (all in mw_main)
```

SDRAM word addresses (24 bits): tiles `0x000000`, PCM `0x180000`, sprites `0x380000`, program `0x800000`, sound program
`0x900000` (19 MB of the 32 are addressed, 12.3 MB used).

The image (`mra/*.mra`, `0xF40000` bytes, layout in the MRA header) keeps each region's own order except where planes
are interleaved: a tile row's image group is 8 bytes (two words of chunky bytes, the fifth plane's byte and three
pad bytes), kept as 3 SDRAM words, and a sprite row's fifth-plane word (from the image's separate fifth-plane region)
is written after its four low-plane words, so every row is one burst. The tile port returns `{w0, w1, w2[15:8]}`
(40 bits), the sprite port `{w0..w4}` (80 bits).

## The loader

As Violent Storm's: the ROM image arrives from the HPS a byte at a time; pairs are merged into words, queued in a
64-entry FIFO (`dl_wait` holds the HPS off at 32), and a dispatcher classifies each word by image offset and writes it
as a byte-enabled SDRAM word at its region's address (with the interleave above). The caches are swept on every
download start. The default EEPROM is a separate download (MRA index 2), and the same index is used to save and
restore it (`<nvram>`).

### Fast load (the MRA's `address=` attribute)

The five MRAs carry `address="0x32000000"` on the ROM image. A Main_MiSTer that supports the attribute copies the
assembled image into the DDR3 in one go, then ends a download that has no data bytes, only a start address (the
image's length; an ordinary download starts at 0, which is how `MysticWarriors.sv` tells them apart: `fast_dl`). The
core stays in reset from the start until `mw_mem` has read the image back in 256-byte blocks (a 32-beat burst through
the arbiter's client port, `ddr_arb.sv` `c_*`) and pushed every word through the same loader FIFO (`fl_done`).
A Main_MiSTer that does not know the attribute streams the bytes as before, with the same RBF and MRAs. This is the
Violent Storm core's implementation, taken over unchanged with this core's image length.

## Video

The 6 MHz pixel clock comes from the 96 MHz system clock (a pixel every 16 clocks; a 384-pixel line is 6,144 clocks, the
budget the renderers were designed against). The mixer is one core (16 clocks a pixel), as in Monster Maulers. Flip
Screen (`flip_buf.sv`) turns the finished picture 180 degrees through two DDR3 frame buffers, as in the other cores,
with `W = 288`. CRT Adjust is rmonic79's module; with this raster the picture is 288 pixels in a line of 384, starting
79 pixels after the hsync pulse starts and ending 17 before the next, so H-Size goes to +3 (a step is 4.5 pixels) and
H-Position to +16.

The scandoubler gets the horizontal blank alone (`hde`), the vertical blank separately, as in the Violent Storm and
Monster Maulers cores after their scandoubler fix; the Scale option is the framework's `video_freak`, wired as there.

## The built-in memory test

With the Diagnostic overlay on, `mem_test.sv` sums every byte of the image per region as it loads, reads each region back
through the machine's own ports twice (ok = read back what was loaded, stable = the two passes agree; the tile and sprite
rows are summed with their fifth plane) and tests the tile RAM with an address pattern.
