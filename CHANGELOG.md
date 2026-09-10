# Changelog

## 1.3.3

### Fixed
- Track charge spells across configured presets, including casts before a boss pull,
  and share readiness between base and replacement spell IDs.
- Restore only completed charge recharges instead of prematurely filling the stack.
- Retry an empty early warning until its boss timer expires, allowing a cooldown
  that becomes ready during that window to be called once.
- Exclude BigWigs cast bars from timer reminders, including Chillstorm uptime.
- Exclude the verified Demonic Rage uptime bar and message on Xathuux.

### Validation
- The reporter confirmed in-game testing of the fixes.
- Fiery Brand has automated coverage; no separate live Fiery Brand result was supplied.
- Unknown ordinary uptime bars retain the existing filtering behavior.

## 1.3.2

### Fixed
- Removed a charge-tracking fallback that could mark an empty defensive as ready
  before its recharge finished, causing callouts for unavailable abilities such
  as Death's Advance.

## 1.3.1

### Fixed
- Exclude developer tools and regression scripts from release packages.

## 1.3.0

### Added
- Dedicated Profiles tab for profile management and import/export.
- Minimap launcher with the NaowhUI logo and a saved, draggable position.
- Reminder Font selector shared by defensive, ability, and raid reminder text.
- Hide After Casting toggle, off by default. Dismissal uses the displayed icon
  independently of speech; protected visibility falls back to the display timer.

### Changed
- Icon Display Duration defaults to 3 seconds, adjustable from 1 to 15 seconds.
  Existing profiles retain their saved duration.
- Removed Where It Runs and its global dungeon/raid gates. The main enable
  switch and per-boss choices remain in control.
- Bundled the NaowhUI logo for the addon-list icon and colored Naowh blue in the title.

### Fixed
- Charge tracking could spend a charge twice, invent one after a failed read,
  or credit the same recharge twice. Death's Advance recovery and callouts were
  verified in Ruby Life Pools on the test build.
- Skipped warnings and warnings with empty or unusable presets no longer erase
  the previous icon before its display timer expires.

## 1.2.0

### Changed
- Importing a pack names each row by its spec rather than its class. A Warrior's
  three rows all read "Warrior (DPS)" and "Warrior (Tank)" before, with no way
  to tell Arms from Fury; they now read "Protection (Tank)", "Arms (DPS)",
  "Fury (DPS)". Class colouring is unchanged, and it is what tells apart the
  four spec names that belong to two classes each.

### Added
- Select All and Deselect All on the pack import, beside the name field. A pack
  can carry all forty specs, so bringing in one or two of them meant thirty
  eight clicks of turning the rest off.

## 1.1.2

### Fixed
- A defensive with charges could be called while you had none of them. At zero
  charges the spell's cooldown is not running, and the charge tracker read that
  idle cooldown as proof a charge was in hand, so it handed itself one. Death's
  Advance was named at 0 of 2 on Rav'i because of it. The tracker now believes
  the client when it says a charge is still recharging.
- Where the game will state your real charge count, which is everywhere outside
  a dungeon or raid, that count is now used instead of the tracked estimate. The
  estimate could only drift, and had nothing to correct itself against for the
  rest of the session once it had.

## 1.1.1

### Fixed
- A flood of "table index is nil" errors while BigWigs' options or Edit Mode
  were open. The preview bars BigWigs raises there are not real boss timers and
  carry no ability, and filing one under the ability it does not have was the
  error. Those bars are now ignored, which is what should have happened anyway:
  there is nothing to remind anyone about.

## 1.1.0

### Added
- Window Scale, on the setup page under Options Window. Sets the size of the
  options window and every editor it opens, from 50% to 100%, for people whose
  screen the config UI did not fit on. Saved for the computer rather than in
  the profile, so switching profile leaves it alone and an exported pack never
  carries it to someone on a different monitor.

## 1.0.1

### Fixed
- Reminder Packs could not be imported or exported on the CurseForge and Wago
  builds, which reported "The serializer libraries are missing from this
  build." Those builds pulled an unrelated library that shares the LibSerialize
  name, so nothing registered the serializer the pack code reads. Local
  installs were never affected.

### Changed
- The version moves on every release now, so the number in the TOC and beside
  the build stamp identifies which files a report came from. Three separate
  1.0.0 files were published while this was not the case.

