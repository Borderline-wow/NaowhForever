# BiS List

Your best-in-slot picks for every gear slot, ranked: your BiS (an orange star), your second
pick (a silver one), then the rest. Picks come from wowsrc.com's ranking for your spec, from
every dungeon drop your class can use, or from Alt+Shift-clicking any item. The list has its
own window (`/nfbis`, a key binding, or the BiS stat in the Dungeon Journal): your paperdoll
on the left, a card per slot with its picks on the right, where to run next (a waypoint on
whoever has your BiS out in the world) and the best enchant for what you wear; and a Quests
page, the quests that reward a pick you do not have yet, as the Dungeon Journal shows its own.
Listed items
say so on their tooltip, and call out when they drop. Lists are shared by every character of a
class, and can be shared as a string.

What drops in a dungeon, and where, is the [Dungeon Journal](../DungeonJournal/README.md)'s: the picker's dungeon
drops and an item's boss and dungeon come from its data, so the two always agree.

Laid out like the [Dungeon Journal](../DungeonJournal/README.md), on [`Shared/`](../Shared/README.md).

## Layout

```
BiS/
  BiS.xml            what loads, in order (the TOC includes only this file)
  BiS.lua            settings, a list's shape, change listeners (ns.BiS)
  Rankings.lua       rankings, class rules, dungeon drops, sources, Run Next (B.Rankings)
  Lists.lua          your lists, their old formats, and the ns calls that change them (B.Lists)
  Gains.lua          what your BiS gets you: Naowh Score and stats over what you wear
  Upgrades.lua       how much stronger each BiS makes you, in percent, by your spec's weights (B.Upgrades)
  Enchants.lua       the best enchant for what you wear, for your spec and the item's level (B.Enchants)
  Sharing.lua        export and import strings (ns.ExportBisList, ns.ImportBisList)
  Alerts.lua         tooltip line, Alt+Shift-click, Drop Alert (which picks, alert, chat, sounds), the roll badge and its test
  Quests.lua         the quests that reward your picks, by zone, as the Journal's quests (B.Quests)
  Sources.lua        where a click on an item's source goes: Journal, quest, waypoint, recipe, map, Wowhead (B.Sources)
  Data/              generated, no logic
    BiS.lua          wowsrc.com's ranking per spec and item sources (Tools/build_bis_data.py)
    Spots.lua        where the NPC with a BiS stands out in the world (Tools/build_bis_spots.py)
    Enchants.lua     every enchant, what it gives and goes on, the skill it needs (Tools/build_enchants.py)
  View/
    Style.lua        what only the BiS List draws
    View.lua         the list page and a slot's picker, on the shared engine
    Rows.lua         your progress, the filter, a slot's row and its enchant, a pick, a place to run next
    Paperdoll.lua    your model in your BiS, turned and zoomed, the slots as the game lays them
                     out, and what your BiS gets you
    QuestsPage.lua   the Quests page: the Journal's quest and item rows, on a Journal view
    Toast.lua        Drop Alert's alert on screen, drawn by your settings, live and in its preview (B.Toast)
    Bags.lua         Bag Marks: the slot marks (Shared.Parts.ItemMarks) on your bags' items, the
                     game's bags or EllesmereUI's through its overlay hook
  UI/
    Actions.lua      new, rename, delete, import, export, test: the window and page share them
    Picker.lua       a slot's picker, in a side panel beside the window
    Window.lua       the window
    AlertPreview.lua Drop Alert's studio on the settings page: the on-screen alert as it will look,
                     changed by clicking its parts or their chips, with its size, time, background
                     and glow beside it, and Play test
    SettingsPage.lua its page in the options window
```

Other modules call in through `ns`: `ns.IsBisItem` (the Journal, Bag Space, the loot feed),
`ns.ClassCanUse` and `ns.BisSlotsFor` (the Journal), `ns.AddBisItem`, `ns.PromoteBisItem`,
`ns.RemoveBisItem` (the Journal's item menu), `ns.ImportBisList` (profile packs),
`ns.OpenBisWindow`.

## I want to change...

| What | Where |
| --- | --- |
| A colour, a size, an icon | `View/Style.lua`, or `Shared/Style.lua` for the house look (the stars) |
| What a class can wear or wield | `Rankings.lua` |
| A spec's ranking | `python Tools/build_bis_data.py` (daily in CI) |
| Where an item drops | A dungeon drop: the Dungeon Journal's data (`Tools/build_journal.py`), which the BiS List reads; anything else: `Tools/bis_sources.json`, then rebuild |
| What a list keeps, or an old format | `Lists.lua` (saved lists) and `Sharing.lua` (strings) |
| Which enchant or upgrade wins for a spec | the spec's weights in `StatWeights/Data/Defaults.lua` (players change their own in the module's page); a proc's worth in `PROCS` in `Tools/build_enchants.py` |
| Where a zone's NPC stands | `python Tools/build_bis_spots.py` (on our machines: it reads Wowhead) |
| The quests that reward a BiS | `python Tools/build_bis_quests.py`, then `python Tools/build_quest_chains.py` |

## Checking

- `lua Tools/regression/test-bis-slots.lua`: lists, picks, old formats, sharing, Run Next.
- `lua Tools/regression/test-bis-dungeon-drops.lua`: class rules, dungeon drops, sources.
- `lua Tools/regression/test-bis-window.lua`: the window, paperdoll and picker, a click
  changing the list, the redraw's cost (no garbage), Drop Alert only listening while on and
  as you set it (which picks, alert, chat, sounds, its look, and the settings page's studio and rows), Run Next's waypoints, and enchants by spec and item level.
- `lua Tools/regression/test-dungeon-journal.lua`: also the Quests page, the quests that
  reward your picks, by zone, for your side, class and race.
