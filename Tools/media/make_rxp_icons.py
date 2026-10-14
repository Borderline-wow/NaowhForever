"""Generate the step icons Naowh draws in place of RestedXP's, in two styles. Run from any directory.

Every glyph is one geometry on a 24-unit grid (y down, as the navigation glyphs): its body is outlined in the
line style and solid in the filled style, and its detail is stroked in the line style and cut out of the body
in the filled one. They are white over alpha, so the escape that draws them tints them with the theme.
"""
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402

OUT = paths.ROOT / "Core" / "Integrations" / "RestedXP" / "Media" / "Icons"
GRID = 24
SIZE = 64
LINE_WIDTH = 2.0
BOLD_WIDTH = 3.2
CUT_WIDTH = 1.9
STYLES = ("line", "filled")


def circle(cx, cy, r):
    return ("circle", cx, cy, r)


def poly(points):
    return ("poly", points)


def line(points):
    return ("line", points)


def dot(cx, cy, r):
    return ("dot", cx, cy, r)


def arc(cx, cy, r, start, end, count=18):
    return [(cx + r * math.cos(math.radians(start + (end - start) * i / count)),
             cy - r * math.sin(math.radians(start + (end - start) * i / count))) for i in range(count + 1)]


def rounded(x, y, w, h, r, tail=()):
    points = []
    corners = ((x + w - r, y + r, 0), (x + r, y + r, 90), (x + r, y + h - r, 180), (x + w - r, y + h - r, 270))
    for i, (cx, cy, start) in enumerate(corners):
        if i == 3:
            points += list(tail)
        points += arc(cx, cy, r, start, start + 90, 5)
    return points


def teardrop(cx, cy, r, tip):
    reach = math.acos(r / (tip - cy))
    start, end = math.pi / 2 + reach, math.pi / 2 - reach + 2 * math.pi
    ring = [(cx + r * math.cos(start + (end - start) * i / 28), cy + r * math.sin(start + (end - start) * i / 28))
            for i in range(29)]
    return [(cx, tip)] + ring


def heart():
    points = []
    for i in range(48):
        t = math.tau * i / 48
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((12 + x * 0.6, 11.2 - y * 0.6))
    return points


def question():
    hook = arc(12, 9.2, 3.4, 170, -40, 14)
    return line(hook + [(12.2, 13.2), (12, 14.4)])


def badge(shape, mark):
    return {"body": [shape], "detail": mark}


BAR = line([(12, 6.4), (12, 13.2)])
BANG = [BAR, dot(12, 16.9, 1.3)]
ASK = [question(), dot(12, 17.6, 1.3)]
DIAMOND = poly([(12, 1.8), (22.2, 12), (12, 22.2), (1.8, 12)])
DISC = circle(12, 12, 9.6)

GLYPHS = {
    "accept": badge(DISC, BANG),
    "daily": badge(DIAMOND, BANG),
    "turnin": badge(DISC, ASK),
    "dailyturnin": badge(DIAMOND, ASK),
    "collect": {"body": [poly(rounded(3.6, 8.6, 16.8, 12.6, 2.8)), line(arc(12, 8.6, 4, 180, 0, 12))],
                "detail": [line([(4, 13.6), (20, 13.6)])]},
    "equip": {"body": [poly([(12, 2.6), (20.6, 5.8), (19.4, 15.2), (12, 21.6), (4.6, 15.2), (3.4, 5.8)])],
              "detail": [line([(12, 6.6), (12, 16.2)])]},
    "combat": {"body": [poly([(12, 1.8), (15, 5.2), (15, 14.8), (9, 14.8), (9, 5.2)]),
                        line([(6.2, 17), (17.8, 17)]), line([(12, 17), (12, 22)])],
               "detail": [line([(12, 5.4), (12, 12.6)])]},
    "complete": badge(DISC, [line([(7.4, 12.4), (10.8, 15.8), (16.8, 8.6)])]),
    "vendor": {"body": [DISC], "detail": [circle(12, 12, 5.4)]},
    "reputation": {"body": [poly([(5, 3), (19, 3), (19, 21.4), (12, 16.8), (5, 21.4)])],
                   "detail": [line([(8.8, 8), (15.2, 8)])]},
    "fly": {"body": [poly([(21.4, 2.6), (2.6, 10.4), (10, 13.8), (13.4, 21.4)])],
            "detail": [line([(21.4, 2.6), (10, 13.8)])]},
    "fp": {"body": [DISC],
           "detail": [poly([(17.2, 6.8), (6.4, 11.2), (10.8, 13.2), (12.8, 17.6)]),
                      line([(17.2, 6.8), (10.8, 13.2)])]},
    "goto": {"body": [poly(teardrop(12, 9.6, 6.9, 21.8))], "detail": [circle(12, 9.6, 2.5)]},
    "gossip": {"body": [poly(rounded(3, 3.6, 18, 13.2, 3, [(6.4, 16.8), (5.4, 21.4), (11.6, 16.8)]))],
               "detail": [line([(7.8, 8.4), (16.2, 8.4)]), line([(7.8, 12), (13.4, 12)])]},
    "interact": {"body": [circle(12, 12, 6.2), line([(12, 2.2), (12, 5.2)]), line([(12, 18.8), (12, 21.8)]),
                          line([(2.2, 12), (5.2, 12)]), line([(18.8, 12), (21.8, 12)])],
                 "detail": [dot(12, 12, 1.6)]},
    "home": {"body": [poly([(12, 2.6), (21.6, 11.2), (18.6, 11.2), (18.6, 21), (5.4, 21), (5.4, 11.2),
                            (2.4, 11.2)])],
             "detail": [line([(10, 21), (10, 14.8), (14, 14.8), (14, 21)])]},
    "trainer": {"body": [poly([(2.6, 4.6), (11, 6.2), (12, 7.2), (13, 6.2), (21.4, 4.6), (21.4, 18.8),
                               (13, 19.6), (12, 20.6), (11, 19.6), (2.6, 18.8)])],
                "detail": [line([(12, 7.4), (12, 20.4)])]},
    "arrow": {"body": [poly([(12, 2.4), (19.6, 20.6), (12, 16.4), (4.4, 20.6)])], "detail": []},
    "marker": {"body": [poly([(6.4, 3.4), (20.4, 8.6), (6.4, 13.8)]), line([(6.4, 3), (6.4, 21.4)])],
               "detail": []},
    "xp": {"body": [poly([(12, 2.6), (20.6, 12), (15, 12), (15, 21.2), (9, 21.2), (9, 12), (3.4, 12)])],
           "detail": []},
    "stable": {"body": [circle(5.6, 11, 2.3), circle(9.6, 6.4, 2.3), circle(14.4, 6.4, 2.3), circle(18.4, 11, 2.3),
                        circle(12, 16.4, 4.9)], "detail": []},
    "tame": {"body": [poly(heart())], "detail": []},
    "abandon": badge(DISC, [line([(8.4, 8.4), (15.6, 15.6)]), line([(15.6, 8.4), (8.4, 15.6)])]),
    "error": {"body": [line([(5, 5), (19, 19)]), line([(19, 5), (5, 19)])], "detail": []},
    "link": {"body": [line([(10, 5.4), (4.4, 5.4), (4.4, 19.8), (18.6, 19.8), (18.6, 14)]),
                      line([(11.4, 12.6), (20, 4)]), line([(14, 4), (20, 4), (20, 10)])], "detail": []},
    "clock": {"body": [DISC], "detail": [line([(12, 6.2), (12, 12), (16.2, 14.6)])]},
    "engrave": {"body": [poly([(3.4, 20.6), (5.2, 14), (16.4, 2.8), (21.2, 7.6), (10, 18.8)])],
                "detail": [line([(13.6, 5.6), (18.4, 10.4)])]},
    "clicknext": {"body": [line([(8, 4.6), (15.4, 12), (8, 19.4)])], "detail": []},
    "deathskip": {"body": [poly([(12, 2.6), (17.4, 4.4), (20.2, 9), (19.4, 14), (16.4, 16.2), (16.4, 20.8),
                                 (7.6, 20.8), (7.6, 16.2), (4.6, 14), (3.8, 9), (6.6, 4.4)])],
                  "detail": [dot(8.8, 11, 2), dot(15.2, 11, 2), line([(10.6, 17), (10.6, 20.8)]),
                             line([(13.4, 17), (13.4, 20.8)])]},
}


