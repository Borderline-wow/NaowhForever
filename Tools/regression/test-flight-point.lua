-- Run with Lua 5.1 from the repository root: the flight point reminder. An undiscovered neutral or
-- own-faction node in range names the place. Before this character's flight map has been opened,
-- a friendly node in range asks you to open a flight master's map, unless the map already marks it undiscovered.
-- A learned node, an enemy node, and a friendly node past 400 yards stay quiet. A capital names
-- its own flight point with no distance check, and stays quiet once that point is known.
-- Combat and a taxi hide it. Talking to a flight master records that
-- town's point without opening the flight map. The switch off registers nothing. The snapshot
-- is this character's GUID.

local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local NEUTRAL, HORDE, ALLIANCE = 0, 1, 2
local BARRENS, STORMWIND, UNDERCITY, CAVES = 1413, 1453, 1458, 9001
local DARKSHORE, KALIMDOR, DUSKWOOD, EASTERN_KINGDOMS = 1439, 1414, 1431, 1415
local AUBERDINE, RATCHET, STORMWIND_FP, DARKSHIRE, THORIUM = 26, 80, 2, 12, 74
local UNREACHABLE, CURRENT = 2, 0
local SECRET = "secret"
local GUID = "Player-1-GLYADIN"
local TAXI, VENDOR = 102, 101

local state = { map = BARRENS, pos = { x = 0, y = 0 }, faction = "Alliance", taxi = false,
    combat = false, secret = false, guid = GUID, nodes = {}, asked = nil, asks = 0, subzone = "", openNodes = {},
    options = {} }
local frames, named = {}, {}

