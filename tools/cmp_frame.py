#!/usr/bin/env python3
"""Compare an RTL frame dump (sim/tb_frame or the system bench: 32-bit little-endian 0x00RRGGBB, 288 x 224) with a
MAME snapshot PNG, or two PNGs, or two dumps.

    cmp_frame.py rtl.rgb mame.png [out_diff.png] [--w 288 --h 224] [--dx n --dy n]

Prints the number of differing pixels, their bounding box, the largest channel error and how many are small (<= 2).
--dx / --dy shift the second picture before comparing (the first's pixel (x, y) against the second's (x + dx, y + dy)),
to measure an offset. The diff image shows differing pixels red over the second picture, dimmed. Exits 1 on any
difference."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio


def load(path, w, h):
    if path.endswith('.png'):
        pw, ph, rgb = pngio.read(path)
        pix = [(rgb[i * 3] << 16) | (rgb[i * 3 + 1] << 8) | rgb[i * 3 + 2] for i in range(pw * ph)]
        # a snapshot larger than the picture is cropped from the top left
        return [pix[y * pw + x] if x < pw and y < ph else 0 for y in range(h) for x in range(w)]
    d = open(path, 'rb').read()
    n = len(d) // 4
    a = struct.unpack('<%dI' % n, d[:n * 4])
    return [a[i] & 0xffffff if i < n else 0 for i in range(w * h)]


def main():
    args, opt = [], {'--w': 288, '--h': 224, '--dx': 0, '--dy': 0}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] in opt:
            opt[sys.argv[i]] = int(sys.argv[i + 1]); i += 2
        else:
            args.append(sys.argv[i]); i += 1
    if len(args) < 2:
        print(__doc__)
        return 2
    W, H, dx, dy = opt['--w'], opt['--h'], opt['--dx'], opt['--dy']
    a, b = load(args[0], W, H), load(args[1], W, H)
    bad = 0; xs = []; ys = []; maxe = 0; small = 0
    diff = [0] * (W * H)
    for y in range(H):
        for x in range(W):
            i = y * W + x
            x2, y2 = x + dx, y + dy
            if not (0 <= x2 < W and 0 <= y2 < H):
                continue
            q = b[y2 * W + x2]
            if a[i] != q:
                bad += 1; xs.append(x); ys.append(y)
                e = max(abs(((a[i] >> s) & 255) - ((q >> s) & 255)) for s in (0, 8, 16))
                maxe = max(maxe, e)
                if e <= 2:
                    small += 1
                diff[i] = 0xff0000
            else:
                diff[i] = (q >> 1) & 0x7f7f7f
    if len(args) > 2:
        out = bytearray()
        for v in diff:
            out += bytes(((v >> 16) & 255, (v >> 8) & 255, v & 255))
        pngio.write(args[2], W, H, out)
    if bad == 0:
        print('IDENTICAL (%d pixels)' % (W * H))
        return 0
    print('%d of %d pixels differ; bbox x %d..%d y %d..%d; max channel error %d; %d with error <= 2'
          % (bad, W * H, min(xs), max(xs), min(ys), max(ys), maxe, small))
    return 1


if __name__ == '__main__':
    sys.exit(main())
