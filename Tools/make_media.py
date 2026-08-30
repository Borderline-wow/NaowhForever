# Generates the addon's Media/ textures as uncompressed 32-bit TGAs.
# WoW mask textures read the alpha channel, so the disc and ring carry their shape in
# alpha; the ring is also drawn directly as border art, so its RGB is a neutral dark grey.
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


def ring(x, y, size):
    c = size / 2.0
    outer = c - 0.5
    inner = outer - size * 0.055
    d = math.hypot(x - c, y - c)
    # alpha = inside the outer edge AND outside the inner edge
    a = smooth(outer, d) * (1.0 - smooth(inner, d))
    v = int(round(255 * a))
    return (0x2E, 0x31, 0x36, v)


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


os.makedirs(OUT, exist_ok=True)
write_tga(os.path.join(OUT, "circle_mask.tga"), 128, disc)
write_tga(os.path.join(OUT, "circle_ring.tga"), 128, ring)
write_tga(os.path.join(OUT, "cog.tga"), 64, gear)
write_tga(os.path.join(OUT, "icon.tga"), 64, icon)
