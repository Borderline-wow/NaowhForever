# Macros

Naowh's Forge, the Macros module's own window (`/nfmacros`): your account and character
macros and your pack's in a list, the one you pick in an editor that counts its bytes against
the game's 255, marks the lines that will not work and says what each line does in plain words.
The Smart Macros (NF Health, NF Mana, NF Food, NF Bandage, NF Trinket 1 and 2, NF Focus, NF
Accept) are written by the module and kept on the best item or spell you carry, out of combat.
The Library keeps, by class, the macros you saved to it and those your profile pack brings.

## Layout

```
NaowhForever_Macros/
  NaowhForever_Macros.toc   its metadata, and one file line: Macros.xml
  Macros.xml                every file, in load order
  Macros.lua                its settings, the pack's class macros, the macro icons and the module table (ns.Macros)
  Constants.lua             the limits, icons and command sets several files share (M.C)
  Data/
    Items.lua               the mana potions and bandages the Smart Macros use, best first (M.Items)
  Text.lua                  reading a macro's text (ns.MacroText): problems, plain words, the editor's colors, Shorten
  Commands.lua              the commands the game knows, whose they are, and what would fail when pressed (M.Commands)
  Store.lua                 the game's macros, the pack's and the Library's, and the icon each shows (M.Store)
  Smart.lua                 the Smart Macros: their text, writing them out of combat, their events (M.Smart)
  Profile.lua               a pack's class macro made on this character and picked up (ns.PickupProfileMacro)
  Sharing.lua               macros as a string to share, and a shared string read back (M.Sharing)
  View/
    Style.lua               the Forge's colors, fonts and sizes, on top of Shared/Style.lua (M.Style)
    Parts.lua               the Forge's small parts: text, pools, icons, section titles, list rows (M.Parts)
  UI/
    Editor.lua              the editor: the macro being written, its meter, line numbers, problems, saving (M.Forge)
    Inspector.lua           beside the editor: Explain, Conditions, Commands and Icons
    MacroList.lua           My Macros' list
    SmartPage.lua           the Smart Macros tab
    Library.lua             the Library tab
    Window.lua              the window, its tabs, title bar and footer (ns.OpenMacroWindow)
    SettingsPage.lua        its settings page (Macros/Settings), declared as cards
  README.md                 this file
```

Each layer uses only the ones above it. `M.Forge` holds the window's shared state (the window,
the open tab, the macro in the editor) and the functions its UI files call on each other.

## Why

- NF Health picks from the core's healing lists (`ns.HEALTHSTONES`, `ns.HEALING_POTIONS`, in
  `Shared/Game/Consumables.lua`), never Aura Buffs', so it works with Aura Buffs off.
- `LIMIT` is 255: the game keeps only the first 255 bytes of a macro's text, counted in bytes.
- `NAME_MAX` is 16, the bytes a macro's name holds. The name box's `SetMaxBytes` is one more, as
  it counts the closing null byte.
- `QUESTION` (134400) is the question mark icon. A macro made with it shows what `#showtooltip`
  names, so the Smart Macros and new macros follow their spell or item; the editor writes an icon
  only when the player picked one.
- `ACCEPT_ICON` (136814) is the ready check mark, NF Accept's icon; `FOCUS_ICON` (132212) stands
  for NF Focus on its Smart Macros card.
- The class macros (`classMacros`) live in the profile's `utilityReminders`, not in the module's
  own settings, so they travel with shared profile packs; the window's look stays in the module.
- Icons the player picks for a pack macro are kept by macro name in the account settings, outside
  the profile, so a pack export never carries them and the author's icon can always come back.
- The known commands come from the client's `SLASH_` and `EMOTE_CMD` strings. Commands of addons
  that are not loaded are missing from that list, so an unknown command is a warning, not an error.
- A `@word` that is not a unit is a player's or pet's name, which the game takes. Only one close
  to a real unit, `NEAR` (2) edits away, is called a typo.
- An edit box cannot color its own text, so the editor holds the macro with color codes in it:
  Colorize puts them in, Strip takes them out, and PlainPos and CodedPos move the cursor between
  the two. A `|` the player types is doubled, as the game shows `||` as one `|`.
- A lone `/` names no command yet, so Explain says nothing for it.
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
- The game sorts macros by name and moves them whenever one is added, renamed or deleted, so the
  editor finds its macro again by the name and text it was last saved with, not by the index it
  was opened at.
- Sizing the editor's text box fires its `OnTextChanged`, which draws the line numbers again: the
  box is sized only when its height changes, or that ran every frame and the cursor never blinked.
- The editor's first draw can come before its page has a width, so it draws again when the page
  is sized, for lines to wrap at it.
- The cursor's line is kept in view on `OnScrollRangeChanged` too: the scroll range can grow a
  frame after the text does.
- `CODE_LINES` is 10: a macro rarely needs more lines. `NEAR_LIMIT` (220) turns the byte meter
  amber before the game's 255.

## Checking

- `luacheck NaowhForever_Macros` from the repo root.
- `lua Tools/regression/test-macro-text.lua`: the text rules (problems, plain words, colors, Shorten).
- `lua Tools/regression/test-macros.lua`: the Smart Macros and profile macros against stubbed
  macro, bag and item APIs, with the Food & Drink Bar.
- `lua Tools/regression/test-macro-window.lua`: the window built from the real files, every tab
  drawn and its controls used.
