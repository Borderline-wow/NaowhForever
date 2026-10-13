"""Build Mana Efficiency's data from the game's own spell tables (Tools/sources/wago.py).

Every class spell rank that costs mana and heals or deals damage, with what the game rolls
for it, so QoL's Mana Efficiency can work out a rank's healing or damage per mana and per
second at hover time, without reading tooltip text:

- which class spells: SkillLineAbility's spells on the class skill lines (SkillLine category
  7) that one class owns (every class mask on the line is that class's), which leaves out the
  pet, mount, rune and engraving lines;
- the cost: a SpellPower row of power type 0 (mana) with a mana cost or a cost in percent;
- the amounts, from SpellEffect: a direct heal (10) or damage (2 school damage, 9 health
  leech), a periodic heal (aura 8) or damage (auras 3 and 53) on an aura effect, and a
  periodic trigger (aura 23) whose spell, named in the effect, heals or deals damage (Arcane
  Missiles). Each one's EffectBasePointsF (the middle of the roll: the client rolls it plus or
  minus half its Variance, so the average is the base), EffectRealPointsPerLevel and
  EffectBonusCoefficient;
- the ticks: the aura's duration (SpellMisc.DurationIndex -> SpellDuration) over its
  EffectAuraPeriod;
- whether it is an area spell: its first amount effect reaches everyone in an area or cone, or
  puts an aura on everyone near (a flag on the entry, so the tooltip says per target);
- the levels the per-level growth counts between (SpellLevels.SpellLevel and MaxLevel), and
  the school spell damage is read for (SpellMisc.SchoolMask).

What a spell does is what it does to its target: the amount effects that land where its first
one does (the same implicit targets). A heal on the caster from a damage spell (Drain Life,
Death Coil) is left out; a spell that both heals and deals damage to that one target gets both.

A spell is left out, with no line, when part of its amount is somewhere the tables do not say:
weapon damage (Aimed Shot, Multi-Shot), a triggered spell or a proc (seals, Judgement), or an
area trigger the server runs (Blizzard, Rain of Fire, Consecration, Flamestrike's burn).
Better no line than a wrong number.

Writes NaowhForever_QoL/Interface/SpellEfficiencyData.lua.

Usage: python Tools/build/spell_efficiency.py [--build 1.60.1.70205]
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
import wago  # noqa: E402
from journal import header, write  # noqa: E402

ROOT = paths.ROOT
OUT = ROOT / "NaowhForever_QoL" / "Interface" / "SpellEfficiencyData.lua"

CLASS_CATEGORY = "7"             # SkillLine.CategoryID of the class skill lines
MANA = "0"                       # SpellPower.PowerType of mana
HEAL, DAMAGE = 1, 0              # a part's first field
DIRECT = {10: HEAL, 2: DAMAGE, 9: DAMAGE}     # SpellEffect.Effect: heal, school damage, health leech
AURA_EFFECTS = {6, 27, 35, 65}   # apply aura, persistent area aura, party and raid area auras
PERIODIC = {8: HEAL, 3: DAMAGE, 53: DAMAGE}   # EffectAura: periodic heal, damage, leech
PERIODIC_TRIGGER = 23            # EffectAura: periodic trigger spell
# Effects whose amount the tables do not hold: dummy and script effects (the server's own code),
# weapon damage (no school, percent, plain, normalized), trigger spell (plain, with value),
# create area trigger.
ELSEWHERE_EFFECTS = {3, 77, 17, 31, 58, 121, 64, 142, 179}
# Auras whose amount the tables do not hold: proc trigger spell (plain, with value), periodic dummy.
ELSEWHERE_AURAS = {42, 231, 226}
# Implicit targets that reach every unit in an area or cone (Frost Nova, Prayer of Healing, Cone of
# Cold), and the effects that put an aura on everyone near (Tranquility). A chain jumps one target
# to the next with less each time, so it counts as its first target and is not area.
AREA_TARGETS = {15, 16, 24, 30, 31, 33, 34, 37, 54, 56, 61}
AREA_EFFECTS = {27, 35, 65}
PLACEHOLDER = 1                  # a direct base of 1 with no bonus stands in for a scripted amount (Swiftmend)
MS = 1000
DECIMALS = 4
SEPARATOR = ","                  # between an entry's numbers in its string
COLUMNS = {
    "SkillLine": ("ID", "CategoryID"),
    "SkillLineAbility": ("SkillLine", "Spell", "ClassMask"),
    "SpellPower": ("SpellID", "PowerType", "ManaCost", "PowerCostPct"),
    "SpellEffect": ("SpellID", "EffectIndex", "Effect", "EffectAura", "EffectBasePointsF",
                    "EffectRealPointsPerLevel", "EffectBonusCoefficient", "EffectAuraPeriod",
                    "EffectTriggerSpell", "ImplicitTarget_0", "ImplicitTarget_1"),
    "SpellLevels": ("SpellID", "SpellLevel", "MaxLevel"),
    "SpellMisc": ("SpellID", "DurationIndex", "SchoolMask"),
    "SpellDuration": ("ID", "Duration"),
}
# An entry's fields, in order, then one or two parts of PART_FIELDS each (a damage part and a
# heal part when the spell does both to its target), written as one string (lua_entry).
# SpellEfficiency.lua reads them by place.
FIELDS = ("school", "level", "maxLevel", "area")
PART_FIELDS = ("heal", "direct", "directPerLevel", "directCoefficient", "tick", "tickPerLevel",
               "tickCoefficient", "ticks", "seconds")


def number(text):
    return float(text or 0)


def class_spells(skill_lines, abilities):
    """The spells on the class skill lines a single class owns."""
    lines = {row["ID"] for row in skill_lines if row["CategoryID"] == CLASS_CATEGORY}
    owners, spells = {}, {}
    for row in abilities:
        line = row["SkillLine"]
        if line not in lines:
            continue
        if row["ClassMask"] not in ("0", ""):
            owners.setdefault(line, set()).add(int(row["ClassMask"]))
        spells.setdefault(line, set()).add(int(row["Spell"]))
    out = set()
    for line, masks in owners.items():
        if len(masks) == 1 and next(iter(masks)) > 0:
            out |= spells[line]
    return out


def mana_spells(power):
    return {int(row["SpellID"]) for row in power
            if row["PowerType"] == MANA and (number(row["ManaCost"]) > 0 or number(row["PowerCostPct"]) > 0)}


def by_spell(rows):
    out = {}
    for row in rows:
        out.setdefault(int(row["SpellID"]), []).append(row)
    for effects in out.values():
        effects.sort(key=lambda r: int(r.get("EffectIndex") or 0))
    return out


def elsewhere(effect):
    """Whether part of the effect's amount is in something the tables do not hold."""
    return (int(effect["Effect"] or 0) in ELSEWHERE_EFFECTS
            or int(effect["EffectAura"] or 0) in ELSEWHERE_AURAS)


