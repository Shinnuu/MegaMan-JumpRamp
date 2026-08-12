--------------------------------------------------------------------------------
-- jumpramp hunter - finds the "airborne / on ground" byte for a game.
--
-- Research helper, not part of the ramp. Fully automatic: it drives the game
-- itself, so no human has to play along.
--
--   Phase A  reach gameplay. With a gate, mash until the gate opens. Without
--            one, mash for a fixed spell and screenshot so the result can be
--            eyeballed.
--   Phase B  hunt: repeat jump cycles, keeping only addresses that hold ONE
--            consistent value on the ground and a different consistent value in
--            the air. Timers, enemies and RNG fail this and drop out.
--   Phase C  characterise the survivors against real movement - idle, running,
--            jumping from a run - and record the SET of values each takes while
--            grounded versus while airborne.
--   Phase D  score: a byte whose grounded and airborne value sets are DISJOINT
--            is a real airborne flag. Anything overlapping is not.
--
-- Phase C exists because the hunt alone is misleading: it only ever samples a
-- standstill jump. On Mega Man X that made running (0x04) look like part of the
-- grounded value when it is a distinct state, and on Mega Man 3 it hid that the
-- airborne value also sets when walking off a ledge.
--
-- Appends to hunter_log.txt next to this script, then quits.
--
-- Run:  EmuHawk.exe --lua=<path>\hunter.lua "<rom.zip>"
--------------------------------------------------------------------------------

local CYCLES        = 14    -- hunt cycles
local SETTLE_FRAMES = 40
local HOLD_FRAMES   = 4
local RISE_FRAMES   = 8
local LAND_FRAMES   = 80
local GATE_TIMEOUT  = 5400  -- give up waiting for a gate after ~90s
local NOGATE_BOOT   = 2600  -- gateless games: mash this long before the first try
local RETRY_BOOT    = 1800  -- extra mashing before each retry
local ATTEMPTS      = 4     -- hunts to try before giving up
local SPEED         = 800   -- run the emulator fast; this is not a play session

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
local LOG = DIR .. "/hunter_log.txt"

local out = {}
local function say(s)
  table.insert(out, s)
  console.log(s)
end

local function finish()
  local f = io.open(LOG, "a")
  if f then
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
  end
  client.exit()
end

--------------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------------

local function zeros(base, len, d)
  for i = 0, len - 1 do
    if memory.read_u8(base + i, d) ~= 0 then return false end
  end
  return true
end

local SNES = { domain = "WRAM", jump = "B", scan_base = 0x0000, scan_len = 0x2000 }
local NES  = { domain = "RAM",  jump = "A", scan_base = 0x0000, scan_len = 0x0800 }

local function mk(id, patterns, base, gate)
  local p = { id = id, patterns = patterns, gate = gate }
  for k, v in pairs(base) do p[k] = v end
  return p
end

-- Ordered most-specific first: "megamanx" is a prefix of "megamanx2", and
-- "megaman" is a substring of nearly everything.
local CFG = {
  mk("mmx3", { "megamanx3", "rockmanx3" }, SNES, function(d)
    return memory.read_u8(0x00D1, d) == 0x04 and memory.read_u8(0x00D2, d) == 0x04
       and memory.read_u8(0x1F37, d) == 0x00 and zeros(0x1F45, 1, d)
  end),
  mk("mmx2", { "megamanx2", "rockmanx2" }, SNES, function(d)
    return memory.read_u8(0x00D1, d) == 0x04 and memory.read_u8(0x00D2, d) == 0x04
       and memory.read_u8(0x1F37, d) == 0x00 and zeros(0x1F25, 6, d)
  end),
  mk("mmx1", { "megamanx", "rockmanx" }, SNES, function(d)
    return memory.read_u8(0x00D2, d) == 0x04 and memory.read_u8(0x00D3, d) == 0x04
       and memory.read_u8(0x1F24, d) == 0x00 and zeros(0x1F13, 7, d)
  end),
  mk("mm7",  { "megaman7", "rockman7" },  SNES, nil),
  mk("mm6",  { "megaman6", "rockman6" },  NES,  nil),
  mk("mm5",  { "megaman5", "rockman5" },  NES,  nil),
  mk("mm4",  { "megaman4", "rockman4" },  NES,  nil),
  mk("mm3",  { "megaman3", "rockman3" },  NES,  function(d)
    return memory.read_u8(0x00B2, d) == 0x80 and memory.read_u8(0x0030, d) ~= 0x0E
  end),
  mk("mm2",  { "megaman2", "rockman2" },  NES,  nil),
  mk("mm1",  { "megaman",  "rockman"  },  NES,  nil),
}

