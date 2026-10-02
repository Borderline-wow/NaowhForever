"""Tells whether a newer WoW Forever build is out than the one the Journal's data is read
from (wago.BUILD), and what it changes for the Journal. Run daily by
.github/workflows/watch-build.yml, which opens a pull request when there is one.

What it checks, between the build in use and the new one (the game's own tables, through
wago.tools; nothing is read from Wowhead, the report only links to it):

- Faction rewards: each reward of the Journal's factions that is new, gone, or changed (its
  standing, price, item level, required level or quality), by name.
- Hotfixes: they are recorded per build, and wago.tools records a new build's only some time
  after it appears: until then the new build lacks the items added by hotfix (the Darkspear
  Raiders' and Theramore's). How far it has them is measured (wago.hotfix_coverage: the
  share of the items our data's builds got by hotfix that it has). Under wago.CAUGHT_UP, the
  build in use's are carried over (wago.CARRY_FROM; a hotfix stays in the game until
  Blizzard takes it back) and listed, and a reward even that cannot keep makes the build
  wait, unless --allow-losses. At CAUGHT_UP or more, the build stands alone: a reward it
  lacks was removed by Blizzard, and is dropped and listed.
- Its own hotfixes coming in: with nothing newer out, while the build in use still carries
  items over, the same measure tells when wago.tools has recorded its own hotfixes; then the
  data is rebuilt from them alone (what is still missing was removed by Blizzard).
- Kill counts: every encounter ID a boss in DungeonJournal/Data/Dungeons is counted by,
  that the build in use has, is still in the new build's DungeonEncounter table. One that is
  gone stops counting kills. (A few are pinned by hand in journal_bosses.json, for a raid
  the table does not have yet; those are only counted.)
- New encounters on the maps of the Journal's dungeons: a boss the Journal may be missing.
- New dungeon and raid maps: a dungeon the Journal does not have yet.

A build wago has only just added may not be readable yet (it has to learn each table's
layout first): then the report says so, ready is false, and the next day's run tries again.

Writes a Markdown report to stdout (or --report): a verdict and a summary table, then what
changes for players, then the checks. With --update, makes the change: sets wago.BUILD and
CARRY_FROM, rebuilds the faction data, and adds a line for players under "## Unreleased" in
CHANGELOG.md (a new build always has one; its own hotfixes coming in, when they change
something). With --github-output, writes the workflow's step outputs: newer, ready, build,
problems, made (a change to open a pull request for), changelog (it has a changelog line),
branch, title and issue (the issue's title, where the workflow may not open the PR).

Usage: python Tools/watch_build.py [--build 1.60.1.12345] [--force] [--update] [--allow-losses]
                                   [--report report.md] [--github-output $GITHUB_OUTPUT]
"""
import argparse
import json
import re
import sys
from pathlib import Path

import wago

ROOT = Path(__file__).resolve().parent.parent
DUNGEONS = ROOT / "DungeonJournal" / "Data" / "Dungeons"
CHANGELOG = ROOT / "CHANGELOG.md"
WAGO_PY = Path(__file__).resolve().parent / "wago.py"
INSTANCE_TYPES = {"1": "dungeon", "2": "raid"}   # the Map table's InstanceType
WOWHEAD = "https://www.wowhead.com/forever"      # linked to, for the reader; never fetched
ARROW = " &rarr; "
STANDINGS = {1: "Hated", 2: "Hostile", 3: "Unfriendly", 4: "Neutral", 5: "Friendly", 6: "Honored",
             7: "Revered", 8: "Exalted"}
QUALITIES = {0: "Poor", 1: "Common", 2: "Uncommon", 3: "Rare", 4: "Epic", 5: "Legendary"}
# A reward's fields the report compares, and how each reads.
FIELDS = (("standing", "standing", lambda v: STANDINGS.get(v, v)),
          ("price", "price", lambda v: coins(v)),
          ("level", "item level", str),
          ("reqlevel", "requires level", str),
          ("quality", "quality", lambda v: QUALITIES.get(v, v)))

BOSS = re.compile(r'name = "((?:[^"\\]|\\.)*)"[^\n]*?encounters = \{ ([\d, ]+) \}')
DUNGEON_NAME = re.compile(r'^\s*name = "((?:[^"\\]|\\.)*)",', re.M)


