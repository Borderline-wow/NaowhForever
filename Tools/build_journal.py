"""Build the Dungeon Journal's data from Tools/journal_bosses.json and Wowhead Forever.

The boss lists are kept by hand in journal_bosses.json. For each boss this finds its NPC on
Wowhead Forever by name and reads the "drops" list on its page: every item with the number
of kills it dropped from. Gear of uncommon quality or better is kept when it drops from at
least 1 in 100 kills and Wowhead does not mark it a world drop (the random greens any mob
of that level carries). The chance is the item's own: the times it dropped out of the kills
recorded for it (all difficulties together), not out of the page's total, which adds up
every game version that shares the page. A boss new in Forever has its drops listed with
no kills counted yet: its gear is kept with the chance unknown. Two more sources add what Wowhead has not
tied to the boss: the dungeon's Wowhead guide, where it has one, and the boss sources in
NaowhForever_BiSData.lua (wowsrc.com's). Their items have no chance either.

Each dungeon also gets the zone its entrance is in and that zone's territory (Alliance, Horde
or Contested) from Wowhead Forever's zone list, and the entrance itself where
journal_bosses.json has one.

Each boss gets its encounter IDs, what ENCOUNTER_END names it by (the Journal counts kills
with it): the game's DungeonEncounter table for the Forever build, from wago.tools' export,
joined on the dungeon's instance (its map in Data/Quests.lua, else the Map table by name) and
the boss's name, or its encounterNames entry in journal_bosses.json. Every row of the
5-player dungeon counts: difficulty 0 fires on any, and Forever has two "Normal"s, 1 and
201, with their own rows in some dungeons. The first ID listed is the one kills are saved
under. A rare, or a boss fought inside a shared encounter (the Ring of Law), has none.

Writes one file per dungeon, DungeonJournal/Data/Dungeons/<Key>.lua, and
DungeonJournal/Data/Items.lua with what the addon needs to know about each item before
the client has loaded it; a new dungeon's file also goes in DungeonJournal/DungeonJournal.xml. Answers are cached in journal_cache.json; delete an
entry to fetch it again.

Raids are in the same list with "raid" (how many players) and "announced": only the
raids announced for Forever get a file, so a classic raid waits in journal_bosses.json until
Blizzard announces it. A dungeon's "note" is shown at the top of its page, "loot": false leaves its loot out (a
raid whose drops Wowhead has no Forever data for yet: its page only has world drops), and
"encounterIDs" pins a boss's encounter IDs where the game's table hides its row.
"countedWith" names, for a boss the game runs no fight for, the boss whose fight it falls in
(Sneed's Shredder, which Sneed climbs out of): it takes that fight's encounter IDs, so its
kills count with it, and says so ("with").

Usage: python Tools/build_journal.py
"""
import csv
import io
import json
import re
import sys
import urllib.error
import urllib.parse
from pathlib import Path

from build_dungeon_loot import EQUIPPABLE, SEP, WOWHEAD, fetch, guide_loot, kind, listview, lua_string

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
BOSSES = TOOLS / "journal_bosses.json"
CACHE = TOOLS / "journal_cache.json"
OUT = ROOT / "DungeonJournal"
BIS_DATA = ROOT / "BiS" / "NaowhForever_BiSData.lua"
QUESTS = OUT / "Data" / "Quests.lua"

BUILD = "1.60.1.70094"   # the Forever client build the game's tables are read from
WAGO = "https://wago.tools/db2/{}/csv?build=" + BUILD
# A 5-player dungeon's difficulties, the one firing on every difficulty first. 198 and 215
# are the 10- and 20-player raid versions of some dungeons: never the Journal's.
DUNGEON_DIFFICULTIES = ("0", "1", "201")

MIN_CHANCE = 1.0   # percent of kills
MIN_QUALITY = 2    # uncommon
WORLD_DROP = 16384  # Wowhead's flags2 bit for an item any mob can drop

cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}


def cached(key, get):
    if key not in cache:
        cache[key] = get()
    return cache[key]


def save_cache():
    """Written whole to a temporary file first, so a stopped run never leaves half a cache.
    Windows refuses the swap while another program holds the cache open (an editor, a virus
    scan); then it is written in place."""
    text = json.dumps(cache, indent=1, sort_keys=True)
    tmp = CACHE.with_suffix(".tmp")
    tmp.write_text(text, encoding="utf-8")
    try:
        tmp.replace(CACHE)
    except PermissionError:
        CACHE.write_text(text, encoding="utf-8")
        tmp.unlink()


