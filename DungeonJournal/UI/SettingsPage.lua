-------------------------------------------------------------------------------
--  UI/SettingsPage.lua -- the Dungeon Journal's settings page (Dungeon Journal/Settings in the
--  options window): a card that says where you stand and opens the Journal, then a card per
--  part. What it lists comes from J.OPTION_GROUPS, the same list the window's Filters menu is
--  built from, so the two always match. Your latest kills and loot are in the window (UI/Recent.lua).
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
    if ask and accept then return "Asks and accepts shared quests" end
    if ask then return "Asks for shared quests" end
    if accept then return "Accepts shared quests" end
    return "Off"
end

local function WindowSummary(store)
    return ("%d%% opacity"):format(math.floor((store.Get("windowAlpha") or 1) * 100 + 0.5))
end

local page = Settings.Page("Dungeon Journal/Settings", S)

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
    id = "map", name = "Beside the World Map", order = 20,
    help = "The Journal beside the world map (M): a dungeon's bosses and loot inside it, a zone's factions "
        .. "outside.",
    summary = MapSummary,
    rows = {
        { key = "mapPanel", label = "Bosses and Loot in Dungeons", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Inside a dungeon, opening the world map (M) shows its bosses and loot beside it." },
        { key = "mapFactions", label = "Factions Beside the Map", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "In a zone or a battleground, opening the world map (M) shows the factions earned there: your "
              .. "standing, their rewards and the quests that raise them." },
    },
})

page:Card({
    id = "quests", name = "Quests", order = 30,
    help = "Sharing dungeon quests with a group that runs Naowh Forever.",
    summary = QuestsSummary,
    rows = {
        { key = "shareRequests", label = "Quest Share Requests", toggle = true, needs = JournalOn, why = JOURNAL_OFF,
          help = "Click the group icon on a dungeon quest you do not have: the members on it are asked one at a "
              .. "time, and the first running Naowh Forever shares it. Off, you neither ask nor answer." },
        { key = "acceptShared", label = "Accept Shared Dungeon Quests", toggle = true, needs = JournalOn,
          why = JOURNAL_OFF,
          help = "Accepts a dungeon quest a group member shares with you as soon as it opens. Hold the Skip "
              .. "Modifier (QoL > Questing) to look at one first." },
    },
})

page:Card({
    id = "keys", name = "Key Bindings", order = 40,
    help = "Keys for the Journal, also in the game's Key Bindings under Naowh Forever.",
    rows = {
        { label = "Boss Loot at Cursor", binding = "NAOWHFOREVER_BOSSLOOT",
          help = "Hover a boss, or target one, and press this key: what it drops, at your cursor. Press it "
              .. "again to close it." },
        { label = "Open Dungeon Journal", binding = "NAOWHFOREVER_JOURNAL",
          help = "Press this key to open the Dungeon Journal, and again to close it." },
    },
})

page:Card({
    id = "window", name = "Window", order = 50,
    help = "The Journal's own window.",
    summary = WindowSummary,
    rows = {
        { key = "windowAlpha", label = "Window Opacity", slider = { OPACITY_MIN, 100, 5 }, unit = "%", scale = 0.01,
          help = "How solid the Journal's window is, in percent. Also on its title bar." },
    },
})
