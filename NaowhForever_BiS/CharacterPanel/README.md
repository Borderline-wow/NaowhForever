# Character Panel

The game's character panel (C) in the BiS List's look. Blizzard keeps the panel and everything
it does: its slots' clicks, drags and tooltips, its tabs and its stats. Naowh fades its art
(`SetAlpha`, never `Hide`) and lays its own frames over it, from post-hooks only.

Off by default (BiS List > Character Panel), and nothing is hooked until it is first turned on.

EllesmereUI styles the same panel, and the two are never on at once. Turning Naowh's on turns
EllesmereUI's Character Sheet off (`EllesmereUIDB.themedCharacterSheet = false`, what its own
switch sets), and turning Naowh's off turns it back on if Naowh's was what turned it off; either
way a reload is offered, as EllesmereUI swaps its look at login. Should EllesmereUI's come back on
by other means (read through `EllesmereUI.GetBlizzWindowStyle("charsheet")`), Naowh's stands down.

## Layout

```
CharacterPanel/
  CharacterPanel.xml   what loads, in order
  Panel.lua            the namespace (ns.CharacterPanel), its switch, EllesmereUI's check
  Slots.lua            the slots: edge in the quality's colour, item level, Forever's mark,
                       your BiS's star, the enchant dot
  Score.lua            your Naowh Score as a card under your level: the score big, a bar to
                       its share of the best; hover for the score with your BiS, click for
                       the BiS List
  SpecStats.lua        the stats: your spec's first (the stats it weighs, in a fixed order,
                       each with a bar for its worth against the spec's yardstick, "VS AGI",
                       and your total; hover a row for what it is worth and what it does), or
                       the game's All Stats; the switch at the bottom
  Chrome.lua           the frame: our backdrop and title, the game's art faded or tinted,
                       the stats' rows restyled as the game's list makes them
  SettingsPage.lua     its cards on the BiS List's settings page
```

The Inspect Panel (`InspectPanel/`) dresses the inspect window with the same parts: the rule
for EllesmereUI (`CP.Rival`), the frame (`CP.Restyler`, `CP.Chrome`), the slots (`CP.SlotOver`),
the score card (`CP.ScoreCard`) and the badge plate (`CP.BadgePlate`).

## How the slots work

Ours is a frame over each of the game's slot buttons (`Character<Name>Slot`), kept in a side
table: nothing of ours is stored on the game's frames. A post-hook of
`PaperDollItemSlotButton_Update` paints it each time the game updates the slot. Turned off,
the game's art comes back and ours hides.

## Checking

`lua Tools/regression/test-character-panel.lua`: off and hooking nothing by default, the art
faded and each part painted when on, standing down for EllesmereUI, the art back when off, and
no garbage from a slot's update.
