<!-- Thanks for contributing! Please read .github/CONTRIBUTING.md first.
     The checklist below mirrors the acceptance criteria used in review. -->

## What does this PR do?

<!-- Player-facing description: what changes for the player? -->

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
- [ ] Line added under `## Unreleased` in `CHANGELOG.md`; TOC version and `ns.CODE_BUILD` untouched
