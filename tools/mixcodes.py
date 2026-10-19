#!/usr/bin/env python3
"""Which blending and shadow features a directory of frozen states (tools/lua/dump_state.lua) exercises.

    mixcodes.py <dir> [--all]

Per frame (only the frames that use a feature, unless --all): the K055555 V_INMIX (33) / V_INMIX_ON (34), the
K054338 levels of mix codes 1..3 ('+' additive, as set_alpha_level reads them: inverted unless additive in the
current MAME, inverted always in 0.289), and for each enabled layer the histogram of its tiles' resolved mix codes
((attr >> 2 & 3) & ~V_INMIX_ON | V_INMIX & V_INMIX_ON, mystwarr_tile_callback) over the non-empty cells of the pages
it covers (the whole pages, not only what is on screen); then the live sprites, those with a mix code (attribute bits
9:8) and those with a shadow code (bits 11:10).

The layers where tiles of different non-zero codes meet are where MAME 0.289's rule (every mix-coded tile at the
level of the last code its tile callback saw) and the current one (each tile at its own code) can differ."""
import glob
import os
import re
import sys


def load(path):
    st, pages = {}, {}
    for line in open(path):
        k, _, rest = line.partition(' ')
        if k == 'VRAM':
            parts = rest.split()
            pages[int(parts[0])] = [int(x, 16) for x in parts[1:]]
        elif k in ('K55REGS', 'K38REGS', 'K56REGS', 'SPRITERAM'):
            st[k] = [int(x, 16) for x in rest.split()]
    return st, pages


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    show_all = '--all' in sys.argv
    files = sorted(glob.glob(os.path.join(d, 'state_*.txt')), key=lambda p: int(re.search(r'state_(\d+)', p).group(1)))
    tally = {'frames': 0, 'mixed_layers': 0, 'tile_mix': 0, 'additive': 0, 'spr_mix': 0, 'spr_shadow': 0}
    for p in files:
        fr = int(re.search(r'state_(\d+)', p).group(1))
        st, pages = load(p)
        k55, k38, k56, sr = st['K55REGS'], st['K38REGS'], st['K56REGS'], st['SPRITERAM']
        vinmix, von, en = k55[33], k55[34], k55[45]
        layers = []
        any_tile_mix = any_mixed = False
        for layer in range(4):
            if not en >> layer & 1:
                continue
            rs, rn = (k56[8 + layer] >> 3) & 3, (k56[8 + layer] & 3) + 1
            cs, cn = (k56[12 + layer] >> 3) & 3, (k56[12 + layer] & 3) + 1
            lvon, lvin = von >> (layer * 2) & 3, vinmix >> (layer * 2) & 3
            h = [0, 0, 0, 0]
            for r in range(rn):
                for c in range(cn):
                    v = pages.get((((rs + r) & 3) << 2) | ((cs + c) & 3))
                    if not v:
                        continue
                    for t in range(0, 4096, 2):
                        if v[t + 1] or v[t]:
                            h[((v[t] >> 2 & 3) & ~lvon) | (lvin & lvon)] += 1
            nz = [c for c in (1, 2, 3) if h[c]]
            any_tile_mix |= bool(nz)
            any_mixed |= len(nz) > 1
            layers.append('%c:%s%s' % ('ABCD'[layer], '/'.join(str(x) for x in h), '*' if len(nz) > 1 else ''))

        def lvl(v):
            add = v >> 5 & 1
            raw = v & 0x1f
            cur = raw if add else 0x1f - raw
            return ((cur << 3) | (cur >> 2)), add
        codes = [k38[13] & 0xff, k38[14] >> 8, k38[14] & 0xff]
        lv = [lvl(c) for c in codes]
        live = mixed = shad = 0
        for e in range(256):
            w = sr[e * 8:e * 8 + 8]
            if w[0] & 0x8000:
                live += 1
                if w[6] >> 8 & 3:
                    mixed += 1
                if w[6] >> 10 & 3:
                    shad += 1
        used_add = any(lv[c - 1][1] for c in (1, 2, 3))
        tally['frames'] += 1
        tally['mixed_layers'] += any_mixed
        tally['tile_mix'] += any_tile_mix
        tally['additive'] += used_add and (any_tile_mix or mixed > 0)
        tally['spr_mix'] += mixed > 0
        tally['spr_shadow'] += shad > 0
        if show_all or any_tile_mix or mixed or shad:
            print('frame %5d  vinmix %02x on %02x  levels %s  en %02x  %s  sprites %d mix %d shadow %d' % (
                fr, vinmix, von, ' '.join('%d=%3d%s' % (c, lv[c - 1][0], '+' if lv[c - 1][1] else ' ') for c in (1, 2, 3)),
                en, ' '.join(layers), live, mixed, shad))
    print('%(frames)d frames: %(tile_mix)d with mix-coded tiles (%(mixed_layers)d with different codes in one layer), '
          '%(additive)d with an additive code in use, %(spr_mix)d with mix-coded sprites, %(spr_shadow)d with shadow sprites'
          % tally)
    return 0


if __name__ == '__main__':
    sys.exit(main())