def coins(copper):
    """12345 -> "1g 23s 45c"; 0 -> "none"."""
    if not copper:
        return "none"
    parts = [(copper // 10000, "g"), (copper // 100 % 100, "s"), (copper % 100, "c")]
    return " ".join(f"{n}{coin}" for n, coin in parts if n)


def item_link(item):
    name = item.get("name") or f"Item {item['id']}"
    return f"[{name}]({WOWHEAD}/item={item['id']})"


def faction_link(faction):
    return f"[{faction['name']}]({WOWHEAD}/faction={faction['id']})"


def journal_encounters():
    """Encounter ID -> (dungeon, boss) for every boss the Journal counts kills of."""
    found = {}
    for path in sorted(DUNGEONS.glob("*.lua")):
        text = path.read_text(encoding="utf-8")
        title = DUNGEON_NAME.search(text)
        dungeon = title.group(1) if title else path.stem
        for boss, ids in BOSS.findall(text):
            for encounter in ids.split(","):
                found[encounter.strip()] = (dungeon, boss)
    return found


def encounters(build):
    """Encounter ID -> its row, for the build."""
    return {row["ID"]: row for row in wago.table("DungeonEncounter", build, hotfixes=False)}


def instance_maps(build):
    """Map ID -> its row, for the build's dungeons and raids."""
    return {row["ID"]: row for row in wago.table("Map", build, hotfixes=False)
            if row["InstanceType"] in INSTANCE_TYPES}


def newest(wanted):
    """The build to compare with: the one asked for, else the newest Forever build wago has."""
    builds = wago.forever_builds()
    if wanted:
        for build in builds:
            if build["version"] == wanted:
                return build
        return {"version": wanted, "products": [], "created_at": ""}
    if not builds:
        sys.exit("wago.tools lists no Forever build")
    return builds[0]


def check(old, new):
    """What the build changes for the Journal's dungeons: {total, pinned, gone, renamed, added,
    fresh}, each list of what the report shows."""
    ours = journal_encounters()
    before, after = encounters(old), encounters(new)
    gone = [(e, *ours[e]) for e in sorted(ours, key=int) if e in before and e not in after]
    renamed = [(e, *ours[e], after[e]["Name_lang"]) for e in sorted(ours, key=int)
               if e in after and e in before and before[e]["Name_lang"] != after[e]["Name_lang"]]
    pinned = sum(1 for e in ours if e not in before and e not in after)
    maps = {after[e]["MapID"] for e in ours if e in after} | {before[e]["MapID"] for e in ours if e in before}
    names = {m: row["MapName_lang"] for m, row in instance_maps(new).items()}
    added = [(row["Name_lang"], row["ID"], names.get(row["MapID"], "map " + row["MapID"]))
             for e, row in sorted(after.items(), key=lambda kv: int(kv[0]))
             if e not in before and row["MapID"] in maps]
    old_maps, new_maps = instance_maps(old), instance_maps(new)
    fresh = [(row["MapName_lang"], row["ID"], INSTANCE_TYPES[row["InstanceType"]], row["MaxPlayers"])
             for m, row in sorted(new_maps.items(), key=lambda kv: int(kv[0])) if m not in old_maps]
    return {"total": len(ours) - pinned, "pinned": pinned, "gone": gone, "renamed": renamed,
            "added": added, "fresh": fresh}


def rewards(old, carry_old, new, carry_new):
    """What moving the faction data changes: from build old (with carry_old's items it lacks)
    to build new (with carry_new's). {kept, new, gone, changed, carried}, each a list of
    (faction, item[, changes]) in the factions' order, faction as {name, id}; changes as
    [(field, before, after)] read for people. kept is how many rewards stay."""
    import build_factions
    config = json.loads(build_factions.FACTIONS.read_text(encoding="utf-8"))
    names = {int(row["ID"]): row["Name_lang"] for row in wago.table("Faction", new)}
    _, before, _ = build_factions.game_items(old, carry_old)
    _, after, carried = build_factions.game_items(new, carry_new)
    found = {"kept": 0, "new": [], "gone": [], "changed": [], "carried": []}
    for entry in config["factions"]:
        faction = {"name": entry.get("name") or names.get(entry["id"]) or entry["key"], "id": entry["id"]}
        was = {i["id"]: i for i in before.get(entry["id"], [])}
        now = {i["id"]: i for i in after.get(entry["id"], [])}
        found["kept"] += sum(1 for i in now if i in was)
        found["new"] += [(faction, now[i]) for i in sorted(now) if i not in was]
        found["gone"] += [(faction, was[i]) for i in sorted(was) if i not in now]
        for i in sorted(set(was) & set(now)):
            changes = [(label, show(was[i][key]), show(now[i][key])) for key, label, show in FIELDS
                       if was[i][key] != now[i][key]]
            if changes:
                found["changed"].append((faction, now[i], changes))
        found["carried"] += [(faction, now[i]) for i in sorted(now) if i in carried]
    return found


def set_build(version, carry):
    """Points wago.BUILD at the version, and wago.CARRY_FROM at the build whose hotfixed items
    fill in its gaps (None: none, it has its own)."""
    text = WAGO_PY.read_bytes().decode("utf-8")
    text, n = re.subn(r'^BUILD = "[\d.]+"', f'BUILD = "{version}"', text, count=1, flags=re.M)
    value = f'"{carry}"' if carry else "None"
    text, m = re.subn(r'^CARRY_FROM = [^\r\n]*', f'CARRY_FROM = {value}', text, count=1, flags=re.M)
    if n != 1 or m != 1:
        sys.exit("wago.py has no BUILD or CARRY_FROM line to update")
    WAGO_PY.write_bytes(text.encode("utf-8"))


def plural(n, one, many=None):
    return f"{n} {one if n == 1 else (many or one + 's')}"


def reward_table(rows, extra=None):
    """A Markdown table of rewards: (faction, item[, changes]) rows."""
    lines = ["| Reward | Faction | " + (extra or "Standing") + " |", "|---|---|---|"]
    for row in rows:
        faction, item = row[0], row[1]
        if extra:
            cell = "<br>".join(f"{label}: {a}{ARROW}{b}" for label, a, b in row[2])
        else:
            cell = f"{STANDINGS.get(item['standing'], item['standing'])}, {coins(item['price'])}"
        lines.append(f"| {item_link(item)} | {faction_link(faction)} | {cell} |")
    return lines


def carried_table(rows):
    """The carried rewards as a table: one row per name, a reward sold at several levels once,
    with each of its items linked."""
    lines = ["| Reward | Faction | Items |", "|---|---|---|"]
    grouped = {}
    for faction, item in rows:
        grouped.setdefault((faction["id"], item.get("name") or f"Item {item['id']}"), (faction, []))[1].append(item)
    for (_, name), (faction, items) in grouped.items():
        first = items[0]
        ids = " &middot; ".join(f"[{i['id']}]({WOWHEAD}/item={i['id']})" for i in items)
        lines.append(f"| [{name}]({WOWHEAD}/item={first['id']}) | {faction_link(faction)} | {ids} |")
    return lines


# How each changed field reads in a changelog line.
CHANGELOG_FIELDS = {"standing": "standings", "price": "prices", "item level": "item levels",
                    "requires level": "required levels", "quality": "quality"}


def changes_said(found):
    """What found changes in the faction rewards, in words for players: [] when nothing."""
    parts = []
    if found["changed"]:
        fields = []
        for _, _, changes in found["changed"]:
            for label, _, _ in changes:
                word = CHANGELOG_FIELDS.get(label, label)
                if word not in fields:
                    fields.append(word)
        parts.append(f"{plural(len(found['changed']), 'faction reward')} changed ({', '.join(fields)})")
    if found["new"]:
        parts.append(f"{plural(len(found['new']), 'new faction reward')}")
    if found["gone"]:
        parts.append(f"{plural(len(found['gone']), 'faction reward')} removed")
    return parts


def changelog_line(build, found, hotfixes=False):
    """The CHANGELOG line for players. A new build: the Journal's data is updated to it, and
    what that changes in the faction rewards, when it changes something. The build's own
    hotfixes come in (hotfixes): what they change, or None when they change nothing."""
    parts = changes_said(found)
    if hotfixes:
        if not parts:
            return None
        return f"- Dungeon Journal: faction rewards follow WoW Forever build {build}'s hotfixes: {', '.join(parts)}."
    line = f"- Dungeon Journal: its data is updated to WoW Forever build {build}"
    return line + (": " + ", ".join(parts) if parts else "") + "."


def add_changelog(line):
    """Puts the line under "## Unreleased", in its "### Changed" (made when it has none, before
    "### Fixed" or at the section's end). Keeps the file's line endings."""
    raw = CHANGELOG.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(nl)
    start = lines.index("## Unreleased")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    changed = next((i for i in range(start, end) if lines[i] == "### Changed"), None)
    if changed is None:
        at = next((i for i in range(start, end) if lines[i] == "### Fixed"), end)
        lines[at:at] = ["### Changed", line, ""]
    else:
        # After the section's last line: the next heading, less the blank lines before it.
        at = next((i for i in range(changed + 1, end) if lines[i].startswith("### ")), end)
        while at > changed + 1 and lines[at - 1] == "":
            at -= 1
        lines.insert(at, line)
    CHANGELOG.write_bytes(nl.join(lines).encode("utf-8"))


def hotfixes_row(found, carry, coverage):
    """The summary table's hotfix line: whose hotfixes the rewards come from."""
    share = f"{coverage:.0%} of the items added by hotfix"
    if found["carried"]:
        return f"| **Hotfixes** | {plural(len(found['carried']), 'reward')} carried over from {carry} " \
               f"(list below): " \
               f"wago.tools has {share} for this build so far |"
    return f"| **Hotfixes** | this build's own: wago.tools has {share} |"


def carry_source(old, carry_old, coverage):
    """The build whose hotfixed items fill in a build's gaps. None once wago.tools has that
    build's own hotfixes (coverage at CAUGHT_UP or more). Else the build the data's hotfixed
    items really come from: the build in use, or the one it carries from while it does (its
    own are not on wago.tools, so it has none to give)."""
    if coverage >= wago.CAUGHT_UP:
        return None
    return carry_old or old


def players_section(found, removals, allowed, changelog, check_only=False):
    """What changes for players: the changed, new and gone rewards, and the changelog line."""
    lines = ["### What changes for players", ""]
    if not (found["changed"] or found["new"] or found["gone"]):
        lines += ["Nothing: every faction reward, its standing and its price stay the same.", ""]
    if found["changed"]:
        lines += [f"**{plural(len(found['changed']), 'reward')} changed**", ""]
        lines += reward_table(found["changed"], "What changed") + [""]
    if found["new"]:
        lines += [f"**{plural(len(found['new']), 'new reward')}**", ""] + reward_table(found["new"]) + [""]
    if found["gone"]:
        if removals:
            note = ("wago.tools has this build's own hotfixes, so these are really gone from the game; "
                    "this drops them.")
            lines += [f"**{plural(len(found['gone']), 'reward')} removed by Blizzard**: {note}", ""]
        else:
            if check_only:
                note = "The build in use, checked again: nothing moves."
            else:
                note = ("Moving anyway (allow losses): they leave the Journal." if allowed
                        else "Not moving: the next run tries again.")
            lines += [f"**{plural(len(found['gone']), 'reward')} the new build lacks**: {note}", ""]
        lines += reward_table(found["gone"]) + [""]
    if changelog:
        lines += ["The line this adds to CHANGELOG.md, under Unreleased:", "", "```", changelog[2:], "```", ""]
    return lines


def carried_section(found, carry, build):
    """The rewards carried over, folded away: long, and nothing to act on unless one is wrong."""
    if not found["carried"]:
        return []
    lines = [f"<details><summary><b>{plural(len(found['carried']), 'reward')} come from {carry}'s hotfixes, "
             "for now</b></summary>", "",
             f"They were added to the game by hotfix. wago.tools records hotfixes per build and has not recorded "
             f"{build}'s yet, so these come from {carry}'s; a hotfix stays in the game until Blizzard takes it "
             "back. Once wago.tools has them, the build watcher takes these from the build's own hotfixes and "
             "drops any Blizzard removed.", ""]
    return lines + carried_table(found["carried"]) + ["", "</details>", ""]


def report(target, old, unreadable=None, dungeons=None, found=None, waiting=False, allowed=False, notes=(),
           changelog=None, carry=None, coverage=1.0, removals=False, check_only=False):
    """The report on moving to a new build, as Markdown lines. carry is the build whose hotfixed
    items fill in the new one's (None: its own are in), coverage how much of the hotfixed items
    the new build has, removals whether rewards it lacks are Blizzard's removals, check_only
    whether it is the build in use checked again (force), where nothing moves."""
    new = target["version"]
    seen = ""
    if target["products"]:
        seen = f" &middot; {', '.join(target['products'])} &middot; first seen {target['created_at'][:16]} UTC"
    lines = [f"## WoW Forever {new}", ""]

    # The verdict first: what a reviewer needs to know at a glance.
    if unreadable:
        return lines + [f"> **Waiting:** wago.tools cannot read {', '.join(unreadable)} for this build yet (it has "
                        "not learnt their layout). The next run tries again.", ""]
    if dungeons is None:
        return lines + [f"Nothing newer: the Journal is on the newest Forever build ({old}).", ""]
    gone = len(found["gone"])
    if check_only:
        verdict = (f"> **Checked again:** {new} is the build in use, so nothing moves; this is what its "
                   "tables have now.")
    elif waiting:
        verdict = (f"> **Waiting:** the new build lacks {plural(gone, 'reward')} the build in use has, and "
                   "wago.tools has not recorded its hotfixes yet: nothing moves, the next run tries again. If "
                   "they are really gone from the game, Run workflow with allow losses.")
    elif dungeons["gone"]:
        n = len(dungeons["gone"])
        verdict = (f"> **Check before merging:** {plural(n, 'encounter')} the Journal counts kills by "
                   f"{'is' if n == 1 else 'are'} gone from the game.")
    else:
        said = changes_said(found)
        verdict = (f"> **Ready to merge:** {'all ' if not gone else ''}{found['kept']} faction rewards kept"
                   + (f": {', '.join(said)}. Details below." if said else "; nothing else changes for players."))
    lines += [verdict, ""]

    # The summary table.
    kills = "all " + str(dungeons["total"]) + " present" if not dungeons["gone"] else f"**{len(dungeons['gone'])} gone**"
    if dungeons["pinned"]:
        kills += f" &middot; {dungeons['pinned']} pinned by hand"
    lines += ["| | |", "|---|---|", f"| **New build** | {new}{seen} |", f"| **Data read from until now** | {old} |",
              f"| **Faction rewards** | {found['kept']} kept &middot; {len(found['changed'])} changed "
              f"&middot; {len(found['new'])} new &middot; {len(found['gone'])} gone |",
              hotfixes_row(found, carry, coverage),
              f"| **Kill counts** | {kills} |",
              f"| **New encounters in our dungeons** | {len(dungeons['added']) or 'none'} |",
              f"| **New dungeons and raids** | {len(dungeons['fresh']) or 'none'} |", ""]

    # A check of the build in use adds nothing to CHANGELOG.md, so it shows no line for it.
    lines += players_section(found, removals, allowed, None if check_only else changelog, check_only)

    # The dungeons.
    lines += ["### Dungeons and raids", ""]
    if not (dungeons["gone"] or dungeons["renamed"] or dungeons["added"] or dungeons["fresh"]):
        lines += [f"Nothing changes: all {dungeons['total']} encounter IDs the Journal counts kills by are in "
                  "the new build, and it has no new encounter in our dungeons nor a new dungeon or raid."]
    for e, dungeon, boss in dungeons["gone"]:
        lines.append(f"- **Gone:** encounter {e}, {boss} ({dungeon}). Its kills stop counting.")
    for e, dungeon, boss, name in dungeons["renamed"]:
        lines.append(f"- Renamed: encounter {e}, {boss} ({dungeon}), is now \"{name}\" in the game.")
    for name, e, where in dungeons["added"]:
        lines.append(f"- New encounter: {name} (encounter {e}) in {where}.")
    for name, m, kind, players in dungeons["fresh"]:
        lines.append(f"- New {kind}: {name} (map {m}), for {players} players.")
    if dungeons["pinned"]:
        lines += ["", f"{plural(dungeons['pinned'], 'encounter')} pinned by hand in journal_bosses.json "
                  f"{'is' if dungeons['pinned'] == 1 else 'are'} in neither build's table yet (a raid it lacks)."]
    lines.append("")

    lines += carried_section(found, carry, new)
    if notes:
        lines += ["### Added by hand, and in the game's tables now", ""]
        lines += [f"- {note}" for note in notes] + [""]
    return lines


def hotfixes_report(build, carry, found, coverage, changelog):
    """The report on the build in use's own hotfixes coming in, as Markdown lines."""
    said = changes_said(found)
    lines = [f"## WoW Forever {build}: its own hotfixes are in", "",
             f"> **Ready to merge:** wago.tools has recorded {build}'s own hotfixes, so the rewards that came from "
             f"{carry}'s now come from this build's"
             + (f": {', '.join(said)}. Details below." if said else ". Nothing changes for players."), "",
             "| | |", "|---|---|", f"| **Build** | {build} |",
             f"| **Hotfixes** | this build's own now: wago.tools has {coverage:.0%} of the items added by hotfix "
             f"(was: carried over from {carry}) |",
             f"| **Faction rewards** | {found['kept']} kept &middot; {len(found['changed'])} changed "
             f"&middot; {len(found['new'])} new &middot; {len(found['gone'])} gone |", ""]
    return lines + players_section(found, True, False, changelog)


def outputs(path, **values):
    """Writes the workflow's step outputs: key=value lines, booleans as true or false."""
    with open(path, "a", encoding="utf-8") as out:
        for key, value in values.items():
            value = ("true" if value else "false") if isinstance(value, bool) else value
            out.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--build", help="the build to compare with (default: the newest Forever build)")
    parser.add_argument("--force", action="store_true", help="check even when it is the build in use")
    parser.add_argument("--update", action="store_true",
                        help="make the change: set wago.BUILD and CARRY_FROM, rebuild factions, add the changelog")
    parser.add_argument("--allow-losses", action="store_true",
                        help="move to a build even when its tables lack rewards the build in use has")
    parser.add_argument("--report", help="write the report here instead of to stdout")
    parser.add_argument("--github-output", help="write the workflow's step outputs here")
    args = parser.parse_args()

    old, carry_old = wago.BUILD, wago.CARRY_FROM
    target = newest(args.build)
    new = target["version"]
    newer = wago.version_key(new) > wago.version_key(old)
    sources = [b for b in (old, carry_old) if b]    # the builds the data's hotfixed items come from
    ready, problems, made, changelog = True, False, False, False
    branch = title = issue = ""
    import build_factions

    if newer or args.force:
        missing = wago.unreadable(new)
        if missing:
            ready = False
            lines = report(target, old, unreadable=missing)
        else:
            # wago has the new build's hotfixes: it stands alone, and what it lacks is gone.
            # Else the build in use's hotfixed items fill in its gaps, and losses wait.
            coverage = wago.hotfix_coverage(new, sources)
            carry = carry_source(old, carry_old, coverage)
            dungeons = check(old, new)
            found = rewards(old, carry_old, new, carry)
            problems = bool(dungeons["gone"])
            removals = carry is None and newer
            waiting = bool(found["gone"]) and newer and not removals and not args.allow_losses
            ready = not waiting
            line = changelog_line(new, found)
            notes = ()
            if args.update and newer and ready:
                set_build(new, carry)
                notes, _ = build_factions.build_all(new, carry)
                add_changelog(line)
                made, changelog = True, True
                branch = f"forever-build-{new.replace('.', '-')}"
                title = f"chore(data): WoW Forever build {new}"
                issue = f"WoW Forever build {new} is out"
            lines = report(target, old, dungeons=dungeons, found=found, waiting=waiting,
                           allowed=args.allow_losses, notes=notes, changelog=line, carry=carry,
                           coverage=coverage, removals=removals, check_only=not newer)
    elif carry_old and not wago.unreadable(old) and wago.hotfix_coverage(old, [carry_old]) >= wago.CAUGHT_UP:
        # Nothing newer, but wago has caught up with the build in use's own hotfixes: stop
        # carrying over; what the build lacks now is gone from the game.
        coverage = wago.hotfix_coverage(old, [carry_old])
        found = rewards(old, carry_old, old, None)
        line = changelog_line(old, found, hotfixes=True)
        if args.update:
            set_build(old, None)
            build_factions.build_all(old, None)
            if line:
                add_changelog(line)
            made, changelog = True, line is not None
            branch = f"forever-hotfixes-{old.replace('.', '-')}"
            title = f"chore(data): WoW Forever build {old}'s own hotfixes"
            issue = f"WoW Forever build {old}: its own hotfixes are in"
        lines = hotfixes_report(old, carry_old, found, coverage, line)
    else:
        lines = report(target, old)

    text = "\n".join(lines) + "\n"
    if args.report:
        Path(args.report).write_text(text, encoding="utf-8")
    else:
        print(text)
    if args.github_output:
        outputs(args.github_output, newer=newer, ready=ready, build=new, problems=problems, made=made,
                changelog=changelog, branch=branch, title=title, issue=issue)


if __name__ == "__main__":
    main()
