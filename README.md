# Mega Man (NES + SNES) — Jump Speed Ramp

A BizHawk Lua script for challenge runs: **every jump makes the emulator 1
percentage point faster.** It never resets on its own — only the reset hotkey
brings it back to 100%.

100 jumps = 200% speed. 400 jumps = 500% speed.

## Why emulator-side and not a ROM hack

The speed change is applied with BizHawk's `client.speedmode()`, which scales the
whole machine uniformly — game logic, animation, audio and your reaction window
all move together. That is what makes it a clean difficulty ramp.

Doing it inside the game instead (scaling velocity constants, or double-stepping
the main loop) would break the physics: collision is resolved per frame against
tiles, so scaled velocities clip you through walls and jump arcs stop matching
muscle memory. Emulator-side is both far simpler and strictly more faithful.

## Usage

1. Open EmuHawk and load your ROM.
2. **Tools → Lua Console → Script → Open Script**
3. Select `jumpramp.lua`.

Either BizHawk in this workspace works:

- `C:\path\to\Game Modding\Tools\BizHawk-2.10\EmuHawk.exe`
- `C:\path\to\Game Modding\HGSS modding\BizHawk-2.11.1-win-x64\EmuHawk.exe`

The console prints the detected game, jump button and memory domain at load. The
on-screen overlay shows the jump count, current speed, and whether the counter is
`ACTIVE`, `waiting` (not in gameplay), or `PAUSED`.

## Hotkeys

| Key | Action |
|-----|--------|
| `Home` | Reset to 100% and zero the counter |
| `End` | Pause/resume counting (current speed is held) |
| `PageUp` | Add one jump by hand |
| `PageDown` | Remove one jump by hand |

If a hotkey does nothing, BizHawk may use a different internal name for that key.
Set `DEBUG_KEYS = true` at the top of the script, press the key, and the Lua
console prints the name it actually sees — paste that into the config block.

## Game support

| Game | Platform | Jump | Airborne byte | Counting |
|------|----------|------|---------------|----------|
| Mega Man | NES | A | `$01F5` {CC} | exact — verified 6/6 |
| Mega Man 2 | NES | A | `$0032` {00} | exact — verified 6/6 |
| Mega Man 3 | NES | A | `$0030` {01} | exact — verified 6/6 |
| Mega Man 4 | NES | A | `$0030` {01} | exact — verified 6/6 |
| Mega Man 5 | NES | A | `$0030` {01} | exact — verified 6/6 |
| Mega Man 6 | NES | A | `$00AD` {00} | exact — verified 6/6 |
| Mega Man 7 | SNES | B | `$0C02` {06,08,0A} | exact — verified 5/5 |
| Mega Man X | SNES | B | `$0BAA` {06,08,0A} | exact — verified 6/6 |
| Mega Man X2 | SNES | B | `$09DA` {06,08,0A} | **inferred, unverified** |
| Mega Man X3 | SNES | B | `$09DA` {06,08,0A} | exact — verified 6/6 |
| Mega Man & Bass | SNES | B | — | button (no ROM to test) |

**Exact counting** uses a verified player-state byte. A jump is counted when the
player *enters the airborne state* **and** the jump button went down within
`JUMP_WINDOW` (8) frames. That combination is what makes it exact:

- midair mashing → button pressed, but no airborne transition → ignored
- walking off a ledge → airborne transition, but no button press → ignored
- sliding in MM3 (Down+A) → button pressed, never leaves the ground → ignored
- jumping from a standstill, from a run, or off a wall → both → counted

**Button counting** is the fallback where no airborne byte has been found yet. It
counts the rising edge of the jump button during live gameplay, so midair
mashing and slides inflate it. Fine as a proof of concept; see next steps.

Platform differences are handled per profile: NES reads the `RAM` domain and
jumps with **A**, SNES reads `WRAM` and jumps with **B**.

