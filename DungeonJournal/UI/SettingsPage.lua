-------------------------------------------------------------------------------
--  UI/SettingsPage.lua -- the Dungeon Journal's settings, three tabs in the options window:
--  Journal (a card that says where you stand and opens it, what it lists, its window and its
--  key), Quest Tracker (the tracker and sharing quests) and Map (the Journal beside the world
--  map, and Boss Loot at Cursor's key). What it lists comes from J.OPTION_GROUPS, the same list
--  the window's Filters menu is built from, so the two always match. Your latest kills and loot are in the window (UI/Recent.lua).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot
local Quests = J.Quests

S.OnChange(function(key)
    if key == "enabled" then ns.UI:RefreshPage(true) end
end)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local OPACITY_MIN = J.Style.OPACITY_MIN
local JOURNAL_OFF = "Turn on the Dungeon Journal"
local BIS_OFF = "Needs the BiS List"

-- The dungeon for you right now: the one you are in, else the first dungeon (not a raid)
-- whose range holds your level; nil when none does.
local function ForYou()
    local here = J.Current()
    if here then return here[1], true end
    local level = UnitLevel("player")
    for _, dungeon in ipairs(J.Dungeons()) do
        local levels = not dungeon.raid and J.Levels(dungeon)
        if levels and level >= levels[1] and level <= levels[2] then return dungeon, false end
    end
end

local function Headline()
    local dungeon, inside = ForYou()
    if not dungeon then return "Every dungeon and raid: what drops, your quests, and more." end
    local name = ns.Color("accentSoft", dungeon.name)
    if inside then return ("You are in %s."):format(name) end
    return ("%s is for your level (%s)."):format(name, J.LevelRange(dungeon))
end

-- Your quests there, as the Journal counts them; nil when there are none.
local function Detail()
    local dungeon = ForYou()
    if not (dungeon and dungeon.quests) then return end
    local toPickUp, inLog = Quests.Count(dungeon.quests)
    if toPickUp + inLog == 0 then return end
    local parts = {}
    if toPickUp > 0 then parts[#parts + 1] = ("%d to pick up"):format(toPickUp) end
    if inLog > 0 then parts[#parts + 1] = ("%d in your log"):format(inLog) end
    return "Your quests there: " .. table.concat(parts, ", ") .. "."
end

local function JournalOn() return S.Get("enabled") == true end
local function BisOn() return Loot.BisOn() end

-- Which side's dungeons are listed: the faction switch beside the window's search, as a
-- dropdown. Both settings are kept, so the switch and this always agree; the one turned on
-- is set first, so the list is never left with neither.
local FACTION_VALUES = { both = "Both Factions", Alliance = "Alliance Ground", Horde = "Horde Ground" }
local FACTION_ORDER = { "both", "Alliance", "Horde" }

local function FactionGet()
    local alliance, horde = S.Get("showAlliance"), S.Get("showHorde")
    if alliance and horde then return "both" end
    return alliance and "Alliance" or "Horde"
end

local function FactionSet(value)
    if value == "Horde" then
        S.Set("showHorde", true); S.Set("showAlliance", false)
    else
        S.Set("showAlliance", true); S.Set("showHorde", value ~= "Alliance")
    end
end

-- One of J.OPTION_GROUPS as a row: the same words as the Filters menu.
local function ListRows()
    local rows = {}
    for _, option in ipairs(J.OPTION_GROUPS[1].options) do
        local row = { key = option.key, label = option.label, toggle = true, help = option.tooltip }
        if option.needsBis then
            row.needs, row.why, row.help = BisOn, BIS_OFF, option.tooltip .. " " .. J.NEEDS_BIS
        end
        rows[#rows + 1] = row
    end
    rows[#rows + 1] = { label = "Dungeons Listed", choice = { FACTION_VALUES, FACTION_ORDER },
        get = FactionGet, set = FactionSet,
        help = "The dungeons on whose ground the list shows. Contested ones and the raids are always listed. "
            .. "Also the switch beside the Journal's search." }
    return rows
end

local function ListSummary(store)
    local hiding = 0
    for _, option in ipairs(J.OPTION_GROUPS[1].options) do
        if option.hides ~= nil and store.Get(option.key) == option.hides then hiding = hiding + 1 end
    end
    return FACTION_VALUES[FactionGet()] .. (hiding == 1 and ", 1 filter on" or (", %d filters on"):format(hiding))
end

local function MapSummary(store)
    local panel, factions = store.Get("mapPanel"), store.Get("mapFactions")
    if panel and factions then return "Dungeons and zones" end
    if panel then return "In dungeons" end
    if factions then return "In zones" end
    return "Nothing beside the map"
end

local function QuestsSummary(store)
    local ask, accept = store.Get("shareRequests"), store.Get("acceptShared")
    local text = "Off"
    if ask and accept then
        text = "Asks and accepts shared quests"
    elseif ask then
        text = "Asks for shared quests"
    elseif accept then
        text = "Accepts shared quests"
    end
    local where = store.Get("trackerAuto") and (store.Get("trackerOutside") and "everywhere" or "in dungeons")
        or store.Get("trackerOutside") and "outside dungeons"
    if where then text = text == "Off" and "Tracker " .. where or text .. ", tracker " .. where end
    return text
end

-- "80% opacity", for the part whose setting is key.
local function OpacitySummary(key)
    return function(store)
        return ("%d%% opacity"):format(math.floor((store.Get(key) or 1) * 100 + 0.5))
    end
end

-------------------------------------------------------------------------------
--  Journal
-------------------------------------------------------------------------------
local page = Settings.Page("Dungeon Journal/Journal", S)

page:Window({
    text = "Open Dungeon Journal",
    open = function() ns.OpenJournalWindow() end,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "lists", name = "What It Lists", order = 10,
    help = "What the Journal lists on a boss. The same switches as the Filters icon on its title bar.",
    summary = ListSummary,
    rows = ListRows(),
})

page:Card({
    id = "window", name = "Window", order = 90,
    help = "The Journal's own window.",
    summary = OpacitySummary("windowAlpha"),
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { OPACITY_MIN, 100, 5 }, unit = "%", scale = 0.01,
          help = "How solid the Journal's window and its side panels are." },
    },
})

page:Card({
    id = "keys", name = "Key Binding", order = 30,
    help = "The key that opens the Journal.",
    rows = {
        { label = "Open Dungeon Journal", binding = "NAOWHFOREVER_JOURNAL",
          help = "Press it to open or close the Dungeon Journal." },
    },
})

-------------------------------------------------------------------------------
--  Quest Tracker
-------------------------------------------------------------------------------
local tracker = Settings.Page("Dungeon Journal/Quest Tracker", S)

tracker:Card({
    id = "quests", name = "Quests", order = 10,
    help = "The quest tracker, and sharing dungeon quests with your group.",
    summary = QuestsSummary,
    rows = {
        { key = "trackerAuto", label = "Open Tracker in Dungeons", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Opens the quest tracker when you enter a dungeon with quests for you." },
        { key = "trackerOutside", label = "Show Outside Dungeons", toggle = true, needs = JournalOn,
          why = JOURNAL_OFF,
          help = "Opens the quest tracker out in the world, on the dungeon your quests are for." },
        { key = "hideGameTracker", label = "Hide the Game's Quest Tracker", toggle = true, needs = JournalOn,
          why = JOURNAL_OFF,
          help = "Fades out the game's quest tracker while this one is open in a dungeon." },
        { key = "shareRequests", label = "Quest Share Requests", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Ask your group to share a dungeon quest you don't have, from its group icon." },
        { key = "acceptShared", label = "Accept Shared Dungeon Quests", toggle = true, needs = JournalOn,
          why = JOURNAL_OFF,
          help = "Accepts dungeon quests your group shares with you straight away." },
    },
})

tracker:Card({
    id = "trackerwindow", name = "Window", order = 90,
    help = "The Dungeon Quest Tracker's window.",
    summary = OpacitySummary("trackerAlpha"),
    rows = {
        { key = "trackerAlpha", label = "Window Opacity", slider = { OPACITY_MIN, 100, 5 }, unit = "%", scale = 0.01,
          help = "How solid the Dungeon Quest Tracker is." },
    },
})

-------------------------------------------------------------------------------
--  Map
-------------------------------------------------------------------------------
local map = Settings.Page("Dungeon Journal/Map", S)

map:Card({
    id = "map", name = "Beside the World Map", order = 10,
    help = "The Journal beside the world map: bosses and loot in dungeons, factions outside.",
    summary = MapSummary,
    rows = {
        { key = "mapPanel", label = "Bosses and Loot in Dungeons", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Shows a dungeon's bosses and loot beside the world map while you are inside." },
        { key = "mapFactions", label = "Factions Beside the Map", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Shows the factions earned where you are beside the world map." },
    },
})

map:Card({
    id = "mapwindow", name = "Window", order = 90,
    help = "The map's window, the Journal beside the world map and Boss Loot at Cursor.",
    summary = OpacitySummary("mapAlpha"),
    rows = {
        { key = "mapAlpha", label = "Window Opacity", slider = { OPACITY_MIN, 100, 5 }, unit = "%", scale = 0.01,
          help = "How solid the map's window, the Journal beside the map and Boss Loot at Cursor are." },
    },
})

map:Card({
    id = "lootkey", name = "Boss Loot at Cursor", order = 20,
    help = "A key that shows a boss's loot at your cursor.",
    rows = {
        { label = "Boss Loot at Cursor", binding = "NAOWHFOREVER_BOSSLOOT",
          help = "Press it over a boss, or with one targeted, to see what it drops." },
    },
})
