<!-- Thanks for contributing! Please read .github/CONTRIBUTING.md first.
     Title: "type: summary", e.g. "fix(bag-space): keep the row hidden in combat".
     The checklist below mirrors the acceptance criteria used in review. -->

## What does this PR do?

<!-- Player-facing description: what changes for the player? -->

## Changelog

<!-- One line per change, for players: what changed for them and where to find it. Start each
     with Added:, Changed: or Fixed:. The release copies these into CHANGELOG.md, so don't
     edit that file. Example:
     Fixed: Loot Feed: looting coins while the Coins line is up adds to it instead of erroring. -->

## How was it tested?

<!-- Forever client build, what you did in game, any regression tests run. -->

## Screenshots

<!-- Required for any visual change: before and after. Delete if not visual. -->

## Checklist

<!-- Check what applies; mark N/A where it genuinely does not. -->

- [ ] New features and settings default **OFF** (no behavior change without opt-in)
- [ ] Free while off: no events registered, no hooks doing work, no frames built, no OnUpdate
- [ ] Cheap while on: event-driven, no polling, no table churn in hot paths
- [ ] No `SetScript` on Blizzard frames (`hooksecurefunc` / `HookScript` only); Blizzard layout frames faded with `SetAlpha`, not hidden
- [ ] Aura reads guarded by `C_Secrets.ShouldAurasBeSecret()` (or N/A)
- [ ] Tested in the Forever client, no Lua errors in or out of combat
- [ ] Lua 5.1, ASCII only, CRLF line endings
- [ ] Changelog line above; `CHANGELOG.md`, TOC version and `ns.CODE_BUILD` untouched
- [ ] My own work, or I have the right to submit it: nothing copied from another addon, site or tool against its license or terms, and I take responsibility for what I submit ([details](https://github.com/nwh-gaming-ab/NaowhForever/blob/main/.github/CONTRIBUTING.md#your-responsibility-for-what-you-submit))
