"""Build the Training Planner's weapon skills: which each class can learn, from which weapon master.

The weapon skills (One-Handed Swords, Bows, Staves ...) are taught by the weapon masters of the
capital cities, not the class trainers. Each master's Wowhead Forever NPC page lists the skills
he teaches, each with the classes that may learn it (reqclass, a class mask: bit n-1 for class
n). Wowhead gives no level or price for them: the level a class may learn one at (Polearms,
Dual Wield) is the game's own SkillRaceClassInfo MinLevel (Tools/sources/wago.py), else 1.
Dual Wield is taught by the class trainer, not a master, for the classes that have a level for it.

Where a master stands is Shared/Game/Towns.lua; the planner finds him there by name.

Wowhead's answers are kept in Tools/data/training_weapons_cache.json; delete an entry to ask again.

Writes NaowhForever_Training/Data/TrainingWeapons.lua.

Usage: python Tools/build/training_weapons.py [--build 1.60.1.70170]
"""
import argparse
import json
import re
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
import wago  # noqa: E402
from wowhead import WOWHEAD, fetch, listview  # noqa: E402
from journal import ROOT, write  # noqa: E402
from training import CLASSES  # noqa: E402

TOWNS = ROOT / "Shared" / "Game" / "Towns.lua"
OUT = ROOT / "NaowhForever_Training" / "Data" / "TrainingWeapons.lua"
CACHE = paths.DATA / "training_weapons_cache.json"
MASTER_TITLE = "Weapon Master"
DUAL_WIELD = 674


def master_names():
    """The weapon masters Towns.lua stands, by name."""
    text = TOWNS.read_text(encoding="utf-8")
    return sorted(set(re.findall(r'"profession", "([^"]+)", "' + MASTER_TITLE + '"', text)))


def master_skills(name, cache):
    """The skills one master teaches, as [{id, name, reqclass}], from his Wowhead page."""
    if name not in cache:
        search = fetch(f"{WOWHEAD}/search?q={urllib.parse.quote(name)}")
        npc = re.search(r"npc=(\d+)", search).group(1)
        page = fetch(f"{WOWHEAD}/npc={npc}")
        if not re.search(rf"<title>{re.escape(name)} - NPC", page):
            raise SystemExit(f"{name}: npc={npc} is not him")
        cache[name] = {"npc": int(npc), "skills": [
            {"id": r["id"], "name": r["name"], "reqclass": r["reqclass"]}
            for r in listview(page, "teaches-other")]}
    return cache[name]["skills"]


def min_levels(build_id):
    """Spell ID -> class ID -> the level the game lets that class learn it at, where it has one."""
    skill_of = {}
    for row in wago.table("SkillLineAbility", build_id):
        skill_of.setdefault(int(row["Spell"]), row["SkillLine"])
    by_skill = {}
    for row in wago.table("SkillRaceClassInfo", build_id):
        by_skill.setdefault(row["SkillID"], []).append((int(row["ClassMask"]), int(row["MinLevel"])))
    out = {}
    for spell, skill in skill_of.items():
        for class_id in CLASSES:
            levels = [lvl for mask, lvl in by_skill.get(skill, []) if mask >> (class_id - 1) & 1]
            if levels:
                out.setdefault(spell, {})[class_id] = max(levels)
    return out


def build(build_id):
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    masters = {}
    for name in master_names():
        for skill in master_skills(name, cache):
            masters.setdefault(skill["id"], {"name": skill["name"], "mask": skill["reqclass"], "by": []})
            masters[skill["id"]]["by"].append(name)
    CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    levels = min_levels(build_id)

    out = [f"-- TrainingWeapons.lua: the weapon skills each class learns, built from game build {build_id}.",
           "local ns = _G.NaowhForever",
           "",
           "ns.TrainingWeapons = {"]
    counts = []
    for class_id, slug in CLASSES.items():
        rows = []
        for spell, skill in masters.items():
            if skill["mask"] >> (class_id - 1) & 1:
                rows.append((levels.get(spell, {}).get(class_id) or 1, spell, skill["by"]))
        if levels.get(DUAL_WIELD, {}).get(class_id):
            rows.append((levels[DUAL_WIELD][class_id], DUAL_WIELD, []))
        rows.sort(key=lambda r: (r[0], r[1]))
        counts.append(f"{slug} {len(rows)}")
        out.append(f"    [{class_id}] = {{")
        for level, spell, by in rows:
            taught = ", masters = { " + ", ".join(f'"{n}"' for n in sorted(by)) + " }" if by else ""
            out.append(f"        {{ {level}, {spell}, 0{taught} }},")
        out.append("    },")
    out.append("}")
    write(OUT, out)
    print(f"Wrote {OUT.relative_to(ROOT)}: " + ", ".join(counts))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", default=wago.BUILD, help="the Forever build to read (default: wago.BUILD)")
    build(parser.parse_args().build)


if __name__ == "__main__":
    main()
