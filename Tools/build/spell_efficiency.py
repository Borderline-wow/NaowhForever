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
weapon damage (Aimed Shot, Multi-Shot), a triggered spell or a proc (seals, Judgement). Better no
line than a wrong number.

The one exception is a spell whose own description names the spell that holds its amount, which
is how the client's own tooltip finds it (Spell.Description_lang: "$1279976s1 Frost damage"):
- an area trigger (effect 179, with a periodic dummy aura 226 for the period) that the server
  runs: Blizzard, Rain of Fire, Flamestrike's burn, Consecration, Hurricane, Volley. The named
  spell's damage lands once per period for the aura's duration, on every enemy in the area, so it
  is one target's share; a description that multiplies it by a count (the "*8" of Consecration)
  must agree with the ticks, and a description that makes the amount a percent of power
  (Healing Rain's "$<healpower>*$m1/100") is left out. Consecration's second amount is the
  extra the first enemies take, which one target always gets;
- a dummy spell whose description names a spell for each amount, once and not over time (Holy
  Shock: damage to an enemy, healing to an ally; Fire Nova), one direct part for each. It is an
  area spell when the named spell's targets are.

The player's talents, from the same tables: a class talent whose aura adds a percent to damage
and healing (spell mod 0) or to damage and healing over time (22) of the spells in its class mask
(the aura's own, or else the talent spell's) and is passive (Arcane Power and Presence of Mind,
which are spells to cast, are not), for the spells above (Healing Light, Spiritual
Healing, Improved Renew, Fire Power), written as the talent's node in Forever's tree
(NaowhForever_Training/Data/TrainingBuilds.lua), the mod and its percent for one rank. Mana cost
mods are left to the game: the cost read at hover time already has them. Two talents that spare
mana are not in the tables (the server's own code decides them) and are written from what the
game's description says: Illumination (a crit heal gives back half the base cost, at the chance the
tables give the rank) and Elemental Focus (a 10% chance after a fire, frost or nature spell that
the next damage spell is free).

A talent with several ranks does not have a spell per rank in Forever: the value of each of its
effects at each rank is a curve (TraitDefinitionEffectPoints -> CurvePoint), 4, 8, 12 for Healing
Light. A mod is written with its value at every rank. An effect with no curve of its own grows
like the talent's effect that has one (Piercing Ice's periodic percent), scaled to its own base.
A talent whose direct percent names a spell with ticks, and no periodic percent of it does,
counts on the ticks too (Gift of Nature on Tranquility, which has no direct part).

Writes NaowhForever_QoL/Interface/SpellEfficiencyData.lua.

Usage: python Tools/build/spell_efficiency.py [--build 1.60.1.70205]
"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
import wago  # noqa: E402
from journal import header, write  # noqa: E402

