--------------------------------------------------------------------------------
-- Mega Man (NES + SNES) - Jump Speed Ramp
--
-- Every jump makes the emulator faster. It never resets on its own; only the
-- Home hotkey brings it back to normal.
--
-- Load in EmuHawk:  Tools -> Lua Console -> Script -> Open Script
--
-- NES:   Mega Man 1-6                        (jump = A)
-- SNES:  Mega Man 7, X, X2, X3, & Bass       (jump = B)
--
-- Counting is exact on every game except Mega Man & Bass: a jump registers only
-- when the player actually leaves the ground AND the jump button was pressed,
-- so midair mashing, walking off ledges and slides do not inflate it.
--
--   ==========================================================================
--    TO CHANGE HOW FAST IT RAMPS, edit the STEP line a few lines below, save
--    the file, then reload the script in the Lua Console. Nothing else needs
--    touching. See "Changing the speed increment" in the README.
--   ==========================================================================
--------------------------------------------------------------------------------

--------------------------------- CONFIG ---------------------------------------

--  >>>>>>>>>>  HOW MUCH FASTER PER JUMP  <<<<<<<<<<
--
--     0.5    +1% every 2 jumps     (default)
--     1      +1% every jump        (steeper)
--     0.1    +1% every 10 jumps    (very gradual)
--     2.5    +2.5% every jump      (brutal)
--    -0.5    ramps DOWN instead of up
--
local STEP = 0.5
--
--  ^^^^^  change that number, save the file, reload the script  ^^^^^

-- Fractions accumulate exactly and do not drift. Note though that BizHawk only
-- runs at WHOLE percentages - there is no such thing as 100.5% speed - so a
-- fractional STEP does not make the speed change by a fraction, it makes it
-- change less often. With STEP = 0.5 the speed moves every second jump. When
-- STEP is fractional the overlay shows the exact running total in brackets, so
-- banked progress is visible between moves.

local BASE_SPEED  = 100    -- speed with zero jumps, percent
local MAX_SPEED   = 1000   -- your own ceiling; also clamped to BizHawk's 6400
local MIN_SPEED   = 25     -- your own floor; also clamped to BizHawk's 1

-- BizHawk's real limits, measured rather than assumed. client.speedmode()
-- truncates fractions to whole percent, and SILENTLY IGNORES anything outside
-- 1..6400 - it never raises an error, the speed simply does not change. Without
-- clamping to these, an over-ambitious MAX_SPEED looks like a stuck ramp.
local EMU_MIN_SPEED = 1
local EMU_MAX_SPEED = 6400

-- Hotkeys. If one does nothing, set DEBUG_KEYS = true to learn the real name
-- BizHawk uses for the key you pressed, then paste it in here.
local KEY_RESET   = "Home"      -- back to 100%, jump counter to zero
local KEY_TOGGLE  = "End"       -- pause/resume counting (speed is held)
local KEY_UP      = "PageUp"    -- +1 jump by hand (practice)
local KEY_DOWN    = "PageDown"  -- -1 jump by hand (practice)

-- How many frames after a jump-button press the player may go airborne and
-- still have it count as that press's jump. Only used by profiles that have a
-- verified `airborne` byte. Measured: both MMX and MM3 enter their airborne
-- state within 1-2 frames, so this is deliberately slack.
local JUMP_WINDOW = 8

local DEBUG_KEYS  = false  -- true = print every keyboard key name to the console
local DEBUG_GATE  = false  -- true = show which gate condition is blocking
local PERSIST     = true   -- remember the counter across script reloads

--------------------------------------------------------------------------------
-- Profiles
--
-- Gate conditions are evaluated against `domain`. Each entry is
--   { addr = <n>, len = <n, default 1>, eq | ne | oneof }
-- and every byte in the range must satisfy it. A nil gate means "count every
-- button press", which is honest but noisy - menu presses register too.
--
-- Order matters: patterns are plain substring tests against the ROM title
-- lowercased with non-alphanumerics stripped ("megamanx2usa"), and "megaman"
-- is a substring of nearly every other title, so MM1 has to be tested last.
--------------------------------------------------------------------------------

local SNES_JUMP = { "B" }   -- Mega Man X / 7 / & Bass: B jumps, Y fires
local NES_JUMP  = { "A" }   -- Mega Man 1-6: A jumps, B fires

