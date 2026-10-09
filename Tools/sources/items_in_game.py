"""Which items the Forever server sends, as seen in the game: Tools/data/items_in_game.json.

wago.tools records the items Blizzard hotfixes into the game some time after they land, and
not always all of them: Ravager (7717) loads in game on 1.60.1.70205 with no row in wago's
ItemSparse. This list is what the game itself answered, so Tools/build/journal.py lists an
item as in the game when wago's tables or this list have it ("loads"), and as not in Forever
yet when neither does. "refused" are the items the server would not send.

Two inputs, both on a machine with the Forever client, each optional:
  - the client's hotfix cache, Cache/ADB/enUS/DBCache.bin: every item record the server sent,
    or refused, while you played (the last answer for an item counts);
  - the Journal's item probe, /nf itemprobe in game: it asks the server for every item the
    Journal lists, and keeps the answers in SavedVariables (NaowhForeverDB.journalProbe),
    written at /reload or logout.
What they say is folded into the list: a newer answer for an item replaces an older one.

Usage: python Tools/sources/items_in_game.py [--cache DBCache.bin] [--probe NaowhForever.lua]
With neither, the default paths of a Windows install are read where they exist.
"""
import datetime
import glob
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402

OUT = paths.DATA / "items_in_game.json"
GAME = Path(r"C:\Program Files (x86)\World of Warcraft\_classic_beta_")
CACHE = GAME / "Cache" / "ADB" / "enUS" / "DBCache.bin"
PROBES = str(GAME / "WTF" / "Account" / "*" / "SavedVariables" / "NaowhForever.lua")

MAGIC = b"XFTH"
ITEM_SPARSE = 0x919BE54E
ENTRY = struct.Struct("<4siiIIIIB3x")
HEADER = 12 + 32
SENT, REMOVED, REFUSED = 1, 2, 3


def read_cache(data):
    magic, version, build = struct.unpack_from("<4sII", data, 0)
    if magic != MAGIC or version != 9:
        raise ValueError(f"not a DBCache.bin this reads (magic {magic!r}, version {version})")
    answers, offset = {}, HEADER
    while offset + ENTRY.size <= len(data):
        magic, _, _, _, table, record, size, status = ENTRY.unpack_from(data, offset)
        if magic != MAGIC:
            raise ValueError(f"DBCache.bin: no entry at byte {offset}")
        if table == ITEM_SPARSE and status in (SENT, REMOVED, REFUSED):
            answers[record] = status == SENT
        offset += ENTRY.size + size
    return build, answers


def lua_block(text, key):
    found = re.search(r'\["%s"\]\s*=\s*\{' % re.escape(key), text)
    if not found:
        return None
    depth, at = 0, found.end() - 1
    for i in range(at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[at:i + 1]
    raise ValueError(f'SavedVariables: ["{key}"] is not closed')


def lua_numbers(block, key):
    inner = lua_block(block, key)
    if inner is None:
        return []
    return [int(n) for n in re.findall(r"^\s*(\d+),", re.sub(r"--[^\n]*", "", inner), re.M)]


def read_probe(text):
    block = lua_block(text, "journalProbe")
    if block is None:
        return 0, {}
    build = re.search(r'\["build"\]\s*=\s*(\d+)', block)
    answers = {i: True for i in lua_numbers(block, "loads")}
    answers.update({i: False for i in lua_numbers(block, "refused")})
    return int(build.group(1)) if build else 0, answers


def merge(known, build, answers):
    loads, refused = set(known.get("loads", [])), set(known.get("refused", []))
    for item, sent in answers.items():
        (loads if sent else refused).add(item)
        (refused if sent else loads).discard(item)
    return {"build": max(build, known.get("build", 0)), "loads": sorted(loads), "refused": sorted(refused)}


def write(found, day):
    lines = ["{", f'  "build": {found["build"]},', f'  "read": "{day}",',
             '  "loads": [' + ", ".join(str(i) for i in found["loads"]) + "],",
             '  "refused": [' + ", ".join(str(i) for i in found["refused"]) + "]", "}"]
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


def main(args):
    cache = [Path(args[args.index("--cache") + 1])] if "--cache" in args else [CACHE] if CACHE.exists() else []
    probes = [Path(args[args.index("--probe") + 1])] if "--probe" in args else [Path(p) for p in glob.glob(PROBES)]
    found = json.loads(OUT.read_text(encoding="ascii")) if OUT.exists() else {}
    if not cache and not probes:
        sys.exit("No DBCache.bin nor probe found: pass --cache or --probe")
    for path in cache:
        build, answers = read_cache(path.read_bytes())
        found = merge(found, build, answers)
        print(f"{path}: build {build}, {sum(answers.values())} items load, "
              f"{len(answers) - sum(answers.values())} refused", file=sys.stderr)
    for path in probes:
        build, answers = read_probe(path.read_text(encoding="utf-8", errors="replace"))
        if answers:
            found = merge(found, build, answers)
            print(f"{path}: probe of build {build}, {sum(answers.values())} items load, "
                  f"{len(answers) - sum(answers.values())} refused", file=sys.stderr)
    write(found, datetime.date.today().isoformat())
    print(f"{OUT.name}: {len(found['loads'])} items load, {len(found['refused'])} refused", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
