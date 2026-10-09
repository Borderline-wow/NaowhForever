"""Build NaowhForever_Completo/Data/Rares.lua: every rare of every zone.

A zone page (/forever/zone=<areaID>) lists the creatures found there in its "npcs" listview;
the rare ones have classification 4 (rare) or 2 (rare elite). Each rare's page
(/forever/npc=<id>) then gives where it spawns (g_mapperData), the same way
completo_quests.py finds the mobs whose drop begins a quest.

The same creature page's "drops" listview gives its loot; only the special drops are kept:
rare and epic items, recipes, and what is new in Forever (Tools/data/forever_new.json, marked with
Forever's sign in the addon), its own (Wowhead's specificDrop) first.

A creature page lags behind its items' pages: the new rare item sets (the Barrens' Blessing of
Kalimdor) are on the items' "dropped-by" lists before their rares' pages list them. So each
piece of Forever's new item sets (all but the PvP ones) is read too, and added to the drops of
the rares that drop it.

Answers are cached in completo_rares.json ({ "zones": { area: [rows] }, "npcs": { id: spots },
"drops": { id: [drops] }, "setpieces": { item: { name, quality, classs, droppers } } }), so a
run that dies on Wowhead's rate limit resumes where it stopped. --offline writes from the
cache only.

Usage: python Tools/build/completo_rares.py [--offline]
"""
import json
import math
import re
import sys
import time
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
import wowhead  # noqa: E402
from completo_quests import GAP, fetch_npc, forever_spot, load, lua_string, save, zone_name  # noqa: E402
from quest_chains import ZONE_MAP  # noqa: E402

ROOT = paths.ROOT
OUT = ROOT / "NaowhForever_Completo" / "Data" / "Rares.lua"
CACHE = paths.DATA / "completo_rares.json"
ZONES = paths.DATA / "completo_zones.json"
RARE, RARE_ELITE = 4, 2
# Spawn points closer than this (map percent) are one spot; a rare keeps at most MAX_SPOTS.
NEAR = 3
MAX_SPOTS = 12
# A patrol: Wowhead records a walking rare at every point of its way, so its points link up
# (each within LINK of the next) into a group at least PATROL_POINTS strong and PATROL_SPAN
# across. Its way is drawn as a trail of dots TRAIL_GAP apart, at most MAX_TRAIL per rare.
LINK = 2.5
PATROL_POINTS = 10
PATROL_SPAN = 6
TRAIL_GAP = 2
MAX_TRAIL = 80
KEEP = ("id", "name", "minlevel", "maxlevel", "classification", "react", "type")
# Rares only an event brings, not there to hunt: the Scourge Invasion's (Lumbering Horror,
# Spirit of the Damned, Bone Witch), listed in each zone it reaches.
EVENT_ONLY = {14697, 16379, 16380}
# Wowhead's level for a creature shown as "??" (a boss level).
SKULL_LEVEL = 9999


# Loot worth naming: rare (blue) or epic items, and recipes (class 9), whether its own drop or a
# random world drop; at most MAX_LOOT, its own first, then the best and likeliest.
LOOT_QUALITY = 3
RECIPE = 9
MAX_LOOT = 8
# New in Forever: its own of any quality (quest items too), a world drop from green up (not the
# new food and water).
NEW_ITEMS = paths.DATA / "forever_new.json"
NEW_WORLD_QUALITY = 2
# Forever's own item sets start at this ID; the PvP ones are left out by name.
NEW_SETS_FROM = 2000
PVP_SET = re.compile(r"^(Champion|Warlord|Field Marshal|Lieutenant Commander)'s ")


def new_items():
    data = load(NEW_ITEMS)
    return set(data.get("items", []))


def new_set_pieces():
    """The pieces of Forever's new item sets, PvP sets left out."""
    page = wowhead.fetch(f"{wowhead.WOWHEAD}/item-sets")
    start = page.index("=", page.index("var itemSets")) + 1
    sets, _ = json.JSONDecoder().raw_decode(page[start:].lstrip())
    return sorted({piece for s in sets if s["id"] >= NEW_SETS_FROM and not PVP_SET.match(s.get("name") or "")
                   for piece in s.get("pieces") or []})


