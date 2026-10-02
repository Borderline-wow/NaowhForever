"""Build NaowhForever_DungeonLoot.lua: every item a WoW Forever dungeon drops, from Wowhead.

A Wowhead Forever zone page has a "drops" listview (new Listview({... id: 'drops' ...
data: [...]})) with the items whose drop source is that zone; each carries its slot,
class and subclass, item level, required level, quality and, in sourcemore, the NPC that
drops it most. World drops are not in it: those have no zone. The new Forever dungeons
have no drops on their zone pages yet; the two with a Wowhead guide get their loot from
the guide's "Loot" tabs, one tab per boss, with each item's details from its XML page.
Uncommon and better items that can be equipped are kept. Answers are cached in
dungeon_loot.json; delete an entry to fetch it again.

Usage: python Tools/build_dungeon_loot.py
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "BiS" / "NaowhForever_DungeonLoot.lua"
CACHE = Path(__file__).resolve().parent / "dungeon_loot.json"
WOWHEAD = "https://www.wowhead.com/forever"

# (name, Wowhead zone, Wowhead guide) in level order, named as NaowhForever_BiSData.lua
# names them. Blackrock Spire is one zone; its bosses are split into the two halves below.
DUNGEONS = [
    ("Ragefire Chasm", 2437, None),
    ("Hall of Thanes", 16919, "hall-of-thanes-dungeon-overview-location-rewards"),
    ("Wailing Caverns", 718, None),
    ("The Deadmines", 1581, None),
    ("Ruins of Lordaeron", 16611, "ruins-of-lordaeron-dungeon-overview-location-rewards"),
    ("Shadowfang Keep", 209, None),
    ("Blackfathom Deeps", 719, None),
    ("The Stockade", 717, None),
    ("Excavation Site: Wetlands", 16732, None),
    ("Gnomeregan", 721, None),
    ("Razorfen Kraul", 491, None),
    ("City of Dalaran", 16544, None),
    ("Scarlet Monastery", 796, None),
    ("Razorfen Downs", 722, None),
    ("The Drowned City", None, None),
    ("Uldaman", 1337, None),
    ("Krol'dok", None, None),
    ("Zul'Farrak", 1176, None),
    ("Maraudon", 2100, None),
    ("Sunken Temple", 1477, None),
    ("Alcaz Prison", None, None),
    ("Blackrock Depths", 1584, None),
    ("Dire Maul", 2557, None),
    ("Blackrock Spire", 1583, None),
    ("Scholomance", 2057, None),
    ("Stratholme", 2017, None),
    ("Blackmaw Hold", None, None),
    ("Shaper's Terrace", None, None),
]

UPPER_SPIRE = {
    "Pyroguard Emberseer", "Solakar Flamewreath", "Jed Runewatcher", "Goraluk Anvilcrack",
    "Warchief Rend Blackhand", "Gyth", "The Beast", "General Drakkisath", "Lord Valthalak",
}
UPPER_SPIRE_MOBS = ("Blackhand ", "Rage Talon ", "Chromatic ", "Rookery ", "Firebrand ")

# Wowhead inventory types that go in a gear slot: no shirt (4), bag (18), tabard (19),
# ammo (24) or quiver (27).
EQUIPPABLE = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 25, 26, 28}
SEP = " \u00b7 "


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    # Wowhead's CDN answers 403 once requests come too fast; it lifts after a pause.
    for wait in (30, 60, 120, 240, None):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                page = r.read().decode("utf-8")
            time.sleep(1)
            return page
        except urllib.error.HTTPError as e:
            if e.code not in (403, 429, 503) or wait is None:
                raise
            print(f"  {e.code} from {urllib.parse.urlsplit(url).netloc}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)


def listview(page, lv_id):
    start = page.find(f"id: '{lv_id}'")
    if start < 0:
        return []
    data = re.compile(r"data:\s*").search(page, start)
    return json.JSONDecoder().raw_decode(page[data.end():])[0]


def keep(item):
    return item.get("quality", 0) >= 2 and item.get("slot") in EQUIPPABLE


def fields(item, boss):
    return {
        "name": item["name"], "slot": item["slot"], "class": item["classs"],
        "subclass": item["subclass"], "level": item["level"], "reqlevel": item.get("reqlevel") or 0,
        "quality": item["quality"], "boss": boss,
    }


def zone_loot(zone):
    items = []
    for item in listview(fetch(f"{WOWHEAD}/zone={zone}"), "drops"):
        if not keep(item):
            continue
        named = [s["n"] for s in item.get("sourcemore") or [] if s.get("n") and s.get("z", zone) == zone]
        items.append(dict(fields(item, named[0] if named else None), id=item["id"]))
    return items


def guide_loot(slug):
    page = fetch(f"{WOWHEAD}/guide/{slug}")
    markup = json.loads(re.search(r'WH\.markup\.printHtml\(("(?:[^"\\]|\\.)*")', page).group(1))
    loot = markup[markup.index('[tabs name="Loot"'):]
    loot = loot[:loot.index("[/tabs]")]
    items = []
    for boss, body in re.findall(r'\[tab name="([^"]+)"\](.*?)\[/tab\]', loot, re.S):
        for item_id in re.findall(r"\[item=(\d+)\]", body):
            xml = fetch(f"{WOWHEAD}/item={item_id}&xml")
            item = json.loads("{" + re.search(r"<json><!\[CDATA\[(.*?)\]\]></json>", xml, re.S).group(1) + "}")
            if keep(item):
                items.append(dict(fields(item, boss.strip()), id=int(item_id)))
    return items


def place(dungeon, boss):
    if dungeon != "Blackrock Spire" or not boss:
        return dungeon
    upper = boss in UPPER_SPIRE or boss.startswith(UPPER_SPIRE_MOBS)
    return ("Upper " if upper else "Lower ") + dungeon


def lua_string(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + s.replace("\u00b7", "\\194\\183") + '"'


def kind(item):
    """(item class, subclass): 2 weapon or 4 armor; anything with no armor type is 0."""
    if item["class"] == 2:
        return 2, item["subclass"]
    return 4, max(item["subclass"], 0)


def main():
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    loot, counts, empty = {}, [], []

    for name, zone, guide in DUNGEONS:
        found = []
        for key, get in ((zone and f"zone={zone}", lambda: zone_loot(zone)),
                         (guide and f"guide={guide}", lambda: guide_loot(guide))):
            if not key:
                continue
            if key not in cache:
                cache[key] = get()
                CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True), encoding="utf-8")
            found += cache[key]
        added = 0
        for item in found:
            if item["id"] in loot:
                continue
            where = place(name, item["boss"])
            loot[item["id"]] = dict(item, source=(item["boss"] or "Trash drop") + SEP + where)
            added += 1
        counts.append((name, added))
        if not found:
            empty.append(name)

    lines = [
        "-------------------------------------------------------------------------------",
        "--  NaowhForever_DungeonLoot.lua -- every uncommon or better item a WoW Forever dungeon",
        "--  drops that goes in a gear slot, from Wowhead's Forever database (zone drop lists, and",
        "--  the dungeon guides for the new dungeons). Generated by Tools/build_dungeon_loot.py; do",
        "--  not edit by hand.",
        "--",
        "--  [itemID] = { class, subclass, item level, required level, source }",
        "--  class: 2 weapon, subclass as Enum.ItemWeaponSubclass. 4 armor, subclass 1 cloth,",
        "--  2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem, 0 anything else",
        "--  (cloak, neck, ring, trinket, held in off-hand). source is the boss, or the mob that",
        "--  drops it most, or Trash drop, then the dungeon, worded like NaowhForever_BiSData.lua's",
        "--  sources.",
        "-------------------------------------------------------------------------------",
        "local ns = _G.NaowhForever",
        "",
        "ns.BiSDungeonLoot = {",
    ]
    for item_id in sorted(loot):
        item = loot[item_id]
        cls, sub = kind(item)
        lines.append(f"    [{item_id}] = {{ {cls}, {sub}, {item['level']}, {item['reqlevel']}, {lua_string(item['source'])} }},")
    lines.append("}")
    OUT.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))

    for name, added in counts:
        print(f"{added:5d}  {name}", file=sys.stderr)
    print(f"{len(loot)} items -> {OUT.name}", file=sys.stderr)
    if empty:
        print(f"No Wowhead loot data for: {', '.join(empty)}", file=sys.stderr)


if __name__ == "__main__":
    main()
