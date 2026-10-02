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


def chain(x, y, size):
    # Two chain links on the diagonal, bottom-left to top-right, each a stroked capsule, the
    # second passing through the first: the Journal's Chain action. Where they cross, the
    # one underneath is cut back by a hair, over on one side of the diagonal and under on
    # the other, so they read as linked rather than as one shape.
    ux, uy = 0.7071, -0.7071
    c, half, radius, width, gap = size / 2.0, size * 0.10, size * 0.13, size * 0.085, size * 0.045
    rings = []
    for offset in (-0.19, 0.19):
        mx, my = c + ux * offset * size, c + uy * offset * size
        d = seg_dist(x, y, mx - ux * half, my - uy * half, mx + ux * half, my + uy * half)
        rings.append(abs(d - radius))
    a1, a2 = smooth(width / 2, rings[0]), smooth(width / 2, rings[1])
    if (x - c) * uy - (y - c) * ux > 0:
        a2 *= 1.0 - smooth(width / 2 + gap, rings[0])
    else:
        a1 *= 1.0 - smooth(width / 2 + gap, rings[1])
    return (255, 255, 255, int(round(255 * max(a1, a2))))


def info(x, y, size):
    # A thin ring with an "i" in it: the Journal's Naowh's tip button.
    c = size / 2.0
    ring = smooth(size * 0.045, abs(math.hypot(x - c, y - c) - size * 0.42))
    dot = smooth(size * 0.075, math.hypot(x - c, y - size * 0.30))
    stem = smooth(size * 0.065, seg_dist(x, y, c, size * 0.46, c, size * 0.72))
    return (255, 255, 255, int(round(255 * max(ring, dot, stem))))


def pin(x, y, size):
    # A map pin: a round head that narrows to a point, with a hole in the head. The head's
    # circle and a triangle down to the tip, each with a soft edge, joined; the hole cut out.
    cx, cy, r = size * 0.5, size * 0.38, size * 0.27
    head = smooth(r, math.hypot(x - cx, y - cy))
    # The cone's sides touch the head where a line from the tip meets the circle at a tangent.
    tip_y = size * 0.93
    k = r / (tip_y - cy)
    top_y, half = cy + r * k, r * math.sqrt(1.0 - k * k)
    # Distance inside the triangle (left side, right side, top), negative outside.
    def side(ax, ay, bx, by):
        dx, dy = bx - ax, by - ay
        return ((x - ax) * dy - (y - ay) * dx) / math.hypot(dx, dy)
    inside = min(side(cx - half, top_y, cx, tip_y), -side(cx + half, top_y, cx, tip_y), y - top_y)
    cone = max(0.0, min(1.0, inside + 0.5))
    hole = smooth(size * 0.105, math.hypot(x - cx, y - cy))
    a = max(head, cone) * (1.0 - hole)
    return (255, 255, 255, int(round(255 * a)))


def hanger(x, y, size):
    # A coat hanger, for looks (appearances): an open hook at the top, a short neck, and a
    # triangle for the shoulders and the bar.
    w = size * 0.075
    hx, hy, hr = size * 0.5, size * 0.23, size * 0.10
    ring = abs(math.hypot(x - hx, y - hy) - hr)
    # The hook is open at its lower left.
    hook = smooth(w / 2, ring) if not (x < hx and y > hy) else 0.0
    body = [(0.5, 0.33), (0.5, 0.40), (0.08, 0.74), (0.92, 0.74), (0.5, 0.40)]
    d = min(seg_dist(x, y, body[i][0] * size, body[i][1] * size, body[i + 1][0] * size, body[i + 1][1] * size)
            for i in range(len(body) - 1))
    a = max(hook, smooth(w / 2, d))
    return (255, 255, 255, int(round(255 * a)))


