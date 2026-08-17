"""Build ns.TANK_FINGERPRINTS by joining community boss-timeline research with
our own curated tank buster facts.

What is taken and what is not: the source modules are another project's
copyrighted code, so nothing here copies their expression. The script reads
them as a database of FACTS -- encounter id, which base durations belong to
which ability name, which spell id carries that name -- and re-expresses those
facts in our own format. Tank classification itself comes from OUR curated
list first (sheet-derived), with their explicit tank-hit markers as an
additive second source.

The join, per boss module:
  SetEncounterID(N)                     -> encounter key
  `duration == X ... -- Ability`        -> fingerprint(s) per ability name
  `12345, -- Ability` (options/renames) -> ability name -> spell id
  ns.TANK_ABILITIES[spell id]           -> is it a tank buster
  => TANK_FINGERPRINTS[N] = { "X" = true, ... }

Validation that this join is sound: encounter 3456 was measured live before
this script existed. Our measured 8.0 (tank hit, called out) and 25.0/13.0/
23.0 (non-tank, silenced) match the extracted facts exactly, and the
extraction adds a 24.0 late-cast variant of the tank hit that live testing
had not yet seen.

Usage: python extract_fingerprints.py <littlewigs_season_dir> <bigwigs_raid_dir> <abilities_lua>
Prints a report and the replacement TANK_FINGERPRINTS block to stdout.
"""

import re
import sys
from pathlib import Path


def parse_curated(abilities_lua):
    """Spell ids our shipped list already classifies as tank busters."""
    tank = {}
    body = Path(abilities_lua).read_text(encoding="ascii")
    m = re.search(r"ns\.TANK_ABILITIES = \{(.*?)\n\}", body, re.S)
    for sid, dmg in re.findall(r'\[(\d+)\] = "(\w+)"', m.group(1)):
        tank[int(sid)] = dmg
    return tank


def parse_module(path):
    """One boss file -> (encounterID, name->ids, list of (durations, name))."""
    text = path.read_text(encoding="utf-8", errors="replace")

    m = re.search(r"SetEncounterID\((\d+)\)", text)
    if not m:
        return None
    enc = int(m.group(1))

    # Any numeric spell id with a trailing name comment maps name -> ids. Options
    # and rename tables both follow this shape, and collecting every such line is
    # deliberately loose: a name only has to resolve once.
    name_ids = {}
    for sid, name in re.findall(r"(\d{6,9})[,}\]].*?--\s*([^\r\n(]+)", text):
        key = name.strip().lower()
        name_ids.setdefault(key, set()).add(int(sid))

    # Timeline branches: every `duration == X` on a line, with the trailing
    # comment naming the ability the branch handles.
    branches = []
    for line in text.splitlines():
        if "duration ==" not in line:
            continue
        durs = re.findall(r"duration == ([\d.]+)", line)
        name = re.search(r"--\s*([^\r\n(]+)$", line.strip())
        if durs and name:
            branches.append(([float(d) for d in durs], name.group(1).strip().lower()))

    # Explicit tank-hit markers are an additive classification source.
    marked = set()
    for sid in re.findall(r"\[(\d+)\] = \{CL\.tank_hit", text):
        marked.add(int(sid))
    for sid in re.findall(r"(\d{6,9})[,}\]].*?--.*?\(Tank Hit\)", text):
        marked.add(int(sid))

    return enc, name_ids, branches, marked


def main():
    season_dirs = [Path(sys.argv[1]), Path(sys.argv[2])]
    curated = parse_curated(sys.argv[3])

    out = {}          # enc -> { fingerprint-string: spell name }
    new_tank = {}     # spell ids marked tank_hit upstream, missing from curated
    unmatched = []    # tank branches whose name resolved to no spell id

    files = []
    for d in season_dirs:
        files.extend(p for p in sorted(d.rglob("*.lua"))
                     if p.name not in ("Trash.lua",) and not p.name.startswith("!"))

    for path in files:
        parsed = parse_module(path)
        if not parsed:
            continue
        enc, name_ids, branches, marked = parsed

        for sid in marked:
            if sid not in curated:
                new_tank[sid] = path.stem

        for durs, name in branches:
            ids = set()
            for key, s in name_ids.items():
                if key.startswith(name) or name.startswith(key):
                    ids |= s
            if not ids:
                unmatched.append((path.stem, name))
                continue
            if any(sid in curated or sid in marked for sid in ids):
                for d in durs:
                    out.setdefault(enc, {})["%.1f" % d] = name

    print("-- extracted %d encounters, %d with tank fingerprints" % (
        len(files), len(out)))
    for stem, name in unmatched:
        print("-- UNMATCHED tank-name candidate: %s: %s" % (stem, name))
    for sid, stem in sorted(new_tank.items()):
        print('-- upstream tank_hit missing from curated: [%d] %s' % (sid, stem))

    print("\nns.TANK_FINGERPRINTS = {")
    for enc in sorted(out):
        fps = out[enc]
        parts = ", ".join('["%s"] = true' % fp for fp in sorted(fps, key=float))
        names = ", ".join(sorted(set(fps.values())))
        print("    [%d] = { %s },   -- %s" % (enc, parts, names))
    print("}")


if __name__ == "__main__":
    main()
