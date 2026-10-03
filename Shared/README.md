# Shared

What every module can use, so they look and work the same from one copy of the code. Made
for the Dungeon Journal and the BiS List, which move onto it in their own changes, and for any
module after them. Loads after Core and before every module, through `Shared.xml`. Nothing is
made or listened to at load.

## Layout

```
Shared/
  Shared.xml   what loads, in order
  Shared.lua   the namespace (ns.Shared)
  Style.lua    the house look: colours (BiS stars, worn green, looks), icons, sizes
  Items.lua    item and gear helpers: an ID from a link or URL, your loot lines, quality colour, In Bag,
               gear slots, what fits where, what you wear, weapons in short ("1h Sword"),
               waiting on item data
  Places.lua   zones by name, and showing one on the world map
  Parts.lua    components: rank stars, item icon and its check, links, icon buttons, the
               backdrop and its cards, panels, the side panel, chat sharing, lined-up numbers
  Window.lua   a window: the frame, title bar, icons, opacity slider, switch, search, footer,
               and a module's card on its settings page
  View.lua     the row engine: pooled rows, cards, the card grid, one redraw per burst
  Kinds.lua    the rows every page has: section title, note, card
```

## Using it

- **A look:** make your module's `Style` with `setmetatable({ ... }, { __index = ns.Shared.Style })`.
  Put only your own values in it; the house ones come through.
- **A page:** `local kinds = ns.Shared.View.NewKinds()`, add your row kinds to it
  (`New(view)` makes the frame once, `Set(row, ...)` fills it and returns its height), then
  `ns.Shared.View.New(parent, kinds, mixin)`. Your mixin draws: `self:Clear()`, `self:Add(...)`
  rows, `self:Fit(events)`, and `Redraw()` draws again.
- **A window:** `Parts.Window`, `Parts.TitleBar`, `Parts.Opacity`, `Parts.BarButton`,
  `Parts.FooterBrand`.
- **Copying:** `Parts.CopyWowhead(kind, id, name)` opens the copy card on an item, quest or
  NPC's Wowhead link; a menu's Copy uses `ns.ShowCopyLine(title, text, icon)` (QoL's Global
  Copy) for any line.
- **Forever's mark:** `Parts.IsForever(kind, id)` says whether Wowhead's Forever database has
  it as new in Forever (`Data/Forever.lua`, generated; do not edit by hand).

If two modules need the same thing, it goes here, not in either of them.

## Checking

`lua Tools/regression/test-shared.lua` loads these files as `Shared.xml` lists them, against
stubs: nothing made at load, the item helpers, the Forever mark, and the row engine (rows
pooled and reused, one redraw per burst of events, none while hidden, no garbage). A module's
own test can load them the same way before its files, with `Tools/regression/load_files.lua`
and `toc_files.lua`, and time its draws with `measure.lua`.
