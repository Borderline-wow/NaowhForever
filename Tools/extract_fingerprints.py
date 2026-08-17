"""Extract tank fingerprints and event names from community boss modules.

Two module dialects exist and both are handled:

  A. `if duration == 8 or duration == 24 then -- Triple Shot`
     One-decimal durations, ability named in a trailing comment.
  B. `elseif durationRounded == 17 or durationRounded == 29 then -- Mythic
          barInfo = self:WaterJet()`
     Whole-second durations, ability named by the method called on the next
     line(s). The runtime filter matches whole seconds tolerantly, so both
     dialects are emitted in "%.1f" form.

Tank classification, in priority order:
  1. Our curated sheet-derived list (spell ids).
  2. `[id] = {CL.tank_hit...` renames and `note = CL.tank_hit` entries.
  3. `{id, "TANK"}` / `{id, "TANK_HEALER"}` flags in GetOptions.
  4. `(Tank Hit)` comments beside an id.

Facts only: encounter ids, durations, ability names, spell ids. No source
expression is copied; the output is our own format.

Usage:
  python extract_fingerprints.py <our_abilities_lua> <module_dir> [<module_dir> ...]
Prints stats plus three Lua sections (fingerprints, event names, tank spell
additions) for splicing into the data file.
"""

import re
import sys
from pathlib import Path


def norm(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def parse_curated(abilities_lua):
    body = Path(abilities_lua).read_text(encoding="ascii")
    m = re.search(r"ns\.TANK_ABILITIES = \{(.*?)\n\}", body, re.S)
    ids = set()
    for mm in re.finditer(r"\[(\d+)\]", m.group(1)):
        ids.add(int(mm.group(1)))
    return ids


def parse_module(path, curated):
    text = path.read_text(encoding="utf-8", errors="replace")
    me = re.search(r"SetEncounterID\((\d+)\)", text)
    mb = re.search(r'NewBoss\("([^"]+)"', text)
    if not (me and mb):
        return None
    enc, bossname = int(me.group(1)), mb.group(1)

    # id -> proper name, from any id with a trailing comment. Loose on purpose:
    # a name only has to resolve once somewhere in the file.
    id_name = {}
    for sid, name in re.findall(r"(\d{6,9})[,}\]].*?--\s*([^\r\n(]+)", text):
        nm = name.strip()
        if nm and int(sid) not in id_name:
            id_name[int(sid)] = nm

    # Tank-marked spell ids from the module's own markers.
    tank_ids = set()
    for sid in re.findall(r"\[(\d+)\] = \{CL\.tank_hit", text):
        tank_ids.add(int(sid))
    for sid in re.findall(r"\{(\d+),[^}]*note = CL\.tank_hit", text):
        tank_ids.add(int(sid))
    for sid in re.findall(r'\{(\d+),\s*"TANK(?:_HEALER)?"', text):
        tank_ids.add(int(sid))
    for sid in re.findall(r"(\d{6,9})[,}\]].*?--.*?\(Tank Hit\)", text):
        tank_ids.add(int(sid))

    # Which normalized ability names count as tank hits on this boss.
    tank_names = set()
    for sid in tank_ids | (curated & set(id_name)):
        nm = id_name.get(sid)
        if nm:
            tank_names.add(norm(nm))
    # Names whose id resolves to curated even without a module marker.
    for sid, nm in id_name.items():
        if sid in curated:
            tank_names.add(norm(nm))

    # Branches, both dialects.
    branches = []  # (durations, display_name)
    lines = text.splitlines()
    for i, line in enumerate(lines):
        durs = re.findall(r"(?:durationRounded|duration|rounded) == ([\d.]+)", line)
        if not durs:
            continue
        name = None
        cm = re.search(r"--\s*([^\r\n(]+)$", line.strip())
        if cm:
            cand = cm.group(1).strip()
            # A trailing comment that is just numbers or a difficulty tag names nothing.
            if re.search(r"[A-Za-z]", cand) and not re.fullmatch(
                    r"(?:[\d/ .]+)?(?:Mythic|Heroic|Normal)?", cand):
                name = cand
        if not name:
            for j in range(i + 1, min(i + 4, len(lines))):
                mcall = re.search(r"self:(\w+)\(", lines[j])
                if mcall:
                    method = re.sub(r"Timeline$", "", mcall.group(1))
                    # Prefer the proper name whose normalization matches the method.
                    for sid, nm in id_name.items():
                        if norm(nm) == norm(method):
                            name = nm
                            break
                    if not name:
                        # CamelCase -> spaced words as the fallback display.
                        name = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", method)
                    break
        if name:
            branches.append(([float(d) for d in durs], name))

    return {
        "enc": enc, "boss": bossname, "id_name": id_name,
        "tank_ids": tank_ids, "tank_names": tank_names, "branches": branches,
    }


def main():
    curated = parse_curated(sys.argv[1])
    mods = []
    for arg in sys.argv[2:]:
        for f in sorted(Path(arg).rglob("*.lua")):
            if f.name.startswith("!") or f.name == "Trash.lua":
                continue
            parsed = parse_module(f, curated)
            if parsed:
                mods.append(parsed)

    fingerprints = {}   # enc -> { fp: set(names) }
    event_names = {}    # enc -> { fp: set(names) }
    new_tank = {}       # sid -> (boss, name)

    for m in mods:
        enc = m["enc"]
        for sid in m["tank_ids"]:
            if sid not in curated:
                new_tank[sid] = (m["boss"], m["id_name"].get(sid, "?"))
        for durs, name in m["branches"]:
            for d in durs:
                fp = "%.1f" % d
                event_names.setdefault(enc, {}).setdefault(fp, set()).add(name)
                if norm(name) in m["tank_names"]:
                    fingerprints.setdefault(enc, {}).setdefault(fp, set()).add(name)

    print("-- modules: %d | encounters with events: %d | with tank fingerprints: %d"
          % (len(mods), len(event_names), len(fingerprints)))
    for m in mods:
        if m["enc"] not in fingerprints:
            has = "no tank branch resolved"
            if not (m["tank_ids"] or any(norm(n) in map(norm, m["id_name"].values())
                                         for n in m["tank_names"])):
                has = "module marks no tank hit"
            print("--   uncovered: %s (%d): %s" % (m["boss"], m["enc"], has))

    def esc(x):
        return x.replace("\\", "").replace('"', "'")

    print("\n--8<-- TANK_FINGERPRINTS")
    for enc in sorted(fingerprints):
        fps = fingerprints[enc]
        parts = ", ".join('["%s"] = true' % fp for fp in sorted(fps, key=float))
        names = ", ".join(sorted({esc(n) for s in fps.values() for n in s}))
        print("    [%d] = { %s },   -- %s" % (enc, parts, names))

    print("\n--8<-- EVENT_NAMES")
    for enc in sorted(event_names):
        fps = event_names[enc]
        parts = ", ".join('["%s"] = "%s"' % (fp, esc(" / ".join(sorted(fps[fp]))))
                          for fp in sorted(fps, key=float))
        print("    [%d] = { %s }," % (enc, parts))

    print("\n--8<-- NEW_TANK_ABILITIES")
    for sid in sorted(new_tank):
        boss, name = new_tank[sid]
        print('    [%d] = "Unknown",   -- %s: %s' % (sid, esc(boss), esc(name)))


if __name__ == "__main__":
    main()
