# Inspect Panel

The game's inspect window in the BiS List's look, as the Naowh Character Panel dresses the
character panel, with a pane of ours on its right for the player you inspect. Blizzard keeps the
window and everything it does: its slots' clicks and tooltips, ctrl-click to the dressing room,
the Talents button, the Guild tab. Naowh fades its art (`SetAlpha`, never `Hide`), widens the
window by the pane (its own frames keep their width on the left) and lays its own frames over
it, from post-hooks only.

On by default (QoL > Character > Inspect Panel), like the Character Panel, and nothing is hooked
or built until the game loads its inspect window (`Blizzard_InspectUI`, on the first inspect).
EllesmereUI's inspect sheet and this one are never on at once, by the Character Panel's rule
(`CP.Rival`): turning this on turns `EllesmereUIDB.themedInspectSheet` off, off turns it back on if
this was what turned it off, either way with a reload offered; while EllesmereUI's is on
(`EllesmereUI.GetBlizzWindowStyle("inspect")`), this stands down.

## What it shows

```
+------------------------------------------+----------------------+
| Name                                  x  | NAOWH SCORE          |
|        Level 60 Fury Warrior             | 41.2                 |
|             [Talents]                    | [=========-------]   |
| [] badge plate                       []  | You 26.4    Best 55.7|
| []                                   []  | TALENTS / GEAR /     |
| []          model                    []  | GUILD / NOTE         |
| []                                   []  |   (or History)       |
|          [] [] []                        | [ Player | History ] |
+------------------------------------------+----------------------+
```

- **Slots:** the character panel's look (`CP.SlotOver`): an edge in the item's quality colour,
  the item level, Forever's mark; the green arrow on what would be an upgrade for you by your
  stat weights (hover the slot for how much); an orange dot on a slot an enchanter could enchant
  that has none. Their BiS star shows only when their own Naowh Forever answers with their list
  (`TheirBiS.lua`); your BiS star and your enchant advice are about your gear, so they are not
  shown on theirs.
- **Score card:** their Naowh Score as your panel's card, yours under it to compare. Read from
  their gear while the game's inspect data is theirs, "..." while their items load.
- **Badge plate:** their supporter badge in the model's corner, as yours on your panel.
- **Player tab:** talents (points per tree, their lead tree and its role, and one of Naowh's
  Training Planner builds by name when their points follow it), the gear check (unenchanted and
  empty slots, item level, upgrades for you), their guild and how you know them, and your note
  and tag on them (Player History's).
- **History tab:** with Player History on, how often you grouped, your last groups and the last
  lines either of you said, as plain text.

We cannot read another player's stats, so the pane has none: the score, the gear check and the
talents say what the stats would.

## Their BiS

Asked of the player inspected by addon whisper (`NaowhInspect`), answered by their Naowh Forever
with which of the items they wear are on their list and its rank there, in one message under
255 bytes. An answer is kept only for the ask out, from that player (name and GUID matched
against the inspect unit), while the window still shows them, every field checked; answers are
rate-limited per asker and in all, and nothing they sent goes back. Share Your BiS (on by
default) is the answering side.

## Layout

```
InspectPanel/
  InspectPanel.xml   what loads, in order
  Panel.lua          the namespace (ns.InspectPanel), its switch, the window widened and dressed,
                     whose inspect data the game holds (IP.Ready), the refresh each part paints on
  Slots.lua          the slots and the gear check
  TheirBiS.lua       their BiS asked and kept; yours answered
  Card.lua           the score card and the badge plate
  Details.lua        the Player tab
  History.lua        the History tab
  SettingsPage.lua   its card on QoL > Character
```

## Blizzard's side (Forever, `Blizzard_InspectUI`, `Camelot` and `Mainline` files)

- `InspectFrame` (`Camelot/Blizzard_InspectUI.xml`, `ButtonFrameTemplate`): `OnShow` and `OnHide`
  hooked; shown on `INSPECT_READY` for `InspectFrame.unit`.
- `InspectPaperDollItemSlotButton_Update` (`Mainline/InspectPaperDollFrame.lua`): post-hooked to
  paint our slot frames over `Inspect<Slot>Slot` (`Camelot/InspectPaperDollFrame.xml`).
- `FrameTemplate_SetButtonBarHeight` (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`):
  post-hooked so the inset keeps its width when the paper doll or guild tab moves its bottom.
- `INSPECTFRAME_SUBFRAMES` (`Camelot/Blizzard_InspectUI_Overrides.lua`): the tabs' frames, kept on
  the left part of the wider window.

## Checking

`lua Tools/regression/test-inspect-panel.lua`: off and hooking nothing; waiting for the game's
inspect window; on, the art faded, the window widened and each part painted for the GUID shown;
a stale `INSPECT_READY` ignored; the BiS round trip and every way an answer is dropped; the
answering side's limits; History with a record, without one and without the module; missing APIs;
standing down for EllesmereUI; the art back when off; and no garbage from a slot's update, a
refresh or an answer read.
