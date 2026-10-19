-- Start the game in a later stage, for corpora beyond what the scripted inputs reach: with dump_state.lua as
-- RUSCRIPT=<this file>, the byte at POKE_ADDR (default $200300, which holds 0 / 1 / 4 in the first stage, the
-- second and the attract demo's jungle stage) is written with POKE_VAL every frame from POKE_FROM to POKE_TO
-- (defaults 300 .. 1200: from the start button to before the first stage is set up).
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local addr = tonumber(os.getenv("POKE_ADDR") or "200300", 16)
local val  = tonumber(os.getenv("POKE_VAL") or "1")
local from = tonumber(os.getenv("POKE_FROM") or "300")
local to   = tonumber(os.getenv("POKE_TO") or "1200")
local n = 0
_G.DUMPKEEP.poke = emu.add_machine_frame_notifier(function()
  n = n + 1
  if n >= from and n <= to then sp:write_u8(addr, val) end
end)
print(string.format("stage_poke: $%06x = %d, frames %d..%d", addr, val, from, to))
