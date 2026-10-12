# Locales

The player-facing strings, by language. `enUS.lua` is the source catalog: its keys are the
English strings the addon uses, and `true` means the English key is also the displayed value.
The translations live in their own addon, `NaowhForever_Locales`, and only the one in use loads.

## Layout

```
Core/Locales/
  enUS.lua   the English catalog, and the fallback for every locale
NaowhForever_Language/
  Language.lua   nothing to run: the addon holds NaowhForeverLanguageDB, the language picked in Settings
NaowhForever_Locales/      load on demand
  Locales.xml   one file per language: deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW
```

## Adding a language

1. Copy `NaowhForever_Locales/deDE.lua` and name the copy with the WoW locale code.
2. Change the code on its second line, translate the values on the right and keep every key exactly.
3. Add the file to `NaowhForever_Locales/Locales.xml`, and the code and its name to `LANGUAGES` and
   `LANGUAGE_NAMES` in `Core/Core.lua`.

## Why

- The language is the one picked in Settings (Language), else the client's. Core.lua picks it before
  any file reads a string, because most files translate their strings once, as they load. A pick
  saved in Naowh Forever's own saved variables would come too late: they load after its files run.
  So the pick lives in `NaowhForever_Language`, a tiny addon Naowh Forever lists under OptionalDeps,
  whose saved variables are loaded before Naowh Forever's first file. A new pick needs a /reload.
- The translations are a load-on-demand addon, loaded by Core.lua only for a language other than
  English, so an English client never reads them. Each file returns at once unless its code is
  `NaowhForeverLocaleCode`, and the one in use fills `NaowhForeverTranslation`; `ns.L` looks there
  first, then in the English catalog.
- Korean and Chinese text needs the game's own fonts (`ns.LocaleFont`): no font the addon ships
  or offers has those characters, so every font path turns into the language's. Naowh covers
  Cyrillic; only Friz Quadrata (the Classic+ skin) swaps to its Cyrillic cut for Russian.
- Use `ns.L("English text")` for new player-facing text. It falls back to the English text when the
  active locale has not translated that key.
- Spell and item logic stays on IDs; Blizzard supplies their localized names.
- The shared parts translate what they show: settings rows, cards, groups and footers, tooltips,
  dialogs, title bars, tabs, links, section titles, notes and the HUD Editor's element names.
  Modules hand them the English text, which stays the key for saved data, caches, cog menus and
  the search index; the search also indexes the shown words, so both languages find a row.
- `ns.Upper` and `ns.Lower` change the case of accented letters too (Lua's own are byte-wise and
  leave "ü" as it is), and `ns.Upper` writes "ß" as "SS".
- A key that would mean two things gets its context in brackets, and `enUS.lua` gives its English
  text: `L["Back (slot)"] = "Back"` keeps the cloak slot apart from the Back button.
- The repository is ASCII only, except the translations, which are UTF-8.
