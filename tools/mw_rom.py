#!/usr/bin/env python3
"""Checks a Mystic Warriors ROM image (built from mra/*.mra by tools/mra_build.py) against MAME's regions.

MAME's regions are rebuilt here from the zip by MAME's own loading rules (mystwarr.cpp, ROM_START( mystwarr ) and
its clones), independently of the MRA's interleave maps:

    ROM_LOAD16_BYTE    ROM_SKIP(1): byte i at offset + 2i
    ROM_LOADTILE_WORD  ROM_GROUPWORD | ROM_SKIP(3) | ROM_REVERSE: bytes 2i, 2i+1 at offset + 5i + {1, 0}
    ROM_LOADTILE_BYTE  ROM_GROUPBYTE | ROM_SKIP(4): byte i at offset + 5i
    ROM_LOAD64_WORD    ROM_GROUPWORD | ROM_SKIP(6): bytes 2i, 2i+1 at offset + 8i + {0, 1}

and then laid out the way target/mister/mw_mem.sv expects the image (the MRA header), which is compared with the
image byte for byte. The memory-side view the RTL depends on is spelled out on the way:

    tile row r (8 pixels): region k056832 bytes 5r .. 5r+4  -> image TILE + 8r .. 8r+4 (three zero bytes after)
    sprite row r (16 pixels): region k055673 bytes 8r .. 8r+7 -> image SPR + 8r; the fifth plane's bytes
                              4 MB + 2r, 2r+1 -> image SPR5 + 2r, 2r+1

    python3 tools/mw_rom.py mystwarr.zip mystwarr.rom [setname]
"""
import sys, os, zipfile, zlib

PROG = {   # setname: (even, odd) program ROMs at 000000
    "mystwarr":   ("128eaa01.20f", "128eaa02.20g"),
    "mystwarru":  ("128uaa01.20f", "128uaa02.20g"),
    "mystwarrj":  ("128jaa01.20f", "128jaa02.20g"),
    "mystwarra":  ("128aab01.20f", "128aab02.20g"),
    "mystwarraa": ("128aaa01.20f", "128aaa02.20g"),
}
IMG = dict(PROG=0x000000, SND=0x200000, TILE=0x240000, PCM=0x640000, SPR=0xA40000, SPR5=0xE40000, END=0xF40000)

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    z = zipfile.ZipFile(sys.argv[1])
    setname = sys.argv[3] if len(sys.argv) > 3 else "mystwarr"
    files = {}
    for i in z.infolist():
        if i.is_dir(): continue
        files.setdefault(os.path.basename(i.filename), []).append(i)
    def rom(name):
        cands = files[name]
        return z.read(cands[0])

    # ---- MAME's regions
    maincpu = bytearray(0x200000)
    def load16_byte(reg, name, off):
        d = rom(name)
        for i, b in enumerate(d): reg[off + 2 * i] = b
    e, o = PROG[setname]
    load16_byte(maincpu, e, 0x000000); load16_byte(maincpu, o, 0x000001)
    load16_byte(maincpu, "128a03.19f", 0x100000); load16_byte(maincpu, "128a04.19g", 0x100001)

    soundcpu = bytearray(0x40000)
    d = rom("128a05.6b"); soundcpu[0:0x20000] = d; soundcpu[0x20000:0x40000] = d      # ROM_RELOAD

    k056832 = bytearray(0x500000)                                                      # ROMREGION_ERASE00
    def loadtile_word(name, off):
        d = rom(name)
        for i in range(len(d) // 2):
            k056832[off + 5 * i + 0] = d[2 * i + 1]                                    # ROM_REVERSE
            k056832[off + 5 * i + 1] = d[2 * i]
    def loadtile_byte(name, off):
        d = rom(name)
        for i, b in enumerate(d): k056832[off + 5 * i] = b
    loadtile_word("128a08.1h", 0); loadtile_word("128a09.1k", 2); loadtile_byte("128a10.3h", 4)

    k055673 = bytearray(0x500000)
    def load64_word(name, off):
        d = rom(name)
        for i in range(len(d) // 2):
            k055673[off + 8 * i] = d[2 * i]; k055673[off + 8 * i + 1] = d[2 * i + 1]
    load64_word("128a16.22k", 0); load64_word("128a15.20k", 2); load64_word("128a14.19k", 4); load64_word("128a13.17k", 6)
    load16_byte(k055673, "128a12.12k", 0x400000); load16_byte(k055673, "128a11.10k", 0x400001)

    k054539 = rom("128a06.2d") + rom("128a07.1d")

    # ---- the image as mw_mem.sv expects it
    want = bytearray(IMG["END"])
    want[IMG["PROG"]:IMG["PROG"] + 0x200000] = maincpu
    want[IMG["SND"]:IMG["SND"] + 0x40000] = soundcpu
    for r in range(0x80000):                                   # 512K tile rows of five bytes
        want[IMG["TILE"] + 8 * r: IMG["TILE"] + 8 * r + 5] = k056832[5 * r: 5 * r + 5]
    assert not any(k056832[5 * 0x80000:]), "tile data beyond 512K rows"
    want[IMG["PCM"]:IMG["PCM"] + 0x400000] = k054539
    want[IMG["SPR"]:IMG["SPR"] + 0x400000] = k055673[0:0x400000]
    want[IMG["SPR5"]:IMG["SPR5"] + 0x100000] = k055673[0x400000:0x500000]

    img = open(sys.argv[2], "rb").read()
    if len(img) != len(want):
        print("image is %d bytes, expected %d" % (len(img), len(want))); return 1
    bad = 0
    for name, (a, b) in (("program", (IMG["PROG"], IMG["SND"])), ("sound", (IMG["SND"], IMG["TILE"])),
                         ("tiles", (IMG["TILE"], IMG["PCM"])), ("pcm", (IMG["PCM"], IMG["SPR"])),
                         ("sprites", (IMG["SPR"], IMG["SPR5"])), ("sprite plane 5", (IMG["SPR5"], IMG["END"]))):
        n = sum(1 for i in range(a, b) if img[i] != want[i])
        print("%-15s %08x-%08x  crc %08x  %s" % (name, a, b - 1, zlib.crc32(img[a:b]) & 0xffffffff,
                                               "ok" if n == 0 else "%d bytes differ" % n))
        bad += n
    # a few rows decoded the way the RTL decodes them, for the record
    r = 0x1234
    t = img[IMG["TILE"] + 8 * r: IMG["TILE"] + 8 * r + 5]
    px = [((t[4] >> (7 - x)) & 1) << 4 | ((t[x >> 1] >> (4 if x % 2 == 0 else 0)) & 15) for x in range(8)]
    print("tile row %05x: bytes %s -> pixels %s" % (r, t.hex(), px))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