def fetch_piece(item):
    """{ name, quality, classs, droppers: [{ npc, chance }] } from the item's page."""
    page = wowhead.fetch(f"{wowhead.WOWHEAD}/item={item}")
    info = {"name": "", "quality": 0, "classs": None, "droppers": []}
    for m in re.finditer(r"WH\.Gatherer\.addData\(3, \d+, (\{.*?\})\);", page):
        entry = json.loads(m.group(1)).get(str(item))
        if entry:
            info["name"], info["quality"] = entry.get("name_enus") or "", entry.get("quality") or 0
    classs = re.search(r'"classs":(\d+)', page)
    info["classs"] = int(classs.group(1)) if classs else None
    if "id: 'dropped-by'" in page:
        for row in wowhead.listview(page, "dropped-by"):
            outof = row.get("outof") or 0
            chance = 100 * (row.get("count") or 0) / outof if outof else 0
            info["droppers"].append({"npc": row["id"], "chance": round(chance, 1)})
    return info


def fetch_drops(npc):
    """[{ id, name, quality, chance (percent), specific, classs }] from the rare's page."""
    page = wowhead.fetch(f"{wowhead.WOWHEAD}/npc={npc}")
    out = []
    for row in wowhead.listview(page, "drops"):
        mode = (row.get("modes") or {}).get("0") or {}
        chance = row.get("percentOverride")
        if chance is None:
            chance = 100 * mode["count"] / mode["outof"] if mode.get("outof") and mode.get("count", -1) > 0 else 0
        out.append({"id": row["id"], "name": row.get("name") or "", "quality": row.get("quality") or 0,
                    "chance": round(chance, 1), "specific": bool(row.get("specificDrop")),
                    "classs": row.get("classs")})
    return out


def special(d, new):
    if d["id"] in new:
        return d["specific"] or d["quality"] >= NEW_WORLD_QUALITY
    return d["quality"] >= LOOT_QUALITY or d["classs"] == RECIPE


def loot_of(drops, new):
    """(shown, more): its special drops (LOOT_QUALITY or better, recipes, or new in Forever), its
    own first, then by quality and chance, at most MAX_LOOT; and how many more there are."""
    picked = [d for d in drops if special(d, new)]
    picked.sort(key=lambda d: (not d["specific"], -d["quality"], -d["chance"], d["name"]))
    return picked[:MAX_LOOT], max(0, len(picked) - MAX_LOOT)


def with_set_pieces(drops, npc, pieces):
    """The rare's drops and the set pieces it drops that its page does not list yet."""
    have = {d["id"] for d in drops}
    out = list(drops)
    for item, info in pieces.items():
        if int(item) in have or not info:
            continue
        for dropper in info["droppers"]:
            if dropper["npc"] == npc:
                out.append({"id": int(item), "name": info["name"], "quality": info["quality"],
                            "chance": dropper["chance"], "specific": True, "classs": info["classs"]})
    return out


def fetch_zone(area):
    """{ "name": the zone's name, "rares": its rare creatures' listview rows }."""
    page = wowhead.fetch(f"{wowhead.WOWHEAD}/zone={area}")
    rares = []
    for row in wowhead.listview(page, "npcs"):
        if row.get("classification") in (RARE, RARE_ELITE):
            kept = {k: row[k] for k in KEEP if k in row}
            kept["status"] = (row.get("envChange") or {}).get("status")
            rares.append(kept)
    return {"name": zone_name(page), "rares": rares}


def groups(coords):
    """The points linked up: each group's points within LINK of another of its points."""
    left, out = list(coords), []
    while left:
        stack, group = [left.pop()], []
        while stack:
            p = stack.pop()
            group.append(p)
            near = [q for q in left if math.dist(p, q) <= LINK]
            for q in near:
                left.remove(q)
            stack += near
        out.append(group)
    return out


def patrol(group):
    return len(group) >= PATROL_POINTS and max(math.dist(a, b) for a in group for b in group) >= PATROL_SPAN


