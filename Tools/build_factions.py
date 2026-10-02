"""Build the Dungeon Journal's factions from Tools/journal_factions.json and the game's own
tables (Tools/wago.py).

Every item that needs a standing with a faction says so in the game's item table
(ItemSparse: MinFactionID, MinReputation, 0 Hated to 7 Exalted, one below the game's
reaction), with its price at a vendor (BuyPrice, in copper), quality, item level and
required level; the Item table gives its class and subclass. Hotfixes are applied: the
items added since the build was cut are only there. A faction's rewards are the items that
need a standing with it, all but grey ones (the tables keep a few grey test items). Nothing
is read from Wowhead.

By hand, on top: a faction's "add" list in journal_factions.json adds rewards the game's
tables do not have yet (announced, or on the test realm), and its "remove" list drops ones
that are wrong. An added item is written like this, standing by its name and price in coins
(both price and note can be left out):

    "add": [
        { "item": 272063, "standing": "Honored", "price": "9g 1s 14c", "note": "on the PTR" }
    ],
    "remove": [ 4996 ]

What the game's tables know about an added item (its quality, level, class) is used where
they have the item at all.

Hotfixes carried over: an item the build's tables lack entirely is taken from the tables of
wago.CARRY_FROM, the build before, with its hotfixes (see Tools/wago.py). An item the build
has, the build's own row wins. Once they list it as this faction's reward, theirs win, and the
build says its hand-written line can go.

Writes one file per faction, DungeonJournal/Data/Factions/<Key>.lua,
DungeonJournal/Data/FactionItems.lua with what the Journal needs to know about each reward
before the client has loaded it, and DungeonJournal/Data/Build.lua: the build the data is
read from and when it came out, shown by the Journal's title.

Usage: python Tools/build_factions.py [--build 1.60.1.70124] [--carry-from 1.60.1.70094]
"""
import argparse
import json
import re
import sys
from pathlib import Path

import wago
from build_dungeon_loot import kind, lua_string
from build_journal import OUT, header, write

FACTIONS = Path(__file__).resolve().parent / "journal_factions.json"
GEAR = (2, 4)    # the game's item classes for weapons and armor
POOR = 0         # grey: never a reward
CLOAK = 16       # the game's inventory type for a back item
COSMETIC = 5     # the game's armor subclass for a cosmetic item: a look, no stats
STANDINGS = {"hated": 1, "hostile": 2, "unfriendly": 3, "neutral": 4, "friendly": 5, "honored": 6,
             "revered": 7, "exalted": 8}
COIN = {"g": 10000, "s": 100, "c": 1}


def item_facts(sparse, item):
    """An item's facts from its ItemSparse and Item rows: {id, class, subclass, level,
    reqlevel, quality, price, slot}."""
    return {
        "id": int(sparse["ID"]),
        "class": int(item.get("ClassID") or 0),
        "subclass": int(item.get("SubclassID") or 0),
        "level": int(sparse["ItemLevel"] or 0),
        "reqlevel": int(sparse["RequiredLevel"] or 0),
        "quality": int(sparse["OverallQualityID"] or 0),
        "price": int(sparse["BuyPrice"] or 0),
        "slot": int(sparse["InventoryType"] or 0),
        "name": sparse.get("Display_lang") or "",
    }


def game_items(build, carry=None):
    """Item ID -> its facts, for every item in the build's tables, and faction ID -> its
    rewards there (the items that need a standing with it, each with its standing as the
    game's reaction: 4 Neutral to 8 Exalted), and the IDs of the items carried over. With
    carry, a build whose tables fill in the items build's lack entirely."""
    classes = {row["ID"]: row for row in wago.table("Item", build)}
    rows = wago.table("ItemSparse", build)
    carried = set()
    if carry:
        have = {row["ID"] for row in rows}
        older = [row for row in wago.table("ItemSparse", carry) if row["ID"] not in have]
        carried = {int(row["ID"]) for row in older}
        rows = rows + older
        for row in wago.table("Item", carry):
            classes.setdefault(row["ID"], row)
    every, rewards = {}, {}
    for row in rows:
        item = item_facts(row, classes.get(row["ID"], {}))
        every[item["id"]] = item
        faction = int(row["MinFactionID"] or 0)
        if faction and item["quality"] != POOR:
            rewards.setdefault(faction, []).append(dict(item, standing=int(row["MinReputation"]) + 1))
    return every, rewards, carried


def standing(text, where):
    """"Revered" -> 7."""
    value = STANDINGS.get(str(text).strip().lower())
    if value is None:
        sys.exit(f"{where}: standing {text!r} is not one of {', '.join(s.title() for s in STANDINGS)}")
    return value