local function detect()
  local raw = ""
  if gameinfo and gameinfo.getromname then raw = gameinfo.getromname() or "" end
  local norm = raw:lower():gsub("[^%w]", "")
  for _, c in ipairs(CFG) do
    for _, p in ipairs(c.patterns) do
      if norm:find(p, 1, true) then return c, raw end
    end
  end
  return nil, raw
end

local cfg, romname = detect()

say("==================================================")
say("hunter: " .. tostring(romname))
if not cfg then
  say("  no hunt profile for this ROM")
  finish()
end
say(string.format("  %s  domain %s  jump %s  scan $%04X..$%04X  gate %s",
  cfg.id, cfg.domain, cfg.jump, cfg.scan_base, cfg.scan_base + cfg.scan_len - 1,
  cfg.gate and "yes" or "NONE"))

pcall(client.speedmode, SPEED)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local ALL = { "Start", "A", "B", "Up", "Down", "Left", "Right" }

local function set(t)
  local s = {}
  for _, b in ipairs(ALL) do s[b] = false end
  for k, v in pairs(t or {}) do s[k] = v end
  joypad.set(s, 1)
end

local function step(input)
  set(input)
  emu.frameadvance()
end

local function idle(frames) for _ = 1, frames do step({}) end end

--------------------------------------------------------------------------------
-- Phase A: reach gameplay
--
-- Directions matter as much as Start. Mega Man 3's stage select opens with the
-- cursor on the centre Mega Man face, which is not a selectable stage, so Start
-- alone does nothing forever.
--------------------------------------------------------------------------------

local BOOT = {
  "Start", "Up", "Start", "A",
  "Left",  "Start", "Down", "Start",
  "Right", "Start", "B",
}

