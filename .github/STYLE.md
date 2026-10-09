# Naowh Forever house style

How every file in this addon is laid out and written. The rules a change is reviewed against
(off by default, cheap while on, no taint, Forever only, your own code) are in
[CONTRIBUTING.md](CONTRIBUTING.md); this is the shape the code takes. The Dungeon Journal
(`NaowhForever_DungeonJournal/`) is the reference: when in doubt, copy what it does.

A refactor to this style never changes behavior: no wording, default, saved-variable, setting
or db key, frame global name, binding, slash command or `ns.*` name read by another file
changes, and every taint and secret-value guard stays exactly as it is.

## 1. Where things go

### A module

```
NaowhForever_<Name>/
  NaowhForever_<Name>.toc   its metadata, and one file line: <Name>.xml
  <Name>.xml                every file, in load order
  <Name>.lua                its settings (UI.ModuleSettings), its registry and its public API
  Constants.lua             the numbers several of its files share (timings, limits, IDs)
  Loot.lua, Quests.lua      rules: one job each, nothing drawn (an event frame made on first enable)
  Data/                     data only, no logic; generated files are never edited by hand
  View/                     drawing a page on the shared row engine (one file per row kind)
    Style.lua               its own look, on top of Shared/Style.lua
  UI/                       where it shows: windows, trackers, map pins, popups
    SettingsPage.lua        its settings page, declared as cards
  Media/                    art only this module uses; shared icons and fonts are in Core/Media
  README.md                 Layout (the tree above, one line a file) and Why
```

- **Load order is layering.** `<Name>.lua`, `Constants.lua`, `Data/`, the rules, `View/`, then
  `UI/`. Each file uses only what loaded above it.
- `<Name>.lua` makes the module table (`ns.Journal`, short `J`). Everything the module shares
  hangs off it (`J.Loot`, `J.Style`, `J.C` for `Constants.lua`); only what other addons or the
  core call goes on `ns` itself.
- **Every module loads through its XML**, even a one-file one, so adding a file never touches
  a TOC. Add the file to `<Name>.xml` where its layer is.
- **Files are named plainly inside their folder**: `Loot.lua`, not `NaowhForever_JournalLoot.lua`.
  Only an addon folder and its TOC carry the NaowhForever_ prefix: the game names the addon by them.
- **README.md "Why"** holds what a comment used to: Forever API quirks, taint and secret-value
  reasons, why a number is what it is, load-order needs. Short plain sentences, one per point:

  ```
  ## Why

  - `PIN_DROP` is 2: the Naowh font leaves room above its capitals, so the pin is moved down
    to the letters.
  - The XP Bar fades the game's bars with SetAlpha, never Hide: hiding their containers
    tainted the action bars.
  ```

**A one-file module** (the Swing Timer) maps onto the same layout inside its one file:
`NaowhForever_SwingTimer.toc` lists `SwingTimer.xml`, which loads its file; the file runs in
layer order (settings and API, rules, drawing, the settings page last), its numbers at the
top, its look from `Shared/Style.lua`. When a part grows into a job of its own (a settings
page, a second bar), it moves into its own file in the folder its layer names, listed in
the XML.

### The core

`NaowhForever.toc` lists the libraries, the locales, then one XML per load point. **No area
edits it**: a file is added to its area's XML.

| Load point | What it loads |
| --- | --- |
| `Core\Locales\*.lua` | the locale tables, before the namespace; listed in the TOC because `AllowLoadTextLocale` is a TOC option |
| `Core\Core.xml` | the namespace and DB (`Core.lua`), the feature switches, presets, message senders, waypoints |
| `Core\Integrations\RestedXP\RestedXP.xml` | the Naowh themes in RestedXP Guides; needs the core's theme palettes |
| `Core\Options.xml` | the widget kit (`ns.UI`), Unlock Mode, the options window, the Game Menu button, the settings search |
| `Shared\Shared.xml` | what every module shares (see `Shared/README.md`) |
| `Core\Profiles.xml` | the profile strings, their dialogs and the Profiles page |
| `Core\Settings.xml` | the QoL settings store (`Settings.lua`), Naowh's setups applied to it, the Alerts group |
| `Core\Badges\Badges.xml` | the staff and patron lists, then the badges that read them |
| `Core\Pages.xml` | Patch Notes, Credits, the onboarding, after the Badges |

- An area that loads at two points has one XML per point, named for what it holds (Core's
  `Profiles.xml` and `Settings.xml`). A new file goes in the XML of the point it needs.
- **QoL** (`NaowhForever_QoL/`) is a module addon of one file per feature, in folders by its
  settings tab: its rules, its drawing, then its settings card at the end. A feature's data is
  `<Feature>Data.lua` before it; an XML template sits beside its Lua and is included in its place.
  Numbers several QoL files share go in `NaowhForever_QoL/Constants.lua`. Its settings store stays
  in the core (`Core/Settings.lua`), which the core and other modules read.
- **Core**, **Badges**, **Integrations** follow the same file anatomy. Each area keeps a
  `README.md` with Layout and Why, as `Shared/` does.
