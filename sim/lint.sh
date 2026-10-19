#!/bin/sh
# Verilator lint of the machine and the memory subsystem: sim/lint.sh
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET \
    +1364-2005ext+v waivers.vlt --top-module mw_core \
    ../rtl/*.sv ../modules/cpu-tg68k/gen/tg68k.v ../modules/cpu-tv80/*.v 2>&1 | grep -E "^%(Error|Warning)" | head -${1:-60}
echo "--- mem"
verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM waivers_mister.vlt \
    --top-module mw_mem ../target/mister/mw_mem.sv ../target/mister/rom_cache.sv ../target/mister/mem_test.sv \
    ../target/mister/sdram_ctrl.sv 2>&1 | grep -E "^%(Error|Warning)" | head -${1:-60}
