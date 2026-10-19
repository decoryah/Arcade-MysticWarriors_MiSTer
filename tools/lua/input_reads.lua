-- Where in the frame the game reads its controls, and where MAME's frame notifier (and so the Lua probes' input
-- changes) falls: with dump_state.lua as RUSCRIPT=<this file>, DUMPDIR/input_reads.csv gets, for frames READS_FROM to
-- READS_TO (default 1100 .. 1200), the time into MAME's frame of each read of 494000 (P1_P2) and of each frame notifier,
-- and the board's raster line at that instant. MAME's screen here is 512 x 256 at the board's frame rate (mystwarr:
-- set_raw, then set_size): MAME line L starts (L - 16) * 66 us from the picture's first line, which is raster line 16
-- of the board's 64 us lines (mw_core's mapping).
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local scr  = mach.screens[":screen"]
local DIR  = os.getenv("DUMPDIR") or "."
local from = tonumber(os.getenv("READS_FROM") or "1100")
local to   = tonumber(os.getenv("READS_TO") or "1200")
local out  = assert(io.open(DIR .. "/input_reads.csv", "w"))
out:write("frame,event,us_into_frame,mame_line,raster_line\n")
local period = scr.frame_period
local f = 0
local function where()
  local left = scr:time_until_pos(0, 0)
  if type(left) ~= "number" then left = left:as_double() end
  local t = period - left                   -- seconds since MAME's line 0
  if t >= period - 1e-9 then t = 0 end
  local us = t * 1e6
  local mline = us / (period * 1e6 / 256)
  local raster = 16 + (us - 16 * period * 1e6 / 256) / (period * 1e6 / 264)
  if raster < 0 then raster = raster + 264 end
  return string.format("%.1f,%.2f,%.2f", us, mline, raster)
end
_G.DUMPKEEP.ir_tap = sp:install_read_tap(0x494000, 0x494001, "ir_p12", function(off, data, mask)
  if f >= from and f <= to then out:write(string.format("%d,read,%s\n", f, where())) end
end)
_G.DUMPKEEP.ir_n = emu.add_machine_frame_notifier(function()
  f = f + 1
  if f >= from and f <= to then out:write(string.format("%d,notifier,%s\n", f, where())) end
  out:flush()
end)
