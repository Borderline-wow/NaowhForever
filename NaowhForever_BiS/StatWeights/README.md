# Stat Weights

What each stat is worth to your spec, and so how much stronger an item makes you over what
you wear. Every spec has default weights; players change any of them in its window (the
scales on the BiS List's title bar), and only their changes are kept, for the account. Off by default.

- **Always on, for the BiS List:** its best enchant per slot and the upgrade percent on each
  BiS and on Run Next use these weights (yours where you changed them).
- **On (Upgrades on Tooltips):** a line on the tooltip of gear that is an upgrade for your spec,
  in its name: "Fire: (arrow) +9% upgrade", and under it what the item is weighed against.
  Nothing on gear that is not one. A ring or trinket is weighed against the weaker of the two
  you wear, a two-hander against both hands.

Your spec is Automatic: the talent tree you spent the most points in (Forever keeps one spec
per class, its three trees as the talent tree's groups, read as its own talent frame reads
them), or the one you pick.

The switch and your spec are a card on the BiS List's settings page. The window has a switch
between your class's specs and a sample of the tooltip line; on the left only the stats the spec
uses, each a bar (how much it counts next to the others) and a number to type over, percents
and weapon dps under their own title, a changed one marked with its own reset. 0 takes a stat
off; Add a stat puts one on at 0 for your number. On the right, your BiS list's best upgrades
by these weights, so a change shows what it does. Import, Export and Reset are on its title bar. Export copies your changes as a line (`NFSW1:spec:stat=value,...`, only
what differs from the defaults); Import takes one, or a WoWSims EP export (Stat Weights, Copy to
Current EP, Export), which replaces the spec's weights. An enchant's weapon damage is worth a
point of dps over the weapon's speed, so it has no weight of its own.

Forever's gear carries hit, crit, haste, dodge and block as ratings, read as their percent at
60 (10 hit rating is 1%; `PER_PERCENT` in `StatWeights.lua`). Hit and crit are one rating each
for weapons and spells alike, so a hit item counts for Hit % and Spell Hit %, and a crit item
for Crit % and Spell Crit %: a spec weighs the one it uses.

The defaults are estimates for now (dated in the window's footer); simulated weights from WoWSims will
replace them once its Forever sim is out.

The percent is the item's weighted stats minus what you wear there, over what your stats are
worth now (your five stats as the game sums them, the rest from your gear; a weapon's damage
per second counts too, the off hand's at half, a hunter's ranged weapon's instead). An
estimate: it orders upgrades, it does not promise a number on a meter.

## Layout

```
StatWeights/
  StatWeights.xml      what loads, in order (the addon's BiS.xml includes it)
  Data/Defaults.lua    each spec's default weights, by hand (ns.StatWeightDefaults)
  StatWeights.lua      its settings, the stats and the game's keys for them, specs, your talents' spec,
                       your changes (ns.StatWeights)
  Worth.lua            an item's stats and worth, your power, the gain and best gain (SW.Gain, SW.BestGain)
  Sharing.lua          a spec's weights as a line, and back, or a simulator's export (SW.Export, SW.Import)
  Tooltip.lua          the tooltip line, installed the first time the module is turned on
  UI/Window.lua        its window: your spec's stats as bars and numbers, your best upgrades, reset, share
  UI/SettingsPage.lua  its card on the BiS List's settings page: the switch and your spec
```

## I want to change...

| What | Where |
| --- | --- |
| A spec's default weights | `Data/Defaults.lua` (its role's, then the spec's own) |
| A stat players can weigh | `STATS` and `GAME_KEYS` in `StatWeights.lua`, and its group in `UI/Window.lua` |
| The tooltip line | `Tooltip.lua` |

## Why

- The defaults are for level 60, measured in the spec's anchor at 1: its main stat for a fighter,
  Spell Damage for a caster, Healing for a healer, Stamina for a tank. A percent is worth that many
  anchor points per 1%, and dps a point of a weapon's damage per second (14 attack power's worth).
- `PER_PERCENT` is a rating's points per 1% at 60, as the game's tooltips read them (10 hit rating is
  "1.0%"); the weights are per 1%.
- A weapon's damage per second counts whole in the main hand, half in the off hand, and a hunter's
  ranged weapon's only. `SPEED` (2.6) stands in when the game has no weapon speed to give.
- A druid's Feral tree is weighed for damage; a bear picks Feral Tank by hand. Forever keeps one spec
  per class and its three classic trees as the talent tree's groups, which its own talent frame reads
  the same way (`C_Traits`' group display and currency info); read once, and again after a talent
  change.
- The spec you weigh by: the one picked on the page, else your talents' (Automatic), else your BiS
  list's, else your class's first.
- Your changes are kept only where they differ from the default (closer than `SAME` is the default).
- An item's stats are read once, at most `CACHE_MAX` items; then the cache starts over, so hovering
  everything stays bounded.
- While the game keeps your stats secret, a gain is measured against your stats' worth and weapon
  speeds from just before; they are forgotten when your gear or level changes, so no gain is shown
  from numbers that no longer hold.
- Under `MIN_GAIN` (half a percent) is no upgrade. A ring or trinket is weighed against the weaker of
  the two you wear, a two-hander against both hands. The game files a cloak under cloth; everyone
  wears one, so its subclass is read as 0 for the class rules.
- The comparison tooltips beside an item's (what you wear) have no `GetItem` on this client: those go
  by the ID. An item's own link is read where there is one, for its random stats.
- A simulator's export is WoWSims' EP export: `( <tool>: v1: "Name": Class=Rogue, Agility=2.1, ... )`.
  A spell and a melee version of a stat count for the one we have, summed; keys we have no stat for
  are left out, and a hunter's weapon is its ranged one.

## Checking

- `lua Tools/regression/test-stat-weights.lua`: the defaults (every spec, its anchor, ranges,
  ratings), your changes and new defaults, sharing, the gain math, the tooltip line and its
  hook only once on, the window.
