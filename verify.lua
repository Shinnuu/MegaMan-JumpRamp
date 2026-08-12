--------------------------------------------------------------------------------
-- jumpramp verify - proves a game's exact counting is actually exact.
--
-- Drives the game itself: performs a known number of real jumps, and between
-- them mashes the jump button while PROVABLY airborne (checked against the
-- airborne byte, not assumed from timing). Then counts both ways:
--
--   EXACT  - airborne transition + jump button within JUMP_WINDOW frames
--   button - every jump-button press during live gameplay
--
-- A correct airborne byte gives exact == the number of real jumps, while the
-- button counter inflates by every mash. If exact is high, the byte is wrong.
--
-- The timing here is deliberately not fixed: a tapped jump in Mega Man 3 lasts
-- only ~12 frames, so a "midair" mash on a fixed delay can land on the ground
-- and be a genuine second jump. Mashes only happen while the byte says airborne.
--
-- Keep the AIRBORNE table in step with jumpramp.lua - profile_sync_test.py
-- checks that for you.
--
-- Run:  EmuHawk.exe --lua=<path>\verify.lua "<rom.zip>"
--------------------------------------------------------------------------------

local CYCLES      = 6
local MASHES      = 3
local JUMP_WINDOW = 8      -- must match jumpramp.lua
local SPEED       = 800

--------------------------------------------------------------------------------

local function script_dir()
  local ok, dir = pcall(function()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src:match("^(.*)[/\\][^/\\]*$")
  end)
  if ok then return dir end
  return nil
end

local DIR = script_dir() or "."
local LOG = DIR .. "/verify_log.txt"

local out = {}
local function say(s) table.insert(out, s); console.log(s) end
local function finish()
  local f = io.open(LOG, "a")
  if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
  client.exit()
end

--------------------------------------------------------------------------------
-- Profiles. AIRBORNE must mirror jumpramp.lua.
--------------------------------------------------------------------------------

local function zeros(base, len, d)
  for i = 0, len - 1 do
    if memory.read_u8(base + i, d) ~= 0 then return false end
  end
  return true
end

local SNES = { domain = "WRAM", jump = "B" }
local NES  = { domain = "RAM",  jump = "A" }

-- boot: how long to mash for a gateless game before assuming we are in a stage.
-- These are the durations that actually worked during hunting; too few frames
-- leaves us in a stage select, too many can walk past the stage entirely.
local function mk(id, patterns, base, airborne, gate, boot)
  local p = { id = id, patterns = patterns, airborne = airborne, gate = gate,
              boot = boot or 4400 }
  for k, v in pairs(base) do p[k] = v end
  return p
end

local CFG = {
  mk("mmx3", { "megamanx3", "rockmanx3" }, SNES,
     { addr = 0x09DA, values = { 0x06, 0x08, 0x0A } }, function(d)
    return memory.read_u8(0x00D1, d) == 0x04 and memory.read_u8(0x00D2, d) == 0x04
       and memory.read_u8(0x1F37, d) == 0x00 and zeros(0x1F45, 1, d)
  end),
  mk("mmx2", { "megamanx2", "rockmanx2" }, SNES,
     { addr = 0x09DA, values = { 0x06, 0x08, 0x0A } }, function(d)
    return memory.read_u8(0x00D1, d) == 0x04 and memory.read_u8(0x00D2, d) == 0x04
       and memory.read_u8(0x1F37, d) == 0x00 and zeros(0x1F25, 6, d)
  end),
  mk("mmx1", { "megamanx", "rockmanx" }, SNES,
     { addr = 0x0BAA, values = { 0x06, 0x08, 0x0A } }, function(d)
    return memory.read_u8(0x00D2, d) == 0x04 and memory.read_u8(0x00D3, d) == 0x04
       and memory.read_u8(0x1F24, d) == 0x00 and zeros(0x1F13, 7, d)
  end),
  mk("mm7",  { "megaman7", "rockman7" }, SNES,
     { addr = 0x0C02, values = { 0x06, 0x08, 0x0A } }, nil, 6300),
  mk("mm6",  { "megaman6", "rockman6" }, NES,
     { addr = 0x00AD, values = { 0x00 } }, nil, 2608),
  mk("mm5",  { "megaman5", "rockman5" }, NES,
     { addr = 0x0030, values = { 0x01 } }, nil, 2608),
  mk("mm4",  { "megaman4", "rockman4" }, NES,
     { addr = 0x0030, values = { 0x01 } }, nil, 4400),
  mk("mm3",  { "megaman3", "rockman3" }, NES,
     { addr = 0x0030, values = { 0x01 } }, function(d)
    return memory.read_u8(0x00B2, d) == 0x80 and memory.read_u8(0x0030, d) ~= 0x0E
  end),
  mk("mm2",  { "megaman2", "rockman2" }, NES,
     { addr = 0x0032, values = { 0x00 } }, nil, 2720),
  mk("mm1",  { "megaman",  "rockman"  }, NES,
     { addr = 0x01F5, values = { 0xCC } }, nil, 6300),
}

local raw = ""
if gameinfo and gameinfo.getromname then raw = gameinfo.getromname() or "" end
local norm = raw:lower():gsub("[^%w]", "")
local cfg
for _, c in ipairs(CFG) do
  for _, p in ipairs(c.patterns) do
    if norm:find(p, 1, true) then cfg = c break end
  end
  if cfg then break end