**Gates are secondary now.** Mega Man X, X2, X3 and Mega Man 3 also check a
"live gameplay" gate (menu state, pause flag, `can_move`), which drives the
`ACTIVE` / `waiting` overlay. The other games have no gate, and it matters much
less than it sounds: a menu cannot produce an *airborne transition*, so exact
counting effectively gates itself. The console prints which mode a game is in
when the script loads.

## Known limitations

**Mega Man & Bass still counts button presses**, because there is no ROM for it
in `Games/`. Every other game counts exactly.

**Mega Man X2's byte is inferred, not measured** — see above.

**Mega Man 1's byte is the least trustworthy** of the verified set. It counts
correctly in testing, but it is not a canonical state byte, so it is the most
likely to misbehave somewhere unusual.

**No dash confusion.** On SNES X games dash is A and jump is B, so dashes never
count. On NES, jump is a dedicated button.

**Remapped controls.** The script assumes the stock button layout. If you changed
jump in the in-game options, edit that profile's `jump_buttons`.

**If your ROM isn't recognised**, the script says so in the console and runs
ungated with SNES buttons. Add your ROM's title to the matching profile's
`patterns` list. Patterns are plain substring tests against the ROM title,
lowercased with all non-alphanumerics stripped (`megamanx2usa`). Profile order
matters — `megaman` is a substring of nearly every title, so Mega Man 1 is
deliberately tested last.

## Where the addresses came from

**SNES (X1–X3)** — vanilla WRAM offsets from lx5's Archipelago clients in
`Reference/lx5-apworlds/src/`:

| | X1 | X2 | X3 |
|---|---|---|---|
| menu state | `$7E00D2` | `$7E00D1` | `$7E00D1` |
| gameplay state | `$7E00D3` | `$7E00D2` | `$7E00D2` |
| pause state | `$7E1F24` | `$7E1F37` | `$7E1F37` |
| `can_move` | `$7E1F13` ×7 | `$7E1F25` ×6 | `$7E1F45` ×1 |

In-gameplay means menu state `0x04`, gameplay state `0x04`, pause `0x00`, and
every `can_move` byte `0x00`. Gameplay state `0x06` is death, excluded for free.

X2's apworld also exposes a `player_action` byte, but it lives in an SRAM mirror
that only exists in an AP-patched ROM — no use for vanilla runs.

**NES (MM2, MM3)** — from the `mm2` and `mm3` worlds in the Archipelago checkout
(`Archipelago/worlds/`), both of which read the `RAM` domain:

| | Address | Meaning |
|---|---|---|
| MM3 energy bar | `$00B2` | `0x80` = in stage, `0x00` = not, anything else = uninitialised |
| MM3 Mega Man state | `$0030` | `0x0E` is the death state |
| MM2 difficulty | `$00CB` | `0` or `1` once booted — init guard only |

MM3's energy-bar byte doubles as an init guard and an in-stage tracker, which is
why MM3 gets a real gate while MM2 doesn't.

### Airborne bytes (found by `hunter.lua`)

`hunter.lua` drives the game itself, runs jump cycles, keeps only addresses that
hold one consistent value grounded and a different consistent value airborne,
then characterises the survivors against real movement. Three families emerged:

**The X-series state machine** — same values, different struct bases, and it
turns up on Mega Man 7 too:

| Game | Address | Values |
|---|---|---|
| Mega Man X | `$0BAA` | `00` idle · `02` start walk · `04` walking/running · `06` jump start · `08` rising · `0A` falling · `0C` dead |
| Mega Man X3 | `$09DA` | same |
| Mega Man X2 | `$09DA` | same (inferred — see below) |
| Mega Man 7 | `$0C02` | same |

**The classic-series state byte** — `$0030`, `0x00` grounded (idle *and*
running), `0x01` airborne, `0x0E` dead. Used by **MM3, MM4, MM5**. This is the
byte the Archipelago client already documents as `MM3_MEGAMAN_STATE`.

