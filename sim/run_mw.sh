#!/bin/sh
# The whole-machine bench: mw_core behind mw_mem and a behavioural SDRAM, the real 68000 and Z80 programs from reset.
#   sim/run_mw.sh <image.rom> <eeprom.nv> <frames> <out prefix>
# Environment (see sim/tb_mw.cpp): BACKDOOR=1 places the image straight into the SDRAM model, PATCH=addr:bytes,..
# patches the program (SKIPBOOT=1 applies tools/skipboot.txt's patch for the power-on check), SCHED=survey|play and
# SCHEDLAG=n, SNAPFRAMES=a,b SNAPEVERY=n DUMPSTATE=a,b, TRACE=1, AUDIO=1, ROMCHK=1, TESTSW=1.
# About 0.1 MHz: some seconds of wall clock a frame. THREADS=n builds a multithreaded model (give it its own OBJ=).
# A first build, or REBUILD=1, compiles the model.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
IMG="$1"; NV="$2"
[ -f "$IMG" ] && [ -f "$NV" ] && [ -n "$3" ] && [ -n "$4" ] || { echo "usage: $0 <image.rom> <eeprom.nv> <frames> <prefix>" >&2; exit 2; }
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
case "$NV" in /*) ;; *) NV="$PWD/$NV" ;; esac
if [ "${SKIPBOOT:-0}" = 1 ] && [ -z "$PATCH" ]; then export PATCH="$(grep -v '^#' ../tools/skipboot.txt | tr -d ' \r\n')"; fi
OBJ=${OBJ:-obj_mw}
if [ ! -x $OBJ/Vtb_mw_top ] || [ -n "$REBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-16} -O3 ${THREADS:+--threads $THREADS} -CFLAGS "-O2 -march=native" -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD -Wno-CASEINCOMPLETE \
    -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSWIRE -Wno-SYNCASYNCNET \
    +1364-2005ext+v waivers.vlt --top-module tb_mw_top --prefix Vtb_mw_top -Mdir $OBJ \
    ../rtl/*.sv ../modules/cpu-tg68k/gen/tg68k.v ../modules/cpu-tv80/*.v \
    ../target/mister/mw_mem.sv ../target/mister/rom_cache.sv ../target/mister/mem_test.sv ../target/mister/sdram_ctrl.sv \
    sdram_model.sv tb_mw_top.sv tb_mw.cpp > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
fi
./$OBJ/Vtb_mw_top "$IMG" "$NV" "$3" "$4"
