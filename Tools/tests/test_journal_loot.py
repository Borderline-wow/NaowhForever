"""Tests for Tools/build_journal.py's choice of a boss's loot. Wowhead counts Classic Era's and
Forever's kills together, so an item new in Forever is kept whatever its chance looks like,
and the rest above MIN_CHANCE. Offline: the drop rows are made up here, in the shape
npc_drops caches. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_journal  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
