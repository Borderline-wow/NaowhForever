# Smart Reminders repository instructions

Before touching WoW code:

1. Read ./CLAUDE.md in full, including the project context it references.
2. Read ./docs/WOW_DEVELOPMENT.md in full.
3. Read applicable parent/nested instructions, current contribution rules, and the affected source.

These files supplement existing project conventions. Read each unchanged document once per session; do not recurse between entry points. Explicit user instructions and higher-priority agent instructions govern task scope. Verified target-client API/security constraints govern implementation. Preserve repository architecture and ask only when an unresolved conflict requires a user decision.

## Project rules and source map

- Read NaowhSmartReminders.toc before editing. The installed addon name and Lua filename prefix differ; preserve packaging paths and global entry points.
- Core owns the database, profiles, theme, and shared primitives. Widgets owns ns.UI; Window owns the standalone options shell.
- NaowhUI_SmartReminders.lua owns the main runtime; Abilities holds spell data; RaidReminders extends shared scheduling; Packs handles sharing; Bosses, Observed, and Note provide supporting data/UI.
- Reuse the existing scheduling and boss-mod bridges instead of adding a second timer/event system.
- Preserve NaowhUI_SmartRemindersDB and existing profile/import formats. Imports must retain their preview-before-apply flow.
- Keep optional media and boss-mod integrations optional. Verify their actual callback contracts before modifying integrations.
- Test reminder cancellation, duplicate suppression, encounter transitions, profile changes, disabled reminders, and sound/display timing when those paths change.
- Keep ability readiness and charge handling within verified current API contracts. Do not infer unavailable combat state.
- Use Tools and existing CI checks where relevant. Do not change release metadata, generated packs, or sibling worktrees merely to make a local fix.