def copper(price, where):
    """A price in copper: a number, or coins as the game writes them ("9g 1s 14c", "50s")."""
    if price is None or isinstance(price, int):
        return price or 0
    parts = re.findall(r"(\d+)\s*([gsc])", str(price).lower())
    if not parts or re.sub(r"[\d\s]*[gsc]", "", str(price).lower()).strip():
        sys.exit(f"{where}: price {price!r} should read like \"9g 1s 14c\" or \"50s\"")
    return sum(int(n) * COIN[coin] for n, coin in parts)


def by_hand(faction, items, every, notes):
    """The faction's rewards with its "add" and "remove" lists from journal_factions.json put
    in. notes gets a line for each added item the game's tables now list as this reward."""
    key = faction["key"]
    removed = {int(i) for i in faction.get("remove", [])}
    items = [i for i in items if i["id"] not in removed]
    have = {i["id"]: i for i in items}
    for entry in faction.get("add", []):
        where = f"journal_factions.json, {key}, item {entry.get('item')}"
        if not isinstance(entry.get("item"), int):
            sys.exit(f"{where}: \"item\" should be the item's ID, a number")
        wanted = standing(entry.get("standing"), where)
        if entry["item"] in have:
            game = have[entry["item"]]
            said = "" if game["standing"] == wanted else f" (the game says {game['standing']}, not {wanted})"
            notes.append(f"{key}: item {entry['item']} is in the game's tables now{said}; its \"add\" line can go.")
            continue
        # Unknown to the game's tables: an item every class may use, white until the client
        # has loaded it and knows better.
        known = every.get(entry["item"])
        item = dict(known) if known else {"id": entry["item"], "class": 0, "subclass": 0, "level": 0,
                                          "reqlevel": 0, "quality": 1, "price": 0, "slot": 0}
        item["standing"] = wanted
        if "price" in entry:
            item["price"] = copper(entry["price"], where)
        item["hand"] = True
        items.append(item)
    return items


def turnins(faction, every, zones=None):
    """The faction's repeatable quests, kept by hand in its "turnins" list: each
    {"name", "quests": [their IDs, one per side], "rep": what a turn-in gives, "takes":
    [[item ID, count], ...]}, and optionally "level", "at" (quest ID -> [side, who takes it,
    zone, x, y]) and "from" ([[zone, how many give its items, [some of their names]]]). The
    game's tables cannot vouch for the quests (its quest table lists only the few the client
    needs itself), but they can for the items: one the game does not know, or an entry that
    does not read, stops the build as a typo. A zone becomes its map ID through zones (zone
    name -> map IDs), for the waypoint; one inside a dungeon has none."""
    key = faction["key"]
    zones = zones or {}
    out = []
    for entry in faction.get("turnins", []):
        where = f"journal_factions.json, {key}, turn-in {entry.get('name')!r}"
        ids, rep, takes = entry.get("quests"), entry.get("rep"), entry.get("takes")
        if not isinstance(entry.get("name"), str) or not entry["name"].isascii():
            sys.exit(f"{where}: \"name\" should be the quest's name, in ASCII")
        if not ids or not all(isinstance(q, int) for q in ids):
            sys.exit(f"{where}: \"quests\" should be a list of quest IDs")
        if not isinstance(rep, int) or rep <= 0:
            sys.exit(f"{where}: \"rep\" should be the reputation a turn-in gives, a number")
        if not takes or not all(isinstance(t, list) and len(t) == 2 and all(isinstance(n, int) and n > 0 for n in t)
                                for t in takes):
            sys.exit(f"{where}: \"takes\" should be [[item ID, count], ...]")
        for item, _ in takes:
            if item not in every:
                sys.exit(f"{where}: the game has no item {item}")
        at = entry.get("at", {})
        quests = []
        for qid in ids:
            side, giver, zone, x, y = at.get(str(qid)) or ["B", None, None, None, None]
            if side not in ("A", "H", "B"):
                sys.exit(f"{where}: quest {qid}'s side should be A, H or B")
            spot = f" ({x:g}, {y:g})" if x is not None and y is not None else ""
            text = " - ".join(part for part in (zone, (giver or "") + spot) if part)
            maps = zones.get(zone) or [None]
            quests.append({"id": qid, "side": side, "where": text,
                           "map": maps[0] if x is not None else None, "x": x, "y": y})
        out.append({"name": entry["name"], "quests": quests, "rep": rep, "takes": takes,
                    "level": entry.get("level"), "from": entry.get("from", [])})
    return out


def facts(item):
    """(class, subclass) as the Journal's item facts keep them: gear as build_journal's kind,
    anything else as an item with no armor type, which every class may use. A cloak too: the
    game files cloaks as cloth, yet every class wears one (the dungeon data, from Wowhead,
    has them as no armor type the same way). And a cosmetic item, which any class can wear."""
    cosmetic = item["class"] == 4 and item["subclass"] == COSMETIC
    if item["class"] in GEAR and item["slot"] != CLOAK and not cosmetic:
        return kind(item)
    return 4, 0


