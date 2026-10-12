# Locales

The player-facing strings, by language. `enUS.lua` is the source catalog: its keys are the
English strings the addon uses, and `true` means the English key is also the displayed value.
Each other language is its own load-on-demand addon, `NaowhForever_<code>`, and only the one in
use loads.

## Layout

```
Core/Locales/
  enUS.lua   the English catalog, and the fallback for every locale
NaowhForever_Language/      always loaded, listed first in NaowhForever.toc's own Dependencies
  Language.xml
  Language.lua   nothing to run: the addon holds NaowhForeverLanguageDB, the language picked in Settings
NaowhForever_deDE/           load on demand, one such addon per language
  NaowhForever_deDE.toc
  deDE.xml
  deDE.lua    the strings
NaowhForever_esES/  NaowhForever_esMX/  NaowhForever_frFR/  NaowhForever_itIT/  NaowhForever_koKR/
NaowhForever_ptBR/  NaowhForever_ruRU/  NaowhForever_zhCN/  NaowhForever_zhTW/
  (the same layout, one per language)
```

## Adding a language

1. Copy `NaowhForever_deDE/` to `NaowhForever_<code>/`, and inside it rename every `deDE` to
   `<code>` (the folder's own files, the `.toc`'s `## Title`/`## Notes`, the `.xml`'s file name
   and its `<Script file>` line).
2. Translate the values on the right in `<code>.lua` and keep every key exactly.
3. Add the code and its name to `LANGUAGES` and `LANGUAGE_NAMES` in `Core/Core.lua`, and the
   `move-folders` line for the new addon to `.pkgmeta`.

## Why

- The language is the one picked in Settings (Language), else the client's. Core.lua picks it before
  any file reads a string, because most files translate their strings once, as they load. A pick
  saved in Naowh Forever's own saved variables would come too late: they load after its files run.
  So the pick lives in `NaowhForever_Language`, a tiny addon Naowh Forever requires (`##
  Dependencies`), whose saved variables are loaded before Naowh Forever's first file. It ships in
  every release the same as any other part of the addon, so this is a real requirement, not an
  OptionalDep: if it is ever missing the whole addon stays off instead of silently losing a saved
  language. A new pick needs a /reload.
- Each language is its own load-on-demand addon, loaded by Core.lua only for that one language, so
  an English client parses none of them and a German client parses only German. They used to share
  one addon with every language's file in its XML; that loaded (and so parsed) all ten files for
  any non-English player, each file skipping its own table-building with a locale-code guard but
  still paying to compile. One addon per language means the client loads only the file it needs.
- Korean and Chinese text needs the game's own fonts (`ns.LocaleFont`): no font the addon ships
  or offers has those characters, so every font path turns into the language's. Naowh covers
  Cyrillic; only Friz Quadrata (the Classic+ skin) swaps to its Cyrillic cut for Russian.
  `ns.LocaleFont` takes the font's requested name as well as its resolved path, and keys the
  Russian swap off the name (`FONT_CLASSIC`), not the resolved path: LibSharedMedia controls that
  path, not this addon, so matching the request is the stable half of the comparison.
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
