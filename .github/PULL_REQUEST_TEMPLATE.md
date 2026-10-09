<!-- Thanks for contributing! Please read .github/CONTRIBUTING.md and .github/STYLE.md first.
     Title: "type: summary", e.g. "fix(bag-space): keep the row hidden in combat".
     The checklist below mirrors the acceptance criteria used in review. -->

## What does this PR do?

<!-- Player-facing description: what changes for the player? -->

## Changelog

<!-- One line per change, for players: what changed for them and where to find it. Start each
     with Added:, Changed: or Fixed:. The release copies these into CHANGELOG.md, so don't
     edit that file. Nothing changes for players? Delete this and label the PR "no changelog".
     Example:
     Fixed: Loot Feed: looting coins while the Coins line is up adds to it instead of erroring. -->

## How was it tested?

<!-- Forever client build, what you did in game, which modules were on and off. -->

## Screenshots

<!-- Required for any visual change: before and after. Delete if not visual. -->

## Checklist

<!-- Check what applies; mark N/A where it genuinely does not. -->

**Players**

- [ ] New features and settings default **OFF**, with the switch and its default in `Core/Features.lua`
- [ ] Free while off: no events registered, no hooks doing work, no frames built, no OnUpdate
- [ ] Cheap while on: event-driven, no polling, no table churn in hot paths
- [ ] Works with any other module turned off: no reads of another module's `ns` fields unless it's a declared dependency or the read is guarded
- [ ] Tested in the Forever client, no Lua errors in or out of combat
- [ ] Help text and tooltips are one short sentence

**Safety**

- [ ] No `SetScript` on Blizzard frames (`hooksecurefunc` / `HookScript` only); Blizzard layout frames faded with `SetAlpha`, not hidden
- [ ] Aura reads guarded by `C_Secrets.ShouldAurasBeSecret()` (or N/A)

**Code ([STYLE.md](https://github.com/naowh-gaming/NaowhForever/blob/main/.github/STYLE.md))**

- [ ] Files where STYLE.md puts them: new files added to their folder's XML, never to a TOC, and named plainly
- [ ] One header comment per file and nothing else; anything the code can't say goes in the README's Why
- [ ] No bare numbers: sizes, timings, IDs and colors are named constants
- [ ] UI built from the shared components (`Shared/`, `ns.UI`), nothing hand-rolled or copied
- [ ] New module (or N/A): entry in `Core/Options/Modules.lua`, `.pkgmeta` `move-folders`, its item in `Core/Onboarding/Setup.lua`, a README with Layout and Why
- [ ] Lua 5.1, ASCII only, CRLF line endings

**Checks and release**

- [ ] `luacheck .`, `Tools/regression/run-all.sh` and `python -m unittest discover -s Tools/tests` pass locally
- [ ] `CHANGELOG.md`, TOC version and `ns.CODE_BUILD` untouched
- [ ] My own work, or I have the right to submit it: nothing copied from another addon, site or tool against its license or terms, and I take responsibility for what I submit ([details](https://github.com/naowh-gaming/NaowhForever/blob/main/.github/CONTRIBUTING.md#your-responsibility-for-what-you-submit))
