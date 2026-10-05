# Shared

What every module can use, so they look and work the same from one copy of the code. The
Dungeon Journal and the BiS List are built on it. Loads after Core and before every module,
through `Shared.xml`. Nothing is made or listened to at load.

## Layout

```
Shared/
  Shared.xml   what loads, in order
  Shared.lua   the namespace (ns.Shared), and what a character keeps by its GUID (Shared.CharacterData)
  Style.lua    the house look: colors (BiS stars, worn green, looks, red and warning orange), icons, sizes
  Items.lua    item and gear helpers: an ID from a link or URL, your loot lines, quality colour, In Bag,
               gear slots, what fits where, what you wear, weapons in short ("1h Sword"),
               waiting on item data
  Bags.lua     the item buttons in your bags, the game's and EllesmereUI's, for the marks
               painted on them (Bag Marks, Scrap Marker)
  Places.lua   zones by name, and showing one on the world map
  Parts.lua    components: rank stars, item icon and its check, an item's slot marks (item level, star, Forever's mark), links, icon buttons, the
               backdrop and its cards, panels, the side panel, chat sharing, lined-up numbers,
               money with its coins (Parts.Coins, made once each; compact, its largest coin only),
               an atlas badge on an icon's top corner (Parts.ItemBadge, Bag Space's clock and quest "!"), a timer line the client runs
               down by itself (Parts.TimerLine), a row of labels spread evenly (Parts.LabelRow), a HUD
               card's background: the card, a soft fade or none (Parts.HudBackdrop)
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
  32, 1 } }` and `Settings.Group("Clock")` between them (see `Settings/Settings.lua`). A row or
  group with `hidden` is left off the page: `true` for one set on the preview instead, or a
  function, so rows for one choice only (the Campfire's Round and Simple rows) show with it. The page
  in the options window, its search entries, the dot on what you changed and each card's reset
  all come from that one declaration. Settings pages hold settings only: a module's lists and
  editors live in its own window, opened from the page's `page:Window{ ... }` card (first on
  the page, or where its `order` puts it). A card that
  shows something on screen can carry a live preview (`studio`, see `Settings/Studio.lua`; its
  `height` a number, or a function for a stage that changes with a setting),
  drawn by the module's own drawing code on plain frames, never on its real (secure) frames.
  `Settings.EditZone(parent, opts)` makes part of a preview editable, every option optional:
  `click(zone)`, `menu(owner, root)` (the house context menu on right-click), `wheel(zone, delta)`,
  `drag = { get, set, live, range, axis, factor }` (a drag along `axis`, "x" by default, snapped to
  `range` `{ low, high, step }` with `Settings.Snap`, drawn through `live` and saved through `set`
  on release), and a hover mark: `wash` (a faint fill) or `edge` (an accent line down its middle).
  Nothing runs per frame except while dragging. The Campfire's Simple bar preview uses it.
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
- **A HUD panel:** an on-screen bar or pill uses the windows' own backdrop, `Parts.Backdrop(frame)`
  painted at `Style.BACKDROP_ALPHA` (near opaque, so the world does not tint it), with the 1px black
  edge (`Style.BORDER_RGB`). The Campfire's Simple bar is one: its words are panel text (no HUD
  shadow), an amount in the text colour before its muted stat, and the accent only on a key word.
- **A timer line:** `Parts.TimerLine(parent, height, text)` is a thin StatusBar the client runs
  down by itself (`SetTimerDuration`), so no Lua runs while it counts: a full-width track in the
  theme's line color, a fill in a gradient into its color, and a soft glow where the fill ends.
  Give it a FontString as `text` (optional) and the time left is written into it the same way,
  short (`35s`, `42m`, `1h`: `Parts.ShortTime(prefix)`, one formatter per prefix, made once).
  `line:Run(start, duration, prefix)` starts it (`prefix` optional, e.g. `"in "`), `line:Stop()`
  empties it, and `line:Paint(color, textColor)` colors the fill and the glow, and the text in
  `textColor` when given, else in `color`. The Campfire's Simple bar uses it, in
  `Style.TIME_OK_RGB`, `TIME_LOW_RGB` and `TIME_OUT_RGB` (plenty, running low, nearly out).
