#!/bin/sh
# The frozen-state frame bench: the video pipeline (tilemap, sprites, mixer) fed a dumped chip state
# (tools/lua/dump_state.lua in MAME), compared with MAME's snapshot of the same frame.
#   sim/run_frames.sh <states dir with state_N.txt and snap_N.png> <image.rom> [FORCE_ENABLE hex, one layer set]
# The image is tools/mra_build.py on a mra/*.mra. Results in <dir>/rtl (or <dir>/$OUT): N.rgb, N.log, diff_N.png (differing
# pixels red). ONLY=a,b,c renders those frames only; REALTIME=1 gives each line the raster's time (sim/tb_frame.cpp) and
# PLUSARGS="+LAT_TROM=n +LAT_SROM=n +LAT_VRAM=n" the memories' latencies.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
OBJ="${OBJ:-$HOME/build_mw/frame}"
mkdir -p "$OBJ"
D="$1"; IMG="$2"
[ -d "$D" ] && [ -f "$IMG" ] || { echo "usage: $0 <states dir> <image.rom> [enable]" >&2; exit 2; }
case "$D" in /*) ;; *) D="$PWD/$D" ;; esac
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
if [ ! -x "$OBJ/Vtb_frame_top" ] || [ -n "$REBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-8} -O2 -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT \
    -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE -Wno-SYNCASYNCNET -Wno-BLKSEQ \
    --top-module tb_frame_top --prefix Vtb_frame_top -Mdir "$OBJ" \
    ../rtl/k056832_tilemap.sv ../rtl/k053247_objlist.sv ../rtl/k053247_draw.sv ../rtl/mw_mixer.sv \
    ../rtl/spr_rowcache.sv ../rtl/spr_sched.sv tb_frame_top.sv tb_frame.cpp > "$OBJ/build.log" 2>&1 || { tail -30 "$OBJ/build.log"; exit 1; }
fi
R="$D/${OUT:-rtl}"
mkdir -p "$R"
ok=0; tot=0
for f in $(ls "$D" | sed -n 's/^state_\([0-9]*\)\.txt$/\1/p' | sort -n); do
  s="$D/state_$f.txt"
  [ -f "$D/snap_$f.png" ] || continue
  [ -z "$ONLY" ] || case ",$ONLY," in *,$f,*) ;; *) continue ;; esac
  env ${3:+FORCE_ENABLE=$3} "$OBJ/Vtb_frame_top" "$s" "$IMG" ../rtl/data/zoom.hex ../rtl/data/recip.hex "$R/$f.rgb" $PLUSARGS > "$R/$f.log" 2>&1 || { echo "frame $f: bench failed: $(tail -1 "$R/$f.log")"; continue; }
  res=$(python3 ../tools/cmp_frame.py "$R/$f.rgb" "$D/snap_$f.png" "$R/diff_$f.png" 2>&1 | head -1)
  tot=$((tot+1)); case "$res" in IDENTICAL*) ok=$((ok+1));; esac
  echo "frame $f: $res"
done
echo "$ok of $tot frames pixel-identical"
