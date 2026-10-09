"""Build the town map's zone exit arrows: where the roads cross from one zone into the next.

Forever has no map link data (C_Map.GetMapLinksForMap returns nothing), so the exits are made
here. Where a road crosses a zone's border was read off the game's map art by eye, and is
written by hand (EXITS), as a map percentage near the crossing. The rest comes from data:

- Which zone owns each spot in the world is Wowhead's zone grid for Forever (from its world
  map's data, a cell about 33 yards across, the game's own areas), turned into uiMapIDs with
  the game's UiMapAssignment (wago.tools), which also places each map's percentages in the
  world.
- Each pick is moved onto the nearest spot of its zone that touches another, the arrow faces
  away from its zone and sits a step inside it, and the road leads to the zone it faces into.
- The other side of each road gets its own arrow, unless that zone lists its roads to this one.

A city gate is written with its city and the arrow's bearing (degrees, 0 north,
anticlockwise), and placed as written: a city sits inside its zone on the grid. Where three
zones meet, an exit names its neighbour to settle which.

Writes NaowhForever_QoL/Interface/ZoneExits.lua.

Usage: python Tools/build/zone_exits.py [--build 1.60.1.70205]
"""
import argparse
import collections
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402
import wago  # noqa: E402
from journal import ROOT, header, write  # noqa: E402
from wowhead import WOWHEAD, fetch  # noqa: E402

OUT = ROOT / "NaowhForever_QoL" / "Interface" / "ZoneExits.lua"
W, H = 1002, 668        # a zone map's art in pixels: directions are measured on it
YARDS_PER_CHUNK = 1600 / 3
SEARCH = 15             # map percent: how far a pick may be from its zone's border
STEP = 0.25             # map percent between the spots searched
NEAR = 3                # map percent: the spots across the border that set the arrow's direction
INSET = 1.5             # percent of the map's width: the arrow sits this far inside its zone
SAME = 6                # map percent: two arrows to one zone closer than this are one exit

# uiMapID -> [ (x, y) | (x, y, neighbour) | (x, y, city, bearing) ], in map percent. A road needs
# writing from one side only: the other side's arrow is found from it, unless that side lists
# its own roads to this zone.
EXITS = {
    1411: [(34.5, 42.5), (45.5, 9.5, 1454, 0)],                                       # Durotar
    1412: [(71, 62)],                                                                  # Mulgore
    1413: [(62.7, 19), (34.5, 28.5, 1442), (48.5, 1.5), (40, 59), (44.5, 91), (51.5, 79)],   # The Barrens
    1416: [(80, 21), (49, 96), (23, 93, 1424)],                                         # Alterac Mountains
    1417: [(14, 46, 1424), (45, 90), (77, 22, 1425)],                                    # Arathi Highlands
    1418: [(48, 5, 1432)],                                                               # Badlands
    1419: [(53, 7, 1435)],                                                               # Blasted Lands
    1420: [(85, 70, 1422), (54, 79, 1421), (61, 71, 1458, 180)],                          # Tirisfal Glades
    1421: [(57, 7, 1420), (68, 79, 1424)],                                               # Silverpine Forest
    1422: [(17, 57, 1420), (77, 52, 1423), (44, 96)],                                     # Western Plaguelands
    1423: [(6, 61, 1422)],                                                               # Eastern Plaguelands
    1424: [(5, 45, 1421), (86, 49, 1417), (88, 31, 1425)],                                # Hillsbrad Foothills
    1425: [(6, 61, 1424), (24, 28)],                                               # The Hinterlands
    1426: [(86, 48, 1432), (53.5, 35, 1455, 0)],                                          # Dun Morogh
    1427: [(45, 93, 1428)],                                                              # Searing Gorge
    1428: [(78, 80, 1433)],                                                              # Burning Steppes
    1429: [(17, 80, 1436), (64, 92, 1431), (95, 72, 1433), (32, 50, 1453, 45)],            # Elwynn Forest
    1430: [(29, 35, 1431), (60, 40, 1435)],                                              # Deadwind Pass
    1431: [(73, 10, 1429), (8, 63, 1436), (45, 90, 1434), (88, 46, 1430)],                 # Duskwood
    1432: [(20, 61, 1426), (25, 5, 1437), (46, 93, 1418)],                                # Loch Modan
    1433: [(5, 89, 1429), (42, 4, 1428)],                                                # Redridge Mountains
    1435: [(3, 57, 1430), (33, 78, 1419)],                                               # Swamp of Sorrows
    1436: [(63, 22, 1429), (67, 62, 1431)],                                              # Westfall
    1437: [(51, 9, 1417)],                                                               # Wetlands
    1438: [(31, 53, 1457, 90)],                                                          # Teldrassil
    1439: [(43, 96, 1440)],                                                              # Darkshore
    1440: [(56, 27, 1448), (42, 73, 1442), (68, 86, 1413), (94, 47, 1447)],                # Ashenvale
    1441: [(8, 26, 1444), (76, 94, 1446)],                                               # Thousand Needles
    1442: [(29, 80, 1443), (86, 94, 1413), (68, 97, 1412)],                              # Stonetalon Mountains
    1443: [(61, 4, 1442), (46, 96, 1444)],                                               # Desolace
    1444: [(45, 4, 1443), (90, 50, 1441)],                                               # Feralas
    1445: [(28, 47, 1413)],                                                              # Dustwallow Marsh
    1446: [(51, 17, 1441), (25, 56, 1449)],                                              # Tanaris
    1447: [(7, 73, 1440)],                                                               # Azshara
    1448: [(67, 8, 1452)],                                                               # Felwood
    1449: [(22, 20, 1451)],                                                              # Un'Goro Crater
    2548: [(15.5, 69, 1433), (27.5, 73.5, 1433)],                                        # Riverglades
    2652: [(35, 5, 1443), (20, 23, 1443)],                                               # Shen'dralas
}


