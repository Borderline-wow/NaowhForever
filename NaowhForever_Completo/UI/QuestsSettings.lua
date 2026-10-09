-- QuestsSettings.lua: Completo's Quests settings page (Completo/Quests), declared as cards.
local ns = _G.NaowhForever

local Completo = ns.Completo
local S = Completo.Settings
local Q = Completo.Quests
local Settings = ns.Shared.Settings

local PAGE = "Completo/Quests"
local PIN_SIZE = ns.Shared.Style.PIN_SIZE_RANGE
local ORDER_QUESTS, ORDER_MAP_PINS = 10, 20
local TEXT_OFF = "Turn on Completo"
local TEXT_PROGRESS = "%d of %d zone quests done"
local TEXT_ZONE = "%s: %d of %d."
local TEXT_EVERY_QUEST = "Every quest of every zone, and where you are in each chain."
local TEXT_CHAINS = "Quest chains"
local TEXT_QUESTS = "Quests"
local TEXT_LOW_TOO = " you can pick up, low level ones too"
local TEXT_STILL_XP = " that still give experience"

local page = Settings.Page(PAGE, S)

local function On() return S.Get("enabled") == true end

local function Headline()
    Q.Refresh()
    return TEXT_PROGRESS:format(Q.Progress())
end

local function Detail()
    local zone = Q.CurrentZone()
    if not zone then return TEXT_EVERY_QUEST end
    local n, total = Q.ZoneProgress(zone)
    return TEXT_ZONE:format(zone.name, n, total)
end

local function OpenQuests()
    ns.OpenCompletoWindow("quests")
end

local function MapSummary(store)
    local what = store.Get("mapChainsOnly") and TEXT_CHAINS or TEXT_QUESTS
    return what .. (store.Get("mapGrey") and TEXT_LOW_TOO or TEXT_STILL_XP)
end

page:Window({
    text = "Open Quests",
    open = OpenQuests,
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "quests", name = "Quests", order = ORDER_QUESTS,
    help = "What a zone's page in the Completo window lists.",
    rows = {
        { key = "hideDone", label = "Hide Done", toggle = true,
          help = "Leave out the quests and chains you have finished." },
    },
})

page:Card({
    id = "mapPins", name = "Map Pins", order = ORDER_MAP_PINS, switch = "mapPins",
    help = "A yellow ! on the world map at every quest giver with a quest you can pick up that still gives "
        .. "experience. Hover it for the quests; click it for a waypoint.",
    summary = MapSummary,
    rows = {
        { key = "mapGrey", label = "Low Level Quests", toggle = true, needs = On, why = TEXT_OFF,
          help = "Also a grey ! for quests you can still pick up that no longer give experience." },
        { key = "mapChainsOnly", label = "Chains Only", toggle = true, needs = On, why = TEXT_OFF,
          help = "Only quest chains: the first quest of each one, and the next step of those you are on." },
        { key = "mapPinSize", label = "Pin Size", slider = PIN_SIZE, needs = On, why = TEXT_OFF,
          help = "How big the pins are on the map." },
    },
})