- **Shared** loads through `Shared.xml` before any module and makes nothing at load.
- **Art lives with its owner.** `Core/Media` holds what everyone uses: the icon set
  `Tools/media/make_media.py` draws, the fonts, links, navigation glyphs and voice clips. Art
  only one area uses sits in that area's `Media/` (`Core/Badges/Media`, `Core/Onboarding/Media`,
  `Core/Integrations/RestedXP/Media`, `NaowhForever_AuraBuffs/Media`, `NaowhForever_DungeonJournal/Media`,
  `NaowhForever_QoL/Media`, `NaowhForever_TopBar/Media`), so a module's art travels with its folder,
  and its README's Layout lists it.

## 2. File anatomy

Top to bottom, one job per file:

```lua
-- Skills.lua: the professions the Dungeon Journal lists recipes for.
local ns = _G.NaowhForever

local GetProfessionInfo = GetProfessionInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local J = ns.Journal
local S = J.Settings

local RECIPE_CLASS = 9
local SKILL_LINE = 7
local TEXT_NOT_YOURS = "Not one of your professions."

local skills = {}
local events

local function AddSkill(index)
    if not index then return end
    local line = select(SKILL_LINE, GetProfessionInfo(index))
    if line then skills[line] = true end
end

local function OnSkillsChanged()
    wipe(skills)
    local first, second = GetProfessions()
    AddSkill(first)
    AddSkill(second)
end

local Skills = {}
J.Skills = Skills

function Skills.IsRecipe(itemID)
    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    return classID == RECIPE_CLASS
end

function Skills.Note(line)
    if skills[line] then return nil end
    return TEXT_NOT_YOURS
end

local function Apply()
    if not S.Get("enabled") then
        if events then events:UnregisterAllEvents() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnSkillsChanged)
    end
    events:RegisterEvent("SKILL_LINES_CHANGED")
    OnSkillsChanged()
end

S.OnChange(Apply)
Apply()
```

1. The one-line header.
2. `local ns = _G.NaowhForever`.
3. Game APIs used in hot paths, aliased once (only those: an alias pins the function).
4. Module references: `T = ns.THEME`, `UI = ns.UI`, `Parts = ns.Shared.Parts`, the module table.
5. Constants, `UPPER_SNAKE`, then player-facing text as named locals.
6. File state: the locals the file owns, and reused scratch tables.
7. Local helpers, then event and script handlers.
8. The public functions, on the module table.
9. Event wiring and init last: register only while the feature is on, and drop it when it
   goes off (`S.OnChange`).

## 3. Naming and shape

- `PascalCase` for every function, local or public (`AddSkill`, `Loot.ReadFilters`).
- `camelCase` for locals and fields (`playerClass`, `usableOnly`).
- `UPPER_SNAKE` for constants (`MAX_LISTED`, `PIN_DROP`), short aliases for the usual tables
  (`ns`, `T`, `UI`, `S`, `J`, `Parts`, `St`).
- Handlers say what they answer: `OnBagUpdate`, `OnEnter`.
- A function does one thing and fits on a screen. Return early instead of nesting:
  `if not unit then return end`.
- **No tables or closures made in hot paths** (event handlers, OnUpdate, loops, sort
  comparators): hoist comparators and helpers to file scope, reuse scratch tables with `wipe`.
- One blank line between functions, none inside short ones.

## 4. Comments

Every Lua file keeps exactly one comment: its first line, `-- <File>.lua: <what it is>.`

```lua
-- Loot.lua: the Dungeon Journal loot rules.
```

Every XML file keeps one too, the first line inside `<Ui>`:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
    <!-- DungeonJournal.xml: the Dungeon Journal's files, in load order. -->
```

Nothing else: no section dividers, no inline notes, no `---@class` blocks, no commented-out
code. What a comment knew that the code does not say moves to the README's Why (section 1).
`Tools/` keeps its own comments.

## 5. Constants

No unexplained literal in logic. Sizes, offsets, timings, colors, IDs, limits and counts get
a name at the top of the file:

```lua
-- Before
C_Timer.After(0.2, Redraw)
icon:SetPoint("LEFT", text, "RIGHT", 4, -2)

-- After
local REDRAW_DELAY = 0.2
local ICON_GAP, PIN_DROP = 4, 2

C_Timer.After(REDRAW_DELAY, Redraw)
icon:SetPoint("LEFT", text, "RIGHT", ICON_GAP, -PIN_DROP)
```

- One file uses it: the top of that file. Several files: the module's `Constants.lua`
  (numbers) or `View/Style.lua` (look). Every module: `Shared/Style.lua`.
- Colors come from `ns.THEME` and the style tables, never as numbers in logic.
- Spell, item and NPC ID lists are data: `Data/`, keyed by ID, never matched by name.
- Player-facing text stays word for word, as a named local at the top
  (`local TEXT_NO_GROUP = "You are not in a group."`).
- Plain `0`, `1`, `-1`, `""`, `true`, `false` and array indexes need no name.
- When the name cannot say why a number is what it is, the README's Why does.

## 6. Feature switches

Every on/off switch of a feature, and its default, lives in one file:
`Core/Features.lua`, as `ns.FEATURES`, grouped by the settings store it is saved
in (`qol`, `journal`, `completo`, `discovery`, `pvp`, ...). It loads right after the core,
before every store. A module reads its switch defaults from it:

```lua
local F = ns.FEATURES.journal

