"""Build BiS/Data/Enchants.lua: every enchant an enchanter can put on your gear, what it gives
and what it takes, so the BiS List can say which is best for your spec on what you wear.

From the game's own tables (wago.tools, Tools/wago.py): the Enchanting recipes, what each
enchant gives (stats, weapon damage, armor, or a spell that gives them) and what gear it goes
on. From Wowhead's Forever list of Enchanting recipes, the skill each needs and where it is
learned (a trainer, a vendor, a drop, a quest): cached in enchant_recipes.json; delete it to
fetch again. A recipe Wowhead does not list is left out.

No enchant has a level or item level limit, in the game's tables or on Wowhead: the BiS List
itself keeps its advice to what suits the item and your level.

A proc (Crusader) is ranked by a fair stat equivalent of its buff, PROCS below; a few that do
something no stat can say (SPECIALS) are listed beside the ranking, not in it.

Usage: python Tools/build_enchants.py
"""
import json
import re
import sys
from pathlib import Path

import wago
from build_bis_data import WOWHEAD, fetch, lua_string

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "BiS" / "Data" / "Enchants.lua"
CACHE = Path(__file__).resolve().parent / "enchant_recipes.json"
ENCHANTING = 333
ENCHANT_ITEM = 53   # SpellEffect: enchant an item
TWO_HANDED = 1378   # weapon subclasses: two-handed axe, mace, polearm, sword and staff

# ITEM_MOD index (SpellItemEnchantment effect 5) -> our stat
ITEM_MOD = {3: "agi", 4: "str", 5: "int", 6: "spi", 7: "sta", 12: "def", 41: "heal", 42: "spell",
            45: ("spell", "heal"), 84: "holy", 86: "nature", 89: "arcane", 124: "spi"}
STAT_AURA = {0: "str", 1: "agi", 2: "sta", 3: "int", 4: "spi"}
SCHOOL = {126: "spell", 2: "holy", 4: "fire", 8: "nature", 16: "frost", 32: "shadow", 64: "arcane"}
# Equip-spell auras (SpellEffect.EffectAura) -> our stat, read with their points
AURA = {85: "mp5", 52: "crit", 57: "scrit", 54: "hit", 99: "ap", 124: "rap", 135: "heal", 49: "dodge",
        51: "block", 65: "haste"}

# Enchant ID -> what its proc is worth on average, from its buff and a typical uptime: Crusader
# is +100 Strength for 15 sec about once a minute, Grand Crusader +120 for 20 sec.
PROCS = {1900: {"str": 25}, 7940: {"str": 35}, 7943: {"str": 55}, 7942: {"spell": 20, "heal": 20},
         7941: {"spell": 40, "heal": 40}, 803: {"dmg": 3}}
# Enchant ID -> the stat it is for: shown, unranked, to a spec that values that stat ("any": all).
SPECIALS = {8216: "spi", 8721: "def", 8217: "scrit", 8220: "def", 911: "any"}
# Wowhead's source codes -> where a recipe is learned, the first that applies.
SOURCES = ((6, "trainer"), (5, "vendor"), (2, "drop"), (4, "quest"))

NAMES = {"str": "Strength", "agi": "Agility", "sta": "Stamina", "int": "Intellect", "spi": "Spirit",
         "def": "Defense", "heal": "Healing", "spell": "Spell Damage", "holy": "Holy Damage",
         "fire": "Fire Damage", "nature": "Nature Damage", "frost": "Frost Damage",
         "shadow": "Shadow Damage", "arcane": "Arcane Damage", "mp5": "Mana every 5 sec",
         "crit": "% Crit", "scrit": "% Spell Crit", "hit": "% Hit", "ap": "Attack Power",
         "rap": "Ranged Attack Power", "dodge": "% Dodge", "block": "% Block", "haste": "% Haste",
         "armor": "Armor", "dmg": "Weapon Damage", "threat": "% Threat"}
ORDER = list(NAMES)


def add(stats, key, value):
    for k in key if isinstance(key, tuple) else (key,):
        stats[k] = stats.get(k, 0) + value


def equip_stats(stats, auras):
    for aura, points, misc in auras:
        if aura == 29:
            for k in (STAT_AURA.values() if misc == -1 else [STAT_AURA.get(misc)]):
                if k:
                    add(stats, k, points)
        elif aura == 13 and misc in SCHOOL:
            add(stats, SCHOOL[misc], points)
        elif aura == 22 and misc == 1:
            add(stats, "armor", points)
        elif aura == 30 and misc == 95:
            add(stats, "def", points)
        elif aura == 10 and points > 0:
            add(stats, "threat", points)
        elif aura in AURA and not (aura == 65 and "haste" in stats):
            add(stats, AURA[aura], points)


