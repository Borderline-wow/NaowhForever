# Threat Meter

Threat on your target (or focus) for everyone in your group, one bar each, sorted, with an
optional aggro line and a warning sound. Its settings page is Threat Meter/Settings, where the
Meter card's preview edits in place: its corner, wheel, clicks and row menu set the settings. Its
on/off switches and their defaults come from `ns.FEATURES.threatMeter`.

## Layout

```
NaowhForever_ThreatMeter/
  NaowhForever_ThreatMeter.toc   the addon; lists only ThreatMeter.xml
  ThreatMeter.xml                every file, in load order
  ThreatMeter.lua                the settings (ns.ThreatMeterSettings), their migrations and the module
                                 table (ns.ThreatMeter, TM)
  Constants.lua                  the sizes and names its files share (TM.C)
  Data/
    Samples.lua                  the sample groups the previews show (TM.SAMPLES)
  Threat.lua                     whose threat to read, on which mob, sorted, and when to warn
  View/
    Meter.lua                    the meter's look and layout, on screen and on the preview (TM.Look)
  UI/
    Meter.lua                    the window: drag, resize, scroll, updates (ns.PreviewThreatMeter)
    SettingsPage.lua             its settings page, declared as cards, with the editable preview
  README.md                      this file
```

## Why

- Forever hands the threat API over readable; a value that does come back secret skips that unit,
  and only a readable "no" from `UnitIsUnit` skips a threat list update, since a secret answer may
  still be the shown mob.
- Forever returns threat in display units already, not the x100 scale Classic's API uses.
- `pullPct` is how close a unit is to pulling aggro (100 takes it), `tankPct` its share of the
  tank's threat. Your threat over how close you are to pulling is the threat that pulls: the aggro
  line.
- Equal threat keeps the read order, so rows do not swap places between updates. Threat entries are
  reused, one per unit seen. Each member token is followed by its pet's, so every odd slot is a
  member, and Ignore Pets steps over the even ones.
- The meter watches your target, or your focus with Focus Tracking. The saved source stays "focus"
  after Focus Tracking is turned off; the meter goes back to the target. A friendly target shows the
  enemy it is fighting (a healer targeting the tank).
- `UNIT_THREAT_LIST_UPDATE` names a real unit token (target, a nameplate, a boss), never
  targettarget, so while the meter follows a friendly target's enemy nothing reports that mob's
  threat moving. It reads again every `FOLLOW_INTERVAL` in that one case, and only in combat.
- The warning sounds once when your threat crosses the threshold, and rearms below it and for each
  new mob. Not While Tanking skips it in a tank role or in Bear Form, Dire Bear Form or Defensive
  Stance (shapeshift form IDs 5, 8 and 18).
- The window's own blue-tinted dark scheme (`WINDOW_BG`, `WINDOW_EDGE`, `HEADER_BG`, `ROW_BG`)
  follows the player's theme through `ns.ThemeTint`; the background follows the theme until a color
  is picked. Your own row's highlight is the theme's accent darkened (`OWN_DARKEN`), or its own tint
  (`OWN_ROW`) with the shipped theme.
- Apply Theme to Your Bar paints your bar in a darker shade of the theme's Accent (`YOUR_SHADE`), so
  the white names and numbers stay readable on it. The tank bar and the aggro line keep their own
  colors, which tell the roles apart. The shade is built once, on first use, after the theme is
  applied.
- The color defaults take a copy of the shared style's colors, so a saved color never writes into
  the shared style.
- Hide When Empty became a Show option, migrated once per profile: on (the old default) becomes With
  Threat, also for In Combat, since a mob only has a threat list while it is being fought; off keeps
  showing when empty. In a Group cannot hide the empty window any more.
- Bar Texture became the SharedMedia list: Naowh Gradient is the meter's own texture, Flat is Solid.

## Checking

- `lua Tools/regression/test-threat-meter.lua`: reading, sorting, the aggro line, the warning, focus,
  the window and the editable preview.
- `lua Tools/regression/test-combat-perf.lua`: an update with 20 bars and a burst of threat events.
- `lua Tools/regression/test-theme-hud.lua`: the window's colors and the themed bar.