ROOT = paths.ROOT
BUILDS = ROOT / "NaowhForever_Training" / "Data" / "TrainingBuilds.lua"
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
AREA_TRIGGER, PERIODIC_DUMMY, DUMMY = 179, 226, 3
REFERENCE = re.compile(r"\$(\d{3,})[sm]\d")
POWER_PERCENT = re.compile(r"\$<\w+>\*\$\d*[sm]\d/100")
OVER_TIME = re.compile(r"every|over |next |\$\d*[td]|\$\d*t\d")
COUNT_BEFORE = re.compile(r"\{(\d+)\*\$\d+m\d\}")
COUNT_AFTER = re.compile(r"\$\d+m\d\*(\d+)\}")
PLACEHOLDER = 1                  # a direct base of 1 with no bonus stands in for a scripted amount (Swiftmend)
MS = 1000
DECIMALS = 4
# SpellEffect.EffectMiscValue_0 of a percent spell mod aura (108) that changes damage and healing,
# or damage and healing over time, and the op each is written with.
MOD_AURA_PERCENT = 108
PASSIVE = 0x40                   # SpellMisc.Attributes_0: a talent that is not a spell to cast (Arcane Power is)
OP_DIRECT, OP_PERIODIC, OP_CRIT_REFUND, OP_FREE_CAST = 0, 1, 2, 3
MOD_OPS = {0: OP_DIRECT, 22: OP_PERIODIC}
# Talents the tables do not decide (see the top), by their first rank. Illumination: gives back
# 50% of the cost of a crit heal, for the heals named, with the chance its first effect has at
# each rank. Elemental Focus: a 10% chance to make the next damage spell free, for fire, frost and
# nature damage.
ILLUMINATION = 20210
ILLUMINATION_REFUND = 0.5
ILLUMINATION_SPELLS = {"Flash of Light", "Holy Light", "Light's Vigil", "Holy Shock"}
ELEMENTAL_FOCUS = 16164
ELEMENTAL_FOCUS_CHANCE = 0.1
FOCUS_SCHOOLS = {3, 4, 5}        # an entry's school: fire, nature, frost
SEPARATOR = ","                  # between an entry's numbers in its string
COLUMNS = {
    "SkillLine": ("ID", "CategoryID"),
    "SkillLineAbility": ("SkillLine", "Spell", "ClassMask"),
    "SpellPower": ("SpellID", "PowerType", "ManaCost", "PowerCostPct"),
    "SpellEffect": ("SpellID", "EffectIndex", "Effect", "EffectAura", "EffectBasePointsF",
                    "EffectRealPointsPerLevel", "EffectBonusCoefficient", "EffectAuraPeriod",
                    "EffectTriggerSpell", "ImplicitTarget_0", "ImplicitTarget_1", "EffectMiscValue_0",
                    "EffectSpellClassMask_0", "EffectSpellClassMask_1", "EffectSpellClassMask_2",
                    "EffectSpellClassMask_3"),
    "SpellLevels": ("SpellID", "SpellLevel", "MaxLevel"),
    "SpellMisc": ("SpellID", "DurationIndex", "SchoolMask", "Attributes_0"),
    "SpellDuration": ("ID", "Duration"),
    "SpellClassOptions": ("SpellID", "SpellClassSet", "SpellClassMask_0", "SpellClassMask_1",
                          "SpellClassMask_2", "SpellClassMask_3"),
    "SpellName": ("ID", "Name_lang"),
    "Talent": ("TabID", "SpellRank_0", "SpellRank_1"),
    "TalentTab": ("ID", "ClassMask"),
    "TraitDefinition": ("ID", "SpellID"),
    "TraitDefinitionEffectPoints": ("TraitDefinitionID", "EffectIndex", "CurveID"),
    "CurvePoint": ("CurveID", "Pos_0", "Pos_1"),
    "Spell": ("ID", "Description_lang"),
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


def referenced(text, spell):
    """The spells a description names, in order, apart from the spell itself."""
    out = []
    for found in REFERENCE.findall(text):
        if int(found) != spell and int(found) not in out:
            out.append(int(found))
    return out


def unsupported(effect):
    """Whether the effect is more than a trigger spell's description can account for."""
    kind = int(effect["Effect"] or 0)
    if kind in (0, DUMMY, AREA_TRIGGER) or kind in DIRECT:
        return False
    return not (kind in AURA_EFFECTS and int(effect["EffectAura"] or 0) == PERIODIC_DUMMY)


def amount_rows(spell, effects):
    return [row for row in effects.get(spell, []) if direct_amount(row)]


def trigger_entry(spell, effects, levels, misc, durations, text):
    """The entry for a spell whose amount is in the spell its description names, else None (see the
    top). An area trigger gives its named spell's amount every period, plus any damage of its own;
    a dummy spell gives each named spell's amount once."""
    own = effects.get(spell, [])
    refs = referenced(text, spell)
    if not refs or POWER_PERCENT.search(text) or any(unsupported(effect) for effect in own):
        return None
    info = misc.get(spell, {})
    parts, area = {}, False
    triggered = any(int(e["Effect"] or 0) == AREA_TRIGGER for e in own)
    if triggered:
        period = next((int(number(e["EffectAuraPeriod"])) for e in own if int(e["EffectAura"] or 0) == PERIODIC_DUMMY), 0)
        duration = durations.get(info.get("DurationIndex"), 0)
        if len(refs) != 1 or period <= 0 or duration < period:
            return None
        ticks = duration // period
        counted = COUNT_BEFORE.search(text) or COUNT_AFTER.search(text)
        if (counted and int(counted.group(1)) != ticks) or ("*$d" in text and period != MS):
            return None
        rows = amount_rows(refs[0], effects)
        if not rows or any(elsewhere(row) for row in effects.get(refs[0], [])):
            return None
        for row in own:
            amount = direct_amount(row)
            if amount:
                part = parts.setdefault(amount[0], new_part(amount[0]))
                part["direct"] += amount[1]
                part["directPerLevel"] += amount[2]
                part["directCoefficient"] += amount[3]
        kinds = {direct_amount(row)[0] for row in rows}
        if len(kinds) != 1 or (parts and set(parts) != kinds):
            return None
        part = parts.setdefault(kinds.pop(), new_part(direct_amount(rows[0])[0]))
        for row in rows:
            amount = direct_amount(row)
            part["tick"] += amount[1]
            part["tickPerLevel"] += amount[2]
            part["tickCoefficient"] += amount[3]
        part["ticks"], part["seconds"] = ticks, ticks * period / MS
    else:
        if OVER_TIME.search(text) or amount_rows(spell, effects) or any(int(e["Effect"] or 0) not in (0, DUMMY) for e in own):
            return None
        for ref in refs:
            rows = amount_rows(ref, effects)
            if len(rows) != 1 or any(elsewhere(row) for row in effects.get(ref, [])):
                return None
            amount = direct_amount(rows[0])
            if amount[0] in parts:
                return None
            part = parts.setdefault(amount[0], new_part(amount[0]))
            part["direct"], part["directPerLevel"], part["directCoefficient"] = amount[1:]
            area = area or is_area(rows[0], effects)
    for part in parts.values():
        del part["period"]
    level = levels.get(spell, {})
    mask = int(info.get("SchoolMask") or 0)
    return {
        "school": (mask & -mask).bit_length() or 1,
        "level": int(level.get("SpellLevel") or 0),
        "maxLevel": int(level.get("MaxLevel") or 0),
        "area": int(triggered or area),
        "parts": list(parts.values()),
    }


def entries(tables):
    """Every class spell rank that costs mana and heals or deals damage: {spell: entry}."""
    spells = class_spells(tables["SkillLine"], tables["SkillLineAbility"]) & mana_spells(tables["SpellPower"])
    effects = by_spell(tables["SpellEffect"])
    levels = {int(r["SpellID"]): r for r in tables["SpellLevels"]}
    misc = {int(r["SpellID"]): r for r in tables["SpellMisc"]}
    durations = {r["ID"]: max(int(number(r["Duration"])), 0) for r in tables["SpellDuration"]}
    texts = {int(r["ID"]): r["Description_lang"] for r in tables.get("Spell", [])}
    out = {}
    for spell in sorted(spells):
        found = entry(spell, effects, levels, misc, durations)
        if not found and spell in texts:
            found = trigger_entry(spell, effects, levels, misc, durations, texts[spell])
        if found:
            out[spell] = found
    return out


def mask_words(row, prefix):
    return [int(row.get(f"{prefix}{i}") or 0) & 0xFFFFFFFF for i in range(4)]


def talent_nodes(text):
    """First-rank spell -> node, from the tree file, whose talent lines are [node] = { spell, ranks, row, column ... }."""
    return {int(spell): int(node)
            for node, spell in re.findall(r"^\s*\[(\d{6,})\] = \{ (\d+), \d+, \d+, \d+", text, re.M)}


def class_talent_spells(tables):
    """The first rank's spell of every class talent."""
    classes = {row["ID"] for row in tables["TalentTab"] if int(row["ClassMask"] or 0)}
    return [int(row["SpellRank_0"]) for row in tables["Talent"]
            if row["TabID"] in classes and row["SpellRank_0"] not in ("", "0")]


def rank_values(tables):
    """{(talent spell, effect index): [the effect's value at rank 1, 2, ...]} for the talents whose
    effects grow with the rank."""
    definitions = {r["ID"]: int(r["SpellID"]) for r in tables["TraitDefinition"]}
    points = {}
    for row in tables["CurvePoint"]:
        points.setdefault(row["CurveID"], {})[int(float(row["Pos_0"]))] = number(row["Pos_1"])
    out = {}
    for row in tables["TraitDefinitionEffectPoints"]:
        curve = points.get(row["CurveID"])
        if curve and row["TraitDefinitionID"] in definitions:
            out[(definitions[row["TraitDefinitionID"]], int(row["EffectIndex"]))] = [curve[r] for r in sorted(curve)]
    return out


def talent_mods(tables, found, nodes):
    """{spell: [(node, op, [value at rank 1, 2, ...]), ...]} for the entries in found."""
    ranks = rank_values(tables)
    effects = by_spell(tables["SpellEffect"])
    options = {int(r["SpellID"]): r for r in tables["SpellClassOptions"]}
    names = {int(r["ID"]): r["Name_lang"] for r in tables["SpellName"]}
    passive = {int(r["SpellID"]) for r in tables["SpellMisc"] if int(r["Attributes_0"] or 0) & PASSIVE}
    mods = {}

    def family(spell):
        return options.get(spell, {}).get("SpellClassSet")

    for talent in class_talent_spells(tables):
        node = nodes.get(talent)
        if node is None or talent not in options or talent not in passive:
            continue
        for effect in effects.get(talent, []):
            op = MOD_OPS.get(int(effect["EffectMiscValue_0"] or 0))
            base = number(effect["EffectBasePointsF"])
            curve = ranks.get((talent, int(effect["EffectIndex"])))
            if curve is None:
                other = next((values for (spell, _), values in sorted(ranks.items()) if spell == talent), None)
                curve = [v * base / other[0] for v in other] if other and other[0] else [base]
            amounts = [v / 100 for v in curve]
            if int(effect["EffectAura"] or 0) != MOD_AURA_PERCENT or op is None or amounts[0] <= 0:
                continue
            mask = mask_words(effect, "EffectSpellClassMask_")
            if not any(mask):
                mask = mask_words(options[talent], "SpellClassMask_")
            for spell in found:
                if (family(spell) == family(talent)
                        and any(a & b for a, b in zip(mask_words(options[spell], "SpellClassMask_"), mask))):
                    mods.setdefault(spell, []).append((node, op, amounts))
    for spell, found_mods in mods.items():
        if any(part["ticks"] for part in found[spell]["parts"]):
            over_time = {node for node, op, _ in found_mods if op == OP_PERIODIC}
            found_mods += [(node, OP_PERIODIC, amounts) for node, op, amounts in list(found_mods)
                           if op == OP_DIRECT and node not in over_time]
    for spell, entry_ in found.items():
        heals = any(part["heal"] == HEAL for part in entry_["parts"])
        if ILLUMINATION in nodes and heals and names.get(spell) in ILLUMINATION_SPELLS \
                and family(spell) == family(ILLUMINATION):
            chances = ranks.get((ILLUMINATION, 0))
            if chances:
                mods.setdefault(spell, []).append(
                    (nodes[ILLUMINATION], OP_CRIT_REFUND, [c / 100 * ILLUMINATION_REFUND for c in chances]))
        if ELEMENTAL_FOCUS in nodes and not heals and entry_["school"] in FOCUS_SCHOOLS \
                and family(spell) == family(ELEMENTAL_FOCUS):
            mods.setdefault(spell, []).append((nodes[ELEMENTAL_FOCUS], OP_FREE_CAST, [ELEMENTAL_FOCUS_CHANCE]))
    return mods


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


def lua(found, build, mods):
    lines = header(OUT.name, "each mana spell rank's healing or damage by spell ID, generated by "
                             f"Tools/build/spell_efficiency.py from build {build}")
    lines.append("ns.SpellEfficiencyData = {")
    for spell in sorted(found):
        lines.append(f"    [{spell}] = {lua_entry(found[spell])},")
    lines.append("}")
    lines.append("")
    lines.append("ns.SpellEfficiencyTalents = {")
    for spell in sorted(mods):
        text = ";".join(SEPARATOR.join([str(node), str(op)] + [lua_number(v) for v in values])
                        for node, op, values in sorted(mods[spell]))
        lines.append(f'    [{spell}] = "{text}",')
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
    mods = talent_mods(tables, found, talent_nodes(BUILDS.read_text(encoding="utf-8")))
    write(OUT, lua(found, build, mods))
    heals = sum(1 for e in found.values() if any(p["heal"] == HEAL for p in e["parts"]))
    both = sum(1 for e in found.values() if len(e["parts"]) > 1)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(found)} spells ({heals} heal, {both} heal and deal damage), "
          f"{len(mods)} with talents, {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
