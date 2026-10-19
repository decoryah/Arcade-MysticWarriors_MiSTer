-- Freeze frames of Mystic Warriors and write everything the frame bench needs,
-- alongside MAME's own snapshot of that same frame. After the Violent Storm core's
-- tools/lua/dump_state.lua (the same video chain and register layout; this game's map
-- is MAME's mystwarr_map: the chips at 48xxxx, VSCCS at 49e000, tile RAM at 600000).
--
--   DUMPFRAMES=<f,f,f...>  frames to capture
--   DUMPDIR=<dir>          output directory (state_<frame>.txt and snap_<frame>.png go there)
--   FORCE_ENABLE=<hex>     override the K055555 layer-enable register, so a single
--                          layer can be isolated for diffing
--   SCHEDULE=survey|play|none   the scripted inputs (default none: attract mode only); the same
--                          inputs by frame as the system bench's SCHED (sim/tb_mw.cpp)
--   SCHEDLAG=n             use the schedule's frame f - n at frame f (n may be negative). A value set here reaches
--                          the game one frame later than the frame it is set in (MAME's input ports take their new
--                          values in its own frame notifier, which runs before this one)
--   SKIPBOOT=1             the system bench's shortcut over the power-on RAM / ROM check: the
--                          patch in SKIPBOOT_FILE (default tools/skipboot.txt), applied by read taps
--   SERVICE=1              the test switch held from frame SERVICE_FROM (default 1200)
--   SURVEY=<every>         a line every <every> frames in DUMPDIR/survey.csv instead of (or with) dumps
--   WORKRAM=1              the dumps also hold the work RAM (WORKRAM, 32K words)
--
-- Write-only chip registers are shadowed through write taps. VRAM is 16 pages of
-- 4 K words behind a bank register: after the snapshot is taken (and only then, because
-- it perturbs the chip) the bank is cycled and all of it read, then the registers
-- the cycling touched are put back.

local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local KEEP = {}
_G.DUMPKEEP = KEEP

local function newregs(n) local t = {} for i = 0, n-1 do t[i] = 0 end return t end

local k56_regs  = newregs(32)    -- VACSET   0x48c000, word
local k56_regsb = newregs(4)     -- VSCCS    0x49e000, word (the low byte of 49e006 is also the IRQ control)
local k46_regs  = newregs(8)     -- K053246  0x484000, byte pairs
local k47_regs  = newregs(8)     -- K055673  0x482010, word
local k55_regs  = newregs(48)    -- K055555  0x480000, byte in low or high half
local k38_regs  = newregs(16)    -- K054338  0x48a000, word

local FORCE_ENABLE = os.getenv("FORCE_ENABLE")
if FORCE_ENABLE then FORCE_ENABLE = tonumber(FORCE_ENABLE, 16) end

local function word_tap(base, size, regs, name)
  return sp:install_write_tap(base, base + size - 1, name, function(off, data, mask)
    local r = (off - base) // 2
    local old = regs[r]
    if mask == 0xffff then regs[r] = data & 0xffff
    elseif mask == 0xff00 then regs[r] = (old & 0x00ff) | (data & 0xff00)
    else regs[r] = (old & 0xff00) | (data & 0x00ff) end
  end)
end

KEEP.t1 = word_tap(0x48c000, 0x40, k56_regs,  "k56")
KEEP.t2 = word_tap(0x49e000, 0x08, k56_regsb, "k56b")
KEEP.t3 = sp:install_write_tap(0x484000, 0x484007, "k46", function(off, data, mask)
  local w = (off - 0x484000) // 2
  if (mask & 0xff00) ~= 0 then k46_regs[w*2] = (data >> 8) & 0xff end
  if (mask & 0x00ff) ~= 0 then k46_regs[w*2+1] = data & 0xff end end)
KEEP.t4 = word_tap(0x482010, 0x10, k47_regs, "k47")
KEEP.t5 = sp:install_write_tap(0x480000, 0x4800ff, "k55", function(off, data, mask)
  -- K055555_word_w: mem_mask 0x00ff -> low byte, else high byte
  local r = (off - 0x480000) // 2
  local v
  if mask == 0x00ff then v = data & 0xff else v = (data >> 8) & 0xff end
  if r < 48 then k55_regs[r] = v end
  -- layer isolation: rewrite the ENABLE register (45) on its way to the chip
  if FORCE_ENABLE and r == 45 then
    if mask == 0x00ff then return (data & 0xff00) | FORCE_ENABLE
    else return (data & 0x00ff) | (FORCE_ENABLE << 8) end
  end
end)
KEEP.t6 = word_tap(0x48a000, 0x20, k38_regs, "k38")

-- SKIPBOOT=1: the system bench's PATCH (sim/run_mw.sh SKIPBOOT=1), from the same file: lines of
-- <hex address>:<hex bytes>, '#' comments. Applied by read taps on the program ROM (the ROM itself is untouched).
if os.getenv("SKIPBOOT") == "1" then
  local path = os.getenv("SKIPBOOT_FILE") or "tools/skipboot.txt"
  local fh = io.open(path, "r")
  if not fh then
    print("SKIPBOOT: cannot open " .. path .. ", running the power-on tests")
  else
    local bytes = {}
    for line in fh:lines() do
      line = line:gsub("#.*", ""):gsub("%s", "")
      local a, h = line:match("^(%x+):(%x+)$")
      if a then
        a = tonumber(a, 16)
        for i = 1, #h, 2 do bytes[a] = tonumber(h:sub(i, i + 1), 16); a = a + 1 end
      end
    end
    fh:close()
    local words = {}
    for a, b in pairs(bytes) do words[a & ~1] = true end
    local n = 0
    for wa in pairs(words) do
      local orig = sp:read_u16(wa)
      local hi = bytes[wa] or (orig >> 8)
      local lo = bytes[wa + 1] or (orig & 0xff)
      local val = (hi << 8) | lo
      KEEP["sk" .. wa] = sp:install_read_tap(wa, wa + 1, "sk" .. wa, function(off, data, mask) return val end)
      print(string.format("SKIPBOOT: $%06x %04x -> %04x", wa, orig, val))
      n = n + 1
    end
  end
end

local FRAMES = {}
for n in string.gmatch(os.getenv("DUMPFRAMES") or "", "%d+") do FRAMES[tonumber(n)] = true end
local LAST = tonumber(os.getenv("LASTFRAME") or "0")
for n in pairs(FRAMES) do if n > LAST then LAST = n end end
local DIR  = os.getenv("DUMPDIR") or "."
local f = 0
local irq_ctrl = 0
KEEP.irq = sp:install_write_tap(0x49e006, 0x49e007, "irqctl", function(off, data, mask)
  if (mask & 0x00ff) ~= 0 then irq_ctrl = data & 0xff end end)

local function hexrun(read, n)
  local t = {}
  for i = 1, n do t[i] = string.format("%04x", read(i-1)) end
  return table.concat(t, " ")
end

local function dump()
  mach.video:snapshot()

  local out = assert(io.open(DIR .. "/state_" .. tostring(f) .. ".txt", "w"))
  out:write("# mystic warriors frozen state, frame ", tostring(f), "\n")
  out:write("FRAME ", tostring(f), "\n")

  local function regline(name, t, n)
    local a = {}
    for i = 0, n-1 do a[i+1] = string.format("%04x", t[i]) end
    out:write(name, " ", table.concat(a, " "), "\n")
  end
  regline("K56REGS",  k56_regs, 32)
  regline("K56REGSB", k56_regsb, 4)
  regline("K46REGS",  k46_regs, 8)
  regline("K47REGS",  k47_regs, 8)
  regline("K55REGS",  k55_regs, 48)
  regline("K38REGS",  k38_regs, 16)
  out:write(string.format("IRQCTL %04x\n", irq_ctrl))

  -- palette: 2048 entries, two 16-bit words each
  out:write("PALETTE ", hexrun(function(i) return sp:read_u16(0x700000 + i*2) end, 4096), "\n")

  -- sprite RAM: k053247 word w lives at 0x400000 + ((w & 0x7f8) << 5) + (w & 7)*2 (k053247_scattered_word_r)
  out:write("SPRITERAM ", hexrun(function(w)
      return sp:read_u16(0x400000 + ((w & 0x7f8) << 5) + (w & 7) * 2)
    end, 2048), "\n")

  -- WORKRAM=1: the 68000's work RAM, 0x200000-0x20ffff
  if os.getenv("WORKRAM") == "1" then
    out:write("WORKRAM ", hexrun(function(i) return sp:read_u16(0x200000 + i*2) end, 32768), "\n")
  end

  -- VRAM: 16 pages of 0x1000 words behind the bank register at 0x48c032. Done last:
  -- it perturbs the chip; the registers it touches are put back.
  local saved_r0  = k56_regs[0]
  local saved_r19 = k56_regs[0x19]
  out:write("CURPAGE ", hexrun(function(i) return sp:read_u16(0x600000 + i*2) end, 4096), "\n")
  for page = 0, 15 do
    local col, row = page & 3, (page >> 2) & 3
    sp:write_u16(0x48c000, saved_r0 & ~0x0002)      -- internal linescroll
    sp:write_u16(0x48c032, (row << 3) | col)
    out:write(string.format("VRAM %d ", page),
              hexrun(function(i) return sp:read_u16(0x600000 + i*2) end, 4096), "\n")
  end
  sp:write_u16(0x48c000, saved_r0)
  sp:write_u16(0x48c032, saved_r19)
  out:close()
  print("DUMPED frame " .. tostring(f))
  io.stdout:flush()
end

-- SURVEY=<every>: a line every <every> frames to DUMPDIR/survey.csv
--   frame, K055555 enables, sprites, K053246 reg 5, K056832 regs 3 / 5, the IRQ control, the 68000's PC
local SURVEY = tonumber(os.getenv("SURVEY") or "0")
local survey_f
if SURVEY > 0 then
  survey_f = assert(io.open(DIR .. "/survey.csv", "w"))
  survey_f:write("frame,en,sprites,k46r5,k56r3,k56r5,irqctl,pc\n")
end
local cpu = mach.devices[":maincpu"]
local function survey()
  local spr = 0
  for e = 0, 255 do
    local w = e * 8
    if (sp:read_u16(0x400000 + ((w & 0x7f8) << 5)) & 0x8000) ~= 0 then spr = spr + 1 end
  end
  survey_f:write(string.format("%d,%02x,%d,%02x,%04x,%04x,%02x,%06x\n", f, k55_regs[45], spr, k46_regs[5],
    k56_regs[3], k56_regs[5], irq_ctrl, cpu.state["PC"].value))
  survey_f:flush()
end

-- scripted inputs: the system bench's SCHED (sim/tb_mw.cpp), frame for frame
local in0 = mach.ioport.ports[":IN0"]
local p12 = mach.ioport.ports[":P1_P2"]
local coin, start, b1, b2, b3, rt, up, dn, lf
if in0 then coin = in0.fields["Coin 1"] end
if p12 then
  start = p12.fields["1 Player Start"]
  b1, b2, b3 = p12.fields["P1 Button 1"], p12.fields["P1 Button 2"], p12.fields["P1 Button 3"]
  rt, up, dn, lf = p12.fields["P1 Right"], p12.fields["P1 Up"], p12.fields["P1 Down"], p12.fields["P1 Left"]
end
local SCHED = os.getenv("SCHEDULE") or "none"
local SCHEDLAG = tonumber(os.getenv("SCHEDLAG") or "0")
local svc = nil
local svc_from = tonumber(os.getenv("SERVICE_FROM") or "1200")
if os.getenv("SERVICE") == "1" then
  local in1 = mach.ioport.ports[":IN1"]
  if in1 then svc = in1.fields["Service Mode"] end
end

KEEP.notif = emu.add_machine_frame_notifier(function()
  f = f + 1
  if svc and f >= svc_from then svc:set_value(1) end
  local n = f - SCHEDLAG
  if SCHED == "survey" and coin then
    coin:set_value((n > 200 and (n % 120) < 8) and 1 or 0)
    start:set_value((n > 260 and (n % 90) < 8 and (n % 120) >= 8) and 1 or 0)
    if n > 500 then
      b1:set_value((n % 11 < 4) and 1 or 0)
      b2:set_value((n % 29 < 3) and 1 or 0)
      b3:set_value((n % 43 < 3) and 1 or 0)
      rt:set_value((n % 97 < 40) and 1 or 0)
      lf:set_value((n % 131 > 100) and 1 or 0)
      up:set_value((n % 53 < 20) and 1 or 0)
      dn:set_value((n % 71 > 60) and 1 or 0)
    end
  end
  if SCHED == "play" and coin then
    coin:set_value((n > 200 and (n % 240) < 8) and 1 or 0)
    start:set_value((n > 260 and (n % 90) < 8 and (n % 240) >= 8) and 1 or 0)
    if n > 500 then
      b1:set_value((n % 7 < 3) and 1 or 0)
      b2:set_value((n % 61 < 2) and 1 or 0)
      b3:set_value((n % 83 < 2) and 1 or 0)
      rt:set_value((n % 160 < 130) and 1 or 0)
      lf:set_value(((n + 40) % 400 < 12) and 1 or 0)
      up:set_value((n % 97 < 18) and 1 or 0)
      dn:set_value((n % 131 > 112) and 1 or 0)
    end
  end
  if SURVEY > 0 and f % SURVEY == 0 then survey() end
  if FRAMES[f] then dump() end
  if LAST > 0 and f >= LAST then mach:exit() end
end)

-- RUSCRIPT=<file>[;<file>...]: run other probes in the same MAME session (the scripted inputs above keep playing)
for s in string.gmatch(os.getenv("RUSCRIPT") or "", "[^;]+") do dofile(s) end