def spread(coords, gap, most):
    """The points, those within gap of one kept left out, at most `most`: the ones with the
    most points around them first."""
    def crowd(c):
        return sum(1 for o in coords if math.dist(c, o) < gap)
    kept = []
    for c in sorted(coords, key=lambda c: (-crowd(c), c[0], c[1])):
        if all(math.dist(c, k) >= gap for k in kept):
            kept.append(c)
    return kept[:most]


def spots_on(spots, map_id):
    """Where the rare is on the map: (stars, trail). A star at each spot it spawns, and on
    each way it patrols the point nearest the way's middle, the one Wowhead saw it at most
    first (a way counts all its points, a spot those within NEAR of it): the map's one star
    for the rare. The trail, dots along those ways."""
    coords = [tuple(c) for c in spots.get(str(map_id)) or []]
    if not coords:
        return [], []
    weighed, trail, still = [], [], []
    for group in sorted(groups(coords), key=len, reverse=True):
        if patrol(group):
            cx = sum(p[0] for p in group) / len(group)
            cy = sum(p[1] for p in group) / len(group)
            weighed.append((len(group), min(group, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)))
            trail += spread(group, TRAIL_GAP, MAX_TRAIL)
        else:
            still += group
    ways = [s for _, s in weighed]
    for s in spread(still, NEAR, MAX_SPOTS):
        if all(math.dist(s, k) >= NEAR for k in ways):
            weighed.append((sum(1 for o in still if math.dist(s, o) < NEAR), s))
    weighed.sort(key=lambda w: (-w[0], w[1]))
    return [s for _, s in weighed][:MAX_SPOTS], trail[:MAX_TRAIL]


def continents():
    """uiMapID -> its continent (0 Eastern Kingdoms, 1 Kalimdor), from the quest zones'
    cache: the continent most of a zone's quests are filed under."""
    out = {}
    for area, z in load(ZONES).items():
        conts = [q.get("category2", 0) for q in z["quests"]]
        if conts:
            out[ZONE_MAP[int(area)]] = max(set(conts), key=conts.count)
    return out


def main():
    offline = "--offline" in sys.argv
    cache = load(CACHE) or {}
    cache.setdefault("zones", {})
    cache.setdefault("npcs", {})
    cache.setdefault("drops", {})
    cache.setdefault("setpieces", {})
    failed = []
    if not offline:
        for area in ZONE_MAP:
            if str(area) in cache["zones"]:
                continue
            try:
                cache["zones"][str(area)] = fetch_zone(area)
            except urllib.error.HTTPError as e:
                failed.append(f"zone {area}: {e}")
                continue
            save(CACHE, cache)
            z = cache["zones"][str(area)]
            print(f"zone {area} {z['name']}: {len(z['rares'])} rares")
            time.sleep(GAP)
        todo = sorted({r["id"] for z in cache["zones"].values() for r in z["rares"]
                       if str(r["id"]) not in cache["npcs"]})
        print(f"{len(todo)} rare pages to fetch")
        for n, npc in enumerate(todo, 1):
            try:
                cache["npcs"][str(npc)] = fetch_npc(npc)
            except urllib.error.HTTPError as e:
                failed.append(f"npc {npc}: {e}")
                continue
            save(CACHE, cache)
            if n % 25 == 0:
                print(f"  {n}/{len(todo)}")
            time.sleep(GAP)
        todo = sorted({r["id"] for z in cache["zones"].values() for r in z["rares"]
                       if str(r["id"]) not in cache["drops"]})
        print(f"{len(todo)} rare pages to fetch for loot")
        for n, npc in enumerate(todo, 1):
            try:
                cache["drops"][str(npc)] = fetch_drops(npc)
            except urllib.error.HTTPError as e:
                failed.append(f"drops {npc}: {e}")
                continue
            save(CACHE, cache)
            if n % 25 == 0:
                print(f"  {n}/{len(todo)}")
            time.sleep(GAP)
        todo = [i for i in new_set_pieces() if str(i) not in cache["setpieces"]]
        print(f"{len(todo)} set piece pages to fetch")
        for n, item in enumerate(todo, 1):
            try:
                cache["setpieces"][str(item)] = fetch_piece(item)
            except urllib.error.HTTPError as e:
                failed.append(f"set piece {item}: {e}")
                continue
            save(CACHE, cache)
            if n % 25 == 0:
                print(f"  {n}/{len(todo)}")
            time.sleep(GAP)
    write(cache)
    for line in failed:
        print("FAILED", line, file=sys.stderr)