## 1.0.0

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
  external is already up, for as long as you set Your Own Cast Covers You For.
  On a tank spec, boss callouts fire only for the tank the boss is actually on;
  DPS and healer specs are never gated.
- Call Together: tick two or more cooldowns on a preset and they are called as
  one -- "Vampiric Blood and Icebound Fortitude" -- showing as a single row
  named for the call. One on cooldown is left out rather than holding the
  callout back.
- Equipped on-use trinkets sit in the cooldown preset picker beside the spec's
  own defensives, and the list follows a gear swap without a reload.
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
- Callouts on any spec, not only ones with a tank role. A raid-wide hit a DPS
  answers with a personal is the same question a tank buster asks, put to
  somebody else. Adding an ability for a spec is the opt-in, and abilities are
  stored per spec, so a spec nobody has set up still calls nothing.
- Call for an External is decided per ability as well as per spec, from that
  ability's own cog, for hits the raid was never going to answer.
- Warning Time takes a negative number, calling a defensive that many seconds
  AFTER a mechanic lands rather than before it, for a hit whose useful moment
  is once it is over.
- Copy All Dungeons / All Raids From a Spec, at the top of the boss lists:
  another spec's whole setup in one press, instead of repeating the per-boss
  copy on every boss. Raids and dungeons stay on their own side, and anything
  the target spec already has is kept.
- Saving a profile under a name already taken offers to overwrite it, naming
  the profile and what replacing it costs, rather than refusing.
- A boss page with nothing on this spec says whether the profile has work under
  other specs, since an empty page otherwise reads as lost data.
- `/nutank tanksheet` cross-checks the curated tank-ability list against the
  Dungeon Journal, separating entries the journal contradicts from ones it
  simply has no role flag for.

### Changed

- Ability Reminders is marked coming soon: the tab is dimmed and opens a note.
  The same reminders are authored per boss in the meantime, which is where that
  page reads them from.
- Importing a pack never overwrites anything. It lands as a new profile under a
  name you choose, so going back to your own profile finds it as you left it,
  and a pack that does not mention a spec no longer drops the one you had.
- A whole profile exports in one string, every spec it holds, with the display,
  sound and behaviour settings alongside it for the importer to take or leave.

### Fixed before release

Found by testers on live keys and raid nights between the release branch being
cut and 1.0.0 going out.

- Tank callouts fired for both tanks on abilities the addon could not attribute
  to a boss unit. Every ability in the pool was checked against its BigWigs or
  LittleWigs module and given the slot that casts it, so a call now goes to the
  tank holding that boss. Abilities whose module never settles a slot keep the
  old behaviour rather than risk silencing a real one.
- A tank holding an add that occupied a boss frame was called for the boss's
  own ability, most visibly on Ula'tek.
- Threat momentarily reading low -- mid-cast, across a stage change, while a
  boss was untargetable -- refused callouts for the tank who had the boss the
  whole time.
- Charge defensives could read ready while on cooldown: a spell's cooldown was
  being stored as its recharge, and for Guardian of Ancient Kings those differ
  by nearly three minutes.
- A repeating ability called on some casts and not others. A boss mod's bar for
  the next cast replaced the callout already due for the current one, and a
  second announcement of the same cast could cancel the next one outright at
  short warning times.
- A debuff bar sharing an ability's spell id could take that ability's callout
  with it when it expired.
- A defensive was named over one still running.
- Rav'i's Triple Shot was treated as a tank hit. Blizzard's own Journal calls it
  a healer mechanic and it is not threat-driven, so it no longer carries the
  tank-hit sound or the tank tag in the ability picker.
- Two boss abilities landing within a second of each other, as Entombed
  Sentinels' do, announced the same defensive twice. A repeat of the same pick
  is now muted for three seconds across different abilities, while a genuine
  repeat of the same ability seconds later still gets its own line.
- Raid-frame glow did nothing for anyone using EllesmereUI raid frames, with no
  error. The library it asks first returns nothing for those frames, so the
  buttons are now looked up directly when it comes up empty.
- The options window opened with every tab blank. One file had passed Lua's
  200-local ceiling and stopped compiling, taking every page builder with it.
- A dropdown could open behind the row below it, a colour swatch could go
  unreachable, and the ability editor's layout could overlap at some sizes.
