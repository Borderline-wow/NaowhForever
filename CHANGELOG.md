# Changelog

## 1.1.0

First release.

### Added
- Boss ability reminders driven by BigWigs or DBM. Pick the boss addon under
  Hook Into; every reminder rides its bars and messages rather than a timeline
  of our own.
- Dungeon Bosses and Raid Bosses tabs: this season's pool read from your own
  Dungeon Journal, with an ability picker per boss. Boss pages start blank and
  abilities are added deliberately.
- Cooldown Presets: named lists of defensives, stored per spec. A preset binds
  to an ability, with its own warning time.
- Callout display: icon and text with independent anchors, sizes and colours,
  placed from the Customize Anchors toolbar.
- Ability Reminders, assignable to a role, class, spec, name or subgroup with
  AND/OR combinations. Text, icon, bar, ring, timer, chat line, text-to-speech,
  nameplate glow and raid-frame glow displays.
- Triggers: a boss mod bar or message, a cast starting or finishing, a phase
  starting, time after pull, time in combat, and an aura applied at a stack
  threshold.
- Skip When Already Covered, which drops a call when a big defensive or
  external is already up, and Only While I Have the Boss, which gates tank
  callouts on the unit actually casting.
- Announce in Chat, including calling for an external by name.
- Observed timings: what the boss actually did on your own pulls, recorded per
  difficulty, with a reminder built from one click.
- Reminder Packs: a whole profile as one string, with preview before apply.
- Standalone options window at `/smartreminders`, `/nsr` or `/naowh`. Own
  theme, widget kit, profiles and SavedVariables, with no EllesmereUI
  dependency.
- Diagnostics under `/nutank`: `status`, `cds`, `keys`, and a trace recorder
  with a copyable export. Pretend Tank lets a DPS reproduce a tank-buster
  report.
- Every option ships off by default.
