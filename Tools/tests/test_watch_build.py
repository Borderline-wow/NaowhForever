"""Tests for Tools/watch_build.py: what it finds between two builds, the report it writes and
the CHANGELOG line it adds. Offline: the game's tables are made up here. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_factions  # noqa: E402
import wago  # noqa: E402
import watch_build  # noqa: E402

TARGET = {"version": "new", "products": ["wow_classic_beta"], "created_at": "2026-10-01 22:54:04"}
CALM = {"total": 199, "pinned": 1, "gone": [], "renamed": [], "added": [], "fresh": []}


def reward(item_id, standing=6, **more):
    item = {"id": item_id, "standing": standing, "class": 4, "subclass": 2, "level": 60, "reqlevel": 55,
            "quality": 3, "price": 90114, "slot": 5, "name": f"Thing {item_id}"}
    item.update(more)
    return item


class Dungeons(unittest.TestCase):
    """watch_build.check on two made-up builds."""

    def setUp(self):
        self.saved = (watch_build.journal_encounters, watch_build.encounters, watch_build.instance_maps)
        watch_build.journal_encounters = lambda: {"100": ("Deadmines", "Rhahk'Zor"), "101": ("Deadmines", "Sneed"),
                                                  "900": ("Hyjal Summit", "Pinned")}
        enc = {
            "old": {"100": {"ID": "100", "Name_lang": "Rhahk'Zor", "MapID": "36"},
                    "101": {"ID": "101", "Name_lang": "Sneed", "MapID": "36"}},
            "new": {"100": {"ID": "100", "Name_lang": "Rhahk'Zor the Big", "MapID": "36"},
                    "102": {"ID": "102", "Name_lang": "Cookie", "MapID": "36"},
                    "500": {"ID": "500", "Name_lang": "Far Away", "MapID": "999"}},
        }
        maps = {
            "old": {"36": {"ID": "36", "MapName_lang": "Deadmines", "InstanceType": "1", "MaxPlayers": "5"}},
            "new": {"36": {"ID": "36", "MapName_lang": "Deadmines", "InstanceType": "1", "MaxPlayers": "5"},
                    "3000": {"ID": "3000", "MapName_lang": "New Raid", "InstanceType": "2", "MaxPlayers": "20"}},
        }
        watch_build.encounters = lambda build: enc[build]
        watch_build.instance_maps = lambda build: maps[build]

    def tearDown(self):
        watch_build.journal_encounters, watch_build.encounters, watch_build.instance_maps = self.saved

    def test_finds(self):
        found = watch_build.check("old", "new")
        self.assertEqual(found["gone"], [("101", "Deadmines", "Sneed")])
        self.assertEqual(found["renamed"], [("100", "Deadmines", "Rhahk'Zor", "Rhahk'Zor the Big")])
        self.assertEqual(found["pinned"], 1)
        self.assertEqual(found["added"], [("Cookie", "102", "Deadmines")], "only the Journal's dungeons' maps")
        self.assertEqual(found["fresh"], [("New Raid", "3000", "raid", "20")])

    def test_report_says_check_first(self):
        found = {"kept": 3, "new": [], "gone": [], "changed": [], "carried": []}
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=watch_build.check("old", "new"), found=found))
        self.assertIn("> **Check before merging:** 1 encounter the Journal counts kills by is gone", text)
        self.assertIn("**Gone:** encounter 101, Sneed (Deadmines)", text)
        self.assertIn("New raid: New Raid (map 3000), for 20 players.", text)


class Rewards(unittest.TestCase):
    """watch_build.rewards between two made-up builds, and how the report shows them."""

    def setUp(self):
        self.saved = (build_factions.game_items, wago.table, wago.CARRY_FROM, build_factions.FACTIONS)
        self.tmp = tempfile.TemporaryDirectory()
        config = Path(self.tmp.name) / "factions.json"
        config.write_text('{"factions": [{"key": "Darkspear", "id": 2798, "tab": "pvp"}]}', encoding="utf-8")
        build_factions.FACTIONS = config
        wago.CARRY_FROM = None
        wago.table = lambda name, build, hotfixes=True: [{"ID": "2798", "Name_lang": "Darkspear Raiders"}]
        builds = {
            "old": {2798: [reward(1), reward(2, level=33, reqlevel=28), reward(3)]},
            "new": {2798: [reward(1), reward(2, level=38, reqlevel=33), reward(4, standing=7), reward(5)]},
        }
        carried = {"new": {5}, "old": set()}
        # Carried items only when something is carried, as the real one.
        build_factions.game_items = lambda build, carry=None: ({}, builds[build],
                                                               carried[build] if carry else set())

    def tearDown(self):
        build_factions.game_items, wago.table, wago.CARRY_FROM, build_factions.FACTIONS = self.saved
        self.tmp.cleanup()

    def test_finds(self):
        found = watch_build.rewards("old", None, "new", "old")
        self.assertEqual(found["kept"], 2)
        self.assertEqual([i["id"] for _, i in found["new"]], [4, 5])
        self.assertEqual([i["id"] for _, i in found["gone"]], [3])
        faction, item, changes = found["changed"][0]
        self.assertEqual((faction["name"], item["id"]), ("Darkspear Raiders", 2))
        self.assertEqual(changes, [("item level", "33", "38"), ("requires level", "28", "33")])
        self.assertEqual([i["id"] for _, i in found["carried"]], [5])

    def test_report(self):
        found = watch_build.rewards("old", None, "new", "old")
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, waiting=True, carry="old",
                                            coverage=0.0))
        self.assertIn("> **Waiting:** the new build lacks 1 reward", text)
        self.assertIn("| **Faction rewards** | 2 kept &middot; 1 changed &middot; 2 new &middot; 1 gone |", text)
        self.assertIn("| [Thing 2](https://www.wowhead.com/forever/item=2) | "
                      "[Darkspear Raiders](https://www.wowhead.com/forever/faction=2798) | "
                      "item level: 33 &rarr; 38<br>requires level: 28 &rarr; 33 |", text)
        self.assertIn("| [Thing 4](https://www.wowhead.com/forever/item=4) | "
                      "[Darkspear Raiders](https://www.wowhead.com/forever/faction=2798) | Revered, 9g 1s 14c |", text)
        self.assertIn("<details><summary><b>1 reward come", text)
        self.assertIn("| [Thing 5](https://www.wowhead.com/forever/item=5) | "
                      "[Darkspear Raiders](https://www.wowhead.com/forever/faction=2798) | "
                      "[5](https://www.wowhead.com/forever/item=5) |", text)
        self.assertIn("all 199 encounter IDs", text)
        self.assertIn("| **Hotfixes** | 1 reward carried over from old (list below): wago.tools has 0% of the "
                      "items added by hotfix for this build so far |", text)

    def test_carry_source(self):
        caught, behind = wago.CAUGHT_UP, 0.0
        self.assertIsNone(watch_build.carry_source("70170", "70124", caught), "its own are in: none")
        self.assertEqual(watch_build.carry_source("70170", None, behind), "70170",
                         "the build in use has its own: they fill in")
        self.assertEqual(watch_build.carry_source("70170", "70124", behind), "70124",
                         "the build in use carries itself: from the build it carries from")

    def test_check_only(self):
        found = watch_build.rewards("old", None, "new", "old")
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, carry="old", coverage=0.0,
                                            changelog="- Dungeon Journal: a line", check_only=True))
        self.assertIn("> **Checked again:** ", text)
        self.assertNotIn("The line this adds to CHANGELOG.md", text, "a check adds no changelog line")
        self.assertNotIn("Ready to merge", text)
        self.assertIn("**1 reward the new build lacks**: The build in use, checked again: nothing moves.", text)

    def test_removed_by_blizzard(self):
        found = watch_build.rewards("old", None, "new", None)
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, carry=None, coverage=0.99,
                                            removals=True))
        self.assertIn("> **Ready to merge:** 2 faction rewards kept: 1 faction reward changed (item levels, "
                      "required levels), 2 new faction rewards, 1 faction reward removed. Details below.", text)
        self.assertIn("**1 reward removed by Blizzard**: wago.tools has this build's own hotfixes", text)
        self.assertIn("| **Hotfixes** | this build's own: wago.tools has 99% of the items added by hotfix |", text)

    def test_own_hotfixes_in(self):
        found = watch_build.rewards("old", None, "new", "old")
        line = watch_build.changelog_line("1.60.1.70170", found, hotfixes=True)
        self.assertEqual(line, "- Dungeon Journal: faction rewards follow WoW Forever build 1.60.1.70170's hotfixes: "
                               "1 faction reward changed (item levels, required levels), 2 new faction rewards, "
                               "1 faction reward removed.")
        text = "\n".join(watch_build.hotfixes_report("1.60.1.70170", "1.60.1.70124", found, 1.0, line))
        self.assertIn("## WoW Forever 1.60.1.70170: its own hotfixes are in", text)
        self.assertIn("wago.tools has recorded 1.60.1.70170's own hotfixes, so the rewards that came from "
                      "1.60.1.70124's now come from this build's", text)
        self.assertIn("removed by Blizzard", text)
        nothing = {"kept": 558, "new": [], "gone": [], "changed": [], "carried": []}
        self.assertIsNone(watch_build.changelog_line("1.60.1.70170", nothing, hotfixes=True),
                          "their hotfixes coming in changes nothing: no changelog line")

    def test_changelog_line(self):
        line = watch_build.changelog_line("1.60.1.70170", watch_build.rewards("old", None, "new", "old"))
        self.assertEqual(line, "- Dungeon Journal: its data is updated to WoW Forever build 1.60.1.70170: "
                               "1 faction reward changed (item levels, required levels), 2 new faction rewards, "
                               "1 faction reward removed.")

    def test_ready(self):
        found = {"kept": 558, "new": [], "gone": [], "changed": [], "carried": []}
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found))
        self.assertIn("> **Ready to merge:** all 558 faction rewards kept; nothing else changes for players.", text)
        self.assertIn("Nothing: every faction reward, its standing and its price stay the same.", text)
        self.assertNotIn("<details>", text)
        self.assertEqual(watch_build.changelog_line("1.60.1.70170", found),
                         "- Dungeon Journal: its data is updated to WoW Forever build 1.60.1.70170.",
                         "nothing else changes: the data is still updated")


def item_row(item_id, slot):
    return {"ID": str(item_id), "ClassID": "4", "SubclassID": "2", "InventoryType": str(slot)}


def sparse_row(item_id, slot, quality=3, level=40, reqlevel=35):
    return {"ID": str(item_id), "Display_lang": f"Gear {item_id}", "OverallQualityID": str(quality),
            "ItemLevel": str(level), "RequiredLevel": str(reqlevel), "InventoryType": str(slot)}


class NewGear(unittest.TestCase):
    """watch_build.new_gear between two made-up builds, and its section of the report."""

    def setUp(self):
        self.saved = (wago.table, watch_build.journal_items)
        tables = {
            # The build in use: 1 has everything; 2 only its Item row (its facts come later).
            ("Item", "old"): [item_row(1, 5), item_row(2, 7)],
            ("ItemSparse", "old"): [sparse_row(1, 5)],
            # What the build in use carries over: 10, by hotfix.
            ("Item", "older"): [item_row(10, 1)],
            ("ItemSparse", "older"): [sparse_row(10, 1)],
            # The new build: 10 in its own tables now; 2 with its facts; 20 to 26 new.
            ("Item", "new"): [item_row(i, s) for i, s in ((1, 5), (2, 7), (10, 1), (20, 5), (21, 12), (22, 5),
                                                          (23, 0), (24, 4), (25, 12), (26, 16))],
            ("ItemSparse", "new"): [sparse_row(1, 5), sparse_row(2, 7, quality=2, reqlevel=0), sparse_row(10, 1),
                                    sparse_row(20, 5), sparse_row(21, 12), sparse_row(22, 5, quality=0),
                                    sparse_row(23, 0, quality=4), sparse_row(24, 4), sparse_row(26, 16)],
        }
        wago.table = lambda name, build, hotfixes=True: tables[(name, build)]
        watch_build.journal_items = lambda: {21}

    def tearDown(self):
        wago.table, watch_build.journal_items = self.saved

    def test_finds(self):
        gear = watch_build.new_gear("old", "older", "new", "old", skip={26})
        self.assertEqual([i["id"] for i in gear], [2, 20, 25],
                         "not 1 (had), 10 (carried over), 21 (in the Journal), 22 (poor), 23 (not worn), "
                         "24 (a shirt), 26 (skipped: a new faction reward)")
        self.assertEqual(gear[1], {"id": 20, "name": "Gear 20", "slot": 5, "level": 40, "reqlevel": 35,
                                   "quality": 3})
        self.assertEqual(gear[2], {"id": 25, "name": "", "slot": 12, "level": None, "reqlevel": None,
                                   "quality": None}, "only an Item row: what the tables do not give is unknown")

    def test_carried_over_counts_as_present(self):
        self.assertIn(10, [i["id"] for i in watch_build.new_gear("old", None, "new", "old")],
                      "without the carry-over, the build in use lacks it")
        self.assertNotIn(10, [i["id"] for i in watch_build.new_gear("old", "older", "new", "old")])

    def test_report(self):
        gear = watch_build.new_gear("old", "older", "new", "old", skip={26})
        found = {"kept": 558, "new": [], "gone": [], "changed": [], "carried": []}
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, gear=gear))
        self.assertIn("> **Ready to merge:** all 558 faction rewards kept; nothing else changes for players.", text,
                      "information only: the verdict does not change")
        self.assertIn("| **New gear not in the Journal** | 3 |", text)
        self.assertLess(text.index("### What changes for players"), text.index("### New gear not in the Journal yet"))
        self.assertLess(text.index("### New gear not in the Journal yet"), text.index("### Dungeons and raids"))
        self.assertIn("**3 items** the build adds", text)
        self.assertIn("| [Gear 2](https://www.wowhead.com/forever/item=2) | Legs | 40 | none | Uncommon |", text)
        self.assertIn("| [Gear 20](https://www.wowhead.com/forever/item=20) | Chest | 40 | 35 | Rare |", text)
        self.assertIn("| [Item 25](https://www.wowhead.com/forever/item=25) | Trinket | unknown | unknown | "
                      "unknown |", text)
        self.assertNotIn("and 0 more", text)

    def test_none(self):
        found = {"kept": 558, "new": [], "gone": [], "changed": [], "carried": []}
        text = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, gear=[]))
        self.assertIn("| **New gear not in the Journal** | none |", text)
        self.assertIn("None: the build adds no uncommon or better item that can be equipped", text)
        checked = "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found, gear=[], check_only=True))
        self.assertIn("None: this is the build in use, checked again, so no item is new.", checked)
        self.assertNotIn("New gear", "\n".join(watch_build.report(TARGET, "old", dungeons=CALM, found=found)),
                         "not looked at: no section")

    def test_cap(self):
        gear = [{"id": i, "name": f"Gear {i}", "slot": 5, "level": 40, "reqlevel": 35, "quality": 3}
                for i in range(1, watch_build.GEAR_ROWS + 4)]
        lines = watch_build.gear_section(gear)
        self.assertIn(f"**{watch_build.GEAR_ROWS + 3} items** the build adds", "\n".join(lines))
        self.assertEqual(sum(1 for line in lines if line.startswith("| [Gear ")), watch_build.GEAR_ROWS)
        self.assertIn("...and 3 more.", lines)

    def test_journal_items(self):
        saved = watch_build.JOURNAL_ITEMS
        with tempfile.TemporaryDirectory() as tmp:
            items, faction = Path(tmp) / "Items.lua", Path(tmp) / "FactionItems.lua"
            items.write_bytes(b"ns.Journal.Items = {\r\n    [872] = { 2, 1, 23, 18, 3 },\r\n"
                              b"    [888] = { 4, 2, 27, 22, 3 },\r\n}\r\n")
            faction.write_bytes(b"local items = ns.Journal.Items\r\nitems[1164] = { 4, 0, 1, 0, 1 }\r\n")
            watch_build.JOURNAL_ITEMS = (items, faction)
            try:
                self.assertEqual(self.saved[1](), {872, 888, 1164})
            finally:
                watch_build.JOURNAL_ITEMS = saved


class Changelog(unittest.TestCase):
    """add_changelog puts the line in Unreleased's Changed, keeping the file's line endings."""

    def write(self, text):
        self.saved = watch_build.CHANGELOG
        self.tmp = tempfile.TemporaryDirectory()
        watch_build.CHANGELOG = Path(self.tmp.name) / "CHANGELOG.md"
        watch_build.CHANGELOG.write_bytes(text.encode())

    def tearDown(self):
        watch_build.CHANGELOG = self.saved
        self.tmp.cleanup()

    def test_after_the_last_change(self):
        self.write("# Changelog\r\n\r\n## Unreleased\r\n\r\n### Added\r\n- A.\r\n\r\n### Changed\r\n- B.\r\n"
                   "  more of B.\r\n\r\n### Fixed\r\n- C.\r\n\r\n## 0.5.17-beta\r\n\r\n### Changed\r\n- Old.\r\n")
        watch_build.add_changelog("- New.")
        self.assertEqual(watch_build.CHANGELOG.read_bytes().decode(),
                         "# Changelog\r\n\r\n## Unreleased\r\n\r\n### Added\r\n- A.\r\n\r\n### Changed\r\n- B.\r\n"
                         "  more of B.\r\n- New.\r\n\r\n### Fixed\r\n- C.\r\n\r\n## 0.5.17-beta\r\n\r\n### Changed\r\n"
                         "- Old.\r\n")

    def test_makes_changed_before_fixed(self):
        self.write("## Unreleased\n\n### Added\n- A.\n\n### Fixed\n- C.\n\n## 0.5.17-beta\n")
        watch_build.add_changelog("- New.")
        self.assertEqual(watch_build.CHANGELOG.read_bytes().decode(),
                         "## Unreleased\n\n### Added\n- A.\n\n### Changed\n- New.\n\n### Fixed\n- C.\n\n## 0.5.17-beta\n")


class Words(unittest.TestCase):
    def test_coins(self):
        self.assertEqual(watch_build.coins(90114), "9g 1s 14c")
        self.assertEqual(watch_build.coins(5000), "50s")
        self.assertEqual(watch_build.coins(0), "none")

    def test_nothing_newer(self):
        self.assertIn("Nothing newer", "\n".join(watch_build.report(TARGET, "new")))

    def test_unreadable(self):
        text = "\n".join(watch_build.report(TARGET, "old", unreadable=["Map"]))
        self.assertIn("> **Waiting:** wago.tools cannot read Map", text)


class Coverage(unittest.TestCase):
    """wago.hotfix_coverage: how much of the items earlier builds got by hotfix a build has."""

    def setUp(self):
        self.table = wago.table
        rows = {
            ("a", False): ["1", "2"], ("a", True): ["1", "2", "10", "11", "12", "13"],
            ("b", False): ["1", "2"], ("b", True): ["1", "2"],                      # none recorded yet
            ("c", False): ["1", "2"], ("c", True): ["1", "2", "10", "11", "12"],    # 13 removed
        }
        wago.table = lambda name, build, hotfixes=True: [{"ID": i} for i in rows[(build, hotfixes)]]

    def tearDown(self):
        wago.table = self.table

    def test_coverage(self):
        self.assertEqual(wago.hotfixed_items("a"), {"10", "11", "12", "13"})
        self.assertEqual(wago.hotfix_coverage("b", ["a"]), 0.0)
        self.assertEqual(wago.hotfix_coverage("c", ["a"]), 0.75)
        self.assertEqual(wago.hotfix_coverage("a", ["b"]), 1.0, "nothing to cover")
        self.assertLess(0.75, wago.CAUGHT_UP)


class Moving(unittest.TestCase):
    def test_set_build_moves_both_lines(self):
        saved = watch_build.WAGO_PY
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "wago.py"
            path.write_bytes(b'BUILD = "1.60.1.1"   # in use\r\nCARRY_FROM = None\r\n')
            watch_build.WAGO_PY = path
            try:
                watch_build.set_build("1.60.1.2", "1.60.1.1")
            finally:
                watch_build.WAGO_PY = saved
            self.assertEqual(path.read_bytes(), b'BUILD = "1.60.1.2"   # in use\r\nCARRY_FROM = "1.60.1.1"\r\n')
            watch_build.WAGO_PY = path
            try:
                watch_build.set_build("1.60.1.2", None)
            finally:
                watch_build.WAGO_PY = saved
            self.assertEqual(path.read_bytes(), b'BUILD = "1.60.1.2"   # in use\r\nCARRY_FROM = None\r\n',
                             "its own hotfixes in: nothing carried")


if __name__ == "__main__":
    unittest.main()
