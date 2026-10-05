"""Tests for Tools/build_journal.py's choice of a boss's loot. Wowhead counts Classic Era's and
Forever's kills together, so an item new in Forever is kept whatever its chance looks like,
and the rest above MIN_CHANCE. Offline: the drop rows are made up here, in the shape
npc_drops caches. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_journal  # noqa: E402
import wago  # noqa: E402


def drop(item_id, count, kills, new=False, quality=3):
    return {"id": item_id, "count": count, "kills": kills, "new": new, "slot": 13, "class": 2,
            "subclass": 1, "level": 26, "reqlevel": 21, "quality": quality}


# Oggleflint's numbers, as Wowhead had them: 4227 Normal kills, Classic Era and Forever's.
SWORD = drop(1, 400, 4227)
SCEPTER = drop(272996, 6, 4227, new=True)   # new in Forever: 0.14% of the shared kills
RARE = drop(2, 6, 4227)                     # an old item that rare: left out
STRAY = drop(252455, 1, 5001, new=True)     # a new item seen once: a stray world drop


class Drops(unittest.TestCase):
    def test_a_new_item_is_kept_whatever_its_chance(self):
        kept = build_journal.choose([SCEPTER, RARE])
        self.assertEqual([i["id"] for i in kept], [272996])
        self.assertIsNone(kept[0]["chance"], "its chance is counted against Classic Era's kills too")

    def test_a_new_item_seen_once_is_not_enough(self):
        self.assertEqual(build_journal.choose([STRAY]), [])
        once = build_journal.choose([drop(273025, 1, 1, new=True)])
        self.assertEqual([i["id"] for i in once], [273025], "a new boss's single kill: its one drop")

    def test_a_boss_new_in_forever_has_real_chances(self):
        kept = build_journal.choose([drop(271201, 10, 30, new=True)], npc_new=True)
        self.assertAlmostEqual(kept[0]["chance"], 100 * 10 / 30, msg="Witherfang: all its kills are Forever's")

    def test_too_few_kills_for_a_chance(self):
        kept = build_journal.choose([drop(6641, 1, 1)], npc_new=True)
        self.assertEqual([i["id"] for i in kept], [6641])
        self.assertIsNone(kept[0]["chance"], "one kill makes every drop 100%")

    def test_chances_and_order(self):
        kept = build_journal.choose([SCEPTER, SWORD])
        self.assertEqual([i["id"] for i in kept], [1, 272996], "most likely first, unknown last")
        self.assertAlmostEqual(kept[0]["chance"], 100 * 400 / 4227)

    def test_no_kills_counted_yet(self):
        kept = build_journal.choose([drop(5, 0, 0)])
        self.assertEqual(kept[0]["chance"], None, "a new boss's drop: kept, its chance unknown")


class WowsrcMerge(unittest.TestCase):
    """merge_wowsrc: wowsrc's Forever list over Wowhead's loot."""

    def setUp(self):
        self.facts = build_journal.item_facts
        build_journal.item_facts = lambda item_id: None   # offline: neither cache nor tables have it

    def tearDown(self):
        build_journal.item_facts = self.facts

    def test_an_item_without_facts_keeps_the_old_loot(self):
        loot = [dict(drop(6341, 1468, 15624), chance=9.0)]
        listed = {"items": [{"id": 273643, "chance": None, "new": True}], "complete": True}
        kept = build_journal.merge_wowsrc(loot, listed)
        self.assertEqual([i["id"] for i in kept], [6341], "not dropped over an item it could not read")

    def test_a_whole_list_moves_old_items_off(self):
        build_journal.item_facts = self.facts
        loot = [dict(drop(6341, 1468, 15624), chance=9.0), dict(drop(3191, 5241, 15624), chance=33.0)]
        listed = {"items": [{"id": 3191, "chance": 35.7, "new": False}], "complete": True}
        kept = build_journal.merge_wowsrc(loot, listed)
        self.assertEqual([i["id"] for i in kept], [3191])
        self.assertEqual(kept[0]["chance"], 35.7, "wowsrc's chance wins")


class InGame(unittest.TestCase):
    """in_game: only items the game's own tables name are listed. Forever 1.60.1's Item table has
    a row for every Classic item, but most of Classic's dungeon loot above level 30 has no
    ItemSparse row: the server never sends it, so the Journal showed "Item 10800"."""

    def setUp(self):
        self.tables = build_journal.game_items
        self.wago_table = wago.table
        build_journal.game_items = None
        rows = {"Item": [{"ID": "10800", "ClassID": "4", "SubclassID": "2"},
                         {"ID": "3191", "ClassID": "2", "SubclassID": "1"},
                         {"ID": "273025", "ClassID": "4", "SubclassID": "3"}],
                "ItemSparse": [{"ID": "3191"}, {"ID": "273025"}]}
        wago.table = lambda name, build=None, hotfixes=True: rows[name]

    def tearDown(self):
        build_journal.game_items = self.tables
        wago.table = self.wago_table

    def test_the_game_names_only_items_with_a_sparse_row(self):
        self.assertEqual(set(build_journal.game_tables()), {"3191", "273025"})

    def test_an_item_the_game_cannot_name_is_left_out(self):
        held = set()
        loot = [dict(drop(10800, 1468, 3847), chance=38.0), dict(drop(3191, 5241, 15624), chance=33.0),
                dict(drop(273025, 2, 4227, new=True), chance=None)]
        kept, gone = build_journal.in_game(loot, held)
        self.assertEqual([i["id"] for i in kept], [3191, 273025])
        self.assertEqual(gone, 1)
        self.assertEqual(held, {10800}, "Darkwater Bracers: an Item row, no ItemSparse row")

    def test_nothing_left_out_when_the_game_has_it_all(self):
        held = set()
        self.assertEqual(build_journal.in_game([drop(3191, 1, 1)], held), ([drop(3191, 1, 1)], 0))
        self.assertEqual(held, set())

    def test_a_boss_whose_loot_all_went_says_so_in_its_data(self):
        boss = {"npc": 8580, "name": "Atal'alarion", "rare": False, "encounters": [3582],
                "loot": [dict(drop(10800, 1468, 3847), chance=38.0)]}
        build_journal.leave_out(boss, set())
        self.assertEqual((boss["loot"], boss["notInGame"]), ([], 1))
        self.assertIn("notInGame = 1", build_journal.lua_boss(boss))
        self.assertNotIn("loot =", build_journal.lua_boss(boss))

    def test_a_boss_with_nothing_left_out_has_no_flag(self):
        boss = {"npc": 1, "name": "Boss", "rare": False, "encounters": [], "loot": [dict(drop(3191, 1, 1), chance=None)]}
        build_journal.leave_out(boss, set())
        self.assertNotIn("notInGame", build_journal.lua_boss(boss))


class DailyWatchLog(unittest.TestCase):
    """The loot job's filter on the build's output (.github/workflows/daily-watch.yml) hides the
    per-dungeon counts and keeps the build's report lines, which start with two spaces."""

    def setUp(self):
        workflow = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "daily-watch.yml"
        found = re.search(r'grep -Ev "([^"]+)" "\$RUNNER_TEMP/build.txt"', workflow.read_text(encoding="utf-8"))
        self.assertIsNotNone(found, "the loot job filters build.txt with grep -Ev")
        self.hidden = re.compile(found.group(1))

    def test_counts_are_hidden(self):
        self.assertTrue(self.hidden.search("   12  Ragefire Chasm"))
        self.assertTrue(self.hidden.search("  133  Dire Maul"))

    def test_report_lines_are_kept(self):
        for line in ("  not in the game's item tables, left out: 47 items (Sunken Temple): 10624",
                     "  no NPC found: Lord Roccor",
                     "  wowsrc item not mapped: Dreadmist Mask (Darkmaster Gandling, Scholomance)",
                     "383 items, 35 dungeons"):
            self.assertFalse(self.hidden.search(line), line)


if __name__ == "__main__":
    unittest.main()
