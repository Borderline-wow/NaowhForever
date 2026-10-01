"""Generate original, tintable navigation glyphs. Run from any directory."""
import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "Media" / "Navigation"


def circle(x, y, radius, count=40):
    return [(x + radius * math.cos(i * 2 * math.pi / count),
             y + radius * math.sin(i * 2 * math.pi / count)) for i in range(count + 1)]


def rectangle(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)]


ICONS = {
    "map": [[(3, 5), (9, 3), (15, 6), (21, 4), (21, 19), (15, 21), (9, 18), (3, 20), (3, 5)],
            [(9, 3), (9, 18)], [(15, 6), (15, 21)]],
    "compass": [circle(12, 12, 9), [(16, 8), (14, 14), (8, 16), (10, 10), (16, 8)]],
    "trophy": [[(6, 3), (18, 3), (17, 9), (14, 13), (10, 13), (7, 9), (6, 3)],
               [(6, 5), (3, 5), (3, 8), (7, 10)], [(18, 5), (21, 5), (21, 8), (17, 10)],
               [(12, 13), (12, 18)], rectangle(7, 18, 10, 3)],
    "hammer": [[(13, 2.5), (21.5, 11), (18, 14.5), (9.5, 6), (13, 2.5)],
               [(14.8, 11.3), (5.1, 21.1), (2.9, 18.9), (12.7, 9.2)]],
    "shield": [[(12, 2), (21, 6), (19, 16), (12, 22), (5, 16), (3, 6), (12, 2)]],
    "spark": [[(12, 2), (15, 9), (22, 12), (15, 15), (12, 22), (9, 15), (2, 12), (9, 9), (12, 2)]],
    "aura": [[(12, 2), (18, 12), (12, 22), (6, 12), (12, 2)], [(4, 7), (2, 12), (4, 17)],
             [(20, 7), (22, 12), (20, 17)]],
    "bars": [rectangle(3, 13, 4, 8), rectangle(10, 4, 4, 17), rectangle(17, 9, 4, 12)],
    "grid": [rectangle(x, y, 4, 4) for y in (7, 14) for x in (3, 10, 17)],
    "infinity": [[(12 + 10 * math.cos(i * math.pi / 40),
                   12 + 5 * math.sin(i * math.pi / 20)) for i in range(81)]],
    "bell": [[(4, 17), (6, 14), (6, 9), (8, 5), (12, 3), (16, 5), (18, 9), (18, 14), (20, 17), (4, 17)],
             [(9, 21), (15, 21)]],
    "pen": [[(3, 21), (5, 14), (17, 2), (22, 7), (10, 19), (3, 21)], [(14, 5), (19, 10)]],
    "window": [rectangle(3, 4, 18, 16), [(3, 9), (21, 9)]],
    "person": [circle(12, 7, 4), [(3, 21), (4, 17), (8, 14), (16, 14), (20, 17), (21, 21), (3, 21)]],
    "notes": [rectangle(4, 3, 16, 18), [(7, 7), (17, 7)], [(7, 11), (17, 11)], [(7, 15), (15, 15)]],
    "settings": [circle(12, 12, 3), circle(12, 12, 7)] + [
        [(12 + r * math.cos(i * math.pi / 4), 12 + r * math.sin(i * math.pi / 4)) for r in (7, 10)]
        for i in range(8)],
    "search": [circle(10, 10, 6), [(15, 15), (21, 21)]],
    "checklist": [[(3, 7), (5, 9), (9, 5)], [(12, 7), (21, 7)],
                  [(3, 16), (5, 18), (9, 14)], [(12, 16), (21, 16)]],
}


def distance(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - a[0] - t * dx, y - a[1] - t * dy)


def main():
    OUT.mkdir(exist_ok=True)
    size = 64
    for name, paths in ICONS.items():
        segments = [(a, b) for path in paths for a, b in zip(path, path[1:]) if a != b]
        data = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8))
        for y in range(size):
            for x in range(size):
                d = min(distance((x + .5) * 24 / size, (size - y - .5) * 24 / size, a, b)
                        for a, b in segments)
                alpha = int(255 * max(0, min(1, (.85 - d) * size / 24 + .5)))
                data.extend((255, 255, 255, alpha))
        (OUT / (name + ".tga")).write_bytes(data)


if __name__ == "__main__":
    main()
