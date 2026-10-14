"""Tests for the RestedXP step icons (Tools/media/make_rxp_icons.py): what is committed is what the script
draws, and each glyph is there in both styles. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402,F401

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "media"))
import make_rxp_icons as icons  # noqa: E402


class RxpIcons(unittest.TestCase):
    def test_every_committed_icon_is_what_the_script_draws(self):
        for style in icons.STYLES:
            for name, glyph in icons.GLYPHS.items():
                path = icons.OUT / style / (name + ".tga")
                self.assertTrue(path.exists(), path)
                self.assertEqual(path.read_bytes(), icons.encode(icons.render(glyph, style)), path)

    def test_no_icon_is_left_over_from_a_glyph_that_is_gone(self):
        for style in icons.STYLES:
            found = sorted(p.stem for p in (icons.OUT / style).glob("*.tga"))
            self.assertEqual(found, sorted(icons.GLYPHS), style)

    def test_every_glyph_is_inside_its_grid(self):
        for name, glyph in icons.GLYPHS.items():
            for shape in glyph["body"] + glyph["detail"]:
                points = [(shape[1], shape[2])] if shape[0] in ("circle", "dot") else shape[1]
                reach = shape[3] if shape[0] in ("circle", "dot") else 0
                for x, y in points:
                    self.assertGreaterEqual(min(x, y) - reach, 0, name)
                    self.assertLessEqual(max(x, y) + reach, icons.GRID, name)

    def test_the_two_styles_are_different_and_neither_is_blank(self):
        for name, glyph in icons.GLYPHS.items():
            line = icons.render(glyph, "line", 24)
            filled = icons.render(glyph, "filled", 24)
            self.assertGreater(sum(map(sum, line)), 10, name)
            self.assertGreater(sum(map(sum, filled)), 10, name)
            self.assertNotEqual(line, filled, name)

    def test_a_texture_is_a_32_bit_square_with_white_color(self):
        data = (icons.OUT / "line" / "accept.tga").read_bytes()
        self.assertEqual(len(data), 18 + icons.SIZE * icons.SIZE * 4)
        self.assertEqual(data[2], 2)
        self.assertEqual((data[12] | data[13] << 8, data[14] | data[15] << 8, data[16]), (icons.SIZE, icons.SIZE, 32))
        self.assertTrue(all(data[18 + i] == 255 for i in range(0, icons.SIZE * icons.SIZE * 4, 4)))


if __name__ == "__main__":
    unittest.main()
