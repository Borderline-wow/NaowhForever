"""Build the town map's boats and zeppelins from the game's own tables (Tools/wago.py).

Every boat and zeppelin rides a taxi path (TaxiPathNode), and waits at each of its two docks:
the nodes with a delay. Those are where the pins go, in world yards, turned into map
percentages of the dock's zone with the zone's bounds on its continent (UiMapAssignment). Each
dock's pin names the other end and opens its zone's map. A zeppelin tower's two docks are a
step apart, too close for two pins, so they share one with both destinations.

Which path is which route, and the zones of its docks, are written here by hand (ROUTES); the
build checks each dock is on the continent and inside the zone it is listed under. Forever's own
docks (Southshore, Zephras Isle) are left out until their routes are known.

Writes QoL/NaowhForever_TownTravel.lua.

Usage: python Tools/build_travel.py [--build 1.60.1.70205]
"""
import argparse
import sys

import wago
from build_journal import ROOT, header, write

OUT = ROOT / "QoL" / "NaowhForever_TownTravel.lua"
EASTERN_KINGDOMS, KALIMDOR = 0, 1
SAME = 2.5   # map percent: docks closer than this share one pin
# (taxi path, kind, factions, its first dock, its second): a dock is (place, continent, uiMapID).
ROUTES = [
    (241, "Boat", "AH", ("Ratchet", KALIMDOR, 1413), ("Booty Bay", EASTERN_KINGDOMS, 1434)),
    (292, "Boat", "A", ("Menethil Harbor", EASTERN_KINGDOMS, 1437), ("Theramore", KALIMDOR, 1445)),
    (293, "Boat", "A", ("Rut'theran Village", KALIMDOR, 1438), ("Auberdine", KALIMDOR, 1439)),
    (295, "Boat", "A", ("Menethil Harbor", EASTERN_KINGDOMS, 1437), ("Auberdine", KALIMDOR, 1439)),
    (303, "Boat", "A", ("Feathermoon Stronghold", KALIMDOR, 1444), ("the Feralas coast", KALIMDOR, 1444)),
    (285, "Zeppelin", "H", ("Grom'gol", EASTERN_KINGDOMS, 1434), ("Orgrimmar", KALIMDOR, 1411)),
    (301, "Zeppelin", "H", ("Grom'gol", EASTERN_KINGDOMS, 1434), ("Undercity", EASTERN_KINGDOMS, 1420)),
    (302, "Zeppelin", "H", ("Orgrimmar", KALIMDOR, 1411), ("Undercity", EASTERN_KINGDOMS, 1420)),
]


def stops(nodes, path):
    """The path's docks in order, each (continent, x, y) once: a dock it stops at twice, at
    the start and the end of the path, is a yard or two off between the two."""
    found = []
    for node in sorted((n for n in nodes if n["PathID"] == str(path)), key=lambda n: int(n["NodeIndex"])):
        if int(node["Delay"]) > 0:
            stop = (int(node["ContinentID"]), float(node["Loc_0"]), float(node["Loc_1"]))
            if not any(abs(stop[1] - f[1]) < 10 and abs(stop[2] - f[2]) < 10 for f in found):
                found.append(stop)
    return found


def map_position(bounds, x, y):
    """World x (north) and y (west) as map percentages of a zone: (left, top), 0 to 100."""
    min_x, min_y, max_x, max_y = bounds
    return (max_y - y) / (max_y - min_y) * 100, (max_x - x) / (max_x - min_x) * 100


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", default=wago.BUILD)
    build = parser.parse_args().build

    nodes = wago.table("TaxiPathNode", build)
    bounds = {}
    for row in wago.table("UiMapAssignment", build):
        if row["OrderIndex"] == "0":
            bounds[int(row["UiMapID"])] = (int(row["MapID"]), tuple(float(row[f"Region_{i}"]) for i in (0, 1, 3, 4)))

    by_map = {}
    for path, kind, factions, first, second in ROUTES:
        docks = stops(nodes, path)
        if len(docks) != 2:
            sys.exit(f"taxi path {path} has {len(docks)} docks, not 2")
        for (continent, x, y), (place, want_continent, map_id), (to, _, to_map) in (
                (docks[0], first, second), (docks[1], second, first)):
            map_continent, zone = bounds[map_id]
            left, top = map_position(zone, x, y)
            if continent != want_continent or map_continent != continent or not (0 <= left <= 100 and 0 <= top <= 100):
                sys.exit(f"taxi path {path}: the {place} dock is not in map {map_id}")
            by_map.setdefault(map_id, []).append((round(left, 1), round(top, 1), f"{kind} to {to}", to_map, factions))

    pins_by_map = {}
    for map_id, docks in by_map.items():
        pins = pins_by_map[map_id] = []
        for left, top, label, to_map, factions in sorted(docks):
            near = [p for p in pins if abs(p[0] - left) < SAME and abs(p[1] - top) < SAME and p[2] == factions]
            if not near:
                pins.append([left, top, factions, label, to_map])
            elif len(near[0]) > 5:
                sys.exit(f"three docks share a pin on map {map_id}")
            else:
                pin = near[0]
                pin[0], pin[1] = round((pin[0] + left) / 2, 1), round((pin[1] + top) / 2, 1)
                pin += [label, to_map]

    lines = header(
        "NaowhForever_TownTravel.lua -- boats and zeppelins on the town map, by world map, from the",
        f"game's tables for build {build}. Generated by Tools/build_travel.py; do not edit by hand.",
        "",
        "[uiMapID] = { { x, y, factions, label, the uiMapID it takes you to[, a second label and",
        "uiMapID, for a tower with two zeppelins] }, ... }. x and y are map percentages.",
    )
    lines.append("ns.TownTravel = {")
    total = 0
    for map_id in sorted(pins_by_map):
        lines.append(f"    [{map_id}] = {{")
        for left, top, factions, *ends in sorted(pins_by_map[map_id]):
            fields = [f"{left:g}", f"{top:g}", f'"{factions}"']
            for label, to_map in zip(ends[::2], ends[1::2]):
                fields += [f'"{label}"', str(to_map)]
                total += 1
            lines.append("        { " + ", ".join(fields) + " },")
        lines.append("    },")
    lines.append("}")
    write(OUT, lines)
    print(f"{total} docks on {len(pins_by_map)} maps -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