local S = ns.UI.ModuleSettings("journal", {
    enabled = F.enabled,
    mapPanel = F.mapPanel,
    mapFactions = F.mapFactions,
    usableOnly = true,
})
```

- A switch is a module's `enabled` (or its `enabledKey`), a settings card's `switch`, or a
  toggle that turns a whole feature on by itself (Auto Repair, Hide Zone Text). A feature's
  options (sizes, colors, which parts show) stay in the module's own defaults.
- The keys are the saved keys: never rename one.
- A new feature adds its switch here, `false`, as CONTRIBUTING's first rule asks.
- Asking for a store or switch that is not there is an error, not nil, so a typo fails at load
  instead of turning a feature off.
- Build flags live here too: `ns.FEATURE_BADGES` is 0 until supporter badges launch (only the
  team's badges, on their defaults; no badge settings, patron lists or support mentions) and 1
  after.
- `Tools/regression/test-features.lua` checks every switch against its store's defaults. A
  test that stubs `ns` loads the real file into its stub before the module's files.

## 7. Shared components

Build every piece of UI from these; never hand-roll one, never copy one to change it. If one
almost fits, add an optional input that leaves every caller as it was. If none fits, add it to
`Shared/`, list it in `Shared/README.md`, and use it.

| Need | Use |
| --- | --- |
| A window | `Parts.Window`, `Parts.TitleBar`, `Parts.Opacity`, `Parts.BarButton`, `Parts.BarIcon`, `Parts.FooterBrand`, `Parts.Resizable` (`Shared/UI/Window.lua`), `Parts.Shadow` (`Shared/UI/Hud.lua`) |
| Tabs and search | `Parts.Tabs`, `Parts.SetTabs`, `Parts.PaintTabs`, `Parts.SearchBox` (`Shared/UI/Tabs.lua`) |
| A tracker | `Parts.TrackerPanel`, `Parts.RowBands` (`Shared/UI/Tracker.lua`) |
| A page of rows | `ns.Shared.View.New`, `View.NewKinds`; common rows in `Shared/View/Kinds.lua` |
| Settings | `UI.ModuleSettings` for the store, `ns.Shared.Settings.Page(page, S):Card{ ... }` for the page, `Settings.Look` for a HUD element's text and bar rows, `Settings.EditZone` and Studio for a live preview |
| Small parts | `Parts.Pill`, `Parts.SetPill`, `Parts.Link`, `Parts.SetLink`, `Parts.IconButton` (`Shared/UI/Parts.lua`), `Parts.ItemIcon` (`Shared/UI/Marks.lua`), `Parts.Coins`, `Parts.LabelRow` (`Shared/UI/Text.lua`), `Parts.Panel`, `Parts.SidePanel`, `Parts.Backdrop` (`Shared/UI/Panels.lua`); every part's file is in `Shared/README.md` |
| HUD | `Parts.HudBackdrop`, `Parts.HudText`, `Parts.HudFont`, `Parts.ProgressLine` (`Shared/UI/Hud.lua`), `Parts.TimerLine` (`Shared/UI/Timer.lua`) |
| Widgets (`Core/Options/Widgets.lua`) | `UI.BuildToggleControl`, `UI.BuildSliderCore`, `UI.BuildDropdownControl`, `UI.BuildColorSwatchControl`, `UI.KeyField`, `UI.SlimScroll`, `UI.Keep*` |
| Core chrome (`Core/Core.lua`) | `ns.Button`, `ns.Font`, `ns.Border`, `ns.AccentBorder`, `ns.Tooltip`, `ns.NewEditBox`, `ns.NewSearchBox`, `ns.Confirm`, `ns.PromptText`, `ns.MakeModal` |
| Moving it | `UI.AttachMover` (`Core/Unlock/Movers.lua`), so it shows in Unlock Mode |
| The look | `ns.THEME` (`T.bg`, `T.panel`, `T.line`, `T.fg`, `T.muted`, `T.accent`), `ns.Shared.Style`, and a module's `Style` made with `setmetatable({ ... }, { __index = ns.Shared.Style })` |

## 8. Checking

- `luacheck <files>` from the repo root (it reads `.luacheckrc`).
- `LUA="/c/Program Files (x86)/Lua/5.1/lua.exe" bash Tools/regression/run-all.sh` on Windows,
  `bash Tools/regression/run-all.sh` elsewhere. A test that slices source by a comment that is
  gone moves its anchor to real code; an assertion is never weakened.
- Addon files are Lua 5.1, ASCII only, CRLF. Check new files with a byte scan for LF-only lines.