**Inverted on-ground booleans** — `0x01` grounded, `0x00` airborne:
**MM2 `$0032`** (`$0033` mirrors it) and **MM6 `$00AD`**. MM6 is the odd one out
of the classic series: it does not use `$0030` at all.

**Mega Man 1** is the weakest result. It has no clean state enum; `$01F5` reads
`0x00`/`0x01` grounded and `0xCC` airborne, and only holds it for ~6 frames of a
jump. It counts correctly, but it is plainly not a canonical state byte.

Two findings mattered more than the addresses themselves:

- On **MMX**, running is `0x04`, not the idle `0x00`. A "left the idle value"
  test would have missed every running jump — which is why a hunt is never
  trusted without characterising it against real movement.
- On **MM3**, `0x01` also sets when walking off a ledge with no button press, so
  the state byte alone would count falls as jumps. Hence the button window.

### Mega Man X2 is inferred, not measured

X2's intro stage puts X on the ride chaser, where the automated hunter dies
before it can jump — all four attempts ended with the gate shut. So `$09DA` was
derived rather than observed:

| Game | HP | State | Offset |
|---|---|---|---|
| Mega Man X | `$0BCF` | `$0BAA` | 0x25 |
| Mega Man X3 | `$09FF` | `$09DA` | 0x25 |
| Mega Man X2 | `$09FF` | `$09DA` (inferred) | 0x25 |

X2 and X3 share their HP address *and* their menu/gameplay/pause addresses, and
the state byte sits exactly `0x25` below HP on both games that were measured. It
is a good inference, but it is an inference. **To confirm it, play X2 into a
normal on-foot stage and check the jump counter tracks.**

**MM1, MM4, MM5, MM6** have no apworld in this workspace, so they ship ungated
with the correct platform domain and button.

## What has actually been verified

Every ROM in `Games/Nes` and `Games/Snes` was booted under BizHawk 2.11.1 with
`probe.lua` (10/10 loaded cleanly):

- **ROM titles resolve as expected.** SNES titles come from `gamedb_snes.txt`
  (`Mega Man X (USA) (Rev 1)`, `Mega Man X2 (USA)`, …); NES titles come from
  bootgod's `NesCarts.xml` and are bare (`Mega Man`, `Mega Man 2`, …). All ten
  match their profile — `match_test.py` covers all three naming conventions.
- **Every gated profile reads `waiting` at the title screen**, which is correct:
  X1 `$00D2`=0x00, X2/X3 `$00D1`=0x00, MM3 `$00B2`=0x00 (not in a stage).
- **Domain names confirmed per platform.** SNES exposes `WRAM` and no `RAM`.
  NES exposes `RAM`; MM2–6 additionally expose a `WRAM` that is *cartridge save
  RAM*, not main RAM.

- **Confirmed in real gameplay by a human** on Mega Man X (SNES, `WRAM`) and
  Mega Man 3 (NES, `RAM`) — both platforms, both memory domains.
- **Exact counting proved automatically on 9 of the 10 available games** by
  `verify.lua`: 6 scripted jumps plus provably-midair mashes give
  `exact = 6, button = 24`.

**Not verified:** Mega Man X2 (inferred address — see above) and Mega Man & Bass
(no ROM in `Games/`).

Mega Man 7 scored 5 rather than 6, and that is fine: its midair-mash count was
15, which is exactly 3 per jump for 5 jumps. One scripted cycle produced no jump
at all, so only 5 jumps happened and all 5 were counted. The harness's "want 6"
was the wrong expectation, not the byte.

### The domain trap

Reading a domain that does not exist **does not raise an error**. BizHawk
silently falls back and returns plausible-looking garbage — on SNES,
`memory.read_u8(0x30, "RAM")` returned `0x02` despite there being no `RAM`
domain at all. A `pcall` around the read can therefore never detect this.