def target(effect):
    return effect.get("ImplicitTarget_0") or "0", effect.get("ImplicitTarget_1") or "0"


def is_area(effect, effects):
    """Whether the effect lands on everyone in an area; a periodic trigger is area when the spell
    it triggers is."""
    if int(effect["EffectAura"] or 0) == PERIODIC_TRIGGER and int(effect["Effect"] or 0) in AURA_EFFECTS:
        triggered = effects.get(int(effect["EffectTriggerSpell"] or 0), [])
        return any(is_area(row, effects) for row in triggered if direct_amount(row))
    return (int(effect["Effect"] or 0) in AREA_EFFECTS
            or any(int(effect.get(key) or 0) in AREA_TARGETS for key in ("ImplicitTarget_0", "ImplicitTarget_1")))


def direct_amount(effect):
    """(kind, base, per level, coefficient) of a direct heal or damage effect, else None."""
    kind = DIRECT.get(int(effect["Effect"] or 0))
    base, coefficient = number(effect["EffectBasePointsF"]), number(effect["EffectBonusCoefficient"])
    if kind is None or (base <= PLACEHOLDER and coefficient <= 0):
        return None
    return kind, base, number(effect["EffectRealPointsPerLevel"]), coefficient


def periodic_amount(effect, effects):
    """(kind, base, per level, coefficient, period in ms) of one tick of a periodic effect, else
    None. A periodic trigger's tick is its triggered spell's direct amount; None when that spell
    has an amount the tables do not hold."""
    if int(effect["Effect"] or 0) not in AURA_EFFECTS:
        return None
    aura, period = int(effect["EffectAura"] or 0), int(number(effect["EffectAuraPeriod"]))
    if period <= 0:
        return None
    if aura == PERIODIC_TRIGGER:
        triggered = effects.get(int(effect["EffectTriggerSpell"] or 0), [])
        if any(elsewhere(e) for e in triggered):
            return None
        for row in triggered:
            amount = direct_amount(row)
            if amount:
                return amount + (period,)
        return None
    kind = PERIODIC.get(aura)
    base, coefficient = number(effect["EffectBasePointsF"]), number(effect["EffectBonusCoefficient"])
    if kind is None or (base <= 0 and coefficient <= 0):
        return None
    return kind, base, number(effect["EffectRealPointsPerLevel"]), coefficient, period


def new_part(kind):
    part = dict.fromkeys(PART_FIELDS, 0.0)
    part["heal"], part["period"] = kind, 0
    return part