local function NewFrame(name)
    local f = { events = {} }
    function f:SetScript(script, fn) self[script] = fn end
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterAllEvents()
        for event in pairs(self.events) do self.events[event] = nil end
    end
    function f:SetMovable() end
    function f:SetClampedToScreen() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetText(text) self.value = text end
    function f:GetStringWidth() return 10 end
    function f:SetTextColor() end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    frames[#frames + 1] = f
    if name then named[name] = f end
    return f
end

local function Listening(event)
    for i = 1, #frames do
        if frames[i].events[event] then return true end
    end
end

local function Fire(event)
    for i = 1, #frames do
        local f = frames[i]
        if f.events[event] and f.OnEvent then f:OnEvent(event) end
    end
end

local function Text()
    local f = named.NaowhForeverFlightPoint
    if not f or not f.shown then return nil end
    return f.text.value
end

local function Node(name, faction, x, learned, id)
    return { name = name, faction = faction, isUndiscovered = not learned, position = { x = x, y = 0 }, nodeID = id }
end

local function At(map, list)
    state.map, state.nodes = map, list
    Fire("ZONE_CHANGED")
    return Text()
end

local values, defaults = {}, {
    enabled = true, flightPoint = false, flightPointFont = "", flightPointFontSize = 12,
    flightPointOutline = "OUTLINE", flightPointBackground = "none", flightPointCustom = false,
    flightPointColor = { r = 0, g = 0x91 / 255, b = 0xed / 255 },
}
local S = { Get = function(k)
    local v = values[k]
    if v == nil then return defaults[k] end
    return v
end }
function S.Set(k, v) values[k] = v end

local account = {}
local ns = { L = dofile("Tools/regression/locale_stub.lua").L, QoLSettings = S,
    TownCapitals = { [STORMWIND] = true, [UNDERCITY] = true },
    AccountSettings = function() return account end,
    THEME = { accent = { r = 0, g = 0.5, b = 0.9 } },
    Font = function(parent)
        parent.text = NewFrame()
        return parent.text
    end,
    AlertStack = function() end,
    Apply = function() end, ShowUnlockMode = function() end, HideUnlockMode = function() end,
    Shared = {
        Parts = { HudBackdrop = function()
            return { SetMode = function(_, mode) return mode end }
        end, HudFont = function() end },
        Style = { CARD_PAD = 12 },
        Settings = { Page = function() return { Card = function() end } end,
            Look = function() return {} end, Group = function() return {} end },
        CharacterData = function(key, create)
            local guid = state.guid
            if not guid then return end
            local all = account[key]
            if type(all) ~= "table" then
                if not create then return end
                all = {}
                account[key] = all
            end
            local mine = all[guid]
            if type(mine) ~= "table" then
                if not create then return end
                mine = {}
                all[guid] = mine
            end
            return mine
        end,
    },
}

local env = {
    NaowhForever = ns,
    Enum = { UIMapType = { Zone = 3, Continent = 2 },
        FlightPathFaction = { Neutral = NEUTRAL, Horde = HORDE, Alliance = ALLIANCE },
        FlightPathState = { Unreachable = UNREACHABLE } },
    CreateFrame = function(_, name) return NewFrame(name) end,
    hooksecurefunc = function(t, key, callback)
        local orig = t[key]
        t[key] = function(...) orig(...); callback(...) end
    end,
    UIParent = {},
    UnitFactionGroup = function() return state.faction end,
    UnitName = function() return "Glyadin" end,
    GetRealmName = function() return "Forever" end,
    UnitGUID = function() return state.guid end,
    GetSubZoneText = function() return state.subzone end,
    GetTaxiMapID = function() return DARKSHORE end,
    UnitOnTaxi = function() return state.taxi end,
    UnitAffectingCombat = function() return state.combat end,
    issecretvalue = function(v) return state.secret and v == SECRET end,
    GetFileIDFromPath = function(path)
        if path == "Interface\\GossipFrame\\TaxiGossipIcon" then return TAXI end
    end,
    C_GossipInfo = { GetOptions = function() return state.options end },
    C_Map = {
        GetBestMapForUnit = function() return state.map end,
        GetMapInfo = function(id)
            if id == CAVES then return { mapID = CAVES, mapType = 4, parentMapID = UNDERCITY } end
            if id == DARKSHORE then return { mapID = DARKSHORE, mapType = 3, parentMapID = KALIMDOR } end
            if id == KALIMDOR then return { mapID = KALIMDOR, mapType = 2, parentMapID = 0 } end
            if id == BARRENS then return { mapID = BARRENS, mapType = 3, parentMapID = KALIMDOR } end
            if id == DUSKWOOD then return { mapID = DUSKWOOD, mapType = 3, parentMapID = EASTERN_KINGDOMS } end
            if id == EASTERN_KINGDOMS then return { mapID = EASTERN_KINGDOMS, mapType = 2, parentMapID = 0 } end
            if id == STORMWIND then return { mapID = id, mapType = 3, parentMapID = 0, name = "Stormwind City" } end
            return { mapID = id, mapType = 3, parentMapID = 0 }
        end,
        GetPlayerMapPosition = function() return state.pos end,
        GetWorldPosFromMapPos = function(_, pos) return 0, pos end,
    },
    C_TaxiMap = {
        GetTaxiNodesForMap = function(map)
            state.asked = map
            state.asks = state.asks + 1
            return state.nodes[map] or state.nodes
        end,
        GetAllTaxiNodes = function() return state.openNodes end,
    },
}
env._G = env
setmetatable(env, { __index = _G })
Load({ "NaowhForever_QoL/Travel/FlightPoint.lua" }, env)

Fire("PLAYER_LOGIN")
check("the switch off registers nothing", not Listening("ZONE_CHANGED") and not Listening("PLAYER_STOPPED_MOVING")
    and not Listening("GOSSIP_SHOW") and not Listening("TAXIMAP_OPENED") and not Listening("TAXIMAP_CLOSED")
    and not Listening("PLAYER_REGEN_DISABLED") and not Listening("PLAYER_CONTROL_LOST")
    and state.asked == nil and named.NaowhForeverFlightPoint == nil)

S.Set("flightPoint", true)
check("turning it on listens for a zone change", Listening("ZONE_CHANGED") and Listening("GOSSIP_SHOW")
    and Listening("TAXIMAP_OPENED") and Listening("TAXIMAP_CLOSED") and Listening("PLAYER_STOPPED_MOVING")
    and Listening("PLAYER_CONTROL_LOST"))

state.subzone, state.pos = "Auberdine", nil
check("a path the map marks undiscovered still says to learn it before any flight map",
    At(DARKSHORE, { Node("Auberdine, Darkshore", ALLIANCE, 0, false, AUBERDINE) }) == "Learn the Auberdine flight point")
state.options = { { icon = VENDOR } }
Fire("GOSSIP_SHOW")
check("a vendor's gossip leaves that reminder", Text() == "Learn the Auberdine flight point" and account.flightPoints == nil)
state.options = { { icon = VENDOR }, { icon = TAXI } }
Fire("GOSSIP_SHOW")
check("talking to the flight master hides an undiscovered point before any snapshot", Text() == nil
    and account.flightPoints[GUID][AUBERDINE] == true and account.flightPoints[GUID].seenMaps == nil)
account.flightPoints = nil
Fire("ZONE_CHANGED")
state.pos = { x = 0, y = 0 }
check("a confirmed gap wins over a nearer point we have not checked",
    At(DARKSHORE, { Node("Auberdine, Darkshore", ALLIANCE, 50, false, AUBERDINE),
        Node("Lor'danel, Darkshore", ALLIANCE, 10, true, 99) }) == "Learn the Auberdine flight point")
state.pos = nil
check("Auberdine's inn asks you to open the flight map before any snapshot",
    At(DARKSHORE, { Node("Auberdine, Darkshore", ALLIANCE, 0, true, AUBERDINE) }) == "Open a flight master's map to save the points you know")
check("a missing indoor position still counts the subzone as the town", Text() == "Open a flight master's map to save the points you know")
state.options = { { icon = TAXI } }
Fire("GOSSIP_SHOW")
check("talking to the flight master saves the point behind the open-map line", Text() == nil
    and account.flightPoints[GUID][AUBERDINE] == true and account.flightPoints[GUID].seenMaps == nil)
account.flightPoints = nil
state.nodes = { [KALIMDOR] = { Node("Auberdine, Darkshore", ALLIANCE, 8000, true, AUBERDINE) } }
Fire("ZONE_CHANGED")
check("an empty zone map uses the continent's flight points",
    Text() == "Open a flight master's map to save the points you know" and state.asked == KALIMDOR)
state.subzone = ""
Fire("ZONE_CHANGED")
check("an empty subzone is not the town", Text() == nil)

state.subzone = "Auberdine"
state.nodes = { Node("Auberdine, Darkshore", ALLIANCE, 0, true, AUBERDINE) }
state.openNodes = { { nodeID = AUBERDINE, state = CURRENT } }
Fire("TAXIMAP_OPENED")
check("a snapshot that marks the flight point known hides it", Text() == nil
    and account.flightPoints[GUID].seenMaps[KALIMDOR] == true and account.flightPoints[GUID][AUBERDINE] == true
    and account.flightPoints["Glyadin-Forever"] == nil)
state.openNodes = { { nodeID = AUBERDINE, state = UNREACHABLE } }
Fire("TAXIMAP_OPENED")
check("an unreachable snapshot keeps the reminder", Text() == "Learn the Auberdine flight point")
state.options = { { icon = TAXI } }
Fire("GOSSIP_SHOW")
check("talking to the flight master hides it without opening the map again", Text() == nil
    and account.flightPoints[GUID][AUBERDINE] == true and account.flightPoints[GUID].seenMaps[KALIMDOR] == true)
state.subzone, state.pos = "", { x = 0, y = 0 }

check("an undiscovered neutral node in range names the place",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100) }) == "Learn the Ratchet flight point")
check("an undiscovered flight point of your own faction names the place",
    At(BARRENS, { Node("Sentinel Hill, Westfall", ALLIANCE, 80) }) == "Learn the Sentinel Hill flight point")