def find_npc(name):
    """The ID of the Wowhead Forever NPC with exactly this name (any case), or None."""
    def get():
        query = urllib.parse.urlencode({"q": name})
        found = json.loads(fetch(f"{WOWHEAD}/search/suggestions-template?{query}"))
        exact = [r["id"] for r in found["results"] if r["type"] == 1 and r["name"].lower() == name.lower()]
        return exact[0] if exact else None
    return cached(f"npc:{name}", get)


def npc_drops(npc):
    """[{id, chance, facts}] for the gear the NPC drops, most likely first."""
    def get():
        try:
            page = fetch(f"{WOWHEAD}/npc={npc}")
        except urllib.error.HTTPError as e:
            if e.code == 404:   # a boss Wowhead has no page for yet (a raid not open)
                return []
            raise
        start = page.find("template: 'item', id: 'drops'")
        if start < 0:
            return []
        total = int(page[start:].split("_totalCount:", 1)[1].split(",", 1)[0])

        def counted(i):
            """The item's drops and the kills they are out of: every difficulty ("0"), else
            its own count, else the page's total."""
            every = (i.get("modes") or {}).get("0")
            if every and every.get("outof"):
                return every.get("count", 0), every["outof"]
            return i.get("count", 0), i.get("outof") or total

        # Only what could be kept is cached: uncommon or better gear that is not a world drop.
        return [{"id": i["id"], "count": counted(i)[0], "kills": counted(i)[1], "slot": i.get("slot"),
                 "class": i.get("classs"), "subclass": i.get("subclass"), "level": i.get("level"),
                 "reqlevel": i.get("reqlevel") or 0, "quality": i.get("quality", 0)}
                for i in listview(page[start:], "drops")
                if i.get("quality", 0) >= MIN_QUALITY and i.get("slot") in EQUIPPABLE
                and not (i.get("commondrop") or i.get("flags2", 0) & WORLD_DROP)]
    drops = []
    for item in cached(f"drops2:{npc}", get):
        if item["kills"] == 0:
            drops.append(dict(item, chance=None))
        elif 100 * item["count"] / item["kills"] >= MIN_CHANCE:
            drops.append(dict(item, chance=100 * item["count"] / item["kills"]))
    drops.sort(key=lambda i: (-(i["chance"] or 0), -i["quality"], i["id"]))
    return drops


def item_facts(item_id):
    """What the item's XML says about it, in the fields npc_drops keeps."""
    def get():
        xml = fetch(f"{WOWHEAD}/item={item_id}&xml")
        item = json.loads("{" + re.search(r"<json><!\[CDATA\[(.*?)\]\]></json>", xml, re.S).group(1) + "}")
        return {"id": item_id, "slot": item.get("slot"), "class": item.get("classs"),
                "subclass": item.get("subclass"), "level": item.get("level"),
                "reqlevel": item.get("reqlevel") or 0, "quality": item.get("quality", 0)}
    return cached(f"item:{item_id}", get)


def plain(dungeon):
    """Lower case, without a leading "The": the BiS data leaves it off."""
    return re.sub(r"^the ", "", dungeon.lower())


def bis_sources():
    """(dungeon, boss), as plain() and lower case -> item IDs, from the BiS data's sources."""
    text = BIS_DATA.read_text(encoding="utf-8")
    by_boss = {}
    pattern = r'\[(\d+)\] = "(.*?)' + SEP + r'(.*?)"'
    for item_id, boss, where in re.findall(pattern, text[text.index("sources = {"):]):
        by_boss.setdefault((plain(where), boss.lower()), []).append(int(item_id))
    return by_boss


TERRITORY = {0: "Alliance", 1: "Horde"}   # anything else is open to both
# One zone in the list: its ID, name and territory, in that order in the JSON.
ZONE_ROW = re.compile(r'\{"category":[^{}]*?"id":(\d+),[^{}]*?"name":"([^"]*)"[^{}]*?"territory":(\d+)')


def zones():
    """Wowhead zone ID -> (name, territory), from Wowhead Forever's zone list."""
    def get():
        page = fetch(f"{WOWHEAD}/zones")
        found = {}
        for m in ZONE_ROW.finditer(page):
            found.setdefault(m.group(1), [m.group(2), int(m.group(3))])
        return found
    return cached("zones", get)


def guide_drops(slug):
    """Boss name (lower case) -> its items, from the guide's Loot tabs."""
    by_boss = {}
    for item in cached(f"guide:{slug}", lambda: guide_loot(slug)):
        by_boss.setdefault(item["boss"].lower(), []).append(dict(item, chance=None))
    return by_boss


