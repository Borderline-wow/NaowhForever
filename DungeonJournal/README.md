# Dungeon Journal

Every dungeon's bosses in kill order, what each drops and how often, your BiS marked, your
quests there, and a tip from Naowh for each boss. Off by default: players turn it on in the
Dungeon Journal settings page.

This module is the addon's reference for how a module is laid out and written. Its folder
holds everything it needs, and it loads through its own `DungeonJournal.xml`.

## Layout

```
DungeonJournal/
  DungeonJournal.xml   what loads, in order (the TOC includes only this file)
  Journal.lua          settings, the dungeon registry and the public API (ns.Journal)
  Loot.lua             the loot rules: what is listed, BiS ranks, upgrades, looks (J.Loot)
  Quests.lua           the quest rules: where each quest stands, its chain, waypoints (J.Quests)
  Team.lua             who was in your group, kept with a kill or an item (J.Team)
  Kills.lua            this character's kills of each boss: when, and who was with it (J.Kills)
  Looted.lua           what this character has looted in the Journal's dungeons: where, who was
                       with it, and the rolls (J.Looted)
  Sharing.lua          asking a group member with Naowh Forever to share a quest (J.Sharing)
  Data/                data, no logic
    Dungeons/*.lua     one per dungeon, generated
    Items.lua          item facts for before the client has loaded an item, generated
    Quests.lua         every dungeon quest, from Wowhead's Forever guide, with hand additions
    QuestChains.lua    each quest's chain, prerequisites and required level, generated
    Tips.lua           Naowh's tips, by hand
  View/                draws one dungeon; used by the window, the map panel and the popup
    Style.lua          every colour, size, spacing and icon
    View.lua           the engine: pooled rows, the card grid, search, redraws
    Parts.lua          shared pieces, the side panel, and the section title and note rows
    Header.lua         the dungeon's name, entrance pin, zone and stats
    QuestRows.lua      your quests: marks, hover card, right-click menu
    BossCards.lua      boss cards, tips and sharing them, the folded-boss chips
    ItemRows.lua       one item of a boss's loot
    ItemMenu.lua       an item's right-click menu (the BiS list)
    QuestPanel.lua     a quest in your log, in the side panel
    BossPanel.lua      a boss's history: each kill, who was with you, what you looted and the rolls
  UI/                  where it shows
    DungeonList.lua    the window's list of dungeons, grouped by your level
    Window.lua         the Journal's window (/nfjournal, /nfdj)
    MapPanel.lua       beside the world map, inside a dungeon
    Popup.lua          Boss Loot at Cursor (a key binding)
    QuestTracker.lua   a dungeon's quests in a small window, one line each
    SettingsPage.lua   its page in the options window
```

Each layer only uses the ones above it: `Data` fills `Journal`, `Loot` and `Quests` read
both, `View` draws what they decide, and `UI` places a view on screen. Everything the
module shares hangs off `ns.Journal` (`J`); only the entry points the rest of the addon
calls are on `ns`.

## I want to change...

| What | Where |
| --- | --- |
| A colour, a size, spacing, an icon | `View/Style.lua` |
| A boss tip | `Data/Tips.lua`, keyed by the boss's NPC ID, one short sentence |
| A dungeon's bosses, wings, kill order, entrance or zone | `Tools/journal_bosses.json`, then `python Tools/build_journal.py` |
| A boss's NPC ID the build cannot find | `"npcs": { "Name": ID }` on the dungeon in `Tools/journal_bosses.json` |
| An icon's drawing | its function in `Tools/make_media.py`, then run it (writes `Media/*.tga`) |
| What counts as usable, BiS, an upgrade, a new look | `Loot.lua` |
| A quest's state, the list's order, where its waypoint goes | `Quests.lua` |
| A dungeon quest | `Data/Quests.lua`, then `python Tools/build_quest_chains.py` for its chain |
| A setting or its default | `Journal.lua` (`UI.ModuleSettings("journal", ...)`) and `UI/SettingsPage.lua` |

`Data/Dungeons/*.lua`, `Data/Items.lua` and `Data/QuestChains.lua` are generated: change
their source and rebuild rather than editing them, or the next build undoes the edit.

The style rules (named values, 1px black edges, the accent, lining icons up with the
Naowh font) are the addon's, in `.github/CONTRIBUTING.md` under Style.

## Adding things

- **A dungeon:** add it to `Tools/journal_bosses.json`, rebuild, and add the line the build
  prints to `DungeonJournal.xml`.
- **A row kind:** a file in `View/` that fills `J.View.Kinds.<name>` with `New(view)`
  (makes the frame once) and `Set(row, ...)` (fills it and returns its height). List it in
  `DungeonJournal.xml` after `View/View.lua`, and draw it with `view:Add("<name>", ...)`.
- **A file:** list it in `DungeonJournal.xml`, never in the TOC.

## Checking

- `luacheck .` from the repo root.
- `lua Tools/regression/test-dungeon-journal.lua` from the repo root: loads every file
  `DungeonJournal.xml` lists, in order, against stubs, and checks the data, the loot rules,
  what counting costs, and that nothing is made or hooked while it is off.
- `lua Tools/regression/test-journal-quests.lua`: the quest rules and the quest data.
- In game: `/reload` after changing a file. If a new file or texture does not show up,
  restart the game.