check("a name with no comma is the whole name",
    At(BARRENS, { Node("Moonglade", ALLIANCE, 10) }) == "Learn the Moonglade flight point")
check("the nearer of two unlearned flight points wins",
    At(BARRENS, { Node("Far Town, The Barrens", NEUTRAL, 200), Node("Near Town, The Barrens", NEUTRAL, 50) })
    == "Learn the Near Town flight point")
check("400 yards is still the town",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 400) }) == "Learn the Ratchet flight point")

check("a flight path the map does not call undiscovered still reminds you until a snapshot says it is known",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100, true, RATCHET) }) == "Learn the Ratchet flight point")
check("a friendly flight point past 400 yards stays hidden",
    At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 401) }) == nil)
state.openNodes = { { nodeID = RATCHET, state = CURRENT } }
state.nodes = { Node("Ratchet, The Barrens", NEUTRAL, 50, true, RATCHET),
    Node("Camp Taurajo, The Barrens", NEUTRAL, 500, false, 77) }
state.map = BARRENS
Fire("TAXIMAP_OPENED")
check("a known flight point nearby does not stand in for one past 400 yards", Text() == nil)
check("a Kalimdor snapshot does not judge an Eastern Kingdoms point it never saw",
    At(DUSKWOOD, { Node("Darkshire, Duskwood", ALLIANCE, 50, true, DARKSHIRE) })
    == "Open a flight master's map to save the points you know")
