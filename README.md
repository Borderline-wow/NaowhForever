# Contributing to Naowh Forever

**Feature requests are open, but not every one will be merged. Naowh Forever already
covers a lot, so each addition is weighed on how many players would use it, how much
upkeep it adds and how much code it brings. If you want to build a feature, message
Glyalith on Discord before you start.**

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
- Do **not** touch the TOC `## Version`, `ns.CODE_BUILD` or tags. That is the release
  commit's job.

## Getting set up

- `Libs/` is not in git (the packager fetches it from `.pkgmeta`). Copy the `Libs` folder
  from a release build into your checkout, or the addon will not load.
- Point your Forever `Interface\AddOns\NaowhForever` folder at your checkout (a junction
  or symlink works). `/reload` picks up new files and TOC changes, no restart needed.
- Offline tests live in `Tools/regression` and run on Lua 5.1:
  `lua5.1 Tools/regression/test-bis-slots.lua .`

## PR etiquette

- One focused change per PR; keep the diff small.
- Screenshots (before and after) for anything visual.
- Fill in the PR template checklist honestly. "N/A" is a fine answer, silence is not.

## Contribution license

By submitting a PR, you keep the copyright to your contribution but grant Naowh Forever
a perpetual, worldwide, royalty-free license to use, modify, incorporate and distribute
it as part of Naowh Forever.
