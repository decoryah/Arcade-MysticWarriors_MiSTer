-- Every frame, the blending features where MAME 0.289 and the current MAME (whose rules the core's mixer follows)
-- part: with dump_state.lua as RUSCRIPT=<this file>, a line in DUMPDIR/mixwatch.csv for each frame in which
--   * a live sprite has a mix code (attribute word 6 bits 9:8; mystwarr_sprite_callback's "effect"),
--   * a mix code in use is additive (K054338 registers 13/14, bit 5 of the code's byte), or
--   * the game wrote tile attributes with mix codes 2 or 3 since the frame before (mystwarr_tile_callback's
--     attr >> 2 & 3: tiles of different codes are where 0.289's "last mix code" and the per-tile rule differ),
-- and the K055555 V_INMIX / V_INMIX_ON when they change.
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local DIR  = os.getenv("DUMPDIR") or "."
local out  = assert(io.open(DIR .. "/mixwatch.csv", "w"))
out:write("frame,what,detail\n")
local f = 0
local tw = {0, 0, 0, 0}         -- tile attribute writes by mix code since the last frame
local k38 = {}
local k55 = {}
_G.DUMPKEEP.wm_t = sp:install_write_tap(0x600000, 0x603fff, "wm_vram", function(off, data, mask)
  if ((off - 0x600000) & 2) == 0 then           -- the even word of a tile entry: the attribute
    local c = data >> 2 & 3
    tw[c + 1] = tw[c + 1] + 1
  end
end)
_G.DUMPKEEP.wm_38 = sp:install_write_tap(0x48a000, 0x48a01f, "wm_k38", function(off, data, mask)
  k38[(off - 0x48a000) // 2] = data end)
_G.DUMPKEEP.wm_55 = sp:install_write_tap(0x480000, 0x4800ff, "wm_k55", function(off, data, mask)
  local r = (off - 0x480000) // 2
  k55[r] = (mask == 0x00ff) and (data & 0xff) or (data >> 8 & 0xff) end)
local last_vin, last_von = -1, -1
_G.DUMPKEEP.wm_n = emu.add_machine_frame_notifier(function()
  f = f + 1
  local mixed, codes = 0, {0, 0, 0}
  for e = 0, 255 do
    local w = e * 8
    local base = 0x400000 + ((w & 0x7f8) << 5)
    if (sp:read_u16(base) & 0x8000) ~= 0 then
      local m = sp:read_u16(base + 12) >> 8 & 3
      if m ~= 0 then mixed = mixed + 1; codes[m] = codes[m] + 1 end
    end
  end
  local r13, r14 = k38[13] or 0, k38[14] or 0
  local add = {(r13 & 0x20) ~= 0, ((r14 >> 8) & 0x20) ~= 0, (r14 & 0x20) ~= 0}
  if mixed > 0 then
    out:write(string.format("%d,sprite_mix,%d sprites (codes 1/2/3: %d/%d/%d) k38 13=%04x 14=%04x\n",
      f, mixed, codes[1], codes[2], codes[3], r13, r14))
  end
  for c = 1, 3 do
    if add[c] and (codes[c] > 0 or tw[c + 1] > 0) then
      out:write(string.format("%d,additive,code %d k38 13=%04x 14=%04x\n", f, c, r13, r14))
    end
  end
  if tw[3] > 0 or tw[4] > 0 then
    out:write(string.format("%d,tile_codes,writes by code 0/1/2/3: %d/%d/%d/%d\n", f, tw[1], tw[2], tw[3], tw[4]))
  end
  local vin, von = k55[33] or 0, k55[34] or 0
  if vin ~= last_vin or von ~= last_von then
    out:write(string.format("%d,vinmix,%02x on %02x\n", f, vin, von))
    last_vin, last_von = vin, von
  end
  tw = {0, 0, 0, 0}
  out:flush()
end)
print("watch_mix: " .. DIR .. "/mixwatch.csv")