def page_data(text):
    """The page's WH.setPageData("key", value) calls, as {key: value}."""
    found = {}
    decoder = json.JSONDecoder()
    for m in re.finditer(r'WH\.setPageData\("([^"]+)",', text):
        found[m.group(1)] = decoder.raw_decode(text, m.end())[0]
    return found


class Maps:
    def __init__(self, build):
        page = fetch(f"{WOWHEAD}/world-map")
        url = re.search(r'https://nether\.wowhead\.com/forever/data/world-map\?[^"\']+', page).group(0)
        data = page_data(fetch(url.replace("&amp;", "&")))
        self.continents = {c["map"]: c for c in data["wow.worldMap.classicplus.config"]["continents"]}
        self.grids = {g["map"]: (g, {row[0]: row[1:] for row in g["rows"]})
                      for g in data["wow.worldMap.classicplus.zones"]}
        self.bounds = {}
        self.area_maps = {}
        for row in wago.table("UiMapAssignment", build):
            if row["OrderIndex"] == "0":
                map_id = int(row["UiMapID"])
                self.bounds[map_id] = (int(row["MapID"]),) + tuple(float(row[f"Region_{i}"]) for i in (0, 1, 3, 4))
                if int(row["AreaID"]) > 0:
                    self.area_maps.setdefault(int(row["AreaID"]), map_id)

    def to_world(self, map_id, x, y):
        _, min_x, min_y, max_x, max_y = self.bounds[map_id]
        return max_x - y / 100 * (max_x - min_x), max_y - x / 100 * (max_y - min_y)

    def to_map(self, map_id, wx, wy):
        _, min_x, min_y, max_x, max_y = self.bounds[map_id]
        return (max_y - wy) / (max_y - min_y) * 100, (max_x - wx) / (max_x - min_x) * 100

    def zone_at(self, map_id, x, y):
        """The uiMapID that owns the spot at (x, y) percent of a map, or None."""
        continent = self.bounds[map_id][0]
        if continent not in self.grids:
            return None
        wx, wy = self.to_world(map_id, x, y)
        c = self.continents[continent]
        cx = c["canvasX"] + (32 - wy / YARDS_PER_CHUNK - c["originCol"]) * c["pxPerChunk"]
        cy = c["canvasY"] + (32 - wx / YARDS_PER_CHUNK - c["originRow"]) * c["pxPerChunk"]
        grid, rows = self.grids[continent]
        runs = rows.get(int((cy - grid["y"]) // grid["cell"]))
        col = int((cx - grid["x"]) // grid["cell"])
        # A row is runs of cells: start, area, start, area, ..., end.
        for i in range(0, len(runs or ()) - 1, 2):
            if runs[i] <= col < runs[i + 2]:
                return self.area_maps.get(runs[i + 1])
        return None

    def exit(self, map_id, x, y, across=None):
        """The crossing nearest (x, y) percent, into across if given: (x, y, rotation, the zone
        across, the crossing's world spot), or None."""
        n = int(SEARCH / STEP)
        spots = {(i, j): self.zone_at(map_id, x + i * STEP, y + j * STEP)
                 for i in range(-n, n + 1) for j in range(-n, n + 1)}
        best = None
        for (i, j), zone in spots.items():
            if zone != map_id:
                continue
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                other = spots.get((i + di, j + dj))
                if other and other != map_id and across in (None, other):
                    d = i * i + j * j
                    if best is None or d < best[0]:
                        best = (d, i, j)
        if best is None:
            return None
        _, bi, bj = best
        vx = vy = 0
        votes = collections.Counter()
        for (i, j), zone in spots.items():
            if zone and zone != map_id and (i - bi) ** 2 + (j - bj) ** 2 <= (NEAR / STEP) ** 2:
                dx, dy = (i - bi) * W, (j - bj) * H
                length = math.hypot(dx, dy)
                vx += dx / length
                vy += dy / length
                votes[zone] += 1
        length = math.hypot(vx, vy)
        vx, vy = vx / length, vy / length
        ex, ey = x + bi * STEP, y + bj * STEP
        for inset in (INSET, INSET / 2, 0):
            ax, ay = ex - vx * inset, ey - vy * inset * W / H
            if self.zone_at(map_id, ax, ay) == map_id:
                break
        # The arrow points up; SetRotation turns it anticlockwise.
        return ax, ay, math.atan2(-vx, -vy), across or votes.most_common(1)[0][0], self.to_world(map_id, ex, ey)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", default=wago.BUILD)
    build = parser.parse_args().build
    maps = Maps(build)

    # [uiMapID] = { { x, y, rotation, the uiMapID it leads to }, ... }: Wowhead Forever's zone grid
    # on the game's maps for the build. x and y are map percentages, rotation is in radians,
    # anticlockwise from pointing up.
    lines = header(OUT.name,
                   "the roads out of each zone, as clickable arrows on the town map, generated by Tools/build/zone_exits.py")
    exits = {}   # uiMapID -> [ (x, y, rotation, across) ]

    def add(map_id, x, y, rotation, across):
        if not (0 <= x <= 100 and 0 <= y <= 100):   # the crossing is off the edge of this map
            return
        for other in exits.setdefault(map_id, []):
            if other[3] == across and math.hypot(other[0] - x, other[1] - y) < SAME:
                return
        exits[map_id].append((x, y, rotation, across))

    crossings = []
    for map_id, picks in EXITS.items():
        for pick in picks:
            if len(pick) == 4:
                add(map_id, pick[0], pick[1], math.radians(pick[3]), pick[2])
                continue
            found = maps.exit(map_id, pick[0], pick[1], pick[2] if len(pick) == 3 else None)
            if not found:
                sys.exit(f"map {map_id}: no border near {pick[0]}, {pick[1]}")
            x, y, rotation, across, spot = found
            add(map_id, x, y, rotation, across)
            crossings.append((map_id, across, spot))
    picked = {(map_id, across) for map_id, exits_there in exits.items() for _, _, _, across in exits_there}
    for map_id, across, (wx, wy) in crossings:
        if across in maps.bounds and (across, map_id) not in picked:
            found = maps.exit(across, *maps.to_map(across, wx, wy), map_id)
            if not found:
                sys.exit(f"map {across}: no border with {map_id} at the other end of its road")
            add(across, *found[:3], map_id)

    lines.append("ns.ZoneExits = {")
    total = 0
    for map_id in sorted(exits):
        lines.append(f"    [{map_id}] = {{")
        for x, y, rotation, across in sorted(exits[map_id]):
            lines.append(f"        {{ {x:.1f}, {y:.1f}, {rotation:.2f}, {across} }},")
            total += 1
        lines.append("    },")
    lines.append("}")
    write(OUT, lines)
    print(f"{total} exits on {len(exits)} maps -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
