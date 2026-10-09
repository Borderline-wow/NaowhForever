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

It adds a divider and a Group Inspect button that opens the window, on the party and raid unit
menus (Blizzard_UnitPopupShared, `forever` branch); see Why.

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
  NaowhForever_GroupInspect.toc   the addon: needs NaowhForever and NaowhForever_BiS; lists only its XML
  GroupInspect.xml   what loads, in order
  GroupInspect.lua   the namespace (ns.GroupInspect, GI), the state its files share (GI.state), the
                     change callbacks (GI.Changed, GI.OnChange) and the API the views read
  Constants.lua      the numbers and lists several files share (GI.C): stale time, slots, rounding,
                     the stat keys and their bounds, the party and raid unit tokens
  Data/
    Preview.lua      the sample party and raid: names, classes, gear, talents and stat profiles
  Records.lua        a member's record, pooled by GUID: who they are, gear, score, talents (GI.Records)
  Inspect.lua        the scan while the window is open: the roster, the inspect walk, item data, its
                     events (GI.Open, GI.Close, GI.Refresh, GI.RefreshAll)
  PreviewGroup.lua   the preview's records, built once from the sample data (GI.Preview, GI.PreviewMode)
  Stats.lua          a member's stats added up from their gear (GI.StatsFromGear)
  OwnStats.lua       your own exact stats and talent points, read for an answer (GI.OwnStats)
  Message.lua        the exchange's messages: the request, an answer written, read back and kept (GI.Message)
  Share.lua          the exchange with other players' Naowh Forever: when to ask, answer and listen
  View/
    Style.lua        its look and its window's sizes and shared words (GI.UI, GI.UI.Style)
    Texts.lua        texts made once each: scores, levels, talents, stats, states, progress
    Parts.lua        the pieces cards, rows and the preview share: class and role icons, a name
                     fitted to its room, kickers, a supporter's badge
    Pill.lua         the NF pill, tinted when their version is older than yours
    Gear.lua         a gear slot: its icon, quality edge, missing enchant, tooltip and empty art
    Card.lua         a party card, built and laid out narrow or wide (GI.UI.PartyCard)
    CardPaint.lua    a party card painted from a record (GI.UI.PaintPartyCard)
    Party.lua        the party cards side by side (GI.UI.PartyBoard)
    RaidOrder.lua    the raid's sorts and filters (GI.UI.RaidOrder, GI.UI.Passes, GI.UI.Filters)
    RaidBar.lua      the raid's toolbar: view tabs, sort menu, filter menu (GI.UI.RaidBar)
    Row.lua          a raid member's row on the shared row engine (GI.UI.RaidKinds)
    Raid.lua         the raid rows under their column header (GI.UI.RaidList)
    Solo.lua         the note while solo, with a link to the preview (GI.UI.SoloNote)
  UI/
    Window.lua       the window: party, raid or a note while solo; opening it starts the scan
    Menu.lua         Group Inspect on a party or raid member's right-click menu
    SettingsPage.lua its settings page: the banner, Share Your Stats, the live preview (GI.Preview),
                     its key binding and the window's opacity
  README.md          this file
```

The window's files only read `ns.GroupInspect`'s API (`Members`, `Member`, `Mode`, `OnChange`,
`Refresh`, `RefreshAll`, `Preview`); records are reused, so nothing keeps one between frames. Five
cards and the raid's rows are made once and reused; a member's change repaints only their card or
row, and sorts again only when their place changes.

## The exchange

Members who run Naowh Forever send their exact stats, talent points per tree and version over
addon messages (prefix `NaowhGroup`) in the group channel:

- request `1 R`, sent only while the window is open (on opening it, and when someone joins);
- answer `1 S <GUID> <version> <t1>/<t2>/<t3> <STR> <AGI> <STA> <INT> <SPI> <AP> <SP> <CRIT> <HIT>
  <ARMOR>`, CRIT and HIT in tenths of a percent, one message under 255 bytes, sent after a short
  random wait, at most once per `ANSWER_GAP`, and again when your gear or talents change while
  someone asked in the last `ASKED_WINDOW` seconds.

Answering needs Share Your Stats (`groupInspectShare`) and a group.

## Why

- The scan runs only while the window is open (`GI.Open`, `GI.Close`): one request at a time
  through Naowh Score's shared queue (`ns.NaowhScore.InspectQueue`), at least its gap apart, out
  of combat, in range, yielding to your own inspect. Players running Naowh Forever are inspected
  after the rest, since they share their stats anyway and only their gear is wanted. Out of range
  is tried again later, and the walk stops once everyone is known; a read goes stale after
  `STALE` seconds (five minutes).
- `INSPECT_READY` is read only for the GUID asked for, so another addon's inspect is left alone.
- Records are pooled and keyed by GUID, and callbacks (`GI.OnChange`) come once per burst of
  changes, on the next frame. `Message.lua` writes its fields and calls `GI.Changed`, and
  `Stats.lua` replaces `GI.StatsFromGear(record)`.
- `GI.state` is the one table `Records.lua`, `Inspect.lua` and `PreviewGroup.lua` share (open,
  preview, records, members and their count); the views read only the API.
- A record waiting on item data tells `Inspect.lua` through `GI.Records.OnLoading`, and the raid's
  filters redraw the window's list through `GI.UI.RaidOrder.OnFiltered`, so each file uses only
  what loaded above it.
- Item data loads late: a record waiting on it listens to `GET_ITEM_INFO_RECEIVED` and reads again
  `LOAD_SETTLE` later, and stops listening once everything has loaded.
- The preview (`GI.Preview`, for the settings page, screenshots and tests) is a fixed party of five
  or raid of twenty-five, built the first time it is asked for, never real players. Each sample
  gear string is `slot:item:quality:item level:on their BiS`, real items from the BiS data.
  Every third enchantable slot of a member without Naowh Forever shows a missing enchant.
- An answer is kept only from the member its GUID names (`ns.SenderIs`), still in the group, every
  field checked against its bounds, at most one per member per `ACCEPT_GAP`; nothing received is
  sent back, and a value the game hands over secret is never read.
- Answers wait a short random time (`PARTY_SPREAD`, `RAID_SPREAD` tenths of a second) so a raid
  does not answer at once, and nothing is sent in combat or in chat lockdown: it waits for
  `PLAYER_REGEN_ENABLED` or `ADDON_RESTRICTION_STATE_CHANGED`.
- Your own stats read nothing while `C_Secrets.ShouldUnitStatsBeSecret()` says they are secret.
- A version is compared number by number, so `0.5.22-beta` is older than `0.5.24-beta`; an older
  one tints the NF pill.
- The right-click entry is added with the game's menu extension API, `Menu.ModifyMenu`, on the unit
  menus tagged `MENU_UNIT_PARTY`, `MENU_UNIT_RAID_PLAYER` and `MENU_UNIT_RAID`, only while the
  module is on, and removed when it goes off; nothing of the game's menus is changed.
- Texts are made once each and kept (`KEPT` of each kind, then started again), so a repaint makes
  no garbage.

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