The script now checks the domain by name against `memory.getmemorydomainlist()`
at startup, and if it is missing, says so loudly and disables the gate rather
than silently gating on the wrong memory. This is why NES uses `RAM` and not
`WRAM` even though both exist on MM2–6.

## Possible next steps

1. **Confirm Mega Man X2** by playing it into a normal on-foot stage (past the
   ride chaser) and checking the counter tracks your jumps. If `$09DA` is wrong,
   run `hunter.lua` from a savestate taken in that stage.
2. **Mega Man & Bass** needs a ROM in `Games/` before anything can be tested.
3. **Improve Mega Man 1's byte.** `$01F5` counts correctly but is not a real
   state enum. A longer hunt, or MM1 RAM maps from the TAS/romhacking community,
   would likely turn up the canonical one.
4. **Gates for the gateless games.** Less urgent than it was: with an airborne
   byte, menu presses cannot produce an airborne transition, so exact counting
   self-gates. A gate would still help the on-screen `ACTIVE`/`waiting` display
   be meaningful. MM3's `$00B2` is the model — one byte nonzero only in-stage.

## Files

- `jumpramp.lua` — the script
- `match_test.py` — checks ROM-title → profile matching. It parses the profile
  list out of `jumpramp.lua` directly, so it cannot drift from the script. Run it
  after adding any ROM title, since profile order is easy to get wrong:

  ```
  py -3.13 match_test.py jumpramp.lua
  ```

- `hunter.lua` — research helper that finds a game's airborne byte, fully
  automatically: it presses its own way into a stage, runs jump cycles, and keeps
  only addresses that are consistently one value grounded and another airborne.
  Add a profile to its `CFG` table, then:

  ```powershell
  & "C:\path\to\Game Modding\HGSS modding\BizHawk-2.11.1-win-x64\EmuHawk.exe" `
    --lua="C:\path\to\Game Modding\MegaMan-JumpRamp\hunter.lua" `
    "C:\path\to\Game Modding\Games\Nes\Mega Man 3 (USA).zip"
  ```

  Results land in `hunter_log.txt`. Always characterise a candidate against real
  movement before trusting it — a hunt only samples a standstill jump, and both
  games so far behaved differently once running and falling were included.

- `verify.lua` — proves a game's exact counting is exact. Drives the game,
  performs a known number of jumps, and mashes the button while *provably*
  airborne (checked against the byte, never assumed from timing). A correct byte
  gives `exact == jumps performed` while the button counter inflates by every
  mash. Retries if the player never left the ground, since that means a menu or
  cutscene rather than a bad byte.

- `profile_sync_test.py` — checks `jumpramp.lua` and `verify.lua` agree on every
  game's airborne byte, so verification can never prove something the ramp does
  not actually do:

  ```
  py -3.13 profile_sync_test.py
  ```

- `probe.lua` — verification helper, not part of the ramp. Boots a ROM, records
  the real `getromname()`, the available memory domains and the gate bytes,
  appends to `probe_log.txt` and quits. Sweep every ROM with:

  ```powershell
  $exe = "C:\path\to\Game Modding\HGSS modding\BizHawk-2.11.1-win-x64\EmuHawk.exe"
  $lua = "C:\path\to\Game Modding\MegaMan-JumpRamp\probe.lua"
  Get-ChildItem "C:\path\to\Game Modding\Games\Nes\*.zip" | ForEach-Object {
      Start-Process $exe -ArgumentList "--lua=`"$lua`"", "`"$($_.FullName)`"" -Wait
  }
  ```

- `jumpramp_state_<game>.txt` — jump counter, one file per game (e.g.
  `jumpramp_state_mmx1.txt`), written next to the script so a run survives a
  script reload. Per-game rather than shared, so counters never mix and two
  EmuHawk instances can run side by side without clobbering each other. Safe to
  delete; gitignored. Only created once you land your first jump.
- `probe_log.txt` — probe output. Gitignored.