def places(build):
    """Zone name -> its map IDs (the game's zone maps, UiMap Type 3; Zephras Isle has two), and
    battleground name -> its instance ID (the Map table's, InstanceType 3). The Journal matches
    where you are by these, so it works in every language."""
    zones = {}
    for row in wago.table("UiMap", build):
        if row["Type"] == "3":
            zones.setdefault(row["Name_lang"], []).append(int(row["ID"]))
    battlegrounds = {row["MapName_lang"]: int(row["ID"]) for row in wago.table("Map", build)
                     if row["InstanceType"] == "3"}
    return zones, battlegrounds


def faction_file(faction, name, items, build, repeatables=(), maps=(), instance=None):
    key = faction["key"]
    lines = header(
        f"Data/Factions/{key}.lua -- {name} in the Dungeon Journal.",
        "Generated by Tools/build_factions.py from Tools/journal_factions.json and the game's",
        f"item tables (build {build}); do not edit by hand.",
    )
    hand = sorted(i["id"] for i in items if i.get("hand"))
    if hand:
        lines.append("-- Added by hand in Tools/journal_factions.json: " + ", ".join(map(str, hand)))
    lines += [f"ns.Journal.AddFaction({lua_string(key)}, {{",
              f"    id = {faction['id']}, name = {lua_string(name)}, tab = {lua_string(faction['tab'])},"]
    for field in ("group", "zone", "side", "battleground"):
        if faction.get(field):
            lines.append(f"    {field} = {lua_string(faction[field])},")
    if faction.get("new"):
        lines.append("    new = true,")
    if faction.get("unreleased"):
        lines.append("    unreleased = true,")
    # Where its quartermaster stands, entered by hand ({name, map, x, y}); the Journal also
    # learns it when you open the vendor.
    spot = faction.get("quartermaster")
    if spot:
        lines.append(f"    quartermaster = {{ name = {lua_string(spot['name'])}, map = {spot['map']}, "
                     f"x = {spot['x']}, y = {spot['y']} }},")
    if faction.get("dungeons"):
        lines.append("    dungeons = { " + ", ".join(lua_string(d) for d in faction["dungeons"]) + " },")
    # Where you earn it, as the game's IDs, for the map panel: its zone's maps, its
    # battleground's instance.
    if maps:
        lines.append("    maps = { " + ", ".join(map(str, maps)) + " },")
    if instance:
        lines.append(f"    instance = {instance},")
    # Its repeatable quests, kept by hand: the quests (one per side), the reputation a
    # turn-in gives, and the items it takes as item, count, item, count...
    # Each quest as the dungeon quests are kept: ID, side, where it is handed in, and the
    # map, x, y of who takes it; from: per zone, how many give its items and some of them.
    if repeatables:
        lines.append("    turnins = {")
        for t in repeatables:
            level = f", level = {t['level']}" if t.get("level") else ""
            lines.append(f"        {{ name = {lua_string(t['name'])}, rep = {t['rep']}{level}, takes = {{ "
                         + ", ".join(f"{item}, {count}" for item, count in t["takes"]) + " },")
            lines.append("            quests = {")
            for q in t["quests"]:
                spot = f", {q['map']}, {q['x']:g}, {q['y']:g}" if q["map"] else ""
                lines.append(f"                {{ {q['id']}, {lua_string(q['side'])}, {lua_string(q['where'])}{spot} }},")
            lines.append("            },")
            if t["from"]:
                lines.append("            from = {")
                for zone, many, names in t["from"]:
                    lines.append(f"                {{ {lua_string(zone)}, {many}"
                                 + "".join(", " + lua_string(n) for n in names) + " },")
                lines.append("            },")
            lines.append("        },")
        lines.append("    },")
    # One tier per standing, lowest first; in each, the best quality and the highest level first.
    tiers = {}
    for item in items:
        tiers.setdefault(item["standing"], []).append(item)
    lines.append("    tiers = {")
    for level in sorted(tiers):
        ordered = sorted(tiers[level], key=lambda i: (-i["quality"], -i["reqlevel"], -i["level"], i["id"]))
        lines.append(f"        {{ standing = {level}, items = {{ "
                     + ", ".join(str(i["id"]) for i in ordered) + " } },")
    lines.append("    },")
    priced = sorted((i["id"], i["price"]) for i in items if i["price"] > 0)
    if priced:
        lines.append("    prices = {")
        lines += [f"        [{item_id}] = {coins}," for item_id, coins in priced]
        lines.append("    },")
    lines.append("})")
    return lines