def add_effect(parts, effect, effects, duration):
    """Adds the effect's amount to the part of its kind. False when it has one that cannot be
    counted (a periodic part with no whole tick, or a second period)."""
    amount = direct_amount(effect)
    if amount:
        part = parts.setdefault(amount[0], new_part(amount[0]))
        part["direct"] += amount[1]
        part["directPerLevel"] += amount[2]
        part["directCoefficient"] += amount[3]
        return True
    amount = periodic_amount(effect, effects)
    if not amount:
        return True
    period = amount[4]
    part = parts.setdefault(amount[0], new_part(amount[0]))
    if duration < period or (part["period"] and part["period"] != period):
        return False
    part["period"] = period
    part["tick"] += amount[1]
    part["tickPerLevel"] += amount[2]
    part["tickCoefficient"] += amount[3]
    part["ticks"] = duration // period
    part["seconds"] = part["ticks"] * period / MS
    return True


def has_amount(effect, effects):
    return bool(direct_amount(effect) or periodic_amount(effect, effects))


def entry(spell, effects, levels, misc, durations):
    """The spell's entry ({FIELDS..., "parts": [...]}), or None when it neither heals nor deals
    damage, or part of its amount is somewhere the tables do not hold."""
    own = effects.get(spell, [])
    if any(elsewhere(effect) for effect in own):
        return None
    first = next((effect for effect in own if has_amount(effect, effects)), None)
    if not first:
        return None
    info = misc.get(spell, {})
    duration = durations.get(info.get("DurationIndex"), 0)
    parts = {}
    triggers = any(int(e["EffectAura"] or 0) == PERIODIC_TRIGGER and periodic_amount(e, effects) for e in own)
    for effect in own:
        if target(effect) != target(first):
            continue
        # Hellfire's own damage to the caster is not what its triggered spell does to each enemy.
        if triggers and int(effect["EffectAura"] or 0) in PERIODIC:
            continue
        if not add_effect(parts, effect, effects, duration):
            return None
    found = [part for part in parts.values() if part["direct"] or part["directCoefficient"] or part["ticks"]]
    if not found:
        return None
    for part in found:
        del part["period"]
    level = levels.get(spell, {})
    mask = int(info.get("SchoolMask") or 0)
    return {
        "school": (mask & -mask).bit_length() or 1,
        "level": int(level.get("SpellLevel") or 0),
        "maxLevel": int(level.get("MaxLevel") or 0),
        "area": int(is_area(first, effects)),
        "parts": found,
    }


def entries(tables):
    """Every class spell rank that costs mana and heals or deals damage: {spell: entry}."""
    spells = class_spells(tables["SkillLine"], tables["SkillLineAbility"]) & mana_spells(tables["SpellPower"])
    effects = by_spell(tables["SpellEffect"])
    levels = {int(r["SpellID"]): r for r in tables["SpellLevels"]}
    misc = {int(r["SpellID"]): r for r in tables["SpellMisc"]}
    durations = {r["ID"]: max(int(number(r["Duration"])), 0) for r in tables["SpellDuration"]}
    out = {}
    for spell in sorted(spells):
        found = entry(spell, effects, levels, misc, durations)
        if found:
            out[spell] = found
    return out


def lua_number(value):
    text = f"{value:.{DECIMALS}f}".rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


def lua_entry(found):
    """The entry as one quoted string of its numbers joined by SEPARATOR: a string per spell
    holds far less memory at login than a table per spell, and SpellEfficiency.lua splits a
    spell's string into its table the first time that spell's tooltip needs it."""
    values = [found[field] for field in FIELDS]
    for part in found["parts"]:
        values += [part[field] for field in PART_FIELDS]
    return '"' + SEPARATOR.join(lua_number(value) for value in values) + '"'


def lua(found, build):
    lines = header(OUT.name, "each mana spell rank's healing or damage by spell ID, generated by "
                             f"Tools/build/spell_efficiency.py from build {build}")
    lines.append("ns.SpellEfficiencyData = {")
    for spell in sorted(found):
        lines.append(f"    [{spell}] = {lua_entry(found[spell])},")
    lines.append("}")
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", default=wago.BUILD)
    build = parser.parse_args().build
    tables = {name: wago.table(name, build) for name in COLUMNS}
    for name, columns in COLUMNS.items():
        rows = tables[name]
        if not rows or any(column not in rows[0] for column in columns):
            sys.exit(f"wago.tools cannot read {name} for {build} yet")
    found = entries(tables)
    write(OUT, lua(found, build))
    heals = sum(1 for e in found.values() if any(p["heal"] == HEAL for p in e["parts"]))
    both = sum(1 for e in found.values() if len(e["parts"]) > 1)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(found)} spells ({heals} heal, {both} heal and deal damage), "
          f"{OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
