# Contributing to Naowh Forever

**Feature requests are open, but not every one will be merged. Naowh Forever already
covers a lot, so each addition is weighed on how many players would use it, how much
upkeep it adds and how much code it brings. If you want to build a feature, message
Glyalith on [Discord](https://discord.gg/naowh) before you start.**

Naowh Forever is Naowh's companion addon for the WoW Forever client: BiS, Dungeon
Journal, Completo, Discovery, Training Planner, Professions, Gear Sets, Blessings, Macros,
Action Bars, buff reminders, Threat Meter, Group Inspect, PvP, Swing Timer, Top Bar and QoL,
in one window.

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

4. **Forever only.** This addon targets the Forever client and nothing else, so do not
   add retail branches here. Forever uses classic-era spell
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
- **Follow the house style in [STYLE.md](STYLE.md):** where files go, the order inside a
  file, naming, constants, the feature switches and the shared components.
- Each module has its own folder and loads its files through its own XML file, which its
  TOC lists once, and names its files plainly inside its folder. The Dungeon Journal is the
  example: `NaowhForever_DungeonJournal/DungeonJournal.xml`, with its layout in
  `NaowhForever_DungeonJournal/README.md`. The base addon's areas (`Core/`, `Shared/`,
  `Core/Badges/`, `Core/Integrations/RestedXP/`) load through their own XML files too. Add a
  new file to its area's XML, never to a TOC. The checks read the XML too, so its files are linted and compiled.
- A feature's on/off switch and its default live in `Core/Features.lua`
  (`ns.FEATURES`), and the module's settings read it from there.
- Settings go through `UI.ModuleSettings`, option widgets through the `ns.UI` kit in
  `Core/Options/Widgets.lua`, confirmations through `ns.Confirm` / `ns.PromptText`,
  and movable frames through `UI.AttachMover` so they show up in Unlock Mode.
- One comment per file: its first line, `-- <File>.lua: <what it is>.` Anything a reader
  needs that the code cannot say goes in the module's `README.md`, under Why.

### Shared components

- Build every piece of UI from the shared components: `Shared/` (listed in
  `Shared/README.md`) and the `ns.UI` widgets in `Core/Options/Widgets.lua`. Windows,
  title bars, buttons, tabs, links, borders, fonts, colours, settings cards, confirmations
  and tooltips all have one.
- Never hand-roll a part that already exists, and never copy one into your module to change
  it.
- If a shared part is close but not quite what you need, make it more flexible: add an
  optional input that leaves every current caller working as before.
- If nothing fits, add a new component to `Shared/`, list it in `Shared/README.md`, and use
  it from your module, so the next module can use it too.
- Colours come from `ns.THEME` and `Shared/Style.lua`, never written as numbers in a module.

### Style

- Every colour, size and gap is a named value, with its reason in the README's Why when the
  name alone does not say what it is for: in the module's style file when more than one file uses it (the
  Dungeon Journal's `View/Style.lua`), else at the top of the file that does. No bare
  numbers in drawing code.
- Edges are 1px black: buttons and input boxes have it by default, and a window's own
  panels use the module's black edge colour. The accent is Naowh Blue, `#0091ED`
  (`T.accent`), and a window's main action is edged in it (`ns.AccentBorder`).
- Text goes through `ns.Font`, in the Naowh font. That font leaves room above its
  capitals, so its letters sit under the middle of their font string: an icon beside text
  is moved down to the letters by a named offset with its reason (the Dungeon Journal's
  `PIN_DROP`, the chat badge's `BADGE_DROP`), never an unnamed number. Measure it in game
  rather than guessing.

### Help text

- A settings card's or row's `help`, and a button's tooltip, is **one short sentence**:
  what it does, in a player's words. Aim for under 100 characters.
- Leave out rules, numbers, slash commands, Unlock Mode and edge cases. They belong in
  the CHANGELOG or the module's own window, not in a tooltip.
- If it needs a second sentence, the setting does too much or its label is wrong.

## Changelog and versions

- Write the changelog under `## Changelog` in the PR description, for players: what changed
  for them and where to find it. One line per change, each starting `Added:`, `Changed:`
  or `Fixed:`. The release copies them into `CHANGELOG.md`, so PRs never conflict over it.
- Do **not** touch `CHANGELOG.md`, the TOC `## Version`, `ns.CODE_BUILD` or tags. The
  Release workflow sets them (README, "Releasing a new version").

## Getting set up

- `Libs/` is not in git (the packager fetches it from `.pkgmeta`). Copy the `Libs` folder
  from a release build into your checkout, or the addon will not load.
- Point your Forever `Interface\AddOns\NaowhForever` folder at your checkout (a junction
  or symlink works). `/reload` picks up new files and TOC changes, no restart needed.
- Modules ship as their own addons, in the `NaowhForever_<Module>/` folders at the root of
  the checkout. Point an `Interface\AddOns\NaowhForever_<Module>` folder at each one too. A
  folder the game has not seen before may need a restart to show up in the AddOns list.
- A new module addon gets its own TOC with `## Dependencies: NaowhForever` (and any module
  it needs), `## Group: NaowhForever`, which files it under Naowh Forever in the AddOns
  list, and one file line, its `<Module>.xml`. It also needs a `move-folders` line in
  `.pkgmeta` after the modules it needs, `addon =` on its entry in `MODULES`
  (`Core/Options/Modules.lua`; `needs =` too when it cannot work without another module),
  and its item in the onboarding's list (`Core/Onboarding/Setup.lua`).
- A new global the addon writes goes in `globals` in `.luacheckrc`, a new game API it
  reads in `read_globals`.

## Checks

Every pull request runs these on GitHub. Get them green before you ask for a review.

| Check | What it looks at |
| --- | --- |
| `pre-commit` | luacheck; CRLF and ASCII in addon files; every TOC file exists with the right letter case; valid XML and YAML; merge markers, trailing whitespace, mixed line endings, private keys and files over 5 MB; the workflows through actionlint and zizmor. The list is in `.pre-commit-config.yaml`. |
| `tests` | Every test in `Tools/regression` on Lua 5.1, including `test-syntax.lua`, which compiles every file the TOCs load, so `goto` or `//` fails here instead of at login; and the tools' Python tests in `Tools/tests`. |
| `pr-rules` | Addon changes have a changelog line under `## Changelog` in the PR description, and the TOC `## Version` and `ns.CODE_BUILD` stay as they are. Label the PR `no changelog` when nothing changes for players, or `release` for the release commit. Editing the description re-runs it. |
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
python -m unittest discover -s Tools/tests    # the tools' Python tests
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

## Your responsibility for what you submit

Naowh Forever is a free project that anyone can contribute to. By submitting a PR, you
confirm that:

- the contribution is your own work, or you have the right to submit it: its license, or
  its author's permission, allows it to be included and distributed in Naowh Forever;
- it does not copy code, art, text or data from another addon, game, website or tool
  unless that source's license or terms allow it, and the PR says where anything taken
  from such a source comes from;
- you, not the Naowh Forever maintainers, are responsible for any breach of a third
  party's copyright, license or terms that your contribution contains.

The maintainers review changes for quality and fit, and cannot check where every line
comes from. They accept contributions on the strength of this confirmation. Anything
found to break a third party's rights is removed, and the responsibility for it stays
with the person who submitted it.
