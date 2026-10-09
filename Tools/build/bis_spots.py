"""Build NaowhForever_BiS/BiS/Data/Spots.lua: where to find the NPC that drops or sells a ranked BiS item out in
the world (not in a dungeon), so the BiS List's Run Next can put a waypoint on it.

From Wowhead's Forever pages: the item's "dropped by" (else "sold by") finds the NPC wowsrc's
source names, and the NPC's page has every spot it spawns at, by map. When the spawns spread
out (a roaming rare, or a camp of mobs), the spot is the spawn nearest their middle. Forever
redrew a few zones (Stormwind, Mulgore, Redridge, the Eastern Plaguelands) and Wowhead still
gives their classic coordinates, so an NPC there gets no spot. Answers are cached in
bis_spots.json (null for an item with none); delete an entry to fetch it again.

Usage: python Tools/build/bis_spots.py
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
from bis_data import OUT as BIS_DATA, SEP, WOWHEAD, current_specs, fetch, listview, lua_string  # noqa: E402
from quest_chains import REDRAWN  # noqa: E402

ROOT = paths.ROOT
OUT = ROOT / "NaowhForever_BiS" / "BiS" / "Data" / "Spots.lua"
CACHE = paths.DATA / "bis_spots.json"
DUNGEONS = ROOT / "NaowhForever_DungeonJournal" / "Data" / "Dungeons"
# Sources that are not somewhere to go, as Rankings.lua's NOT_A_PLACE.
NOT_A_PLACE = {"Crafted", "Quest", "Quest (Horde)", "Quest (Alliance)", "Quest Reward", "World drop", "Reputation"}
ROAMS = 3.0   # map units: spawns spread wider than this are "around" a spot


def sources():
    """Item ID -> its source text, from NaowhForever_BiS/BiS/Data/BiS.lua."""
    text = BIS_DATA.read_text(encoding="utf-8")
    body = text[text.index("sources = {"):]
    return {int(i): re.sub(r"\\(.)", r"\1", s) for i, s in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)",', body)}


def dungeon_names():
    """Every dungeon the Journal lists: what drops there is the Journal's to say."""
    return {re.search(r'name = "([^"]+)"', p.read_text(encoding="utf-8")).group(1) for p in DUNGEONS.glob("*.lua")}


def spot(item_id, who):
    """The spot of the NPC named who that drops or sells the item, or None."""
    page = fetch(f"{WOWHEAD}/item={item_id}")
    time.sleep(1)
    for kind in ("dropped-by", "sold-by"):
        npc = next((n for n in listview(page, kind) if n.get("name", "").lower() == who.lower()), None)
        if npc:
            break
    else:
        return None
    page = fetch(f"{WOWHEAD}/npc={npc['id']}")
    time.sleep(1)
    found = re.search(r"g_mapperData\s*=\s*(\{.*?\});", page, re.S)
    if not found:
        return None
    best = None
    for entries in json.loads(found.group(1)).values():
        for entry in entries:
            if entry.get("uiMapId") and entry.get("coords") and (not best or len(entry["coords"]) > len(best["coords"])):
                best = entry
    if not best or best["uiMapId"] in REDRAWN:
        return None
    coords = best["coords"]
    xs, ys = [c[0] for c in coords], [c[1] for c in coords]
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    x, y = min(coords, key=lambda c: (c[0] - mx) ** 2 + (c[1] - my) ** 2)
    return {"npc": npc["id"], "name": npc["name"], "map": best["uiMapId"], "x": x, "y": y,
            "roams": max(xs) - min(xs) > ROAMS or max(ys) - min(ys) > ROAMS, "sells": kind == "sold-by"}


def main():
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    ranked = {i for slots in current_specs().values() for ids in slots.values() for i in ids}
    dungeons = dungeon_names()
    spots = {}
    for item_id, source in sorted(sources().items()):
        who, _, place = source.rpartition(SEP)
        if item_id not in ranked or who in ("", "Trash drop") or place in NOT_A_PLACE or place in dungeons:
            continue
        key = f"item={item_id}"
        if key not in cache:
            cache[key] = spot(item_id, who)
            CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True), encoding="utf-8")
        if cache[key]:
            spots[item_id] = cache[key]
    lines = [
        "-- Spots.lua: where the NPC that drops or sells a ranked BiS item stands (Tools/build/bis_spots.py).",
        "local ns = _G.NaowhForever",
        "",
        "ns.BiSSpots = {",
    ]
    for item_id, s in sorted(spots.items()):
        lines.append(f"    [{item_id}] = {{ npc = {s['npc']}, name = {lua_string(s['name'])}, map = {s['map']}, "
                     f"x = {s['x']}, y = {s['y']}"
                     f"{', roams = true' if s['roams'] else ''}{', sells = true' if s.get('sells') else ''} }},")
    lines.append("}")
    OUT.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8", newline="")
    print(f"{len(spots)} spots -> {OUT.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
