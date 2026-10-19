#!/usr/bin/env python3
"""Writes the five Mystic Warriors MRAs (mra/*.mra) from a MAME mystwarr.zip.

The image layout is the one target/mister/mw_mem.sv loads (docs/mister-memory.md):
the regions in the order below, 0xF40000 bytes. The default EEPROM is a
separate download (index 2): the HPS then also saves and restores it
(<nvram index="2">), so the game's settings and records persist.

    python3 tools/make_mra.py "/path/to/MAME ROMs (merged)/mystwarr.zip"
"""
import sys, zipfile, os

SETS = [
    # setname, title, region, program ROM names, nvram file inside the merged zip
    ("mystwarr",   "Mystic Warriors (World ver EAA)", "World", ("128eaa01.20f", "128eaa02.20g"), "mystwarr.nv"),
    ("mystwarru",  "Mystic Warriors (USA ver UAA)",   "USA",   ("128uaa01.20f", "128uaa02.20g"), "mystwarru/mystwarru.nv"),
    ("mystwarrj",  "Mystic Warriors (Japan ver JAA)", "Japan", ("128jaa01.20f", "128jaa02.20g"), "mystwarrj/mystwarrj.nv"),
    ("mystwarra",  "Mystic Warriors (Asia ver AAB)",  "Asia",  ("128aab01.20f", "128aab02.20g"), "mystwarra/eeprom"),
    ("mystwarraa", "Mystic Warriors (Asia ver AAA)",  "Asia",  ("128aaa01.20f", "128aaa02.20g"), "mystwarraa/mystwarra.nv"),
]
CRC = {   # the files of the merged set, by base name (MAME mystwarr.cpp)
    "128a03.19f": "e98094f3", "128a04.19g": "88c6a3e4", "128a05.6b": "0e5194e0",
    "128a06.2d": "88ed598c", "128a07.1d": "db79a66e",
    "128a08.1h": "63d6cfa0", "128a09.1k": "573a7725", "128a10.3h": "558e545a",
    "128a11.10k": "4eac941a", "128a12.12k": "63de93e2",
    "128a13.17k": "e89b66a2", "128a14.19k": "f7bd89dd", "128a15.20k": "6bbfedf4", "128a16.22k": "459b6407",
    "128eaa01.20f": "508f249c", "128eaa02.20g": "f8ffa352",
    "128uaa01.20f": "3a89aafd", "128uaa02.20g": "de07410f",
    "128jaa01.20f": "49c37bfe", "128jaa02.20g": "e39fb3bb",
    "128aab01.20f": "3dc89153", "128aab02.20g": "8fe92ad2",
    "128aaa01.20f": "633ead86", "128aaa02.20g": "69ab81a2",
}

def hexdump(data):
    lines = []
    for i in range(0, len(data), 16):
        lines.append(" ".join("%02X" % b for b in data[i:i + 16]))
    return "\n".join(lines)

