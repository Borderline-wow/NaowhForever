# Group Inspect

One window with everyone in your party or raid: their class, whether they run Naowh Forever, their
Naowh Score, item level, gear, talents and stats. A module addon of its own
(`NaowhForever_GroupInspect`, Combat > Group Inspect in the options window), needing
`NaowhForever_BiS`, whose Naowh Score, inspect queue, inspect panel and character panel parts it
reuses: turning BiS off turns this off too, and turning this on brings BiS. Open it with:

- `/nf group` or `/nfgroup`, its Top Bar launcher or its minimap button (Settings > Minimap Icons);
- its key binding (Key Bindings > AddOns > Naowh Forever > Open Group Inspect);
- Open Group Inspect on its settings page (Group Inspect / Settings);
- Group Inspect on a party or raid member's right-click menu.

Off by default (`groupInspect`; the switch at the top of its page, and the addon's under Settings >
Modules).
While it is off nothing is built, listened to or timed, and the right-click entry is not added.
Opening the window turns it on; the scan runs only while the window is open (`GI.Open` /
`GI.Close`), one inspect at a time, never in combat, and always after the player's own inspect.

## The right-click entry

Added with the game's menu extension API, `Menu.ModifyMenu`, on the unit menus tagged
`MENU_UNIT_PARTY`, `MENU_UNIT_RAID_PLAYER` and `MENU_UNIT_RAID` (Blizzard_UnitPopupShared, `forever`
branch), only while the module is on and removed when it goes off. It adds a divider and a Group
Inspect button that opens our window; nothing of the game's menus is changed.

## What it shows

```
Party (2 to 5): a card each, side by side, 256 wide for four or fewer, 203 for five
+--------------------------------+
|============ class band ========|
| [class] Name Surname [b]  [NF] |  [b] their supporter badge, as in chat
|         Level 25 Paladin  [ro] |  role icon only when known
|--------------------------------|
| NAOWH SCORE         ITEM LEVEL |
| 16.9                        24 |
| [=========ramp=====----------] |
| GEAR            9/11 enchanted |
| [hd][nk][sh][bk][ch][wr]       |  the character sheet's left column,
| [hn][wa][lg][ft][r1][r2]       |  its right column, then trinkets and
| [t1][t2]    [mh][oh][rg]       |  weapons; empty slots show the game's art
| TALENTS                        |
| Marksmanship            21/9/0 |
| STATS                From gear |
| Agility      84   Crit   12.3% |  two columns, numbers lined up
| Stamina      53   Hit     3.0% |
| Queued                     [R] |
+--------------------------------+

Raid (6 to 40): a row each; the toolbar picks the view, the sort and the filters
|band| [class] Name [b] [NF][ro]  Score  iLvl | Gear (17 icons) / Talents / Stats | state [R]
```

- **NF pill:** on members whose Naowh Forever answered; hover for its version. Supporter and staff
  badges are separate: their own badge after the name, as in chat (with the chat badge setting).
- **Names:** a long name gets smaller, down to a minimum, and shows whole on hover.
- **Score:** the Naowh Score in its grade's color; on a card, the score card's ramp bar too.
- **Stats:** exact when their Naowh Forever shared them, else added up from their gear (no base
  stats), and labelled so: "From their Naowh Forever", "From gear", or "Yours" on your own card;
  white or grey in a raid row.
- **Raid toolbar:** Gear, Talents or Stats; sort by Naowh Score, item level, name, class or role;
  filter by class, role, armor, who runs Naowh Forever and who is missing an enchant (filters last
  for the session). Each row has its state (queued, inspecting, out of range, offline) and a button
  to inspect that member again; the title bar's Refresh inspects everyone again.
- **Solo:** a short note, with a link to the preview on its settings page.

## Layout

```
NaowhForever_GroupInspect/
  NaowhForever_GroupInspect.toc   the addon: needs NaowhForever and NaowhForever_BiS
  GroupInspect.xml   what loads, in order
  Data.lua           the namespace (ns.GroupInspect), the member records, the inspect queue
  Share.lua          the exchange with other players' Naowh Forever, stats added up from gear
  Window.lua         the window and the pieces the cards, rows and preview share (GI.UI)
  Party.lua          the party cards (GI.UI.PartyBoard)
  Raid.lua           the raid rows on the shared row engine, the toolbar (GI.UI.RaidList, RaidBar)
  SettingsPage.lua   its settings page: the banner, Share Your Stats, the live preview (GI.Preview),
                     its key binding and the window's opacity
```

The window's files only read `ns.GroupInspect`'s API (`Members`, `Member`, `Mode`, `OnChange`,
`Refresh`, `RefreshAll`, `Preview`); records are reused, so nothing keeps one between frames. Five
cards and the raid's rows are made once and reused; a member's change repaints only their card or
row, and sorts again only when their place changes.

## Settings

| Key | Default | What it is |
| --- | --- | --- |
| `groupInspect` | `false` | the module |
| `groupInspectShare` | `true` | answer other players' Group Inspect with your stats and talents |
| `groupInspectSort` | `"score"` | the raid's sort |
| `groupInspectView` | `"gear"` | the raid's view: `gear`, `talents` or `stats` |
| `groupInspectAlpha` | `1` | the window's opacity |

## Checking

`lua Tools/regression/test-group-inspect-ui.lua`: nothing built, listened to or hooked while off; its
module entry, launcher and settings page; the right-click entry added only while on; opening
turns it on and starts the scan, closing stops it; solo, a party of five and three, a raid of forty
on pooled rows; every view, sort and filter; a member's change repainting only their card or row;
the progress line, refresh buttons, gear tooltip and settings preview; and no garbage from a repaint.