check("the other faction's flight point stays hidden",
    At(BARRENS, { Node("Crossroads, The Barrens", HORDE, 20) }) == nil)

state.faction = "Horde"
check("a Horde character is reminded of a Horde flight point",
    At(BARRENS, { Node("Crossroads, The Barrens", HORDE, 20) }) == "Learn the Crossroads flight point")
state.faction = "Alliance"

check("Alliance in Undercity sees nothing",
    At(UNDERCITY, { Node("Undercity, Tirisfal", HORDE, 0) }) == nil and state.asked == UNDERCITY)
check("Alliance in a cave under Undercity still sees nothing",
    At(CAVES, { [UNDERCITY] = { Node("Undercity, Tirisfal", HORDE, 0) } }) == nil and state.asked == UNDERCITY)

check("a capital shows the flight point with no distance check",
    At(STORMWIND, { Node("Stormwind, Elwynn", ALLIANCE, 2000, false, STORMWIND_FP) }) == "Learn the Stormwind flight point")
check("a nearer town does not replace the capital's own flight point",
    At(STORMWIND, { Node("Darkshire, Duskwood", ALLIANCE, 0, false, DARKSHIRE),
        Node("Thorium Point, Searing Gorge", ALLIANCE, 10, false, THORIUM),
        Node("Stormwind, Elwynn", ALLIANCE, 2000, false, STORMWIND_FP) })
    == "Learn the Stormwind flight point")
account.flightPoints[GUID][STORMWIND_FP] = true
check("a known capital flight point hides Darkshire and Thorium Point",
    At(STORMWIND, { Node("Darkshire, Duskwood", ALLIANCE, 0, false, DARKSHIRE),
        Node("Thorium Point, Searing Gorge", ALLIANCE, 0, false, THORIUM),
        Node("Stormwind, Elwynn", ALLIANCE, 0, false, STORMWIND_FP) }) == nil)

state.secret, state.pos = true, { x = SECRET, y = 0 }
check("a secret coordinate hides the reminder", At(STORMWIND, { Node("Stormwind, Elwynn", ALLIANCE, 10) }) == nil)
state.secret, state.pos = false, { x = 0, y = 0 }

At(BARRENS, { Node("Ratchet, The Barrens", NEUTRAL, 100) })
Fire("PLAYER_REGEN_DISABLED")
check("combat hides it", Text() == nil)
Fire("PLAYER_REGEN_ENABLED")
check("leaving combat shows it again", Text() == "Learn the Ratchet flight point")

state.taxi = true
Fire("PLAYER_CONTROL_LOST")
check("a taxi hides it", Text() == nil)
state.taxi = false
Fire("PLAYER_CONTROL_GAINED")
check("landing shows it again", Text() == "Learn the Ratchet flight point")

state.asks = 0
Fire("PLAYER_STOPPED_MOVING")
check("a stop reuses the zone's flight points", state.asks == 0
    and Text() == "Learn the Ratchet flight point")
Fire("ZONE_CHANGED")
check("a zone change reads the flight points again", state.asks > 0
    and Text() == "Learn the Ratchet flight point")
state.asks = 0
Fire("TAXIMAP_OPENED")
check("opening the flight map reads the flight points again", state.asks > 0)

state.nodes = {}
ns.ShowUnlockMode()
check("Unlock Mode shows the sample line", Text() == "Learn the Ratchet flight point")
ns.HideUnlockMode()
check("leaving Unlock Mode hides it when no flight point is nearby", Text() == nil)

S.Set("flightPoint", false)
check("turning it off drops the events and hides the line", not Listening("ZONE_CHANGED")
    and not Listening("GOSSIP_SHOW") and not Listening("PLAYER_CONTROL_LOST") and Text() == nil)

print(checks .. " flight point checks passed")