def boss_entry(name, rare, pinned, extra, items, report):
    npc = pinned.get(name) or find_npc(name)
    loot = npc_drops(npc) if npc else []
    have = {i["id"] for i in loot}
    for item in extra.get(name.lower(), []):
        if item["id"] not in have and item["quality"] >= MIN_QUALITY and item["slot"] in EQUIPPABLE:
            loot.append(dict(item, chance=None))
            have.add(item["id"])
    if not npc:
        report.append(f"no NPC found: {name}")
    elif not loot:
        report.append(f"no loot: {name} ({npc})")
    for item in loot:
        items[item["id"]] = item
    return {"npc": npc, "name": name, "rare": rare, "loot": loot}


tables = {}


def db2_rows(table, fields):
    """The game's table for BUILD, each row as a list of the fields asked for. Read once per
    run and not cached: what is taken from it is, so the cache keeps only the Journal's rows."""
    if table not in tables:
        rows = csv.DictReader(io.StringIO(fetch(WAGO.format(table))))
        tables[table] = [[row[f] for f in fields] for row in rows]
    return tables[table]


def match_name(name):
    """A name as the encounter join compares it: no case, punctuation or leading "The"."""
    name = re.sub(r"^the ", "", name.lower().replace("\u2019", "'"))
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", "", name)).strip()


def map_encounters(map_id):
    """The 5-player encounters in an instance, [ID, name, difficulty]."""
    def get():
        rows = db2_rows("DungeonEncounter", ("ID", "Name_lang", "MapID", "DifficultyID"))
        return [[int(e), name, d] for e, name, m, d in rows if m == map_id and d in DUNGEON_DIFFICULTIES]
    return cached(f"encounters:{BUILD}:{map_id}", get) if map_id else []


def instance_maps():
    """Dungeon name -> its instance map ID: Data/Quests.lua's, else the Map table's by name."""
    text = QUESTS.read_text(encoding="ascii")
    maps = {m.group(1): m.group(2) for m in re.finditer(r'\{ name = "((?:[^"\\]|\\.)*)", map = (\d+),', text)}

    def by_name(dungeon):
        def get():
            want = match_name(dungeon)
            return next((m for m, name in db2_rows("Map", ("ID", "MapName_lang")) if match_name(name) == want), None)
        return cached(f"map:{BUILD}:{dungeon}", get)
    return lambda dungeon: maps.get(dungeon) or by_name(dungeon)


def boss_encounters(name, renamed, encounters):
    """The boss's encounter IDs, the one firing on any difficulty first, then by ID."""
    want = match_name(renamed.get(name, name))
    rows = [e for e in encounters if match_name(e[1]) == want]
    rows.sort(key=lambda e: (DUNGEON_DIFFICULTIES.index(e[2]), e[0]))
    return [e[0] for e in rows]


def chance(item):
    """Whole percent, at least 1; 0 when the chance is not known."""
    return "0" if item["chance"] is None else str(max(1, round(item["chance"])))


def lua_boss(boss):
    fields = [f"npc = {boss['npc'] or 'nil'}", f"name = {lua_string(boss['name'])}"]
    if boss["rare"]:
        fields.append("rare = true")
    if boss["encounters"]:
        fields.append("encounters = { " + ", ".join(str(e) for e in boss["encounters"]) + " }")
    if boss.get("with"):
        fields.append(f"with = {lua_string(boss['with'])}")
    if boss["loot"]:
        fields.append("loot = { " + ", ".join(str(i["id"]) for i in boss["loot"]) + " }")
        if any(i["chance"] is not None for i in boss["loot"]):
            fields.append("chance = { " + ", ".join(chance(i) for i in boss["loot"]) + " }")
    return "{ " + ", ".join(fields) + " }"


def write(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))


def header(title, *about):
    rule = "-------------------------------------------------------------------------------"
    return [rule, f"--  {title}", *(f"--  {line}".rstrip() for line in about), rule, "local ns = _G.NaowhForever", ""]


def dungeon_file(dungeon, wings, zone_names):
    lines = header(
        f"Data/Dungeons/{dungeon['key']}.lua -- {dungeon['name']} in the Dungeon Journal.",
        "Generated by Tools/build_journal.py from Tools/journal_bosses.json and Wowhead Forever;",
        "do not edit by hand. Naowh's tips are in Data/Tips.lua.",
    )
    lines += [f"ns.Journal.AddDungeon({lua_string(dungeon['key'])}, {{",
              f"    name = {lua_string(dungeon['name'])},"]
    if dungeon.get("new"):
        lines.append("    new = true,")
    if dungeon.get("raid"):
        lines.append(f"    raid = {dungeon['raid']},")
    if dungeon.get("note"):
        lines.append(f"    note = {lua_string(dungeon['note'])},")
    zone = zone_names.get(str(dungeon["entranceZone"]))
    if zone:
        territory = TERRITORY.get(zone[1], "Contested")
        lines.append(f"    zone = {lua_string(zone[0])}, territory = {lua_string(territory)},")
    entrance = dungeon.get("entrance")
    if entrance:
        lines.append(f"    entrance = {{ map = {entrance['map']}, x = {entrance['x']}, y = {entrance['y']} }},")
    lines.append("    wings = {")
    for wing in wings:
        name = f"name = {lua_string(wing['name'])}, " if wing.get("name") else ""
        lines.append(f"        {{ {name}bosses = {{")
        lines += [f"            {lua_boss(boss)}," for boss in wing["bosses"]]
        lines.append("        } },")
    lines += ["    },", "})"]
    return lines