def rounded_rect_dist(x, y, cx, cy, hw, hh, r):
    # Signed distance to a rounded rectangle: negative inside.
    qx, qy = abs(x - cx) - (hw - r), abs(y - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sidebar(filled):
    # A window with a panel down its left: the Journal's show and hide the list button. The
    # panel is filled while the list shows, empty while it is hidden.
    def pixel(x, y, size):
        w = size * 0.075
        c = size / 2.0
        d = rounded_rect_dist(x, y, c, c, size * 0.42, size * 0.34, size * 0.08)
        frame = smooth(w / 2, abs(d))
        split = size * 0.40
        divider = smooth(w / 2, abs(x - split)) if d < 0 else 0.0
        panel = 0.0
        if filled and d < -w / 2 and x < split:
            panel = 0.55
        a = max(frame, divider, panel)
        return (255, 255, 255, int(round(255 * a)))
    return pixel


def funnel(x, y, size):
    # A funnel, outlined: the Journal's Filters button.
    w = size * 0.075
    points = [(0.14, 0.20), (0.86, 0.20), (0.57, 0.53), (0.57, 0.78), (0.43, 0.86), (0.43, 0.53),
              (0.14, 0.20)]
    d = min(seg_dist(x, y, points[i][0] * size, points[i][1] * size, points[i + 1][0] * size,
                     points[i + 1][1] * size) for i in range(len(points) - 1))
    return (255, 255, 255, int(round(255 * smooth(w / 2, d))))


def half_circle(x, y, size):
    # A ring with its left half filled: the Journal's Opacity.
    c = size / 2.0
    d = math.hypot(x - c, y - c)
    r, w = size * 0.36, size * 0.075
    ring = smooth(w / 2, abs(d - r))
    fill = smooth(r, d) if x < c else 0.0
    return (255, 255, 255, int(round(255 * max(ring, fill))))


def ellipse_dist(x, y, cx, cy, rx, ry):
    # Close to the signed distance to an ellipse (negative inside); exact enough for a ~1px
    # edge at icon sizes.
    k = math.hypot((x - cx) / rx, (y - cy) / ry)
    return (k - 1.0) * min(rx, ry)


def skull(x, y, size):
    # A skull: a round cranium over a squarer jaw, two eyes, a nose and the gaps between the
    # teeth cut out. The Journal's kill count.
    u, v = x / size, y / size
    head = min(ellipse_dist(u, v, 0.5, 0.42, 0.33, 0.31),
               rounded_rect_dist(u, v, 0.5, 0.72, 0.2, 0.13, 0.05))
    eyes = min(ellipse_dist(u, v, 0.36, 0.46, 0.095, 0.105),
               ellipse_dist(u, v, 0.64, 0.46, 0.095, 0.105))
    nose = ellipse_dist(u, v, 0.5, 0.61, 0.035, 0.055)
    teeth = min(rounded_rect_dist(u, v, 0.43, 0.82, 0.014, 0.06, 0.01),
                rounded_rect_dist(u, v, 0.57, 0.82, 0.014, 0.06, 0.01))
    cut = min(eyes, nose, teeth)
    d = max(head, -cut) * size   # in pixels: inside the head and outside every cut
    return (255, 255, 255, int(round(255 * smooth(0, d))))


def polygon_dist(x, y, points):
    """Signed distance to a closed polygon (negative inside), by its edges and an even-odd
    crossing test."""
    d, inside = float("inf"), False
    n = len(points)
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        d = min(d, seg_dist(x, y, ax, ay, bx, by))
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            inside = not inside
    return -d if inside else d


def star(x, y, size):
    # A five-pointed star, point up: the Journal's mark for your BiS.
    c, outer = size / 2.0, size * 0.47
    inner = outer * 0.42
    points = []
    for i in range(10):
        r = outer if i % 2 == 0 else inner
        a = math.pi / 2 + i * math.pi / 5
        points.append((c + r * math.cos(a), c + size * 0.03 - r * math.sin(a)))
    return (255, 255, 255, int(round(255 * smooth(0, polygon_dist(x, y, points)))))


def crossed_swords(x, y, size):
    # Two swords crossed, points up: contested ground, beside the factions' crests.
    def sword(flip):
        def at(u, v):
            return (1 - u if flip else u, v)
        blade = stroke(size, [at(0.24, 0.80), at(0.80, 0.20)], 0.09)
        guard = stroke(size, [at(0.20, 0.62), at(0.38, 0.80)], 0.08)
        grip = stroke(size, [at(0.24, 0.80), at(0.14, 0.90)], 0.08)
        return max(blade(x, y, size)[3], guard(x, y, size)[3], grip(x, y, size)[3])
    return (255, 255, 255, max(sword(False), sword(True)))


def people(x, y, size):
    # Two people, one in front of the other: group members on the same quest. Each is a
    # round head over rounded shoulders; the one behind is cut back around the one in front.
    u, v = x / size, y / size

    def person(cx, top, scale):
        head = ellipse_dist(u, v, cx, top + 0.15 * scale, 0.14 * scale, 0.14 * scale)
        body = ellipse_dist(u, v, cx, top + 0.62 * scale, 0.27 * scale, 0.26 * scale)
        body = max(body, v - (top + 0.66 * scale))   # shoulders: the top of the body only
        return min(head, body)
    front = person(0.40, 0.18, 1.0)
    back = max(person(0.68, 0.12, 0.82), -(front - 0.06))   # a gap round the front one
    d = min(front, back) * size
    return (255, 255, 255, int(round(255 * smooth(0, d))))


def bag(x, y, size):
    # A tied loot bag: a round body, a band where it is tied, and the cloth fanning out
    # above it in two points. The Journal's loot from a boss.
    u, v = x / size, y / size
    body = min(ellipse_dist(u, v, 0.5, 0.67, 0.35, 0.28),
               rounded_rect_dist(u, v, 0.5, 0.42, 0.11, 0.05, 0.02))
    tie = rounded_rect_dist(u, v, 0.5, 0.33, 0.16, 0.035, 0.03)
    cloth = polygon_dist(u, v, [(0.41, 0.27), (0.59, 0.27), (0.74, 0.08), (0.5, 0.15), (0.26, 0.08)])
    d = min(body, tie, cloth) * size
    return (255, 255, 255, int(round(255 * smooth(0, d))))


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
write_tga(os.path.join(OUT, "chain.tga"), 64, chain)
write_tga(os.path.join(OUT, "info.tga"), 64, info)
write_tga(os.path.join(OUT, "pin.tga"), 64, pin)
write_tga(os.path.join(OUT, "hanger.tga"), 64, hanger)
write_tga(os.path.join(OUT, "sidebar_shown.tga"), 64, sidebar(True))
write_tga(os.path.join(OUT, "sidebar_hidden.tga"), 64, sidebar(False))
write_tga(os.path.join(OUT, "funnel.tga"), 64, funnel)
write_tga(os.path.join(OUT, "opacity.tga"), 64, half_circle)
write_tga(os.path.join(OUT, "skull.tga"), 64, skull)
write_tga(os.path.join(OUT, "star.tga"), 64, star)
write_tga(os.path.join(OUT, "swords.tga"), 64, crossed_swords)
write_tga(os.path.join(OUT, "people.tga"), 64, people)
write_tga(os.path.join(OUT, "bag.tga"), 64, bag)