def mra(setname, title, region, prog, nvdata):
    p0, p1 = prog
    zips = "mystwarr.zip" if setname == "mystwarr" else f"{setname}.zip|mystwarr.zip"
    return f"""<misterromdescription>
    <rotation>horizontal</rotation>
    <name>{title}</name>
    <setname>{setname}</setname>
    <mameversion>0289</mameversion>
    <year>1993</year>
    <manufacturer>Konami</manufacturer>
    <players>4</players>
    <joystick>8</joystick>
    <rbf>mysticwarriors</rbf>
    <region>{region}</region>
    <platform>Konami pre-GX</platform>

    <!--
      Flat image for the Mystic Warriors core (target/mister/mw_mem.sv):

        0x0000000  0x200000  68000 program (0.5 MB, 0.5 MB of zeros, 1 MB: the map's 2 MB)
        0x0200000  0x040000  Z80 sound program, 16 x 16 KB banks (the 128 KB ROM twice)
        0x0240000  0x400000  K056832 tile ROM, 5bpp: per 8-pixel row an 8-byte group
                             (4 chunky bytes, the fifth plane byte, 3 zero)
        0x0640000  0x400000  K054539 PCM
        0x0A40000  0x400000  K055673 sprite ROM, 64-bit words: a 16-pixel row of the four low planes
        0x0E40000  0x100000  K055673 fifth plane, a 16-bit word per row (left 8 pixels, right 8)
        0x0F40000            end

      Expects the MAME 0.289 merged romset (mystwarr.zip holding the parent and the
      four clones) or the split sets: parts are found by name, whatever folder holds them.
    -->
    <rom index="0" zip="{zips}" md5="None" address="0x32000000">

        <!-- 68000 program, 16-bit big-endian words: the even byte is the first ROM -->
        <interleave output="16">
            <part name="{p0}" crc="{CRC[p0]}" map="01"/>
            <part name="{p1}" crc="{CRC[p1]}" map="10"/>
        </interleave>
        <part repeat="0x80000">00</part>
        <interleave output="16">
            <part name="128a03.19f" crc="{CRC['128a03.19f']}" map="01"/>
            <part name="128a04.19g" crc="{CRC['128a04.19g']}" map="10"/>
        </interleave>

        <!-- Z80 sound program (ROM_RELOAD: the 128 KB twice) -->
        <part name="128a05.6b" crc="{CRC['128a05.6b']}"/>
        <part name="128a05.6b" crc="{CRC['128a05.6b']}"/>

        <!--
          K056832 tile ROM. MAME's ROM_LOADTILE_WORD is ROM_GROUPWORD|ROM_SKIP(3)|ROM_REVERSE
          and ROM_LOADTILE_BYTE is ROM_GROUPBYTE|ROM_SKIP(4): 5-byte groups, one per 8-pixel
          row, 4 packed-chunky bytes (the low 4 bits of the pixel) and the 5th plane's byte,
          which holds bit 4 of each of the row's 8 pixels (pixel 0 in bit 7). Padded to 8 bytes.
        -->
        <interleave output="64">
            <part name="128a08.1h" crc="{CRC['128a08.1h']}" map="00000012"/>
            <part name="128a09.1k" crc="{CRC['128a09.1k']}" map="00001200"/>
            <part name="128a10.3h" crc="{CRC['128a10.3h']}" map="00010000"/>
        </interleave>

        <!-- K054539 PCM samples, shared by both chips -->
        <part name="128a06.2d" crc="{CRC['128a06.2d']}"/>
        <part name="128a07.1d" crc="{CRC['128a07.1d']}"/>

        <!--
          K055673 sprite ROM, 64-bit words (ROM_LOAD64_WORD, 8-byte stride): one 64-bit word
          is the four low planes of one 16-pixel row (left 8 pixels in bytes 0-3, right 8 in
          bytes 4-7, one byte a plane).
        -->
        <interleave output="64">
            <part name="128a16.22k" crc="{CRC['128a16.22k']}" map="00000021"/>
            <part name="128a15.20k" crc="{CRC['128a15.20k']}" map="00002100"/>
            <part name="128a14.19k" crc="{CRC['128a14.19k']}" map="00210000"/>
            <part name="128a13.17k" crc="{CRC['128a13.17k']}" map="21000000"/>
        </interleave>
        <!-- the fifth plane (ROM_LOAD16_BYTE at 0x400000): per row, the left and the right 8 pixels' byte -->
        <interleave output="16">
            <part name="128a12.12k" crc="{CRC['128a12.12k']}" map="01"/>
            <part name="128a11.10k" crc="{CRC['128a11.10k']}" map="10"/>
        </interleave>
    </rom>

    <!-- the board's factory EEPROM: without it the game boots upside down with an error -->
    <rom index="2">
        <part>
{hexdump(nvdata)}
        </part>
    </rom>
    <nvram index="2" size="128"/>

    <buttons names="Shoot,Jump,Start,Coin" default="A,B,Start,Select" count="2"/>
</misterromdescription>
"""

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    z = zipfile.ZipFile(sys.argv[1])
    names = {os.path.basename(i.filename): i for i in z.infolist()}
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mra")
    os.makedirs(out, exist_ok=True)
    for base, want in CRC.items():
        if base in names and ("%08x" % names[base].CRC) != want:
            raise SystemExit("%s: crc %08x, expected %s" % (base, names[base].CRC, want))
    for setname, title, region, prog, nv in SETS:
        info = z.getinfo(nv)
        data = z.read(nv)
        assert len(data) == 128, (nv, len(data))
        for n in prog:
            assert ("%08x" % names[n].CRC) == CRC[n], (n, "%08x" % names[n].CRC, CRC[n])
        path = os.path.join(out, title + ".mra")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(mra(setname, title, region, prog, data))
        print("wrote", os.path.normpath(path), "(nvram crc %08x)" % info.CRC)

if __name__ == "__main__":
    sys.exit(main())