def items_file(items, build):
    lines = header(
        "Data/FactionItems.lua -- what the Dungeon Journal knows about each faction reward,",
        "before the client has loaded the item, beside Data/Items.lua's. Generated by",
        f"Tools/build_factions.py from the game's item tables (build {build}); do not edit.",
    )
    lines.append("local items = ns.Journal.Items")
    for item_id in sorted(items):
        item = items[item_id]
        cls, sub = facts(item)
        lines.append(f"items[{item_id}] = {{ {cls}, {sub}, {item['level']}, {item['reqlevel']}, {item['quality']} }}")
    return lines


MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def released(build):
    """"1 Oct 2026": the day wago.tools first listed the build, the same on every run (unlike
    today's date). "" when it lists no such build."""
    for entry in wago.forever_builds():
        if entry["version"] == build and entry["created_at"]:
            year, month, day = entry["created_at"][:10].split("-")
            return f"{int(day)} {MONTHS[int(month) - 1]} {year}"
    return ""


def build_file(build):
    lines = header(
        "Data/Build.lua -- the WoW Forever build the Dungeon Journal's game data is read from,",
        "and the day it came out (the day wago.tools listed it), shown by the window's title.",
        "Generated by Tools/build_factions.py, and moved on by the daily build watcher; do not edit.",
    )
    return lines + [f"ns.Journal.DATA_BUILD = {lua_string(build)}",
                    f"ns.Journal.DATA_DATE = {lua_string(released(build))}"]


def build_all(build, carry=None):
    """Writes every faction's file and FactionItems.lua from the build, with carry's items it
    lacks. Returns the notes about hand-added items the game's tables have now, and the
    rewards carried over: [(faction name, [item IDs])]."""
    missing = wago.unreadable(build) + (wago.unreadable(carry) if carry else [])
    if missing:
        sys.exit(f"wago.tools cannot read {', '.join(missing)} for build {build} yet: try again later")
    config = json.loads(FACTIONS.read_text(encoding="utf-8"))
    names = {int(row["ID"]): row["Name_lang"] for row in wago.table("Faction", build)}
    every, found, carried = game_items(build, carry)
    zones, battlegrounds = places(build)
    kept = []
    items, files, notes = {}, [], []
    for faction in config["factions"]:
        name = faction.get("name") or names.get(faction["id"]) or faction["key"]
        mine = by_hand(faction, found.get(faction["id"], []), every, notes)
        theirs = sorted(i["id"] for i in mine if i["id"] in carried and not i.get("hand"))
        if theirs:
            kept.append((name, theirs))
        # Listed even with none: its page says this build has no rewards for it yet.
        if not mine:
            print(f"  no rewards in this build: {name} ({faction['id']})", file=sys.stderr)
        for item in mine:
            items[item["id"]] = item
        file = f"{faction['key']}.lua"
        maps = list(zones.get(faction.get("zone"), []))
        # The zones it is also earned in, by hand: a typo stops the build.
        for zone in faction.get("alsoIn", []):
            if zone not in zones:
                sys.exit(f"journal_factions.json, {faction['key']}: the game has no zone map {zone!r}")
            maps += zones[zone]
        if faction.get("zone") and not maps:
            print(f"  {name}: no zone map called {faction['zone']!r}, not shown beside the map anywhere",
                  file=sys.stderr)
        instance = battlegrounds.get(faction.get("battleground"))
        if faction.get("battleground") and not instance:
            sys.exit(f"journal_factions.json, {faction['key']}: the game has no battleground "
                     f"{faction['battleground']!r}")
        write(OUT / "Data" / "Factions" / file,
              faction_file(faction, name, mine, build, turnins(faction, every, zones), sorted(maps), instance))
        files.append(file)
        priced = sum(1 for i in mine if i["price"] > 0)
        hand = sum(1 for i in mine if i.get("hand"))
        print(f"{len(mine):5d}  {name} ({priced} priced" + (f", {hand} by hand)" if hand else ")"),
              file=sys.stderr)
    write(OUT / "Data" / "FactionItems.lua", items_file(items, build))
    write(OUT / "Data" / "Build.lua", build_file(build))
    print(f"{len(items)} items, {len(files)} factions, build {build}"
          + (f", {sum(len(i) for _, i in kept)} carried over from {carry}" if carry else ""), file=sys.stderr)
    for note in notes:
        print("  " + note, file=sys.stderr)
    print("DungeonJournal.xml lines:\n" + "\n".join(f'    <Script file="Data\\Factions\\{f}"/>' for f in files))
    return notes, kept


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", default=wago.BUILD, help="the Forever build to read (default: wago.BUILD)")
    parser.add_argument("--carry-from", default=wago.CARRY_FROM,
                        help="a build whose items fill in the ones --build lacks (default: wago.CARRY_FROM)")
    args = parser.parse_args()
    build_all(args.build, args.carry_from)


if __name__ == "__main__":
    main()
