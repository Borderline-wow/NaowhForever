# Macros

Naowh's Forge, the Macros module's own window (`/nfmacros`), has two tabs: Smart Macros and the
Library. Your own macros are written in the game's macro window (`/macro`), and Export and Import in the
Forge's title bar share them as a string. The Smart Macros (NF Health, NF Healthstone, NF Health Potion, NF Mana, NF Food, NF Drink, NF
Bandage, NF Trinket 1 and 2, NF Focus, NF Accept) are written by the module and kept on the best
item or spell you carry, out of combat.
The Library keeps, by class, the macros you saved to it and those your profile pack brings. Save a Macro on its
tab lists your game macros and keeps the one you pick under your class, so it can be added to any character of that class,
and New Macro opens a small dialog to write one: a name and its text, with a byte counter against the game's 255.

## Layout

```
NaowhForever_Macros/
  NaowhForever_Macros.toc   its metadata, and one file line: Macros.xml
  Macros.xml                every file, in load order
  Macros.lua                its settings, the pack's class macros, the macro icons and the module table (ns.Macros)
  Constants.lua             the limits, icons and command sets several files share (M.C)
  Data/
    Items.lua               the mana potions and bandages the Smart Macros use, best first (M.Items)
  Commands.lua              the commands the game knows, whose they are, and what would fail when pressed (M.Commands)
  Store.lua                 the game's macros, the pack's and the Library's, and the icon each shows (M.Store)
  Smart.lua                 the Smart Macros: their text, writing them out of combat, their events (M.Smart)
  Profile.lua               a pack's class macro made on this character and picked up (ns.PickupProfileMacro)
  Sharing.lua               macros as a string to share, and a shared string read back (M.Sharing)
  View/
    Style.lua               the Forge's colors, fonts and sizes, on top of Shared/Style.lua (M.Style)
    Parts.lua               the Forge's small parts: text, pools, icons, section titles, list rows (M.Parts)
  UI/
    SmartPage.lua           the Smart Macros tab (M.Forge, the window's shared state)
    Library.lua             the Library tab, and its Save a Macro picker (F.SavePicker)
    NewMacro.lua            the New Macro dialog on the Library tab (F.NewMacro)
    Window.lua              the window, its tabs, title bar and footer (ns.OpenMacroWindow)
    SettingsPage.lua        its settings page (Macros/Settings), declared as cards
  README.md                 this file
```

Each layer uses only the ones above it. `M.Forge` holds the window's shared state (the window and
the open tab) and the functions its UI files call on each other.

## Why

- NF Healthstone and NF Health Potion are NF Health split by item kind; NF Health itself is
  unchanged. NF Drink is the drink half of NF Food, and the Food Only setting (off) drops the
  drink from NF Food, so macros players already have do not change.
- A bag macro (health, healthstone, health potion, mana, food, drink, bandage) is made with a bare
  `#showtooltip` when nothing in the bags matches, so it can be placed on a bar before the item
  arrives. It is filled when the item shows up, and a macro that already holds an item is left
  alone when the last one is used.
- Extra Lines is one single-line text row per bag macro (`<key>Extra`), because the settings
  engine has no multi-line box. A typed `\n` starts a new line; `;` cannot, as it already
  separates clauses inside a macro line. The lines go after the generated ones; if the macro
  would pass `LIMIT`, or they run a script (`Commands.RunsScript`), they are left out and the player
  gets a message once per text. A change to them, or to Food Only, rewrites the macro at once, even
  when it holds a placeholder or an item it would otherwise keep. The Smart Macros page lists what
  the generated lines use (`Smart.Body`), so an item named in the extras is not shown as the macro's.
- NF Health picks from the core's healing lists (`ns.HEALTHSTONES`, `ns.HEALING_POTIONS`, in
  `Shared/Game/Consumables.lua`), never Aura Buffs', so it works with Aura Buffs off. NF Mana's list
  (`ns.MANA_POTIONS`) is there too, so the Consumable Bar can tell mana potions apart without Macros.
- The Consumable Bar can carry every bag macro: NF Health, NF Healthstone, NF Health Potion, NF Mana,
  NF Food, NF Drink and NF Bandage (`ns.ConsumableMacros`).
  Its buttons run them by name, so this module's rewrite is all that keeps them current: a macro the
  bar uses (`ns.ConsumableBarUsesMacro`) is written and kept current whatever its switch or the
  module's, cannot be removed from here, and shows locked on in Kept Current. One written only for
  the bar goes when the bar stops using it; one switched on here stays. Which ones only the bar
  wanted is saved (`barOnly`), so that still holds after a `/reload`.
- `LIMIT` is 255: the game keeps only the first 255 bytes of a macro's text, counted in bytes.
- `NAME_MAX` is 16, the bytes a macro's name holds.
- `QUESTION` (134400) is the question mark icon. A macro made with it shows what `#showtooltip`
  names, so the Smart Macros and the macros the Library and Import add follow their spell or item
  unless the pack names an icon.
- `ACCEPT_ICON` (136814) is the ready check mark, NF Accept's icon; `FOCUS_ICON` (132212) stands
  for NF Focus on its Smart Macros card.
- The class macros (`classMacros`) live in the profile's `utilityReminders`, not in the module's
  own settings, so they travel with shared profile packs; the window's look stays in the module.
- Icons once picked for a pack macro are still kept by macro name in the account settings, outside
  the profile, so a pack export never carries them; the Library and the pack hand-off use them over
  the pack's own.
- The window has no macro editor: the game's own macro window (`/macro`) already edits, renames and
  deletes macros, and a second one only had to keep up with it. Library cards, Import and the profile
  hand-off add character macros, and say so in `/macro`. New Macro is only a way to write a macro into
  the Library, not an editor: a name and its text (a name holds 16 bytes and the text 255, both capped
  by the boxes), saved under your class like Save a Macro does, and added to this character too with
  Save and Add. Changing one later is `/macro` for a game macro, or saving the same name again to
  update its Library copy.
- The known commands come from the client's `SLASH_` and `EMOTE_CMD` strings. Commands of addons
  that are not loaded are missing from that list, so an unknown command is a warning, not an error.
- The Smart Macros' item lists are classic-era item IDs, best first.
- Chat commands take no conditionals, so NF Focus's announce channel is chosen when the macro is
  written, and the macro is written again on roster changes.
- Only switching a Smart Macro or the module off deletes its macro. A profile or spec switch that
  turns one off leaves it, since deleting a macro also empties its action bar slots.
- Nothing is written before the first `PLAYER_ENTERING_WORLD`, when the character's macros are
  loaded: `GetMacroIndexByName` misses them earlier and every macro would be made twice.
- `UPDATE_MACROS` fires when a macro is deleted, so a Smart Macro that did not fit is made once
  there is room.
- Macros cannot change in combat: a Smart Macro's write waits for `PLAYER_REGEN_ENABLED`, and
  every create, edit, delete and pickup refuses in combat.
- Profile macros and shared strings come from other players, so one that runs a script (`/run`,
  `/script`, `/dump`) is made only after the player says yes.
- A shared macro string is read as data, never run: names and texts within the game's limits, no
  more macros than the game holds, and the decoder's size, depth and value caps.

## Checking

- `luacheck NaowhForever_Macros` from the repo root.
- `lua Tools/regression/test-macros.lua`: the Smart Macros and profile macros against stubbed
  macro, bag and item APIs, with the Food & Drink Bar.
- `lua Tools/regression/test-macro-window.lua`: the window built from the real files, both tabs
  drawn and their controls used.