end

say("==================================================")
say("verify: " .. raw)
if not cfg then say("  no profile"); finish() end
if not cfg.airborne then
  say("  " .. cfg.id .. ": no airborne byte yet - nothing to verify")
  finish()
end
say(string.format("  %s  airborne $%04X  domain %s  jump %s",
  cfg.id, cfg.airborne.addr, cfg.domain, cfg.jump))

pcall(client.speedmode, SPEED)

--------------------------------------------------------------------------------

local ALL = { "Start", "A", "B", "Up", "Down", "Left", "Right" }
local function set(t)
  local s = {}
  for _, b in ipairs(ALL) do s[b] = false end
  for k, v in pairs(t or {}) do s[k] = v end
  joypad.set(s, 1)
end

local function airborne_now()
  local v = memory.read_u8(cfg.airborne.addr, cfg.domain)
  for _, w in ipairs(cfg.airborne.values) do if v == w then return true end end
  return false
end

local function live()
  if not cfg.gate then return true end
  return cfg.gate(cfg.domain)
end

local exact, button = 0, 0
local prev_jump, prev_air, press_age = false, false, 999

-- one frame, running both counters exactly as jumpramp.lua does
local function frame(input)
  set(input)
  emu.frameadvance()

  local held = (input or {})[cfg.jump] == true
  local ok = live()

  if held and not prev_jump then press_age = 0 else press_age = press_age + 1 end

  local air = airborne_now()
  if air and not prev_air and press_age <= JUMP_WINDOW and ok then exact = exact + 1 end
  prev_air = air

  if held and not prev_jump and ok then button = button + 1 end
  prev_jump = held
end

--------------------------------------------------------------------------------
-- reach gameplay (counters not yet armed)
--------------------------------------------------------------------------------

local BOOT = {
  "Start", "Up", "Start", "A",
  "Left",  "Start", "Down", "Start",
  "Right", "Start", "B",
}
local el, bi = 0, 1
local function boot_burst()
  local b = BOOT[bi]; bi = (bi % #BOOT) + 1
  for _ = 1, 2 do set({ [b] = true }); emu.frameadvance(); el = el + 1 end
  for _ = 1, 14 do
    set({}); emu.frameadvance(); el = el + 1
    if cfg.gate and cfg.gate(cfg.domain) then return true end
  end
  return false
end

if cfg.gate then
  local reached = false
  while el < 5400 and not reached do reached = boot_burst() end
  if not reached then say("  FAILED to reach gameplay"); finish() end
else
  while el < cfg.boot do boot_burst() end
end
for _ = 1, 90 do set({}); emu.frameadvance() end

-- sanity: we should be standing on the ground before we start
local settle = 0
while airborne_now() and settle < 400 do set({}); emu.frameadvance(); settle = settle + 1 end

exact, button, prev_jump, prev_air, press_age = 0, 0, false, false, 999

--------------------------------------------------------------------------------

local J = cfg.jump
local midair = 0

-- The jump is held only briefly on purpose. Mega Man 1's airborne window is
-- about 12 frames, so a long hold ends after the jump is already over and no
-- mash can ever land midair - which made MM1 impossible to prove either way.
local function scenario()
  exact, button, prev_jump, prev_air, press_age = 0, 0, false, false, 999
  midair = 0

  for _ = 1, CYCLES do
    local guard = 0
    while airborne_now() and guard < 300 do frame({}); guard = guard + 1 end
    for _ = 1, 40 do frame({}) end

    for _ = 1, 6 do frame({ [J] = true }) end   -- the real jump
    frame({})                                   -- release, so mash 1 is an edge

    local m = 0
    while m < MASHES and airborne_now() do      -- provably midair
      midair = midair + 1
      frame({ [J] = true })
      frame({})
      m = m + 1
    end

    guard = 0
    while airborne_now() and guard < 300 do frame({}); guard = guard + 1 end
    for _ = 1, 40 do frame({}) end
  end
end

-- midair == 0 means the player never left the ground, which almost always means
-- we were in a menu or a cutscene rather than that the byte is wrong. Mash on
-- and try again rather than reporting a failure we cannot stand behind.
for attempt = 1, 4 do
  if attempt > 1 then
    for _ = 1, 110 do boot_burst() end
    for _ = 1, 60 do set({}); emu.frameadvance() end
    local s = 0
    while airborne_now() and s < 400 do set({}); emu.frameadvance(); s = s + 1 end
  end
  scenario()
  say(string.format("  attempt %d: exact=%d midair=%d", attempt, exact, midair))
  if midair > 0 then break end
end

local want_button = CYCLES + midair
say(string.format("  real jumps      : %d", CYCLES))
say(string.format("  midair mashes   : %d (airborne at press)", midair))
say(string.format("  EXACT counter   : %d  (want %d)  %s",
  exact, CYCLES, exact == CYCLES and "PASS" or "FAIL"))
say(string.format("  button counter  : %d  (want %d)  %s",
  button, want_button, button == want_button and "ok" or "odd"))
if midair == 0 then
  say("  WARNING: no midair mashes happened - jump may not have left the ground,")
  say("           so this run does not actually prove anything")
end

finish()
