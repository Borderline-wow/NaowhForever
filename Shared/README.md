# Shared

What every module can use, so they look and work the same from one copy of the code. The
Dungeon Journal and the BiS List are built on it. Loads after Core and before every module,
through `Shared.xml`. Nothing is made or listened to at load.

## Layout

```
Shared/
  Shared.xml   what loads, in order
  Shared.lua   the namespace (ns.Shared)
  Style.lua    the house look: colours (BiS stars, worn green, looks), icons, sizes
  Items.lua    item and gear helpers: an ID from a link or URL, your loot lines, quality colour, In Bag,
               gear slots, what fits where, what you wear, weapons in short ("1h Sword"),
               waiting on item data
  Bags.lua     the item buttons in your bags, the game's and EllesmereUI's, for the marks
               painted on them (Bag Marks, Scrap Marker)
  Places.lua   zones by name, and showing one on the world map
  Parts.lua    components: rank stars, item icon and its check, an item's slot marks (item level, star, Forever's mark), links, icon buttons, the
               backdrop and its cards, panels, the side panel, chat sharing, lined-up numbers,
               money with its coins (Parts.Coins, made once each)
  Window.lua   a window: the frame, title bar, icons, opacity slider, switch, search, footer,
               and a module's card on its settings page
  Tracker.lua  a tracker's small window (Parts.TrackerPanel), and a list row's bands
               (Parts.RowBands: stripe, hover, the line under it)
  View.lua     the row engine: pooled rows, cards, the card grid, one redraw per burst
  Kinds.lua    the rows every page has: section title, note, card, and an item in a list you
               keep (icon, name in its quality colour, a line under it, a tag, a value, an X)
  Settings/
    Settings.lua  every settings page, declared once: pages, cards, rows, reset, search index
    Page.lua      a declared page drawn on the row engine: cards, their heads, two-column rows
    Studio.lua    a card's live preview: a stage and the moments it can be seen in
```

## Using it

- **A look:** make your module's `Style` with `setmetatable({ ... }, { __index = ns.Shared.Style })`.
  Put only your own values in it; the house ones come through.
- **A page:** `local kinds = ns.Shared.View.NewKinds()`, add your row kinds to it
  (`New(view)` makes the frame once, `Set(row, ...)` fills it and returns its height), then
  `ns.Shared.View.New(parent, kinds, mixin)`. Your mixin draws: `self:Clear()`, `self:Add(...)`
  rows, `self:Fit(events)`, and `Redraw()` draws again.
- **Settings:** a module declares its settings next to its code, on the page they show on:
  `ns.Shared.Settings.Page("QoL/General", S):Card({ id, name, help, switch, summary, order,
  studio, rows = { ... } })`, rows like `{ key = "iconSize", label = "Icon Size", slider = { 12,
  32, 1 } }` and `Settings.Group("Clock")` between them (see `Settings/Settings.lua`). The page
  in the options window, its search entries, the dot on what you changed and each card's reset
  all come from that one declaration. Settings pages hold settings only: a module's lists and
  editors live in its own window, opened from the page's `page:Window{ ... }` card (first on
  the page, or where its `order` puts it). A card that
  shows something on screen can carry a live preview (`studio`, see `Settings/Studio.lua`),
  drawn by the module's own drawing code on plain frames, never on its real (secure) frames.
- **A window:** `Parts.Window`, `Parts.TitleBar`, `Parts.Opacity`, `Parts.BarButton`,
  `Parts.FooterBrand`. See `BiS/UI/Window.lua` for a short one.
- **A tracker:** `Parts.TrackerPanel(title, opts)` builds a tracker's window once, on first
  use: the window look, the title (click and drag), a scrolling body, a cog, its place kept.
  Every option is optional:

  | Option | What it adds |
  | --- | --- |
  | `width` | starting width (`TRACKER_W`) |
  | `titleRoom` | room left of the close button for your own buttons |
  | `onTitle`, `titleTip`, `titleHint` | a click on the title, and its tooltip |
  | `onClose` | the close button's click, in place of hiding it |
  | `bar` | a progress bar under the title: `panel.bar`, with `bar.bg` (`TRACKER_BAR_RGB`) and `bar.text` |
  | `picker = { values, order, get, set, menuHeight }` | a dropdown under the title or bar: `panel.picker` |
  | `newBody(scroll)` | what scrolls in the body (a row engine view); else a plain frame for `panel:SetRows` |
  | `settings = { page, card, tip, hint }` | the cog in the bottom right, opening that settings page and card |
  | `opacity()` | its Window Opacity, for `panel:Paint()` |
  | `load()`, `save(point, relativePoint, x, y)`, `place` | its place: read, saved on drag, and the default `{ point, relativePoint, x, y }` |
  | `mover(panel, onMoved)` | Unlock Mode's mover: return `ns.UI.AttachMover(panel, label, onMoved, page)`; it saves through `save` |
  | `maxHeight()` | taller than this, its body scrolls |

  The panel has `panel:Paint()`, `panel:Place()`, `panel:SetTrackerWidth(w)`,
  `panel:Fit(bodyHeight)` (true when it starts or stops scrolling: set its width again and
  redraw), `panel:ScrollGap()`, `panel:Top()` and `panel:SetRows(entries)`: pooled rows of
  `{ text, sub, color, done, waypoint(entry), tip(row), click(row, button) }`, a pin column (a
  tick once done), the text in `color` (`T.fg` when nil), returning their height. Keep the
  entries and refill them, with shared functions that read the entry, and a redraw makes no
  garbage. See `DungeonJournal/UI/QuestTracker.lua`, and the Discovery trackers for `bar`,
  `SetRows` and `mover`.
- **Copying:** `Parts.CopyWowhead(kind, id, name)` opens the copy card on an item, quest or
  NPC's Wowhead link; a menu's Copy uses `ns.ShowCopyLine(title, text, icon)` (QoL's Global
  Copy) for any line.
- **Forever's mark:** `Parts.IsForever(kind, id)` says whether Wowhead's Forever database has
  it as new in Forever (`Data/Forever.lua`, generated by `Tools/build_forever_new.py`; do not
  edit by hand).

## The rule: always use these

Every module builds its UI from these components and the `ns.UI` widgets, never its own copy.

- **It exists:** use it as it is.
- **It almost fits:** make it more flexible. Add an optional input (a parameter or an options
  field) that leaves every current caller working as before, rather than copying it.
- **Nothing fits:** add a new component here, list it above, and use it from your module.
  Anything another module could want belongs here, not inside one module.

Colours and sizes come from `ns.THEME` and `Style.lua`, never written as numbers in a module.

## Checking

`lua Tools/regression/test-shared.lua` loads these files as `Shared.xml` lists them, against
stubs: nothing made at load, the item helpers, the Forever mark, and the row engine (rows
pooled and reused, one redraw per burst of events, none while hidden, no garbage). A module's
own test loads them the same way before its files, with `Tools/regression/load_files.lua`
and `toc_files.lua`, and times its draws with `measure.lua`: see
`test-dungeon-journal.lua` and `test-bis-window.lua`.
