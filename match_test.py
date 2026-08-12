import re, sys

# Parse the profile order + patterns straight out of the Lua so the test can
# never drift from the script.
lua = open(sys.argv[1], encoding='utf-8').read()
block = lua[lua.index('local PROFILES'):lua.index('--------------------------------- STATE')]

profiles = []
for m in re.finditer(r'id\s*=\s*"([^"]+)".*?patterns\s*=\s*\{([^}]*)\}', block, re.S):
    pid = m.group(1)
    pats = re.findall(r'"([^"]+)"', m.group(2))
    profiles.append((pid, pats))

print("profile order parsed from Lua:")
print("  " + " -> ".join(p[0] for p in profiles))
print()

def detect(name):
    norm = re.sub(r'[^0-9a-z]', '', name.lower())
    for pid, pats in profiles:
        for pat in pats:
            if pat in norm:
                return pid
    return None

CASES = [
    ("Mega Man (USA)",                       "mm1"),
    ("Mega Man 2 (USA)",                     "mm2"),
    ("Mega Man 3 (USA)",                     "mm3"),
    ("Mega Man 4 (USA)",                     "mm4"),
    ("Mega Man 5 (USA)",                     "mm5"),
    ("Mega Man 6 (USA)",                     "mm6"),
    ("Mega Man 7 (USA)",                     "mm7"),
    ("Mega Man X (USA)",                     "mmx1"),
    ("Mega Man X2 (USA)",                    "mmx2"),
    ("Mega Man X3 (USA)",                    "mmx3"),
    ("Rockman (Japan)",                      "mm1"),
    ("Rockman 2 - Dr. Wily no Nazo (Japan)", "mm2"),
    ("Rockman 3 - Dr. Wily no Saigo!? (J)",  "mm3"),
    ("Rockman X (Japan)",                    "mmx1"),
    ("Rockman X2 (Japan)",                   "mmx2"),
    ("Rockman X3 (Japan)",                   "mmx3"),
    ("Rockman & Forte (Japan)",              "mmbass"),
    ("Mega Man & Bass (English Patch)",      "mmbass"),
    ("Megaman5",                             "mm5"),
    ("MEGA MAN X2",                          "mmx2"),

    # --- names BizHawk actually produces for the ROMs in Games/ ---------------
    # SNES: resolved from gamedb_snes.txt by SHA1 (verified against the ROMs).
    ("Mega Man X (USA) (Rev 1)",             "mmx1"),
    ("Mega Man X2 (USA)",                    "mmx2"),
    ("Mega Man X3 (USA)",                    "mmx3"),
    ("Mega Man 7 (USA)",                     "mm7"),
    # NES: bootgod NesCarts.xml names (bare, no region suffix).
    ("Mega Man",                             "mm1"),
    ("Mega Man 2",                           "mm2"),
    ("Mega Man 3",                           "mm3"),
    ("Mega Man 4",                           "mm4"),
    ("Mega Man 5",                           "mm5"),
    ("Mega Man 6",                           "mm6"),
    # NES: goodNES style, one word - the other name form in BizHawk's gamedb.
    ("Megaman (U) [!]",                      "mm1"),
    ("Megaman 2 (U) [!]",                    "mm2"),
    ("Megaman 3 (U) [!]",                    "mm3"),
    ("Rockman (J) [!]",                      "mm1"),
    # NES: filename fallback, if BizHawk resolves no database entry.
    ("Mega Man 4 (USA) (Rev 1)",             "mm4"),
]

fails = 0
for name, want in CASES:
    got = detect(name)
    ok = "ok  " if got == want else "FAIL"
    if got != want:
        fails += 1
    print("%s  %-40s want=%-7s got=%s" % (ok, name, want, got))

print()
print("%d/%d passed" % (len(CASES) - fails, len(CASES)))
sys.exit(1 if fails else 0)
