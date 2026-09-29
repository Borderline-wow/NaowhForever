# Contributing to Naowh Forever

**Feature requests are open, but not every one will be merged. Naowh Forever already
covers a lot, so each addition is weighed on how many players would use it, how much
upkeep it adds and how much code it brings. If you want to build a feature, message
Glyalith on [Discord](https://discord.gg/naowh) before you start.**

Naowh Forever is Naowh's companion addon for the WoW Forever client: Smart Reminders,
BiS, Dungeon Quests, Professions, Gear Sets, Swing Timer, Threat Meter, QoL, macros and
buff reminders, in one window.

Thanks for wanting to help! Pull requests are welcome. This document explains how PRs
are reviewed and the rules the codebase lives by, so your change can merge quickly
instead of bouncing through review rounds.

**Building something bigger than a fix? Message Glyalith on Discord first** and describe
what you want to build. It is much better to agree on the approach before you write
500 lines of code.

## How a change gets in

1. Fork the repo and branch off the latest `main`.
2. Make one focused change, test it in the Forever client, and open a PR against `main`.
3. Fill in the PR template. I review every PR and test it in game before it merges.
4. Only the maintainer merges. Releases are cut separately: the version bump is its own
   commit, and the release tag posts the changelog to Discord.

## The five acceptance criteria

Every PR is reviewed against all five. If one is missed the PR will be closed with a
comment, sent back for changes, or merged and fixed up by me.

1. **Off by default, free while off.** New features and new settings start **OFF**. A
   player who never turns your feature on must pay nothing for it: no events registered,
   no hooks doing work, no frames built, no OnUpdate. Build on first enable and register
   events only while the feature is on. Only real bug fixes may change behavior for
   everyone.

2. **Cheap while on.** Event-driven, not polling. Use OnUpdate only while something is
   actually animating or counting down, and stop it when it is done. No table churn in
   hot paths.

3. **No taint, no Lua errors.** A feature that can throw in combat or taint Blizzard's
   UI will not be merged.
   - Never drive Blizzard's own UI functions from addon code to open or refresh their
     frames (calling `QuestMapFrame_OpenToQuestDetails` tainted the whole world map).
   - Never `SetScript` on Blizzard frames; use `hooksecurefunc` / `HookScript`.
   - Do not `Hide()` Blizzard frames that other Blizzard code lays out; fade them with
     `SetAlpha` instead (hiding the XP bar containers tainted the action bars).
   - Aura data goes secret during boss pulls, before `InCombatLockdown()` turns true.
     Guard aura reads with `C_Secrets.ShouldAurasBeSecret()` and freeze while it is true.
   - The combat log is closed to addons on Forever.

4. **Forever only.** This addon targets the Forever client. Retail Smart Reminders lives
   in its own repo, so do not add retail branches here. Forever uses classic-era spell
   IDs (retail IDs do not match) and does not load Blizzard's deprecated shims, so use
   the current API (`C_SpellBook.IsSpellKnown`, not `IsPlayerSpell`). Look IDs up on
   [Wowhead Forever](https://www.wowhead.com/forever).

5. **Your own code.** Do not copy code from other addons. Matching another addon's
   behavior is fine; lifting its source is not. Data scraped from a site needs that
   site's permission.

## Code style

- **Lua 5.1 only.** No `goto`, no `::labels::`, no integer division.
- **ASCII only** in code, comments and strings. No em dashes, no curly quotes.
- **CRLF line endings.** `.gitattributes` sets `* -text` so git never converts them.
  Keep your editor on CRLF, and never `sed -i` from Git Bash, which strips them.
- **Match the surrounding code.** Before building an options row, slider or popup, find
  the nearest existing example in the same module and copy its shape.
- Each module has its own folder with `NaowhForever_<Name>.lua` files. Add new files to
  `NaowhForever.toc` next to the rest of that module's files.
- Settings go through `UI.ModuleSettings`, option widgets through the `ns.UI` kit in
  `Core/NaowhForever_Widgets.lua`, confirmations through `ns.Confirm` / `ns.PromptText`,
  and movable frames through `UI.AttachMover` so they show up in Unlock Mode.
- Keep comments short and only where the code cannot speak for itself.

## Changelog and versions

- Add a line under `## Unreleased` in `CHANGELOG.md`, written for players: what changed
  for them and where to find it.
- Do **not** touch the TOC `## Version`, `ns.CODE_BUILD` or tags. The Release workflow
  sets them (README, "Releasing a new version").

## Getting set up

- `Libs/` is not in git (the packager fetches it from `.pkgmeta`). Copy the `Libs` folder
  from a release build into your checkout, or the addon will not load.
- Point your Forever `Interface\AddOns\NaowhForever` folder at your checkout (a junction
  or symlink works). `/reload` picks up new files and TOC changes, no restart needed.
- A new global the addon writes goes in `globals` in `.luacheckrc`, a new game API it
  reads in `read_globals`.

## Checks

Every pull request runs these on GitHub. Get them green before you ask for a review.

| Check | What it looks at |
| --- | --- |
| `pre-commit` | luacheck; CRLF and ASCII in addon files; every TOC file exists with the right letter case; valid XML and YAML; merge markers, trailing whitespace, mixed line endings, private keys and files over 5 MB; the workflows through actionlint and zizmor. The list is in `.pre-commit-config.yaml`. |
| `tests` | Every test in `Tools/regression` on Lua 5.1, including `test-syntax.lua`, which compiles every file the TOC loads, so `goto` or `//` fails here instead of at login; and the release script's tests in `Tools/tests`. |
| `pr-rules` | Addon changes add a line under `## Unreleased` in `CHANGELOG.md`, and the TOC `## Version` and `ns.CODE_BUILD` stay as they are. Label the PR `no changelog` when nothing changes for players, or `release` for the release commit. |
| `package` | The release packager builds the zip without uploading it, then every TOC file and library must be inside and no tooling may ship. |
| `title` | The PR title is `type: summary` (see [PR etiquette](#pr-etiquette)), since a squash merge turns it into the commit on main. |

Actions and hooks are pinned by commit SHA, and Dependabot opens a weekly PR for new
versions.

### Run them on your machine

After `pre-commit install`, the checks run by themselves on every `git commit`, on the
files you changed, and your commit message is checked too. Use luacheck **1.2.0**, the
version CI runs; older ones warn differently. `.luacheckrc` has a baseline of warnings
that were already in the code: fix one and remove its entry, but never add entries to
get a check passing.

**Windows** (PowerShell):

1. Install Python and Lua 5.1:

   ```powershell
   winget install Python.Python.3.12
   winget install rjpcomputing.luaforwindows
   ```

2. Download `luacheck.exe` 1.2.0 from the
   [luacheck releases](https://github.com/lunarmodules/luacheck/releases/tag/v1.2.0), put
   it in a folder such as `C:\tools`, and add that folder to your user `PATH`.
3. Open a new terminal, then install pre-commit:

   ```powershell
   py -m pip install --user pipx
   py -m pipx ensurepath
   pipx install pre-commit
   ```

**macOS:**

```sh
brew install pre-commit luacheck luajit
```

Homebrew has no Lua 5.1, so the tests run on LuaJIT: `LUA=luajit bash
Tools/regression/run-all.sh`. LuaJIT accepts `goto`, so `test-syntax.lua` only catches
that in CI.

**Linux** (Debian and Ubuntu):

```sh
sudo apt install pre-commit lua5.1 liblua5.1-dev luarocks
sudo luarocks install luacheck 1.2.0-1
```

The `lua-check` package is an older luacheck, so it comes from LuaRocks instead. On other
distributions: `pipx install pre-commit`, `luarocks install luacheck 1.2.0-1`, and your
package manager's Lua 5.1 (or LuaJIT).

**Then, on every OS**, from the repo root:

```sh
pre-commit install              # checks on every commit from now on
pre-commit run --all-files      # everything, once
bash Tools/regression/run-all.sh
python -m unittest discover -s Tools/tests    # the release script
bash Tools/hooks/check-pr.sh origin/main
```

On Windows, run the last two from Git Bash and point the tests at your Lua:
`LUA="/c/Program Files (x86)/Lua/5.1/lua.exe" bash Tools/regression/run-all.sh`.

If a hook fails, it prints the file and line: fix it and commit again. Skipping hooks with
`--no-verify` only moves the failure to the pull request.

## PR etiquette

- One focused change per PR; keep the diff small.
- Commit messages and PR titles follow Conventional Commits: `type: summary` or
  `type(scope): summary`, e.g. `fix(bag-space): keep the row hidden in combat`. Types:
  `feat` (new for players), `fix` (a bug), `perf`, `refactor`, `docs`, `test`, `ci`,
  `build`, `chore`, `revert`. A squash merge turns the PR title into the commit on main.
- Screenshots (before and after) for anything visual.
- Fill in the PR template checklist honestly. "N/A" is a fine answer, silence is not.

## Contribution license

By submitting a PR, you keep the copyright to your contribution but grant Naowh Forever
a perpetual, worldwide, royalty-free license to use, modify, incorporate and distribute
it as part of Naowh Forever.
