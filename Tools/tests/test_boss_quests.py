"""Tests for Tools/build/boss_quests.py's choice of which bosses a dungeon's quests can need:
every wing of the same instance (Scarlet Monastery's four, the two Blackrock Spires), else
the dungeon's own. Offline. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402,F401
import boss_quests  # noqa: E402

BOSSES = {
    "Scarlet Monastery - Library": [(3974, "Houndmaster Loksey")],
    "Scarlet Monastery - Armory": [(3975, "Herod")],
    "Scarlet Monastery - Cathedral": [(3976, "Scarlet Commander Mograine")],
    "Excavation Site: Wetlands": [(260808, "Highland Horror")],
    "Blackmaw Hold": [],
}
MAPS = {
    "Scarlet Monastery - Library": 189,
    "Scarlet Monastery - Armory": 189,
    "Scarlet Monastery - Cathedral": 189,
    "Excavation Site: Wetlands": 2998,
}


class KinBosses(unittest.TestCase):
    def test_wings_of_one_instance_share_their_bosses(self):
        npcs = {npc for npc, _ in boss_quests.kin_bosses("Scarlet Monastery - Cathedral", BOSSES, MAPS)}
        self.assertEqual(npcs, {3974, 3975, 3976})

    def test_a_dungeon_on_its_own_keeps_its_own(self):
        npcs = [npc for npc, _ in boss_quests.kin_bosses("Excavation Site: Wetlands", BOSSES, MAPS)]
        self.assertEqual(npcs, [260808])

    def test_no_map_falls_back_to_its_own(self):
        self.assertEqual(boss_quests.kin_bosses("Blackmaw Hold", BOSSES, MAPS), [])

    def test_the_real_data_links_herod_to_into_the_scarlet_monastery(self):
        bosses = boss_quests.dungeon_bosses()
        maps = boss_quests.dungeon_maps()
        npcs = {npc for npc, _ in boss_quests.kin_bosses("Scarlet Monastery - Cathedral", bosses, maps)}
        self.assertTrue({3974, 3975} <= npcs)


if __name__ == "__main__":
    unittest.main()