def text(stats):
    """"+5 Agility", "+55 Healing, +19 Spell Damage"."""
    parts = []
    for k in ORDER:
        if k in stats:
            v = stats[k]
            parts.append(f"+{v:g}{NAMES[k]}" if NAMES[k].startswith("%") else f"+{v:g} {NAMES[k]}")
    return ", ".join(parts)


def recipes():
    """Spell ID -> {skill, source} for every Enchanting recipe Wowhead lists."""
    if CACHE.exists():
        return {int(k): v for k, v in json.loads(CACHE.read_text(encoding="utf-8")).items()}
    page = fetch(f"{WOWHEAD}/spells/professions/enchanting")
    found = re.search(r"var listviewspells = (\[.*?\]);\s*\n", page, re.S)
    rows = json.loads(re.sub(r"([{,])([A-Za-z_]+):", r'\1"\2":', found.group(1)))
    known = {}
    for row in rows:
        codes = row.get("source") or []
        known[row["id"]] = {"skill": row["learnedat"],
                            "source": next((word for code, word in SOURCES if code in codes), None)}
    CACHE.write_text(json.dumps(known, indent=1, sort_keys=True), encoding="utf-8")
    return known


def main():
    build = wago.BUILD
    spells = [int(r["Spell"]) for r in wago.table("SkillLineAbility", build) if int(r["SkillLine"]) == ENCHANTING]
    effects = {}
    for r in wago.table("SpellEffect", build):
        effects.setdefault(int(r["SpellID"]), []).append(r)
    enchants = {int(r["ID"]): r for r in wago.table("SpellItemEnchantment", build)}
    gear = {int(r["SpellID"]): r for r in wago.table("SpellEquippedItems", build)}
    about = {int(r["ID"]): r.get("Description_lang", "") for r in wago.table("Spell", build)}
    known = recipes()
    rows = []
    for spell in sorted(set(spells)):
        made = next((int(e["EffectMiscValue_0"]) for e in effects.get(spell, []) if int(e["Effect"]) == ENCHANT_ITEM), None)
        enchant = enchants.get(made)
        taught = known.get(spell)
        if not (enchant and taught) or spell not in gear:
            continue
        stats = dict(PROCS.get(made, {}))
        for i in range(3):
            kind, arg, points = (int(enchant[f"{f}_{i}"]) for f in ("Effect", "EffectArg", "EffectPointsMin"))
            if kind == 2:
                add(stats, "dmg", points)
            elif kind == 4 and arg == 0:
                add(stats, "armor", points)
            elif kind == 5 and arg in ITEM_MOD:
                add(stats, ITEM_MOD[arg], points)
            elif kind == 3:
                equip_stats(stats, [(int(t["EffectAura"]), float(t["EffectBasePointsF"]), int(t["EffectMiscValue_0"]))
                                    for t in effects.get(arg, [])])
        special = SPECIALS.get(made)
        if not stats and not special:
            continue
        on = gear[spell]
        cls, inv, sub = int(on["EquippedItemClass"]), int(on["EquippedItemInvTypes"]), int(on["EquippedItemSubclass"])
        if cls == 2 and "two-handed" in about.get(spell, ""):
            sub = TWO_HANDED
        rows.append((spell, made, taught, cls, inv, sub, stats, special))
    lines = [
        "-------------------------------------------------------------------------------",
        "--  BiS/Data/Enchants.lua -- every enchant an enchanter can put on your gear: [recipe spell ID] =",
        "--  { enchant ID, skill (Enchanting it needs), source (trainer, vendor, drop or quest),",
        "--  what it goes on: class 2 weapon or 4 armor, inv (bit per inventory type), sub (bit per",
        "--  subclass), and what it gives: stats by key, text, or special (unranked, for that stat) }.",
        "--  Generated by Tools/build_enchants.py from the game's tables and Wowhead; do not edit.",
        "-------------------------------------------------------------------------------",
        "local ns = _G.NaowhForever",
        "",
        "ns.BiSEnchants = {",
    ]
    for spell, made, taught, cls, inv, sub, stats, special in rows:
        fields = [f"enchant = {made}", f"skill = {taught['skill']}"]
        if taught["source"]:
            fields.append(f'source = "{taught["source"]}"')
        fields += [f"class = {cls}", f"inv = {inv}", f"sub = {sub}"]
        if stats:
            fields.append("stats = { " + ", ".join(f"{k} = {stats[k]:g}" for k in ORDER if k in stats) + " }")
            fields.append(f"text = {lua_string(text(stats))}")
        if made in PROCS:
            fields.append("proc = true")
        if special:
            fields.append(f'special = "{special}"')
        lines.append(f"    [{spell}] = {{ " + ", ".join(fields) + " },")
    lines.append("}")
    OUT.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8", newline="")
    print(f"{len(rows)} enchants -> {OUT.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
