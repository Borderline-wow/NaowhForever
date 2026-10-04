# Stat Weights

What each stat is worth to your spec, and so how much stronger an item makes you over what
you wear. Every spec has default weights; players change any of them on the module's page
(BiS List > Stat Weights), and only their changes are kept, for the account. Off by default.

- **Always on, for the BiS List:** its best enchant per slot and the upgrade percent on each
  BiS and on Run Next use these weights (yours where you changed them).
- **On (Upgrades on Tooltips):** a line on the tooltip of gear that is an upgrade for your spec,
  in its name: "Fire: (arrow) +9% upgrade", and under it what the item is weighed against.
  Nothing on gear that is not one. A ring or trinket is weighed against the weaker of the two
  you wear, a two-hander against both hands.

Your spec is Automatic: the talent tree you spent the most points in (Forever keeps one spec
per class, its three trees as the talent tree's groups, read as its own talent frame reads
them), or the one you pick.

The page keeps it short: the switch and your spec, a sample of the tooltip line, then only the
stats your spec uses, each a bar (how much it counts next to the others) and a number to type
over; percents and weapon dps in their own column. 0 takes a stat off; Add a stat puts one on
at 0 for your number. Under them, your BiS list's best upgrades by these weights, so a change
shows what it does. Export copies your changes as a line (`NFSW1:spec:stat=value,...`, only
what differs from the defaults); Import takes one, or a WoWSims EP export (Stat Weights, Copy to
Current EP, Export), which replaces the spec's weights. An enchant's weapon damage is worth a
point of dps over the weapon's speed, so it has no weight of its own.

The defaults are estimates for now (dated on the page); simulated weights from WoWSims will
replace them once its Forever sim is out.

The percent is the item's weighted stats minus what you wear there, over what your stats are
worth now (your five stats as the game sums them, the rest from your gear; a weapon's damage
per second counts too, the off hand's at half, a hunter's ranged weapon's instead). An
estimate: it orders upgrades, it does not promise a number on a meter.

## Layout

```
StatWeights/
  StatWeights.xml      what loads, in order (the TOC includes only this file)
  Data/Defaults.lua    each spec's default weights, by hand (ns.StatWeightDefaults)
  StatWeights.lua      the rules: specs, your changes, an item's worth and gain, sharing (ns.StatWeights)
  Tooltip.lua          the tooltip line, installed the first time the module is turned on
  UI/SettingsPage.lua  its page: the switch, your spec, your spec's stats as bars and numbers, reset, share
```

## I want to change...

| What | Where |
| --- | --- |
| A spec's default weights | `Data/Defaults.lua` (its role's, then the spec's own) |
| A stat players can weigh | `STATS` and `KEYS` in `StatWeights.lua`, and its heading in `UI/SettingsPage.lua` |
| The tooltip line | `Tooltip.lua` |

## Checking

- `lua Tools/regression/test-stat-weights.lua`: the defaults, your changes, sharing, the gain
  math, the tooltip line and its hook only once on, the page.