def write(cache):
    conts = continents()
    lines = [
        "-- Rares.lua: every rare of every zone, generated by Tools/build/completo_rares.py.",
        "local D = {}",
        "_G.NaowhForever.CompletoRareData = D",
        "",
        "D.Zones = {",
    ]
    # A rare listed in more than one zone goes to the one it spawns in most (the first, by
    # name, where it has no spot at all); one listed in a zone it never spawns in, while it
    # spawns elsewhere, is left to that other zone.
    home = {}
    for area, z in sorted(cache["zones"].items(), key=lambda kv: kv[1]["name"] or ""):
        map_id = ZONE_MAP[int(area)]
        for r in z["rares"]:
            if r["id"] in EVENT_ONLY:
                continue
            spots = cache["npcs"].get(str(r["id"])) or {}
            here = len(spots.get(str(map_id)) or [])
            if not here and any(m != str(map_id) for m in spots):
                continue
            if r["id"] not in home or here > home[r["id"]][1]:
                home[r["id"]] = (map_id, here, r)
    rares = {}
    by_zone = {}
    for npc, (map_id, _, r) in home.items():
        rares[npc] = (map_id, r) + spots_on(cache["npcs"].get(str(npc)) or {}, map_id)
        by_zone.setdefault(map_id, []).append(r)
    for area, z in sorted(cache["zones"].items(), key=lambda kv: kv[1]["name"] or ""):
        map_id = ZONE_MAP[int(area)]
        ids = [r["id"] for r in sorted(by_zone.get(map_id, []),
                                         key=lambda r: (r.get("minlevel") or 0, r["name"]))]
        if ids:
            lines.append(f"    {{ map = {int(map_id)}, name = {lua_string(z['name'])}, "
                         f"continent = {int(conts.get(map_id, -1))}, "
                         f"rares = {{ {', '.join(str(int(i)) for i in ids)} }} }},")
    lines += [
        "}",
        "",
        "D.Rares = {",
    ]
    for npc in sorted(rares):
        map_id, r, spots, trail = rares[npc]
        react = r.get("react") or [None, None]
        a = int(react[0]) if react[0] is not None else -1
        h = int(react[1]) if len(react) > 1 and react[1] is not None else -1
        def flat(points):
            out = []
            for x, y in points:
                fx, fy = forever_spot(map_id, x, y)
                out += [f"{fx:.1f}", f"{fy:.1f}"]
            return "{ " + ", ".join(out) + " }"
        way = f", {flat(trail)}" if trail else ""
        low = int(r.get("minlevel") or 0)
        high = int(r.get("maxlevel") or low)
        low, high = (-1 if v == SKULL_LEVEL else v for v in (low, high))
        lines.append(f"    [{int(npc)}] = {{ {lua_string(r['name'])}, {low}, {high}, "
                     f"{1 if r.get('classification') == RARE_ELITE else 0}, {a}, {h}, {int(map_id)}, "
                     f"{flat(spots)}{way} }},")
    lines += [
        "}",
        "",
        "D.Loot = {",
    ]
    new = new_items()
    for npc in sorted(rares):
        drops = cache.get("drops", {}).get(str(npc))
        if drops is None:
            continue
        drops = with_set_pieces(drops, npc, cache.get("setpieces", {}))
        shown, more = loot_of(drops, new)
        if not shown:
            continue
        items = ", ".join(f"{{ {int(d['id'])}, {int(d['quality'])}, {float(d['chance']):g}, "
                          f"{lua_string(d['name'])}"
                          f"{', 1' if d['id'] in new else ''} }}" for d in shown)
        parts = [items] + ([f"more = {int(more)}"] if more else [])
        lines.append(f"    [{int(npc)}] = {{ {', '.join(parts)} }},")
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii", "replace"))
    print(f"wrote {OUT.relative_to(ROOT)}: {len(rares)} rares")


if __name__ == "__main__":
    main()
