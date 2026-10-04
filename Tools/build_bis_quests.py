"""Build DungeonJournal/Data/BiSQuests.lua: every quest that rewards an item a BiS ranking lists,
for the BiS List's Quests page, as the Dungeon Journal's quest records.

From Wowhead's Forever pages: each ranked item's "Reward from" quests (its level, the level
it needs, its side, class and races, and whether the item is a choice), cached in
bis_quests.json; then each of those quests' page for where it starts (its quest giver on the
map, or the item that starts it) and whether it can be shared, cached in bis_quest_pages.json.
Delete an entry to fetch it again. Every ranked item is looked up, not only the ones whose
source says Quest: a source names one way to get an item, and a drop wins over a quest.

Run Tools/build_quest_chains.py after it: it reads this file's quests too, for their chains,
what to do first and the level they need.

Usage: python Tools/build_bis_quests.py
"""
import json
import re
import sys
import time
import urllib.error
from pathlib import Path

from build_bis_data import WOWHEAD, current_specs, fetch, listview, lua_string
from build_quest_chains import REDRAWN, ZONE_MAP

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "DungeonJournal" / "Data" / "BiSQuests.lua"
ITEMS = Path(__file__).resolve().parent / "bis_quests.json"
PAGES = Path(__file__).resolve().parent / "bis_quest_pages.json"

SIDES = {1: "A", 2: "H"}
CLASSES = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN", 128: "MAGE",
           256: "WARLOCK", 1024: "DRUID"}
# The playable races' bits (the client's ChrRaces.PlayableRaceBit), Forever's Skyborne at 32 and 33.
RACES = {1: "Human", 2: "Orc", 4: "Dwarf", 8: "Night Elf", 16: "Undead", 32: "Tauren", 64: "Gnome", 128: "Troll",
         1 << 32: "Skyborne", 1 << 33: "Skyborne"}
SIDE_RACES = {1: 1 | 4 | 8 | 64 | 1 << 32, 2: 2 | 16 | 32 | 128 | 1 << 33}


def race_limit(mask, side):
    """The races a quest is limited to, or None when it takes every race of its side."""
    if not mask:
        return None
    sides = [SIDE_RACES[s] for s in (1, 2) if side in (s, 3)]
    if all(mask & races == races for races in sides):
        return None
    names = list(dict.fromkeys(bits(mask, RACES)))
    return ", ".join(names) + " only" if names else None


