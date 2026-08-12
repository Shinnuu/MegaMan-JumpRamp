--------------------------------------------------------------------------------
-- jumpramp probe - verification helper, not part of the ramp itself.
--
-- Boots a ROM, records what BizHawk reports about it, then quits. Used to
-- confirm three things the ramp script depends on and that cannot be checked
-- offline:
--
--   1. what gameinfo.getromname() actually returns for this ROM
--   2. that the memory domain the profile expects ("RAM" / "WRAM") exists
--   3. what the gate bytes read at boot
--
-- Appends to probe_log.txt next to this script, so a sweep over several ROMs
-- accumulates into one file.
--
-- Run:  EmuHawk.exe --lua=<path>\probe.lua "<path to rom.zip>"
--------------------------------------------------------------------------------

local FRAMES = 240   -- let the ROM boot before sampling

local function script_dir()
  local ok, dir = pcall(function()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src:match("^(.*)[/\\][^/\\]*$")
  end)
  if ok then return dir end
  return nil
end

local LOG = (script_dir() or ".") .. "/probe_log.txt"

local out = {}
local function say(s)
  table.insert(out, s)
  console.log(s)
end

for _ = 1, FRAMES do
  emu.frameadvance()
end

say("--------------------------------------------------")

local name = "<none>"
if gameinfo and gameinfo.getromname then name = gameinfo.getromname() or "<nil>" end
say("romname : " .. tostring(name))
say("normal  : " .. tostring(name):lower():gsub("[^%w]", ""))

local hash = "<none>"
if gameinfo and gameinfo.getromhash then hash = gameinfo.getromhash() or "<nil>" end
say("romhash : " .. tostring(hash))

-- Domains
local doms = {}
local ok, list = pcall(memory.getmemorydomainlist)
if ok and list then
  for i = 0, 63 do
    local d = list[i]
    if d == nil then break end
    table.insert(doms, tostring(d))
  end
end
say("domains : " .. (#doms > 0 and table.concat(doms, ", ") or "<could not enumerate>"))

-- Gate bytes for whichever platform this looks like.
local function dump(domain, addrs)
  for _, a in ipairs(addrs) do
    local okr, v = pcall(memory.read_u8, a, domain)
    say(string.format("  %-5s $%04X = %s", domain, a,
      okr and string.format("0x%02X", v) or "UNREADABLE"))
  end
end

say("gate bytes at boot:")
dump("RAM",  { 0x0030, 0x00B2, 0x00CB })                    -- NES: MM3 state/bar, MM2 difficulty
dump("WRAM", { 0x00D1, 0x00D2, 0x00D3, 0x1F24, 0x1F37 })    -- SNES: MMX menu/gameplay/pause

local f = io.open(LOG, "a")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
  console.log("probe: appended to " .. LOG)
end

client.exit()