local PROFILES = {
  ----------------------------------------------------------------- SNES ------
  {
    id = "mmx3", name = "Mega Man X3", platform = "SNES",
    patterns = { "megamanx3", "rockmanx3" },
    domain = "WRAM", jump_buttons = SNES_JUMP,
    gate = {
      { addr = 0x00D1, eq = 0x04 },              -- menu state: in game
      { addr = 0x00D2, eq = 0x04 },              -- gameplay state (0x06 = dead)
      { addr = 0x1F37, eq = 0x00 },              -- not paused
      { addr = 0x1F45, eq = 0x00, len = 1 },     -- can_move
    },
    -- Same state machine as X1's $0BAA, at a different struct base.
    airborne = { addr = 0x09DA, values = { 0x06, 0x08, 0x0A } },
  },
  {
    id = "mmx2", name = "Mega Man X2", platform = "SNES",
    patterns = { "megamanx2", "rockmanx2" },
    domain = "WRAM", jump_buttons = SNES_JUMP,
    gate = {
      { addr = 0x00D1, eq = 0x04 },
      { addr = 0x00D2, eq = 0x04 },
      { addr = 0x1F37, eq = 0x00 },
      { addr = 0x1F25, eq = 0x00, len = 6 },
    },
    -- Originally inferred rather than hunted: X2's intro puts X on the ride
    -- chaser, where he dies before any hunt can measure a jump. X2 and X3 share
    -- their HP address ($09FF), and on both X1 and X3 the state byte sits
    -- exactly 0x25 below HP - so X2's had to be $09DA. Since confirmed from a
    -- savestate taken in a normal on-foot stage: 6/6 with 18 midair mashes
    -- correctly rejected.
    airborne = { addr = 0x09DA, values = { 0x06, 0x08, 0x0A } },
  },
  {
    id = "mmx1", name = "Mega Man X", platform = "SNES",
    patterns = { "megamanx", "rockmanx" },
    domain = "WRAM", jump_buttons = SNES_JUMP,
    gate = {
      { addr = 0x00D2, eq = 0x04 },
      { addr = 0x00D3, eq = 0x04 },
      { addr = 0x1F24, eq = 0x00 },
      { addr = 0x1F13, eq = 0x00, len = 7 },
    },
    -- Player state machine, found by hunter.lua and characterised against real
    -- movement: 0x00 idle, 0x02 start walk, 0x04 walking/running,
    -- 0x06 jump start, 0x08 rising, 0x0A falling. (The AP client writes 0x0C
    -- here to kill the player.) Running is 0x04, NOT 0x00 - which is why a
    -- naive "left 0x00" test would miss every running jump.
    airborne = { addr = 0x0BAA, values = { 0x06, 0x08, 0x0A } },
  },
  {
    id = "mm7", name = "Mega Man 7", platform = "SNES",
    patterns = { "megaman7", "rockman7" },
    domain = "WRAM", jump_buttons = SNES_JUMP,
    gate = nil,  -- no in-stage flag found; the airborne byte self-gates
    -- The X-series state machine again, on a classic-series game.
    airborne = { addr = 0x0C02, values = { 0x06, 0x08, 0x0A } },
  },
  {
    id = "mmbass", name = "Mega Man & Bass", platform = "SNES",
    patterns = { "rockmanforte", "rockmanandforte", "megamanbass" },
    domain = "WRAM", jump_buttons = SNES_JUMP,
    gate = nil,  -- not yet mapped
  },

  ------------------------------------------------------------------ NES ------
  {
    id = "mm6", name = "Mega Man 6", platform = "NES",
    patterns = { "megaman6", "rockman6" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = nil,  -- no in-stage flag found; the airborne byte self-gates
    -- MM6 breaks the classic-series pattern: not $0030, and inverted -
    -- 0x01 means on the ground, 0x00 means airborne.
    airborne = { addr = 0x00AD, values = { 0x00 } },
  },
  {
    id = "mm5", name = "Mega Man 5", platform = "NES",
    patterns = { "megaman5", "rockman5" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = nil,  -- no in-stage flag found; the airborne byte self-gates
    airborne = { addr = 0x0030, values = { 0x01 } },
  },
  {
    id = "mm4", name = "Mega Man 4", platform = "NES",
    patterns = { "megaman4", "rockman4" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = nil,  -- no in-stage flag found; the airborne byte self-gates
    airborne = { addr = 0x0030, values = { 0x01 } },
  },
  {
    id = "mm3", name = "Mega Man 3", platform = "NES",
    patterns = { "megaman3", "rockman3" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = {
      -- Health-bar state doubles as an init guard and an in-stage tracker:
      -- 0x80 = in a stage, 0x00 = not. Any other value means uninitialised.
      { addr = 0x00B2, eq = 0x80 },
      -- Mega Man state; 0x0E is the death state the AP client writes to kill.
      { addr = 0x0030, ne = 0x0E },
    },
    -- Same byte doubles as the airborne flag: 0x00 grounded (idle AND running),
    -- 0x01 airborne. Verified that 0x01 also sets when walking off a ledge with
    -- no button press, which is why the jump-button window is required to tell a
    -- jump from a fall. It also means sliding (Down+A) no longer miscounts: the
    -- button is pressed but he never leaves the ground.
    airborne = { addr = 0x0030, values = { 0x01 } },
  },
  {
    id = "mm2", name = "Mega Man 2", platform = "NES",
    patterns = { "megaman2", "rockman2" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = {
      -- Only an init guard, not an in-stage test: difficulty is 0 or 1 once the
      -- game has booted.
      { addr = 0x00CB, oneof = { 0x00, 0x01 } },
    },
    -- Inverted, like MM6: 0x01 on the ground, 0x00 airborne. ($0033 mirrors it.)
    airborne = { addr = 0x0032, values = { 0x00 } },
  },
  {
    -- Must stay last: "megaman"/"rockman" match nearly every other title.
    id = "mm1", name = "Mega Man", platform = "NES",
    patterns = { "megaman", "rockman" },
    domain = "RAM", jump_buttons = NES_JUMP,
    gate = nil,  -- no in-stage flag found; the airborne byte self-gates
    -- Lowest-confidence of the set. MM1 has no clean state enum; $01F5 reads
    -- 0x00/0x01 on the ground and 0xCC while airborne, and it only holds that
    -- value for ~6 frames of a jump. It counts correctly (verified 6/6), and
    -- 0xCC is distinctive enough to be unlikely to occur by accident, but it is
    -- clearly not the canonical "Mega Man state" byte. $01F6 works equally well.
    airborne = { addr = 0x01F5, values = { 0xCC } },
  },
}

--------------------------------- STATE ----------------------------------------

local jumps      = 0
local counting   = true
local profile    = nil
local applied    = -1      -- last speed handed to the emulator
local FRACTIONAL_STEP = (STEP % 1) ~= 0

local prev_jump  = false
local prev_air   = false
local press_age  = 999     -- frames since the jump button last went down
local prev_keys  = {}
local warned     = false
local block_desc = ""      -- for DEBUG_GATE

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

-- Not every Lua sandbox exposes the debug library, so this stays best-effort:
-- if we cannot locate ourselves, the state file just lands in EmuHawk's own
-- working directory instead.
local function script_dir()
  local ok, dir = pcall(function()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src:match("^(.*)[/\\][^/\\]*$")
  end)
  if ok then return dir end
  return nil
end

-- Set once the profile is known. Each game keeps its own counter, so a run in
-- one game cannot clobber another - and two EmuHawk instances can be open at
-- the same time without fighting over a single file.
local STATE_FILE = nil

local function state_path()
  local id = (profile and profile.id) or "unknown"
  return (script_dir() or ".") .. "/jumpramp_state_" .. id .. ".txt"
end

local function save_state()
  if not PERSIST or not STATE_FILE then return end
  local f = io.open(STATE_FILE, "w")
  if not f then return end
  f:write(tostring(jumps))
  f:close()
end

local function load_state()
  if not PERSIST or not STATE_FILE then return end
  local f = io.open(STATE_FILE, "r")
  if not f then return end
  local n = tonumber(f:read("*l") or "")
  f:close()
  if n and n >= 0 then jumps = math.floor(n) end
end

--------------------------------------------------------------------------------
-- Game detection
--------------------------------------------------------------------------------

local function detect_profile()
  local raw = ""
  if gameinfo and gameinfo.getromname then raw = gameinfo.getromname() or "" end
  local norm = raw:lower():gsub("[^%w]", "")
  for _, p in ipairs(PROFILES) do
    for _, pat in ipairs(p.patterns) do
      if norm:find(pat, 1, true) then return p end
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Gameplay gate
--------------------------------------------------------------------------------

local function read8(addr, domain)
  local ok, v = pcall(memory.read_u8, addr, domain)
  if ok then return v end
  return nil
end

-- Reading a domain that does not exist does NOT raise: BizHawk silently falls
-- back to another domain and hands back plausible-looking garbage. Verified on
-- 2.11.1 - on SNES, which has no "RAM" domain, memory.read_u8(0x30, "RAM")
-- happily returned 0x02. So the domain has to be checked up front by name;
-- a failed read can never be relied on to signal it.
--
-- This matters most on NES, where MM2-6 DO expose a "WRAM" domain, but it is
-- cartridge save RAM rather than main RAM. Main RAM is "RAM".
--
-- Returns true, false, or nil when the list cannot be enumerated at all.
local function domain_exists(name)
  local ok, list = pcall(memory.getmemorydomainlist)
  if not ok or not list then return nil end
  for i = 0, 63 do
    local d = list[i]
    if d == nil then break end
    if tostring(d) == name then return true end
  end
  return false
end

-- Returns true (pass), false (blocked), or nil (domain unreadable).
local function check_passes(c, domain)
  local len = c.len or 1
  for i = 0, len - 1 do
    local v = read8(c.addr + i, domain)
    if v == nil then return nil end

    if c.eq ~= nil and v ~= c.eq then return false end
    if c.ne ~= nil and v == c.ne then return false end
    if c.oneof ~= nil then
      local hit = false
      for _, w in ipairs(c.oneof) do
        if v == w then hit = true end
      end
      if not hit then return false end
    end
  end
  return true
end

local function in_gameplay()
  block_desc = ""
  if not profile or not profile.gate then
    return true  -- ungated profile: every button press counts
  end

  for _, c in ipairs(profile.gate) do
    local r = check_passes(c, profile.domain)
    if r == nil then
      if not warned then
        console.log(string.format(
          "jumpramp: cannot read the '%s' domain - is the right core loaded?",
          profile.domain))
        warned = true
      end
      return false
    end
    if r == false then
      block_desc = string.format("blocked by $%04X", c.addr)
      return false
    end
  end
  return true
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function jump_held()
  local ok, pad = pcall(joypad.get, 1)
  if not ok or not pad then return false end
  local buttons = profile and profile.jump_buttons or SNES_JUMP
  for _, b in ipairs(buttons) do
    if pad[b] then return true end
  end
  return false
end

-- Rising-edge test for a keyboard key, so holding it only fires once.
local function key_pressed(keys, name)
  return keys[name] and not prev_keys[name]
end

-- true / false, or nil when this profile has no verified airborne byte.
local function is_airborne()
  local ab = profile and profile.airborne
  if not ab then return nil end
  local v = read8(ab.addr, profile.domain)
  if v == nil then return nil end
  for _, w in ipairs(ab.values) do
    if v == w then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- Speed
--------------------------------------------------------------------------------

-- The true accumulated speed, which may be fractional.
local function exact_speed()
  local s = BASE_SPEED + (jumps * STEP)
  if s > MAX_SPEED then s = MAX_SPEED end
  if s < MIN_SPEED then s = MIN_SPEED end
  return s
end

-- What the emulator can actually be set to: whole percent, inside its own
-- accepted range. Floor rather than round, so a fraction of a percent that has
-- not been fully earned yet does not get handed out early.
local function target_speed()
  -- The epsilon matters. Binary floating point can leave a fractional step just
  -- under a whole number - 0.3 * 10 is 2.9999999999999996, not 3 - and a bare
  -- floor would then hand out the percent one jump late. Far too small to
  -- affect a step the player has not genuinely earned.
  local s = math.floor(exact_speed() + 1e-9)
  if s < EMU_MIN_SPEED then s = EMU_MIN_SPEED end
  if s > EMU_MAX_SPEED then s = EMU_MAX_SPEED end
  return s
end

local function apply_speed()
  local s = target_speed()
  if s ~= applied then
    client.speedmode(s)
    applied = s
  end
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

-- Order matters: the state file is named after the profile, so detect first.
profile = detect_profile()
STATE_FILE = state_path()
load_state()

console.log("=== Mega Man Jump Speed Ramp ===")
if profile then
  console.log(string.format("Game: %s (%s)%s", profile.name, profile.platform,
    profile.gate and "" or "   [UNGATED - menu presses will count]"))
  console.log(string.format("Jump button: %s   Domain: %s   Counting: %s",
    table.concat(profile.jump_buttons, "/"), profile.domain,
    profile.airborne
      and string.format("EXACT (airborne byte $%04X)", profile.airborne.addr)
      or "button presses only"))

  -- Fail loud rather than gating on garbage from a fallback domain.
  if profile.gate then
    local present = domain_exists(profile.domain)
    if present == false then
      console.log(string.format(
        "jumpramp: WARNING - this core exposes no '%s' domain. Disabling the",
        profile.domain))
      console.log("  gate and counting every button press, rather than gating")
      console.log("  on memory that is not what the profile expects.")
      profile.gate = nil
    elseif present == nil then
      console.log("jumpramp: note - could not enumerate memory domains; " ..
        "gate is running unverified.")
    end
  end
else
  console.log("Game: UNRECOGNISED - running ungated, assuming SNES buttons.")
  console.log("Add the ROM title to a profile's `patterns` list to fix this.")
end
console.log(string.format("Step: %s%% per jump   base %d%%   range %d-%d%%",
  tostring(STEP), BASE_SPEED, MIN_SPEED, MAX_SPEED))

if STEP == 0 then
  console.log("jumpramp: STEP is 0 - the speed will never change.")
elseif FRACTIONAL_STEP then
  local per = 1 / math.abs(STEP)
  console.log("jumpramp: fractional step - BizHawk only runs at whole percent,")
  console.log(string.format(
    "  so the speed moves once every %.1f jumps, not on every jump.", per))
end
if MAX_SPEED > EMU_MAX_SPEED then
  console.log(string.format(
    "jumpramp: MAX_SPEED %d is above BizHawk's %d ceiling - clamping to %d.",
    MAX_SPEED, EMU_MAX_SPEED, EMU_MAX_SPEED))
end

console.log(string.format("Resuming at %d jumps (%d%%)", jumps, target_speed()))
console.log(string.format("Hotkeys: %s reset | %s pause counting | %s +1 | %s -1",
  KEY_RESET, KEY_TOGGLE, KEY_UP, KEY_DOWN))
console.log("To change the ramp: edit STEP near the top of jumpramp.lua, save,")
console.log("  then reload this script in the Lua Console.")

-- Leave the emulator at normal speed when the script is stopped, otherwise
-- EmuHawk stays stuck at whatever multiplier the run ended on.
event.onexit(function()
  client.speedmode(100)
end)

apply_speed()

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

while true do
  local keys = input.get() or {}

  if DEBUG_KEYS then
    for k, _ in pairs(keys) do
      if not prev_keys[k] then console.log("key: " .. tostring(k)) end
    end
  end

  if key_pressed(keys, KEY_RESET) then
    jumps = 0
    save_state()
    console.log("jumpramp: reset to " .. BASE_SPEED .. "%")
  elseif key_pressed(keys, KEY_TOGGLE) then
    counting = not counting
    console.log("jumpramp: counting " .. (counting and "ON" or "PAUSED"))
  elseif key_pressed(keys, KEY_UP) then
    jumps = jumps + 1
    save_state()
  elseif key_pressed(keys, KEY_DOWN) then
    if jumps > 0 then jumps = jumps - 1 end
    save_state()
  end

  -- Track the raw button every frame, gated or not, so a press that is held
  -- across a gate transition does not fire the moment gameplay resumes.
  local held = jump_held()
  local live = in_gameplay()

  if held and not prev_jump then
    press_age = 0
  else
    press_age = press_age + 1
  end

  local air = is_airborne()

  if air ~= nil then
    -- Exact mode. A jump is the player entering the airborne state *because* of
    -- a button press. Entering it without a recent press is a fall off a ledge;
    -- a press that never leaves the ground is midair mashing, or a slide.
    if air and not prev_air and press_age <= JUMP_WINDOW and live and counting then
      jumps = jumps + 1
      save_state()
    end
    prev_air = air
  else
    -- Button mode: no verified airborne byte for this game yet.
    if held and not prev_jump and live and counting then
      jumps = jumps + 1
      save_state()
    end
  end

  prev_jump = held
  prev_keys = keys

  apply_speed()

  local status
  if not counting then
    status = "PAUSED"
  elseif live then
    status = "ACTIVE"
  else
    status = "waiting"
    if DEBUG_GATE and block_desc ~= "" then status = status .. " (" .. block_desc .. ")" end
  end

  gui.text(4,  4, string.format("JUMPS %d", jumps))
  if FRACTIONAL_STEP then
    -- Show the running total too, otherwise a fractional step looks broken:
    -- the jump count rises while the whole-percent speed sits still.
    gui.text(4, 20, string.format("SPEED %d%%  (%.2f)", target_speed(), exact_speed()))
  else
    gui.text(4, 20, string.format("SPEED %d%%", target_speed()))
  end
  gui.text(4, 36, status)

  emu.frameadvance()
end
