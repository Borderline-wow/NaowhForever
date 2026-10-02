# Tools

Scripts we run on our machines (and a few in CI) to build the addon's data, check it, and
ship it. None of this goes in the addon zip. Run everything from the repo root with Python
3.12 or Lua 5.1.

Why so many? The game client doesn't ship most of what the addon shows: who drops what,
quest chains and BiS lists all live on servers or websites. So we read them once, offline,
and ship the result as plain Lua data. The scripts keep that repeatable.

Most scripts keep a cache next to them (`*_cache.json`, `*.json`). Delete an entry to fetch
it again. Be gentle with the sites: the scripts wait between requests on purpose.

## Dungeon Journal

| Tool | What it does | Why |
| --- | --- | --- |
| `build_journal.py` | Builds every dungeon's bosses and loot into `DungeonJournal/Data/`. `--offline` asks Wowhead nothing (its cache and the game's tables only), for CI. | The heart of the Journal. How it decides what a boss drops is drawn in `DungeonJournal/README.md`. |
| `journal_bosses.json` | The bosses per dungeon, in kill order, with rares, optional bosses, chests and hand fixes. | Kept by hand: no source has the right list for Forever. |
| `wowsrc.py` | Reads wowsrc.com's Forever loot pages into `wowsrc_loot.json`. `--resolve` maps their item names to IDs in `item_names.json` (`--offline`: without Wowhead). `--check` says what changed on their pages since (daily in CI). | Wowhead hasn't tied Forever's new items to bosses yet; wowsrc has. They gave us permission. |
| `journal_cache.json`, `wowsrc_loot.json`, `item_names.json` | Every Wowhead answer the build used; wowsrc's pages as last read; their item names to IDs. | Committed, so a rebuild (and CI) gives the same data without asking again. |
| `build_factions.py` | Builds the Reputation and PvP tabs from `journal_factions.json` and the game's own item tables. | Rewards, standings and prices are in the client, so we read them from there, not a website. |
| `build_quest_chains.py` | Builds each dungeon quest's chain and what you need first, from Wowhead Forever. | So the Journal can say "do this first". |
| `wago.py` | Reads the game's own tables (DB2) for a Forever build from wago.tools, hotfixes included. `BUILD` is the build our data comes from. | The one source that is the game itself. |
| `watch_build.py` | Compares a new Forever build with ours: faction rewards, kill-count encounters, new dungeons, new dungeon floor maps, new gear the Journal doesn't list yet. `--update` moves us to it. | Runs daily in CI (`.github/workflows/daily-watch.yml`), so a new build never sneaks past us. |

## BiS List

| Tool | What it does | Why |
| --- | --- | --- |
| `build_bis_data.py` | Builds `BiS/NaowhForever_BiSData.lua` from wowsrc.com's per-spec BiS pages. Item IDs are cached in `bis_item_ids.json`. `--check` says what changed on their pages, `--offline` builds without Wowhead (both daily in CI). | The BiS List's picks, with permission from wowsrc. |
| `build_dungeon_loot.py` | Builds `BiS/NaowhForever_DungeonLoot.lua`: everything a dungeon drops, from Wowhead's zone pages. Also holds the shared Wowhead `fetch`. | So a BiS item can say where it drops. |

## Boss reminders

| Tool | What it does | Why |
| --- | --- | --- |
| `extract_fingerprints.py` | Pulls tank-hit timings and names out of boss mod files. | To know which casts are tank hits. |
| `extract_curated_abilities.py` | Pulls the phase-grouped ability lists out of boss mod files. | Same, for the ability lists. |
| `audit_abilities.py` | Cross-checks our damage sheet against those names. | Finds rows that won't match, to check by hand. |

## Media

| Tool | What it does |
| --- | --- |
| `make_media.py` | Draws our icons into `Media/*.tga`. Change an icon in its function, then run it. |
| `make_navigation.py` | Draws the navigation glyphs. |
| `generate-voice-clips.ps1` | Rebuilds the English voice clips on Windows. |

## Checks and release

| Tool | What it does |
| --- | --- |
| `regression/` | Offline Lua tests against stubs. `bash Tools/regression/run-all.sh` runs them all (set `LUA=` to your lua.exe). |
| `tests/` | Python tests for the tools: `python -m unittest discover -s Tools/tests`. |
| `hooks/check-pr.sh` | PR rules: a CHANGELOG line for addon changes, TOC version untouched. |
| `hooks/check_toc.py`, `hooks/toc_files.py` | Every file the TOC loads exists, with the right letter case. |
| `hooks/check-package.sh` | The built zip has one `NaowhForever/` folder, everything it loads, and no tooling. |
| `hooks/daily-pull-request.sh` | The daily watch's pull request: commits what a job changed, opens the PR or brings the open one up to date, or an issue with a link where workflows may not open PRs. |
| `release.py` | Release helper for `.github/workflows/release.yml`: version bump, notes, changelog. |

## What CI runs

- **Every PR** (`checks.yml`): luacheck and pre-commit, the Lua regression tests, PR rules,
  and a package check.
- **Daily** (`daily-watch.yml`), three jobs. Each opens one pull request when there's
  something (`loot` and `bis` through `hooks/daily-pull-request.sh`, which keeps it up to
  date); where workflows may not open one, an issue with a one-click link:
  - `watch`: `watch_build.py`. Only reads the game's tables through wago.tools. If there's a
    new build, a PR moves our faction data to it, with a report of what changed (new gear
    the Journal doesn't list yet, new dungeon floor maps in the game's map table).
  - `loot`: `wowsrc.py --check`. If wowsrc's loot pages changed (a boss gained or lost items,
    a new boss or page), it rebuilds the Journal with `--offline` and opens a PR.
  - `bis`: `build_bis_data.py --check`, the same for wowsrc's BiS lists.

  `--offline` asks Wowhead nothing: a new item's facts come from the game's own tables, and
  what they can't settle (an old classic item) is listed in the PR for a run on our machines.
- **Not in CI:** anything that reads Wowhead. Their terms don't allow scraping it from a
  server, so a full `build_journal.py` (CI only runs it `--offline`), `build_quest_chains.py`
  and `build_dungeon_loot.py` run on our machines, by hand.