local el, bi = 0, 1
local function boot_burst()
  local b = BOOT[bi]
  bi = (bi % #BOOT) + 1
  for _ = 1, 2 do set({ [b] = true }); emu.frameadvance(); el = el + 1 end
  for _ = 1, 14 do
    step({}); el = el + 1
    if cfg.gate and cfg.gate(cfg.domain) then return true end
  end
  return false
end

if cfg.gate then
  local reached = false
  while el < GATE_TIMEOUT and not reached do reached = boot_burst() end
  if not reached then
    say(string.format("  FAILED: gate stayed shut for %d frames", el))
    finish()
  end
  say(string.format("  gate opened after %d frames", el))
else
  while el < NOGATE_BOOT do boot_burst() end
  say(string.format("  gateless: mashed %d frames, assuming in-stage", el))
end

idle(60)
pcall(client.screenshot, string.format("%s/hunter_shot_%s.png", DIR, cfg.id))

--------------------------------------------------------------------------------
-- Phase B: hunt
--------------------------------------------------------------------------------

local function snapshot()
  local t = {}
  local base, dom = cfg.scan_base, cfg.domain
  for i = 0, cfg.scan_len - 1 do t[i] = memory.read_u8(base + i, dom) end
  return t
end

local function live()
  if not cfg.gate then return true end
  return cfg.gate(cfg.domain)
end

local J = cfg.jump

local function hunt()
  local groundv, airv, alive = {}, {}, {}
  for i = 0, cfg.scan_len - 1 do alive[i] = true end

  local good = 0
  for _ = 1, CYCLES do
    idle(SETTLE_FRAMES)
    local okg = live()
    local g = snapshot()

    for _ = 1, HOLD_FRAMES do step({ [J] = true }) end
    idle(RISE_FRAMES)
    local oka = live()
    local a = snapshot()

    idle(LAND_FRAMES)

    if okg and oka then
      good = good + 1
      if good == 1 then
        for i = 0, cfg.scan_len - 1 do groundv[i] = g[i]; airv[i] = a[i] end
      else
        for i = 0, cfg.scan_len - 1 do
          if alive[i] and (g[i] ~= groundv[i] or a[i] ~= airv[i]) then alive[i] = false end
        end
      end
    end
  end

  local c = {}
  for i = 0, cfg.scan_len - 1 do
    if alive[i] and groundv[i] ~= airv[i] then table.insert(c, i) end
  end
  return c, good
end

-- Menus, stage selects and cutscenes all look the same from here: a hunt that
-- finds nothing means we were never actually in a stage. Rather than guess how
-- long each game's intro runs, mash more and try again.
local cand
for attempt = 1, ATTEMPTS do
  if attempt > 1 then
    for _ = 1, math.ceil(RETRY_BOOT / 16) do boot_burst() end
    idle(60)
  end
  pcall(client.screenshot, string.format("%s/hunter_shot_%s_%d.png", DIR, cfg.id, attempt))

  local good
  cand, good = hunt()
  say(string.format("  attempt %d: %d usable cycles, %d candidates", attempt, good, #cand))
  if #cand > 0 then break end
end

if #cand == 0 then
  say("  FAILED: nothing survived after " .. ATTEMPTS ..
      " attempts - check the screenshots, it never reached a stage")
  finish()
end

--------------------------------------------------------------------------------
-- Phase C: characterise survivors against real movement
--------------------------------------------------------------------------------

local seen = { ground = {}, air = {} }
for _, a in ipairs(cand) do
  seen.ground[a] = {}
  seen.air[a] = {}
end

local function record(bucket, frames, input)
  for _ = 1, frames do
    step(input)
    for _, a in ipairs(cand) do
      seen[bucket][a][memory.read_u8(cfg.scan_base + a, cfg.domain)] = true
    end
  end
end

-- Grounded samples: idle, plus SHORT walks each way. Holding a direction for
-- long enough can walk the player off a ledge, and a single falling sample in
-- the grounded bucket makes the real flag look overlapping - that is what wiped
-- out every one of Mega Man 1's 65 candidates on the first run.
record("ground", 40, {})
record("ground", 12, { Right = true })
record("ground", 12, { Left = true })
record("ground", 20, {})

-- Jump from a standstill. Skip the first frames of the press: the state machine
-- can lag a frame behind the input.
for _ = 1, 2 do step({ [J] = true }) end
record("air", 12, { [J] = true })
record("air", 6, {})
idle(120)

-- Jump out of a run, to catch states that only exist while moving - Mega Man X
-- runs in 0x04, not the idle 0x00, so a standstill-only sample is misleading.
for _ = 1, 14 do step({ Right = true }) end
for _ = 1, 2 do step({ Right = true, [J] = true }) end
record("air", 12, { Right = true, [J] = true })
record("air", 6, { Right = true })
idle(120)

record("ground", 30, {})

--------------------------------------------------------------------------------
-- Phase D: score
--------------------------------------------------------------------------------

local function keys(t)
  local ks = {}
  for k in pairs(t) do table.insert(ks, k) end
  table.sort(ks)
  local s = {}
  for _, k in ipairs(ks) do table.insert(s, string.format("%02X", k)) end
  return "{" .. table.concat(s, ",") .. "}", #ks
end

local disjoint, overlap = {}, {}
for _, a in ipairs(cand) do
  local clash = false
  for v in pairs(seen.air[a]) do
    if seen.ground[a][v] then clash = true break end
  end
  table.insert(clash and overlap or disjoint, a)
end

-- A genuine state flag takes very few distinct values. Sprite coordinates and
-- animation counters are disjoint too, but sprawl across dozens - so sort by
-- total set size and the real flag floats to the top.
local size = {}
for _, a in ipairs(disjoint) do
  local _, ng = keys(seen.ground[a])
  local _, na = keys(seen.air[a])
  size[a] = ng + na
end
table.sort(disjoint, function(x, y)
  if size[x] ~= size[y] then return size[x] < size[y] end
  return x < y
end)

say(string.format("  characterise: %d DISJOINT, %d overlapping", #disjoint, #overlap))
say("  -- disjoint, tightest first (most likely airborne flag at the top) --")
for _, a in ipairs(disjoint) do
  local gs = keys(seen.ground[a])
  local as = keys(seen.air[a])
  say(string.format("    $%04X  ground=%-22s air=%s", cfg.scan_base + a, gs, as))
end
if #disjoint == 0 then
  say("    (none - the hunt candidates were all noise)")
end

finish()