def items_file(items):
    lines = header(
        "Data/Items.lua -- what the Dungeon Journal knows about each item it lists, before the",
        "client has loaded the item. Generated by Tools/build_journal.py; do not edit.",
        "",
        "[itemID] = { class, subclass, item level, required level, quality }, with class and",
        "subclass as in NaowhForever_DungeonLoot.lua (2 weapon, 4 armor; 0 no armor type).",
    )
    lines.append("ns.Journal.Items = {")
    for item_id in sorted(items):
        item = items[item_id]
        cls, sub = kind(item)
        lines.append(f"    [{item_id}] = {{ {cls}, {sub}, {item['level']}, {item['reqlevel']}, {item['quality']} }},")
    lines.append("}")
    return lines


def extra_loot(dungeon, bis):
    """Boss name (lower case) -> the items the guide and the BiS sources place on it."""
    extra = guide_drops(dungeon["guide"]) if dungeon.get("guide") else {}
    here = plain(dungeon["name"])
    for (where, boss), ids in bis.items():
        # The BiS data names both of Blackrock Spire's halves after the whole spire.
        if where == here or (where == "blackrock spire" and here.endswith("blackrock spire")):
            extra.setdefault(boss, []).extend(item_facts(i) for i in ids)
    return extra


def main():
    config = json.loads(BOSSES.read_text(encoding="utf-8"))
    bis = bis_sources()
    zone_names = zones()
    map_of = instance_maps()
    items, report, files = {}, [], []
    for dungeon in config["dungeons"]:
        if dungeon.get("announced") is False:
            continue   # a raid not announced for Forever: kept in the list, not built
        extra = extra_loot(dungeon, bis)
        pinned = dungeon.get("npcs", {})
        renamed = dungeon.get("encounterNames", {})
        pinned_encounters = dungeon.get("encounterIDs", {})
        counted_with = dungeon.get("countedWith", {})
        encounters = map_encounters(map_of(dungeon["name"]))
        wings = []
        for wing in dungeon["wings"]:
            # No loot for one whose drops are not known: its items go to a list nobody reads.
            kept = items if dungeon.get("loot", True) else {}
            bosses = [boss_entry(n, False, pinned, extra, kept, report) for n in wing["bosses"]]
            bosses += [boss_entry(n, True, pinned, extra, kept, report) for n in wing.get("rare", [])]
            if not dungeon.get("loot", True):
                for boss in bosses:
                    boss["loot"] = []
            for boss in bosses:
                boss["encounters"] = (boss_encounters(boss["name"], renamed, encounters)
                                      or pinned_encounters.get(boss["name"], []))
            # A boss killed on the way into another's fight counts with that fight.
            for boss in bosses:
                other = counted_with.get(boss["name"])
                if other:
                    fight = next(b for b in bosses if b["name"] == other)
                    boss["encounters"], boss["with"] = fight["encounters"], other
                if not boss["encounters"] and not boss["rare"]:
                    report.append(f"no encounter: {boss['name']} ({dungeon['name']})")
            wings.append({"name": wing.get("name"), "bosses": bosses})
        name = f"{dungeon['key']}.lua"
        write(OUT / "Data" / "Dungeons" / name, dungeon_file(dungeon, wings, zone_names))
        files.append(name)
        save_cache()
        count = sum(len(b["loot"]) for w in wings for b in w["bosses"])
        print(f"{count:5d}  {dungeon['name']}", file=sys.stderr)
    write(OUT / "Data" / "Items.lua", items_file(items))
    print(f"{len(items)} items, {len(files)} dungeons", file=sys.stderr)
    for line in report:
        print(f"  {line}", file=sys.stderr)
    print("DungeonJournal.xml lines:\n" + "\n".join(f'    <Script file="Data\\Dungeons\\{f}"/>' for f in files))


if __name__ == "__main__":
    main()
