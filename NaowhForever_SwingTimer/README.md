# Swing Timer

One bar per weapon that can swing (Main Hand, Off Hand, Ranged), driven by Forever's own
`PLAYER_SWING` event. On top of the bars, each off until turned on: a window at the end of the
melee swing, the Auto Shot cast window on a hunter's Ranged bar, a tick where the current cast ends,
and a Target bar estimated from the melee hits you take. Queued attacks (Heroic Strike, Cleave,
Maul, Raptor Strike) and a paladin's seal color the melee bars. Its settings page is Swing
Timer/Settings; its on/off switches and their defaults come from `ns.FEATURES.swingTimer`.

## Layout

```
NaowhForever_SwingTimer/
  NaowhForever_SwingTimer.toc   the addon; lists only SwingTimer.xml
  SwingTimer.xml                every file, in load order
  SwingTimer.lua                the settings (ns.SwingTimerSettings), the module table (ns.SwingTimer, ST),
                                whether the client has the swing event, and the bars' colors
  Constants.lua                 the names, timings and textures its files share (ST.C)
  Data/
    Spells.lua                  the next-swing attacks and paladin seals, by spell ID (ST.SPELLS)
  View/
    Bar.lua                     a bar's look, on screen and on the previews (ST.Look)
  UI/
    Bars.lua                    the bars on screen: swings, seals, queued attacks, range, the timing aids
    SettingsPage.lua            its settings page, declared as cards, with its previews
  README.md                     this file
```

## Why

- The server hands over each swing's real duration with `PLAYER_SWING`, so parry haste, swing
  resets, extra attacks and haste are already in it; nothing guesses from the combat log, which
  addons cannot read on Forever. The module needs Forever's swing event, its enum, the bar timer the
  fill runs on and the text binding the countdown runs on (`SUPPORTED`); without them it stays off.
- A restricted answer from the swing API or a unit query is "no information", never a value.
- The engine animates the fill and the countdown from a duration object (`SetTimerDuration`, a
  duration text binding), so no Lua runs per frame; the only Lua left is one timer per swing to catch
  its end. The countdown shows tenths of a second, rounded up so the last moment never reads 0.0.
- The next swing's `PLAYER_SWING` can land a moment after the predicted end of the last one; a bar
  waits `END_GRACE` before going idle, so Hide When Idle does not blink between swings.
- The bars from the top down are named by the label each shows (MH, OH, R, TGT); a bar's color
  setting is its label in lower case plus "Color". `SPEED_RETURN` is which of `UnitAttackSpeed`'s
  returns is the bar's weapon speed. The Target bar's key, `"target"`, is not a swing type, so it never
  reaches `C_SwingTimer`.
- Main Hand is always there; the others need a weapon with a speed, and the Target bar a living
  enemy targeted. A haste proc in combat can make the speed read restricted; the bar then goes on
  with the last speed it read, and a swing proves the weapon is there while its speed reads
  restricted, its length standing in for the speed.
- The engine keeps one range flag per swing type, shared with Blizzard's own timer, which only
  re-sends its flag when its own state changes. So the bars only ever turn the flag on, again on every
  refresh and every swing, in case Blizzard's timer turned it off; a bar that does not want range
  ignores the range events. `IsTargetWithinSwingRange` gives nil when there is nothing to measure.
- A weapon swap restarts the swing at the new weapon's speed without a `PLAYER_SWING`, as Blizzard's
  own timer assumes too.
- The swing end window sits at the end the swing lands on: the right while filling, the left while
  depleting. Auto Shot's cast is `AUTO_SHOT_CAST` (half a second) at the end of the ranged cycle;
  moving inside it holds the shot, so the window turns red. Add Latency widens both by your world
  latency.
- The cast tick marks where the current cast ends on the Main Hand swing in flight, pinned to the
  end in the clip color when the cast will still be going as the swing comes due.
- The Target bar restarts on each physical hit you take (`UNIT_COMBAT` with a melee action: wound,
  miss, dodge, parry, block, deflect, absorb, immune, evade) while it is targeting you. Parry haste on
  the target: with more than 60% of its swing left a parry takes 40% of the swing off; between 20%
  and 60% the rest drops to 20%. A duel starting, a mob turning hostile or the target dying shows or
  hides it.
- Next-swing attacks by class: Heroic Strike (78) and Cleave (845) for warriors, Maul (6807) for
  druids, Raptor Strike (2973) for hunters. All share Queued Attack Colour unless `QUEUE_OWN_COLOR`
  gives one its own (Cleave). `ACTIONBAR_UPDATE_STATE` fires constantly in combat, so it is listened
  to only while there is a queued attack to watch for.
- Paladin seals are listed by their first rank: every rank shares the seal's name, which is what is
  matched. Seal of Fury is Forever's own. Forever's Judgement does not consume the seal, so a
  Judgement leaves the seal's colour and count as they are. A seal lasts 30 seconds, 34 with the
  Seal Duration Increase item effect; a seal buff that can be read replaces this with its real
  length. Nothing in combat says a seal has run out, so it is counted from the cast, or from its buff
  when that could be read. In combat the game keeps the player's auras from addons, so there the seal
  is the last one cast; out of combat, and off a boss pull, the auras say which is up.
- Unlock Mode shows every bar full with a sample time so there is something to drag; a running swing
  is parked first, or its end would empty the sample under the mover.
- A slider drag sets its key on every step, so settings apply once on the next frame.
- The color defaults take a copy of the shared style's colors, so a saved color never writes into the
  shared style. Apply Theme to Bar Colours paints the main hand bar in the theme's Accent, the off hand
  bar in its lighter Accent and the ranged bar in a deeper shade of it (`RANGED_SHADE`), so the three
  stay apart.

## Checking

- `lua Tools/regression/test-swing-timer.lua`: the bars, swings, range, the timing aids, seals and
  queued attacks, against stubs of Forever's swing API.
- `lua Tools/regression/test-theme-hud.lua`: the themed bar colors.
