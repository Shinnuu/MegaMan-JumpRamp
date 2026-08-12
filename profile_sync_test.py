"""Check that jumpramp.lua and verify.lua agree about every game's airborne byte.

verify.lua proves the counting is exact; jumpramp.lua does the counting. If the
two tables drift, verify.lua cheerfully proves something the ramp does not do.
This parses both files rather than trusting them to stay in step by hand.

    py -3.13 profile_sync_test.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def strip_comments(src):
    """Remove Lua line comments without eating '--' inside string literals."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '-' and src.startswith('--', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            out.append(' ')
        elif c in '"\'':
            q, start = c, i
            i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == '\\' else 1
            i += 1
            out.append(src[start:i])
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def parse(path, id_pat, air_pat):
    """Return {profile_id: (addr, (values...))}, or (None, None) when absent."""
    src = strip_comments(open(path, encoding='utf-8').read())
    found = {}
    # Walk profile-id occurrences in order; an airborne block belongs to the
    # id that most recently preceded it.
    events = []
    for m in re.finditer(id_pat, src):
        events.append(('id', m.start(), m.group(1)))
    for m in re.finditer(air_pat, src):
        vals = tuple(int(v, 16) for v in re.findall(r'0x([0-9A-Fa-f]+)', m.group(2)))
        events.append(('air', m.start(), (int(m.group(1), 16), vals)))
    events.sort(key=lambda e: e[1])

    current = None
    for kind, _, payload in events:
        if kind == 'id':
            current = payload
            found.setdefault(current, (None, None))
        elif current is not None:
            found[current] = payload
    return found


ramp = parse(
    os.path.join(HERE, 'jumpramp.lua'),
    r'id\s*=\s*"([a-z0-9]+)"',
    r'airborne\s*=\s*\{\s*addr\s*=\s*0x([0-9A-Fa-f]+)\s*,\s*values\s*=\s*\{([^}]*)\}',
)
ver = parse(
    os.path.join(HERE, 'verify.lua'),
    r'mk\("([a-z0-9]+)"',
    r'\{\s*addr\s*=\s*0x([0-9A-Fa-f]+)\s*,\s*values\s*=\s*\{([^}]*)\}',
)

if not ramp:
    sys.exit("could not parse any profiles out of jumpramp.lua")
if not ver:
    sys.exit("could not parse any profiles out of verify.lua")

ids = sorted(set(ramp) | set(ver))
fails = 0
print("%-8s %-26s %-26s" % ("game", "jumpramp.lua", "verify.lua"))


def fmt(entry):
    if entry is None or entry[0] is None:
        return "-"
    addr, vals = entry
    return "$%04X {%s}" % (addr, ",".join("%02X" % v for v in vals))


for pid in ids:
    a = ramp.get(pid)
    b = ver.get(pid)
    ok = (a or (None, None)) == (b or (None, None))
    if not ok:
        fails += 1
    print("%-8s %-26s %-26s %s" % (pid, fmt(a), fmt(b), "ok" if ok else "MISMATCH"))

print()
if fails:
    print("%d profile(s) out of sync" % fails)
else:
    print("all %d profiles in sync" % len(ids))
sys.exit(1 if fails else 0)
