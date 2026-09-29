"""Build NaowhForever_DungeonQuestChains.lua from Wowhead's Forever quest pages.

Each quest page (/forever/quest=<id>) with a chain has a "Series" box in its infobox: a
<table class="series"> with one row per step in order, each step a link to its quest, or
<b> for the page's own quest. A row can hold more than one quest (the faction or class
versions of that step). Every quest ID in NaowhForever_DungeonQuestData.lua is looked up,
including its alt, steps and lead IDs. Answers are cached in quest_chains.json (null for
a quest with no chain); delete an entry to fetch it again.

Usage: python Tools/build_quest_chains.py
"""
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "DungeonQuests" / "NaowhForever_DungeonQuestData.lua"
OUT = ROOT / "DungeonQuests" / "NaowhForever_DungeonQuestChains.lua"
CACHE = Path(__file__).resolve().parent / "quest_chains.json"
# Where each chain step starts, from the quest page's map: { zone, coord, npc, npcId }, or
# null for a quest with no start on a map. Delete an entry to fetch it again.
STARTS = Path(__file__).resolve().parent / "quest_starts.json"

# Wowhead's zone (area) IDs to the client's uiMapIDs.
ZONE_MAP = {
    1: 1426, 3: 1418, 4: 1419, 8: 1435, 10: 1431, 11: 1437, 12: 1429, 14: 1411, 15: 1445,
    16: 1447, 17: 1413, 28: 1422, 33: 1434, 36: 1416, 38: 1432, 40: 1436, 41: 1430,
    44: 1433, 45: 1417, 46: 1428, 47: 1425, 51: 1427, 85: 1420, 130: 1421, 139: 1423,
    141: 1438, 148: 1439, 215: 1412, 267: 1424, 331: 1440, 357: 1444, 361: 1448,
    400: 1441, 405: 1443, 406: 1442, 440: 1446, 490: 1449, 493: 1450, 618: 1452,
    1377: 1451, 1497: 1458, 1519: 1453, 1537: 1455, 1637: 1454, 1638: 1456, 1657: 1457,
}
# Forever redrew these, and Wowhead still gives their classic coordinates. Stormwind has
# enough known quest givers to fit the conversion; on the others a step only gets a spot
# when its quest giver also gives a quest in the data file.
REDRAWN = {1453, 1412, 1433, 1423}
FIT_MAP = 1453


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    # Wowhead's CDN answers 403 once requests come too fast; it lifts after a pause.
    for wait in (30, 60, 120, 240, None):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            if e.code not in (403, 429, 503) or wait is None:
                raise
            print(f"  {e.code} from {urllib.parse.urlsplit(url).netloc}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)


def quest_ids():
    """Every quest ID in the data file, its own first, in file order."""
    ids = []
    src = DATA.read_text(encoding="utf-8")
    for line in re.findall(r'^\s+\{ \d+, ".*$|^\s+steps = .*$', src, re.M):
        own = re.match(r'\s+\{ (\d+), "', line)
        found = [own.group(1)] if own else []
        for field in re.findall(r'(?:alt|steps|lead) = (\{(?:[^{}]|\{[^{}]*\})*\})', line):
            found += re.findall(r"\d+", field)
        for i in found:
            if int(i) not in ids:
                ids.append(int(i))
    return ids


def parse(quest_id, page):
    """{ "chain": [[ids of step 1], ...], "names": { id: name } }, or None without a chain."""
    table = re.search(r'<table class="series">(.*?)</table>', page, re.S)
    if not table:
        return None
    chain, names = [], {}
    for row in re.findall(r"<tr>(.*?)</tr>", table.group(1), re.S):
        step = []
        for qid, name in re.findall(r'href="/forever/quest=(\d+)[^"]*">([^<]*)</a>', row):
            step.append(int(qid))
            names[qid] = html.unescape(name)
        own = re.search(r"<b>([^<]*)</b>", row)
        if own:
            step.insert(0, quest_id)
            names[str(quest_id)] = html.unescape(own.group(1))
        if not step:
            raise ValueError(f"quest {quest_id}: series row without a quest: {row!r}")
        chain.append(step)
    return {"chain": chain, "names": names}


def parse_start(page):
    """The quest giver on the quest page's map, or None when the page has no start."""
    mapper = re.search(r"new Mapper\((\{.*?\})\);", page, re.S)
    if not mapper:
        return None
    for zone, objective in (json.loads(mapper.group(1)).get("objectives") or {}).items():
        for level in objective.get("levels", []):
            for point in level:
                if point.get("point") == "start" and point.get("coord"):
                    return {"zone": int(zone), "coord": point["coord"], "npc": point.get("name"),
                            "npcId": point.get("id")}
    return None


def solve3(m, v):
    """Solves the 3x3 system m * x = v by elimination."""
    a = [row[:] + [v[i]] for i, row in enumerate(m)]
    for c in range(3):
        p = max(range(c, 3), key=lambda r: abs(a[r][c]))
        a[c], a[p] = a[p], a[c]
        for r in range(3):
            if r != c:
                f = a[r][c] / a[c][c]
                a[r] = [x - f * y for x, y in zip(a[r], a[c])]
    return [a[i][3] / a[i][i] for i in range(3)]


def fit(pairs):
    """Least-squares affine map from classic (x, y) to Forever (x, y), and its worst error."""
    rows = [(x, y, 1.0) for (x, y), _ in pairs]
    m = [[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)]
    cx = solve3(m, [sum(r[i] * t[0] for r, (_, t) in zip(rows, pairs)) for i in range(3)])
    cy = solve3(m, [sum(r[i] * t[1] for r, (_, t) in zip(rows, pairs)) for i in range(3)])

    def to(x, y):
        return (cx[0] * x + cx[1] * y + cx[2], cy[0] * x + cy[1] * y + cy[2])

    worst = max(abs(a - b) for (s, t) in pairs for a, b in zip(to(*s), t))
    return to, worst


def own_spots():
    """questID -> (uiMapID, x, y) for every quest in the data file with a quest giver spot."""
    spots = {}
    for line in DATA.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s+\{ (\d+), ".*?", \d+, "[ABH]", .*?"(?:, (\d+), ([\d.]+), ([\d.]+))?(?:,|\s*\})', line)
        if m and m.group(2):
            spots[int(m.group(1))] = (int(m.group(2)), float(m.group(3)), float(m.group(4)))
    return spots


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    ids = quest_ids()
    failed = []
    for quest_id in ids:
        key = str(quest_id)
        if key in cache:
            continue
        try:
            cache[key] = parse(quest_id, fetch(f"https://www.wowhead.com/forever/quest={quest_id}"))
        except (urllib.error.HTTPError, ValueError) as e:
            failed.append(f"{quest_id}: {e}")
            continue
        CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True), encoding="utf-8")
        time.sleep(1)

    own = set(int(i) for i in re.findall(r'^\s+\{ (\d+), "', DATA.read_text(encoding="utf-8"), re.M))
    chains, names = {}, {}
    for quest_id in ids:
        entry = cache.get(str(quest_id))
        if not entry or len(entry["chain"]) < 2:
            continue
        chains[quest_id] = entry["chain"]
        for step in entry["chain"]:
            for i in step:
                if i not in own:
                    names[i] = entry["names"][str(i)]

    # Where each step starts. The data file's own quests keep its spots; the rest come from
    # their quest pages, and the data file's quests on the redrawn maps are fetched too, to
    # match quest givers and fit the conversion.
    spots = own_spots()
    steps = sorted({i for chain in chains.values() for step in chain for i in step})
    wanted = [i for i in steps if i not in spots] + sorted(q for q, s in spots.items() if s[0] in REDRAWN)
    starts = json.loads(STARTS.read_text(encoding="utf-8")) if STARTS.exists() else {}
    for quest_id in wanted:
        key = str(quest_id)
        if key in starts:
            continue
        try:
            starts[key] = parse_start(fetch(f"https://www.wowhead.com/forever/quest={quest_id}"))
        except (urllib.error.HTTPError, ValueError) as e:
            failed.append(f"{quest_id} (start): {e}")
            continue
        STARTS.write_text(json.dumps(starts, indent=1, sort_keys=True), encoding="utf-8")
        time.sleep(1)

    known, pairs = {}, []
    for quest_id, (map_id, x, y) in spots.items():
        start = starts.get(str(quest_id))
        if map_id in REDRAWN and start and ZONE_MAP.get(start["zone"]) == map_id:
            known[start["npcId"]] = (map_id, x, y)
            if map_id == FIT_MAP:
                pairs.append((tuple(start["coord"]), (x, y)))
    # Some quest givers walk about (Nikova Raskol does), so their spot on the page and in the
    # data file differ; one that throws the fit off is left out.
    to_forever, worst = fit(pairs)
    if worst > 1.5:
        tries = [(fit(pairs[:i] + pairs[i + 1:]), i) for i in range(len(pairs))]
        (to_forever, worst), dropped = min(tries, key=lambda t: t[0][1])
        print(f"Stormwind fit leaves out the quest giver at {pairs[dropped][0]}", file=sys.stderr)
        pairs = pairs[:dropped] + pairs[dropped + 1:]
    print(f"Stormwind fit from {len(pairs)} quest givers, worst error {worst:.2f}", file=sys.stderr)
    if worst > 1.5:
        to_forever = None

    chain_starts = {}
    for quest_id in steps:
        start = quest_id not in spots and starts.get(str(quest_id))
        map_id = start and ZONE_MAP.get(start["zone"])
        if not map_id:
            continue
        x, y = start["coord"]
        if start["npcId"] in known:
            map_id, x, y = known[start["npcId"]]
        elif map_id in REDRAWN:
            if map_id != FIT_MAP or not to_forever:
                continue
            x, y = to_forever(x, y)
        chain_starts[quest_id] = (map_id, round(x, 1), round(y, 1), start["npc"] or "")

    def step_lua(step):
        return str(step[0]) if len(step) == 1 else "{ " + ", ".join(str(i) for i in step) + " }"

    lines = [
        "-------------------------------------------------------------------------------",
        "--  NaowhForever_DungeonQuestChains.lua -- the quest chain each dungeon quest belongs to,",
        "--  from the Series box on Wowhead's Forever quest pages. Generated by",
        "--  Tools/build_quest_chains.py; do not edit by hand.",
        "--",
        "--  DungeonQuestChains: questID -> every step of its chain in order, itself included. A",
        "--  step is a quest ID, or a table of IDs (one per faction or class), any of which counts.",
        "--  DungeonQuestChainNames: the names of the steps that are not quests in the data file.",
        "--  DungeonQuestChainStarts: where those steps start, { uiMapID, x, y, quest giver },",
        "--  from the quest page's map; missing where the page has none or the map is not known.",
        "-------------------------------------------------------------------------------",
        "local ns = _G.NaowhForever",
        "",
        "ns.DungeonQuestChains = {",
    ]
    for quest_id in sorted(chains):
        lines.append(f"    [{quest_id}] = {{ {', '.join(step_lua(s) for s in chains[quest_id])} }},")
    lines.append("}")
    lines.append("")
    lines.append("ns.DungeonQuestChainNames = {")
    for quest_id in sorted(names):
        lines.append(f"    [{quest_id}] = {lua_string(names[quest_id])},")
    lines.append("}")
    lines.append("")
    lines.append("ns.DungeonQuestChainStarts = {")
    for quest_id in sorted(chain_starts):
        map_id, x, y, npc = chain_starts[quest_id]
        lines.append(f"    [{quest_id}] = {{ {map_id}, {x:g}, {y:g}, {lua_string(npc)} }},")
    lines.append("}")
    OUT.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8", newline="")

    print(f"{len(ids)} quests, {len(chains)} in a chain, {len(names)} step names, "
          f"{len(chain_starts)} step starts -> {OUT.name}", file=sys.stderr)
    if failed:
        print(f"{len(failed)} could not be read; run again to retry:", file=sys.stderr)
        for line in failed:
            print(f"  {line}", file=sys.stderr)


if __name__ == "__main__":
    main()