def load(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save(path, data):
    path.write_text(json.dumps(data, indent=1, sort_keys=True), encoding="utf-8")


def rewarded_by(item_id):
    """The quests that reward the item: [{id, name, level, reqlevel, side, reqclass, reqrace, choice}]."""
    try:
        page = fetch(f"{WOWHEAD}/item={item_id}")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return []
        raise
    time.sleep(1)
    out = []
    for row in listview(page, "reward-from-q") or []:
        given = [r[0] for r in row.get("itemrewards") or []]
        out.append({"id": row["id"], "name": row.get("name", ""), "level": row.get("level") or 0,
                    "reqlevel": row.get("reqlevel") or 0, "side": row.get("side") or 3,
                    "reqclass": row.get("reqclass") or 0, "reqrace": row.get("reqrace") or 0,
                    "choice": item_id not in given})
    return out


def quest_page(quest_id):
    """Where the quest starts and whether it can be shared, from its page."""
    page = fetch(f"{WOWHEAD}/quest={quest_id}")
    time.sleep(1)
    start = None
    mapper = re.search(r"new Mapper\((\{.*?\})\);", page, re.S)
    objectives = (json.loads(mapper.group(1)).get("objectives") or {}) if mapper else {}
    for zone, objective in objectives.items():
        for level in objective.get("levels", []):
            for point in level:
                if not start and point.get("point") == "start" and len(point.get("coord") or ()) == 2:
                    start = {"zone": int(zone), "zoneName": objective.get("zone"), "coord": point["coord"],
                             "npc": point.get("name") or ""}
    item = re.search(r"Start: \[url=\\/forever\\/item=(\d+)[^\]]*\]([^\[]*)\[", page)
    shared = re.search(r"\[li\](Sharable|Not sharable)", page)
    return {"start": start, "item": item.group(2) if item else None,
            "shareable": None if not shared else shared.group(1) == "Sharable"}


def bits(mask, names):
    return [name for bit, name in names.items() if mask & bit]


def main():
    items, pages = load(ITEMS), load(PAGES)
    ranked = sorted({i for slots in current_specs().values() for ids in slots.values() for i in ids})
    failed = []
    for item_id in ranked:
        key = f"item={item_id}"
        if key in items:
            continue
        try:
            items[key] = rewarded_by(item_id)
        except urllib.error.HTTPError as e:
            failed.append(f"{key}: {e}")
            continue
        save(ITEMS, items)

    quests, rewards, choices = {}, {}, set()
    for key, rows in items.items():
        item_id = int(key.split("=")[1])
        if item_id not in ranked:
            continue
        for row in rows:
            quests.setdefault(row["id"], row)
            if item_id not in rewards.setdefault(row["id"], []):
                rewards[row["id"]].append(item_id)
            if row["choice"]:
                choices.add(row["id"])

    for quest_id in sorted(quests):
        key = f"quest={quest_id}"
        if key in pages:
            continue
        try:
            pages[key] = quest_page(quest_id)
        except (urllib.error.HTTPError, ValueError) as e:
            failed.append(f"{key}: {e}")
            continue
        save(PAGES, pages)

    records, zones = [], {}
    for quest_id, q in quests.items():
        page = pages.get(f"quest={quest_id}") or {}
        start = page.get("start")
        classes = bits(q["reqclass"], CLASSES)
        limits = []
        if len(classes) > 1:
            limits.append(", ".join(c.capitalize() for c in classes) + " only")
        races = race_limit(q["reqrace"], q["side"])
        if races:
            limits.append(races)
        spot = None
        if start and len(start["coord"]) != 2:
            start = None   # a page that maps its quest giver with half a spot
        if start:
            x, y = start["coord"]
            where = f"{start['zoneName']} - {start['npc']} ({x:g}, {y:g})"
            map_id = ZONE_MAP.get(start["zone"])
            if map_id and map_id not in REDRAWN:
                spot = (map_id, x, y)
            zones[quest_id] = start["zoneName"]
        elif page.get("item"):
            where = f"Starts from an item: {page['item']}"
        else:
            where = "Where it starts is not known yet"
        if limits:
            where += " (" + "; ".join(limits) + ")"
        records.append((q["level"] or q["reqlevel"], quest_id, q, page.get("shareable"), where, spot,
                        classes[0] if len(classes) == 1 else None, q["reqrace"] if races else None))
    records.sort(key=lambda r: (r[0], r[1]))

    lines = [
        "-------------------------------------------------------------------------------",
        "--  Data/BiSQuests.lua -- every quest that rewards an item a BiS ranking lists, for the BiS",
        "--  List's Quests page. Generated by Tools/build_bis_quests.py from Wowhead; do not edit.",
        "--",
        "--  BiSQuestData.quests: Data/Quests.lua's records, { questID, name, level, side,",
        "--  shareable, where it starts, uiMapID, x, y; class; races, a mask of the races that can",
        "--  take it, by ChrRaces.PlayableRaceBit }; a quest the Journal lists already",
        "--  is swapped for its record there. Its chain, what to do first and the level it needs are",
        "--  in Data/QuestChains.lua. BiSQuestRewards: questID -> the ranked items it rewards.",
        "--  BiSQuestChoices: the quests where those are a choice among its rewards.",
        "--  BiSQuestZones: questID -> the zone it starts in.",
        "-------------------------------------------------------------------------------",
        "local J = _G.NaowhForever.Journal",
        "",
        "J.BiSQuestData = { quests = {",
    ]
    for level, quest_id, q, shareable, where, spot, cls, races in records:
        fields = [str(quest_id), lua_string(q["name"]), str(level), f'"{SIDES.get(q["side"], "B")}"',
                  "false" if shareable is False else "true", lua_string(where)]
        if spot:
            fields += [str(spot[0]), f"{spot[1]:g}", f"{spot[2]:g}"]
        if cls:
            fields.append(f'class = "{cls}"')
        if races:
            fields.append(f"races = {races}")
        lines.append("    { " + ", ".join(fields) + " },")
    lines.append("} }")
    lines.append("")
    lines.append("J.BiSQuestRewards = {")
    for quest_id in sorted(rewards):
        lines.append(f"    [{quest_id}] = {{ {', '.join(str(i) for i in sorted(rewards[quest_id]))} }},")
    lines.append("}")
    lines.append("")
    lines.append("J.BiSQuestChoices = {")
    for quest_id in sorted(choices):
        lines.append(f"    [{quest_id}] = true,")
    lines.append("}")
    lines.append("")
    lines.append("J.BiSQuestZones = {")
    for quest_id in sorted(zones):
        lines.append(f"    [{quest_id}] = {lua_string(zones[quest_id])},")
    lines.append("}")
    text = "\r\n".join(lines) + "\r\n"
    text.encode("ascii")
    OUT.write_text(text, encoding="utf-8", newline="")
    print(f"{len(ranked)} ranked items, {len(records)} quests reward {sum(len(r) for r in rewards.values())} of them,"
          f" {len(zones)} with a start -> {OUT.name}", file=sys.stderr)
    if failed:
        print(f"{len(failed)} could not be read; run again to retry:", file=sys.stderr)
        for line in failed:
            print(f"  {line}", file=sys.stderr)


if __name__ == "__main__":
    main()
