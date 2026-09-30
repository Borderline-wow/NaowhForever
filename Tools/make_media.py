# Generates the addon's Media/ textures as uncompressed 32-bit TGAs.
# WoW mask textures read the alpha channel, so every shape here lives in alpha over white
# RGB, which lets the same file serve as a mask or be tinted and drawn directly.
# Run from the repo root: python Tools/make_media.py
import math
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "Media")

NAOWH_BLUE = (0x00, 0x91, 0xED)


def write_tga(path, size, pixel_fn):
    # Uncompressed true-color TGA, 32bpp BGRA, bottom-left origin.
    header = struct.pack(
        "<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8
    )
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r, g, b, a = pixel_fn(x + 0.5, size - y - 0.5, size)
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    with open(path, "wb") as f:
        f.write(header + b"".join(rows))
    print("wrote", os.path.normpath(path))


def smooth(edge, dist):
    # 1 inside, 0 outside, ~1px anti-aliased edge.
    return max(0.0, min(1.0, edge - dist + 0.5))


def disc(x, y, size):
    c = size / 2.0
    d = math.hypot(x - c, y - c)
    a = smooth(c - 0.5, d)
    v = int(round(255 * a))
    return (255, 255, 255, v)


def half_disc(x, y, size):
    # Right half of a disc: the sweep piece. Two of these, each clipped to one half of
    # the ring and rotated, draw any arc without per-frame geometry.
    c = size / 2.0
    d = math.hypot(x - c, y - c)
    a = smooth(c - 0.5, d) if x >= c else 0.0
    return (255, 255, 255, int(round(255 * a)))


def hole(x, y, size):
    # Thickness mask: transparent inside the inscribed disc, opaque outside it. Drawn
    # smaller than the ring and wrapped CLAMPTOWHITE, so it punches the centre out and
    # leaves everything beyond its own rect visible.
    c = size / 2.0
    d = math.hypot(x - c, y - c)
    a = 1.0 - smooth(c - 0.5, d)
    return (255, 255, 255, int(round(255 * a)))


def gear(x, y, size):
    c = size / 2.0
    dx, dy = x - c, y - c
    d = math.hypot(dx, dy)
    ang = math.atan2(dy, dx)
    teeth = 8
    body = size * 0.30
    tooth = size * 0.42
    hole = size * 0.13
    wave = 0.5 + 0.5 * math.cos(ang * teeth)
    radius = body + (tooth - body) * (1.0 if wave > 0.5 else 0.0)
    a = smooth(radius, d) * (1.0 - smooth(hole, d))
    v = int(round(255 * a))
    return (0xC8, 0xC8, 0xC8, v)


def icon(x, y, size):
    # Dark grey rounded square, Naowh blue border, blue exclamation mark.
    c = size / 2.0
    half = size * 0.46
    corner = size * 0.12
    qx, qy = abs(x - c) - (half - corner), abs(y - c) - (half - corner)
    dist = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - corner
    inside = smooth(0.0, dist + 0.5)
    edge = inside * (1.0 - smooth(0.0, dist + size * 0.05))
    r, g, b = 0x1A, 0x1C, 0x1F
    a = inside
    if edge > 0.01:
        br, bg, bb = NAOWH_BLUE
        r = int(r + (br - r) * edge)
        g = int(g + (bg - g) * edge)
        b = int(b + (bb - b) * edge)
    # exclamation mark: bar + dot, centered
    bar_w, bar_top, bar_bot = size * 0.09, size * 0.70, size * 0.36
    dot_y, dot_r = size * 0.26, size * 0.06
    mark = 0.0
    if abs(x - c) < bar_w and bar_bot < y < bar_top:
        mark = 1.0
    if math.hypot(x - c, y - dot_y) < dot_r:
        mark = 1.0
    if mark > 0:
        r, g, b = NAOWH_BLUE
    return (int(r), int(g), int(b), int(round(255 * a)))


def seg_dist(px, py, ax, ay, bx, by):
    # Distance from a point to the segment a-b.
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def chevron(x, y, size):
    # A thick right-pointing chevron with rounded ends: the feature rows' open/closed
    # arrow, rotated a quarter turn to point down when open.
    ax, ay = size * 0.36, size * 0.18
    tx, ty = size * 0.66, size * 0.50
    bx, by = size * 0.36, size * 0.82
    d = min(seg_dist(x, y, ax, ay, tx, ty), seg_dist(x, y, tx, ty, bx, by))
    a = smooth(size * 0.10, d)
    return (255, 255, 255, int(round(255 * a)))


def segment_dist(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (ax + t * dx), y - (ay + t * dy))


def stroke(size, points, width):
    # White polyline with round caps, alpha only, for tinting with SetVertexColor.
    def pixel(x, y, _):
        d = min(segment_dist(x, y, *(p * size for p in points[i] + points[i + 1]))
                for i in range(len(points) - 1))
        return (255, 255, 255, int(round(255 * smooth(width * size / 2, d))))
    return pixel


os.makedirs(OUT, exist_ok=True)
# y runs down the image.
write_tga(os.path.join(OUT, "chevron_up.tga"), 64, stroke(64, [(0.22, 0.64), (0.5, 0.36), (0.78, 0.64)], 0.12))
write_tga(os.path.join(OUT, "cross.tga"), 64, lambda x, y, s: max(
    stroke(64, [(0.26, 0.26), (0.74, 0.74)], 0.11)(x, y, s),
    stroke(64, [(0.26, 0.74), (0.74, 0.26)], 0.11)(x, y, s), key=lambda p: p[3]))
write_tga(os.path.join(OUT, "check.tga"), 64, stroke(64, [(0.18, 0.5), (0.4, 0.72), (0.82, 0.28)], 0.13))
write_tga(os.path.join(OUT, "circle_mask.tga"), 128, disc)
write_tga(os.path.join(OUT, "circle_half.tga"), 256, half_disc)
write_tga(os.path.join(OUT, "circle_hole.tga"), 256, hole)
write_tga(os.path.join(OUT, "cog.tga"), 64, gear)
write_tga(os.path.join(OUT, "icon.tga"), 64, icon)
write_tga(os.path.join(OUT, "chevron.tga"), 64, chevron)