def segment(px, py, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((px - a[0]) * dx + (py - a[1]) * dy) / length)) if length else 0.0
    return math.hypot(px - a[0] - t * dx, py - a[1] - t * dy)


def edges(points, closed):
    pairs = list(zip(points, points[1:]))
    if closed and points[0] != points[-1]:
        pairs.append((points[-1], points[0]))
    return pairs


def outline_distance(shape, px, py):
    kind = shape[0]
    if kind == "circle":
        return abs(math.hypot(px - shape[1], py - shape[2]) - shape[3])
    if kind == "dot":
        return max(0.0, math.hypot(px - shape[1], py - shape[2]) - shape[3])
    return min(segment(px, py, a, b) for a, b in edges(shape[1], kind == "poly"))


def inside(points, px, py):
    odd = False
    for a, b in edges(points, True):
        if (a[1] > py) != (b[1] > py) and px < a[0] + (py - a[1]) * (b[0] - a[0]) / (b[1] - a[1]):
            odd = not odd
    return odd


def solid_distance(shape, px, py):
    kind = shape[0]
    if kind in ("circle", "dot"):
        return math.hypot(px - shape[1], py - shape[2]) - shape[3]
    distance = outline_distance(shape, px, py)
    return -distance if inside(shape[1], px, py) else distance


def cover(distance, half):
    return max(0.0, min(1.0, (half - distance) * SIZE / GRID + 0.5))


def stroked(shape, px, py, width):
    if shape[0] == "dot":
        return cover(solid_distance(shape, px, py), 0.0)
    return cover(outline_distance(shape, px, py), width / 2)


def pixel(glyph, style, px, py):
    if style == "line":
        shapes = glyph["body"] + glyph["detail"]
        return max(stroked(s, px, py, LINE_WIDTH) for s in shapes)
    body = 0.0
    for shape in glyph["body"]:
        if shape[0] == "line":
            body = max(body, stroked(shape, px, py, BOLD_WIDTH))
        else:
            body = max(body, cover(solid_distance(shape, px, py), 0.0))
    cut = max((stroked(s, px, py, CUT_WIDTH) for s in glyph["detail"]), default=0.0)
    return body * (1.0 - cut)


def render(glyph, style, size=SIZE):
    rows = []
    for y in range(size):
        rows.append([pixel(glyph, style, (x + 0.5) * GRID / size, (y + 0.5) * GRID / size) for x in range(size)])
    return rows


def encode(rows):
    size = len(rows)
    data = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8))
    for row in reversed(rows):
        for value in row:
            data.extend((255, 255, 255, int(round(255 * value))))
    return bytes(data)


def main():
    for style in STYLES:
        folder = OUT / style
        folder.mkdir(parents=True, exist_ok=True)
        for name, glyph in GLYPHS.items():
            (folder / (name + ".tga")).write_bytes(encode(render(glyph, style)))
    print("wrote", len(GLYPHS) * len(STYLES), "icons to", OUT)


if __name__ == "__main__":
    main()
