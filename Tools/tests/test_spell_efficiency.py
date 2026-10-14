"""Tests for Tools/build/spell_efficiency.py: which spells it keeps from the game's tables and
what it reads for them. Offline: wago.tools is never asked; the rows are made up here. From the
repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402,F401
import spell_efficiency as se  # noqa: E402

HOLY, PET, RUNES = "56", "188", "2853"


def effect(spell, index, kind, base=0, aura=0, coefficient=0, per_level=0, period=0, trigger=0, target="6", target1="0"):
    return {"SpellID": str(spell), "EffectIndex": str(index), "Effect": str(kind), "EffectAura": str(aura),
            "EffectBasePointsF": str(base), "EffectRealPointsPerLevel": str(per_level),
            "EffectBonusCoefficient": str(coefficient), "EffectAuraPeriod": str(period),
            "EffectTriggerSpell": str(trigger), "ImplicitTarget_0": target, "ImplicitTarget_1": target1}


def tables():
    return {
        "SkillLine": [{"ID": HOLY, "CategoryID": "7"}, {"ID": PET, "CategoryID": "7"},
                      {"ID": RUNES, "CategoryID": "7"}, {"ID": "164", "CategoryID": "11"}],
        "SkillLineAbility": (
            [{"SkillLine": HOLY, "Spell": str(s), "ClassMask": "16"} for s in list(range(1, 13)) + [13, 14]]
            + [{"SkillLine": PET, "Spell": "50", "ClassMask": "0"},
               {"SkillLine": RUNES, "Spell": "51", "ClassMask": "16"},
               {"SkillLine": RUNES, "Spell": "52", "ClassMask": "2"},
               {"SkillLine": "164", "Spell": "53", "ClassMask": "16"}]),
        "SpellPower": ([{"SpellID": str(s), "PowerType": "0", "ManaCost": "30", "PowerCostPct": "0"}
                        for s in list(range(1, 12)) + [13, 14, 50, 51, 52, 53]]
                       + [{"SpellID": "12", "PowerType": "1", "ManaCost": "10", "PowerCostPct": "0"}]),
        "SpellEffect": [
            effect(1, 0, 10, base=51, coefficient=0.429, per_level=0.9, target="21"),
            effect(2, 0, 6, base=9, aura=8, coefficient=0.2, period=3000, target="21"),
            effect(3, 0, 10, base=87, coefficient=0.286, per_level=1.8, target="21"),
            effect(3, 1, 6, base=13, aura=8, coefficient=0.071, period=3000, target="21"),
            effect(4, 0, 2, base=19, coefficient=0.407, per_level=0.5),
            effect(5, 0, 58, base=5),
            effect(5, 1, 2, base=20),
            effect(6, 0, 6, aura=23, period=1000, trigger=60, target="1"),
            effect(60, 0, 2, base=24, coefficient=0.286, per_level=0.3),
            effect(7, 0, 6, base=10, aura=53, coefficient=0.1, period=1000),
            effect(7, 1, 6, base=10, aura=8, period=1000, target="1"),
            effect(8, 0, 2, base=30),
            effect(8, 1, 179),
            effect(9, 0, 10, base=1, target="21"),
            effect(10, 0, 2, base=40),
            effect(10, 1, 10, base=20),
            effect(11, 0, 2, base=50),
            effect(11, 1, 77, base=100),
            effect(12, 0, 2, base=50),
            effect(50, 0, 2, base=50), effect(51, 0, 2, base=50), effect(52, 0, 2, base=50),
            effect(53, 0, 2, base=50),
            effect(13, 0, 2, base=20, coefficient=0.1, target="22", target1="15"),
            effect(14, 0, 6, aura=23, period=1000, trigger=61, target="1"),
            effect(14, 1, 6, base=82, aura=3, coefficient=0.022, period=1000, target="1"),
            effect(61, 0, 2, base=82, coefficient=0.022, target="18", target1="16"),
        ],
        "SpellLevels": [{"SpellID": "1", "SpellLevel": "1", "MaxLevel": "3"},
                        {"SpellID": "2", "SpellLevel": "8", "MaxLevel": "13"}],
        "SpellMisc": ([{"SpellID": str(s), "DurationIndex": "0", "SchoolMask": "2"} for s in (1, 9, 10, 11, 12)]
                      + [{"SpellID": "2", "DurationIndex": "8", "SchoolMask": "2"},
                         {"SpellID": "3", "DurationIndex": "86", "SchoolMask": "8"},
                         {"SpellID": "4", "DurationIndex": "0", "SchoolMask": "16"},
                         {"SpellID": "5", "DurationIndex": "0", "SchoolMask": "1"},
                         {"SpellID": "6", "DurationIndex": "27", "SchoolMask": "64"},
                         {"SpellID": "7", "DurationIndex": "28", "SchoolMask": "32"},
                         {"SpellID": "8", "DurationIndex": "0", "SchoolMask": "4"},
                         {"SpellID": "14", "DurationIndex": "27", "SchoolMask": "4"}]),
        "SpellDuration": [{"ID": "8", "Duration": "15000"}, {"ID": "86", "Duration": "21000"},
                          {"ID": "27", "Duration": "3000"}, {"ID": "28", "Duration": "5000"},
                          {"ID": "0", "Duration": "0"}],
    }


class Spells(unittest.TestCase):
    def setUp(self):
        self.found = se.entries(tables())

    def test_class_lines_only(self):
        found = se.class_spells(tables()["SkillLine"], tables()["SkillLineAbility"])
        self.assertIn(1, found)
        self.assertNotIn(50, found, "a pet line has no class")
        self.assertNotIn(51, found, "a line two classes share is not a class's own")
        self.assertNotIn(53, found, "a profession is not a class line")

    def test_mana_only(self):
        self.assertNotIn(12, self.found, "a spell that costs rage")

    def test_direct_heal(self):
        entry = self.found[1]
        self.assertEqual((entry["school"], entry["level"], entry["maxLevel"]), (2, 1, 3))
        part, = entry["parts"]
        self.assertEqual((part["heal"], part["direct"], part["directCoefficient"], part["ticks"]),
                         (se.HEAL, 51, 0.429, 0))

    def test_periodic_heal(self):
        part, = self.found[2]["parts"]
        self.assertEqual((part["direct"], part["tick"], part["tickCoefficient"], part["ticks"], part["seconds"]),
                         (0, 9, 0.2, 5, 15))

    def test_hybrid(self):
        part, = self.found[3]["parts"]
        self.assertEqual((part["direct"], part["tick"], part["ticks"], part["seconds"]), (87, 13, 7, 21))
        self.assertEqual(self.found[3]["school"], 4, "nature")

    def test_direct_damage(self):
        part, = self.found[4]["parts"]
        self.assertEqual((part["heal"], part["direct"], part["directPerLevel"]), (se.DAMAGE, 19, 0.5))
        self.assertEqual(self.found[4]["school"], 5, "frost")

    def test_periodic_trigger(self):
        part, = self.found[6]["parts"]
        self.assertEqual((part["heal"], part["tick"], part["tickCoefficient"], part["ticks"]), (se.DAMAGE, 24, 0.286, 3))

    def test_heal_on_the_caster_is_not_the_target(self):
        part, = self.found[7]["parts"]
        self.assertEqual((part["heal"], part["tick"], part["ticks"]), (se.DAMAGE, 10, 5))

    def test_both_on_one_target(self):
        heal = sorted(part["heal"] for part in self.found[10]["parts"])
        self.assertEqual(heal, [se.DAMAGE, se.HEAL])

    def test_area(self):
        self.assertEqual([self.found[s]["area"] for s in (1, 4, 13)], [0, 0, 1])
        self.assertEqual(self.found[14]["area"], 1, "a periodic trigger is area when its triggered spell is")

    def test_trigger_replaces_the_casters_own_periodic_damage(self):
        part = self.found[14]["parts"][0]
        self.assertEqual((part["tick"], part["ticks"]), (82, 3))

    def test_skipped(self):
        self.assertNotIn(5, self.found, "weapon damage")
        self.assertNotIn(8, self.found, "an area trigger")
        self.assertNotIn(9, self.found, "a base of 1 with no bonus is a scripted amount")
        self.assertNotIn(11, self.found, "a script effect")

    def test_lua(self):
        lines = se.lua(self.found, "1.60.1.1", {2: [(105000, 0, [0.04, 0.08]), (105001, 2, [0.1])]})
        self.assertTrue(lines[0].startswith("-- SpellEfficiencyData.lua: "))
        self.assertIn("Tools/build/spell_efficiency.py", lines[0])
        self.assertIn('    [1] = "2,1,3,0,1,51,0.9,0.429,0,0,0,0,0",', lines)
        both = next(line for line in lines if line.startswith("    [10] = "))
        self.assertRegex(both, r'^    \[10\] = "[-0-9.,]+",$', "one string of numbers, nothing else")
        self.assertEqual(both.count(","), len(se.FIELDS) + 2 * len(se.PART_FIELDS))
        self.assertEqual(se.lua_number(0.28600001335), "0.286")
        self.assertEqual(se.lua_number(-0.0), "0")
        self.assertIn('    [2] = "105000,0,0.04,0.08;105001,2,0.1",', lines)


def mod(spell, index, aura, misc, base, mask):
    row = effect(spell, index, 6, base=base, aura=aura)
    row["EffectMiscValue_0"] = str(misc)
    for i in range(4):
        row[f"EffectSpellClassMask_{i}"] = str(mask if i == 0 else 0)
    return row


def options(spell, family, mask):
    return {"SpellID": str(spell), "SpellClassSet": str(family), "SpellClassMask_0": str(mask),
            "SpellClassMask_1": "0", "SpellClassMask_2": "0", "SpellClassMask_3": "0"}


class Talents(unittest.TestCase):
    def setUp(self):
        t = tables()
        t["SpellMisc"] = [dict(row, Attributes_0="0") for row in t["SpellMisc"]]
        t["SpellMisc"] += [{"SpellID": "900", "DurationIndex": "0", "SchoolMask": "1", "Attributes_0": "464"},
                           {"SpellID": "910", "DurationIndex": "0", "SchoolMask": "1", "Attributes_0": "33882112"},
                           {"SpellID": "920", "DurationIndex": "0", "SchoolMask": "1", "Attributes_0": "464"}]
        t["SpellEffect"] = t["SpellEffect"] + [
            mod(900, 0, 108, 0, 4, 3),      # direct healing and damage on masks 1 and 2
            mod(900, 1, 108, 22, 9, 4),     # over time, on mask 4
            mod(910, 0, 108, 0, 30, 3),     # an on-use talent: not a passive
            mod(920, 0, 108, 14, -10, 3),   # a cost mod: left to the game
        ]
        t["SpellClassOptions"] = [options(900, 6, 0), options(910, 6, 0), options(920, 6, 0), options(1, 6, 1),
                                  options(2, 6, 2), options(3, 7, 1), options(4, 6, 4)]
        t["SpellName"] = [{"ID": str(s), "Name_lang": f"Spell {s}"} for s in (1, 2, 3, 4)]
        t["TalentTab"] = [{"ID": "1", "ClassMask": "16"}]
        t["Talent"] = [{"TabID": "1", "SpellRank_0": str(s), "SpellRank_1": str(s + 1)} for s in (900, 910, 920)]
        t["TraitDefinition"] = [{"ID": "1", "SpellID": "900"}]
        t["TraitDefinitionEffectPoints"] = [{"TraitDefinitionID": "1", "EffectIndex": "0", "CurveID": "7"}]
        t["CurvePoint"] = [{"CurveID": "7", "Pos_0": str(rank), "Pos_1": str(value)}
                           for rank, value in ((1, 4), (2, 8), (3, 12))]
        self.tables = t
        self.found = se.entries(t)
        self.nodes = {900: 105000, 910: 105001, 920: 105002}

    def test_percent_by_rank_for_the_masked_spells(self):
        mods = se.talent_mods(self.tables, self.found, self.nodes)
        self.assertEqual([(n, o, [round(v, 4) for v in values]) for n, o, values in mods[1]],
                         [(105000, 0, [0.04, 0.08, 0.12])])
        self.assertIn(2, mods)
        self.assertNotIn(3, mods, "another class's spell family")

    def test_an_effect_with_no_curve_grows_like_the_talents_other(self):
        mods = se.talent_mods(self.tables, self.found, self.nodes)
        self.assertEqual([(n, o, [round(v, 4) for v in values]) for n, o, values in mods[4]],
                         [(105000, 1, [0.09, 0.18, 0.27])])

    def test_a_talent_with_no_curve_uses_its_base(self):
        self.tables["TraitDefinitionEffectPoints"] = []
        mods = se.talent_mods(self.tables, self.found, self.nodes)
        self.assertEqual(mods[4], [(105000, 1, [0.09])])

    def test_a_direct_percent_counts_on_the_ticks_of_a_spell_it_names(self):
        mods = se.talent_mods(self.tables, self.found, self.nodes)
        self.assertEqual([(n, o) for n, o, _ in mods[2]], [(105000, 0), (105000, 1)])
        self.assertEqual([(n, o) for n, o, _ in mods[1]], [(105000, 0)], "no ticks")

    def test_active_and_cost_talents_are_left_out(self):
        mods = se.talent_mods(self.tables, self.found, self.nodes)
        self.assertEqual({node for found in mods.values() for node, _, _ in found}, {105000})

    def test_a_talent_not_in_the_tree_file_has_no_node(self):
        self.assertEqual(se.talent_mods(self.tables, self.found, {}), {})

    def test_nodes_from_the_tree_file(self):
        text = "\n".join(["        talents = {",
                          "            [105926] = { 20504, 2, 5, 2, 4 },",
                          "            [105941] = { 12294, 1, 7, 1, 2, 105945 },",
                          "        },",
                          "        skip = { [772] = true },"])
        self.assertEqual(se.talent_nodes(text), {20504: 105926, 12294: 105941})


class Triggers(unittest.TestCase):
    """Spells whose amount is in the spell their description names."""

    def setUp(self):
        t = tables()
        cast = [20, 21, 22, 23, 24, 25, 26]
        t["SkillLineAbility"] += [{"SkillLine": HOLY, "Spell": str(s), "ClassMask": "16"} for s in cast]
        t["SpellPower"] += [{"SpellID": str(s), "PowerType": "0", "ManaCost": "50", "PowerCostPct": "0"} for s in cast]
        t["SpellDuration"] += [{"ID": "9", "Duration": "8000"}]
        t["SpellMisc"] += [{"SpellID": str(s), "DurationIndex": "9", "SchoolMask": "16"} for s in (20, 21, 24, 26)]
        t["SpellLevels"] += [{"SpellID": "20", "SpellLevel": "20", "MaxLevel": "25"}]
        t["SpellEffect"] = t["SpellEffect"] + [
            effect(20, 0, 3, coefficient=0.03, target="87", target1="16"),                  # Blizzard
            effect(20, 1, 179, target="87", target1="16"),
            effect(20, 2, 6, aura=226, period=1000, target="1"),
            effect(120, 0, 2, base=24, per_level=0.1, coefficient=0.042, target="87", target1="16"),
            effect(21, 0, 2, base=60, coefficient=0.157, target="16"),                     # Flamestrike
            effect(21, 1, 179, target="87", target1="16"),
            effect(21, 2, 6, aura=226, period=2000, target="1"),
            effect(121, 0, 2, base=11, coefficient=0.032, target="87", target1="16"),
            effect(22, 0, 3, coefficient=1, target="25"),                                  # Holy Shock
            effect(122, 0, 2, base=182, coefficient=0.429, target="6"),
            effect(123, 0, 10, base=156, coefficient=0.429, target="21"),
            effect(23, 0, 3, target="25"),                                                 # Penance
            effect(124, 0, 2, base=81, coefficient=0.285, target="6"),
            effect(24, 0, 179, target="87", target1="16"),                                 # a count of five
            effect(24, 1, 6, aura=226, period=2000, target="1"),
            effect(25, 0, 3, target="25"),                                                 # Healing Rain
            effect(25, 1, 179, target="132", target1="31"),
            effect(25, 2, 6, aura=226, period=1000, target="1"),
            effect(125, 0, 10, base=15, coefficient=0.063, target="87", target1="31"),
            effect(26, 0, 3, target="25"),                                                 # Fire Nova
            effect(126, 0, 2, base=52, coefficient=0.1, target="22", target1="15"),
        ]
        t["Spell"] = [
            {"ID": "20", "Description_lang": "Ice shards doing ${$120m1*$d*$<frostdamage>} Frost damage over $d."},
            {"ID": "21", "Description_lang": "Burns for $s1 Fire damage and ${$121m1*4} Fire damage over $d."},
            {"ID": "22", "Description_lang": "Causing $122s1 Holy damage to an enemy, or $123s1 healing to an ally."},
            {"ID": "23", "Description_lang": "Causing $124s1 Holy damage to an enemy, instantly and every $2t2 sec for $2d."},
            {"ID": "24", "Description_lang": "Burns for ${5*$124m1} Fire damage over $d."},
            {"ID": "25", "Description_lang": "Heals for ${$<healpower>*$125m1/100} every second."},
            {"ID": "26", "Description_lang": "Inflicts $126s1 fire damage to enemies within $126a1 yd."},
        ]
        self.found = se.entries(t)

    def test_area_trigger_is_one_targets_ticks_of_the_named_spell(self):
        entry = self.found[20]
        part, = entry["parts"]
        self.assertEqual((entry["area"], entry["school"], entry["level"], entry["maxLevel"]), (1, 5, 20, 25))
        self.assertEqual((part["heal"], part["direct"], part["tick"], part["tickPerLevel"], part["tickCoefficient"],
                          part["ticks"], part["seconds"]), (se.DAMAGE, 0, 24, 0.1, 0.042, 8, 8))

    def test_the_spells_own_damage_stays_direct_and_the_named_one_ticks(self):
        part, = self.found[21]["parts"]
        self.assertEqual((part["direct"], part["directCoefficient"], part["tick"], part["ticks"]), (60, 0.157, 11, 4))

    def test_dummy_spell_gets_a_part_for_each_named_spell(self):
        entry = self.found[22]
        self.assertEqual(entry["area"], 0)
        self.assertEqual(sorted((p["heal"], p["direct"]) for p in entry["parts"]), [(se.DAMAGE, 182), (se.HEAL, 156)])

    def test_over_time_percent_of_power_and_unnamed_are_left_out(self):
        self.assertNotIn(23, self.found, "a volley over time: one hit would undercount it")
        self.assertNotIn(25, self.found, "an amount that is a percent of healing power")

    def test_dummy_spell_area_follows_the_named_spells_targets(self):
        self.assertEqual(self.found[26]["area"], 1)

    def test_a_count_that_disagrees_with_the_ticks_is_left_out(self):
        self.assertNotIn(24, self.found, "five times over eight seconds of two-second ticks")


if __name__ == "__main__":
    unittest.main()