- **Labels in a row:** `Parts.LabelRow(parent, size, flags, color, opts)` (all but `parent` and
  `size` optional) makes a frame of pooled labels. `row:SetLabels(list, n, icons)` writes the first
  `n` strings of `list` and returns the widest; `row:Pack()` lines them up left to right and
  returns the width, `row:Spread(width)` centres each in an equal share of `width` instead;
  `row:SetColor(color)` and `row:SetTextSize(size)` restyle them. `opts`: `gap` (space between
  labels as they are packed), `separator` (text between labels, e.g. `Style.PLACE_DOT`) in
  `separatorColor` (muted by default), and an item icon before each label (`Parts.ItemIcon`, the
  house edge) sized `icon`, or `iconGrow` more than the text, `iconGap` from it and `iconDrop`
  lower; `icons[i]` is its texture, false for none. Anchor the row by its left edge.
  Refilling it with the same strings makes no garbage.
- **Copying:** `Parts.CopyWowhead(kind, id, name)` opens the copy card on an item, quest or
  NPC's Wowhead link; a menu's Copy uses `ns.ShowCopyLine(title, text, icon)` (QoL's Global
  Copy) for any line.
- **Text on the game world:** `Parts.HudText(fontString, shadow)` gives a HUD line (the XP
  Ticker, an alert) the house look: no outline, a soft drop shadow (`HUD_SHADOW_RGB`,
  `HUD_SHADOW_ALPHA`, `HUD_SHADOW_X`, `HUD_SHADOW_Y` in `Style.lua`). Pass `shadow` false to
  take it off, for text a player chose to outline, or a background mode (`"soft"`, `"none"`) for
  the stronger shadow text needs over the world (`HUD_SOFT_SHADOW_ALPHA`, `HUD_BARE_SHADOW_*`).
  It returns the font string. A HUD card (the Flight Timer, the XP Ticker) puts it on the theme's
  background at `HUD_CARD_ALPHA` with the 1px black border, so the text needs no outline; its
  icons are `PLAY`, `PAUSE` and `RESET`.
- **A HUD card's background:** `Parts.HudBackdrop(frame, opts)` gives a HUD card the background a
  player picks: `backdrop:SetMode(mode)` with `"card"`, `"soft"` or `"none"` (anything else is
  `"card"`) returns the mode, and the same one again does nothing. Card is the theme's background
  at `HUD_CARD_ALPHA` with the 1px black edge (`backdrop.fill`, `backdrop.border`). Soft has no
  edge: a fade in the theme's background, `HUD_SOFT_ALPHA` behind the text and clear
  `HUD_SOFT_FADE` further out, `HUD_SOFT_INSET` of it inside the frame. It is nine pieces of one
  round texture (`Style.SOFT_SHADE`, from `Tools/make_media.py`), so its corners are round and no
  edge shows, made the first time Soft is picked (`backdrop.soft`). None shows nothing. `opts`, all
  optional: `alpha` (the card's fill), `color` (`T.bg`), `softAlpha`, `fade`, `inset` and `mode`.
  Pass the mode to `Parts.HudText` for each line on it; the choice row's values are
  `Parts.HUD_BACKGROUNDS`. The XP Ticker and Bag Space use it.
- **A progress line:** `Parts.ProgressLine(parent, height)` is a thin line that holds still (the
  XP Ticker's level progress): a track in the theme's line color, a fill in a gradient into its
  color, and a fainter segment ahead of the fill (rested XP). `line:SetProgress(value, ahead)`
  takes shares of the whole (0 to 1), and `line:Paint(color, aheadColor)` colors them. Anchor it
  where it goes; it sizes with its anchors, so a card that grows needs no redraw. `line.track` is
  the track, hidden where no card is behind it.
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
