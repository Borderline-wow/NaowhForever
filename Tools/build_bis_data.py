"""Build NaowhForever_BiSData.lua from wowsrc.com's per-spec best-in-slot lists.

wowsrc.com gave permission to use what is on its site. Each spec page
(/specs/<spec>/) has one <details> per gear slot; its <summary> is the #1 pick
and the <li> rows under it are #2 onwards, each carrying a data-tip JSON blob
(name, quality, item level, slot, source) and an icon. The site publishes no
item IDs, so each item is looked up by name in Wowhead's Forever database and
accepted only when name, quality, icon and item level all agree. Answers are
cached in bis_item_ids.json; an entry there can be edited by hand to settle an
item the lookup could not, and a value of null leaves the item out.

Usage: python Tools/build_bis_data.py
"""
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "NaowhForever_BiSData.lua"
CACHE = Path(__file__).resolve().parent / "bis_item_ids.json"

CLASSES = ["druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior"]

# wowsrc slot id -> inventory slot number, in character pane order.
SLOTS = [
    ("head", 1), ("neck", 2), ("shoulder", 3), ("back", 15), ("chest", 5), ("wrist", 9),
    ("hands", 10), ("waist", 6), ("legs", 7), ("feet", 8), ("finger-1", 11), ("finger-2", 12),
    ("trinket-1", 13), ("trinket-2", 14), ("main-hand", 16), ("off-hand", 17), ("ranged", 18),
]

QUALITY = {"poor": 0, "common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    # Wowhead's CDN answers 403 once requests come too fast; it lifts after a pause.
    for wait in (30, 60, 120, 240, None):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            if e.code not in (403, 429, 503) or wait is None:
                raise
            print(f"  {e.code} from {urllib.parse.urlsplit(url).netloc}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)


def spec_slugs():
    slugs = []
    for cls in CLASSES:
        page = fetch(f"https://wowsrc.com/classes/{cls}/")
        for slug in sorted(set(re.findall(r'href="/specs/([a-z-]+)/"', page))):
            slugs.append((cls.upper(), slug))
    return slugs


def parse_spec(slug):
    page = fetch(f"https://wowsrc.com/specs/{slug}/")
    title = re.search(r"<title>WoW Forever ([^:<]+):", page).group(1)
    slots = {}
    for key, inv in SLOTS:
        start = page.find(f'id="slot-{key}"')
        if start < 0:
            continue
        block = page[start:page.index("</details>", start)]
        items = []
        # Each item is a data-tip followed by its icon; rows are already in rank order.
        for tip, icon in re.findall(r'data-tip="([^"]*)".*?/icons/item/([a-z0-9_]+)\.webp', block, re.S):
            t = json.loads(html.unescape(tip))
            items.append({
                "name": t["n"], "quality": QUALITY.get(t.get("r")), "ilvl": t.get("l"),
                "icon": icon, "source": (t.get("src") or "").replace("�", "-"),
            })
        slots[inv] = items
    return title, slots


def lookup(item):
    url = ("https://www.wowhead.com/forever/search/suggestions-template?q="
           + urllib.parse.quote(item["name"]))
    results = json.loads(fetch(url)).get("results", [])
    matches = []
    for r in results:
        if r.get("type") != 3 or r.get("name", "").lower() != item["name"].lower():
            continue
        if r.get("quality") != item["quality"] or r.get("icon") != item["icon"]:
            continue
        ilvl = re.search(r"item level (\d+)", r.get("pinDescription", ""))
        if item["ilvl"] and ilvl and int(ilvl.group(1)) != item["ilvl"]:
            continue
        matches.append(r["id"])
    time.sleep(1)
    return matches


def item_key(item):
    return f'{item["name"]}|{item["icon"]}|{item["quality"]}|{item["ilvl"]}'


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    specs, sources, unresolved = [], {}, {}

    for cls, slug in spec_slugs():
        title, slots = parse_spec(slug)
        print(f"{title}: {sum(len(v) for v in slots.values())} items", file=sys.stderr)
        resolved = {}
        for inv, items in slots.items():
            ids = []
            for item in items:
                key = item_key(item)
                if key not in cache:
                    matches = lookup(item)
                    cache[key] = matches[0] if len(matches) == 1 else None
                    if len(matches) != 1:
                        unresolved[key] = matches
                item_id = cache[key]
                if item_id and item_id not in ids:
                    ids.append(item_id)
                    if item["source"]:
                        sources[item_id] = item["source"]
            resolved[inv] = ids
        specs.append((cls, slug, title, resolved))
        CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True), encoding="utf-8")

    lines = [
        "-------------------------------------------------------------------------------",
        "--  NaowhForever_BiSData.lua -- ranked best-in-slot candidates per spec, from wowsrc.com",
        "--  (used with permission). Generated by Tools/build_bis_data.py; do not edit by hand.",
        "--",
        "--  specs: { class, key, name, slots = { [inventory slot] = { itemID, ... } } }, best first.",
        "--  sources: itemID -> where it comes from, as wowsrc words it.",
        "-------------------------------------------------------------------------------",
        "local ns = _G.NaowhForever",
        "",
        "ns.BiSData = {",
        "    specs = {",
    ]
    for cls, slug, title, slots in specs:
        lines.append(f"        {{ class = {lua_string(cls)}, key = {lua_string(slug)}, name = {lua_string(title)}, slots = {{")
        for _, inv in SLOTS:
            ids = slots.get(inv, [])
            lines.append(f"            [{inv}] = {{ {', '.join(str(i) for i in ids)} }},")
        lines.append("        } },")
    lines.append("    },")
    lines.append("    sources = {")
    for item_id in sorted(sources):
        lines.append(f"        [{item_id}] = {lua_string(sources[item_id])},")
    lines.append("    },")
    lines.append("}")
    OUT.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")

    print(f"{len(specs)} specs, {len(sources)} sourced items -> {OUT.name}", file=sys.stderr)
    if unresolved:
        print(f"{len(unresolved)} items left out (no single match); settle them in {CACHE.name}:", file=sys.stderr)
        for key, matches in sorted(unresolved.items()):
            print(f"  {key}  candidates={matches}", file=sys.stderr)


if __name__ == "__main__":
    main()
