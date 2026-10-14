-- FlightPoint.lua: the QoL reminder to learn a town's flight point.
local ns = _G.NaowhForever

local issecretvalue = issecretvalue

local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WIDTH, ROOM = 300, 10
local STACK_ORDER = 6
local TOWN_RANGE = 400
local ZONE = Enum.UIMapType.Zone
local CONTINENT = Enum.UIMapType.Continent
local NEUTRAL = Enum.FlightPathFaction.Neutral
local HORDE = Enum.FlightPathFaction.Horde
local ALLIANCE = Enum.FlightPathFaction.Alliance
local UNREACHABLE = Enum.FlightPathState.Unreachable
local PAGE = "QoL/Travel"
local PLAYER = "player"
local STORE = "flightPoints"
local LEARN, ASK = "learn", "ask"
local TEXT_ALERT = "Flight Point Reminder"
local SAMPLE_PLACE = "Ratchet"
local TAXI_ICON = "Interface\\GossipFrame\\TaxiGossipIcon"

local TEXT = ns.L("Learn the %s flight point")
local OPEN = ns.L("Open a flight master's map to save the points you know")

local EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "PLAYER_STOPPED_MOVING", "GOSSIP_SHOW", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local REFRESH = { ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true,
    PLAYER_ENTERING_WORLD = true, TAXIMAP_OPENED = true, TAXIMAP_CLOSED = true }

local frame, unlocked, inCombat, taxiIcon
local cachedZone, cachedMap, cachedNodes
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("flightPoint")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function PlaceName(name)
    local comma = name:find(",", 1, true)
    if not comma then return name end
    return name:sub(1, comma - 1)
end

local function Edge(text, at)
    return at < 1 or at > #text or not text:sub(at, at):match("%a")
end

local function HasWord(hay, needle)
    if needle == "" then return false end
    local from = 1
    while true do
        local at = hay:find(needle, from, true)
        if not at then return false end
        if Edge(hay, at - 1) and Edge(hay, at + #needle) then return true end
        from = at + 1
    end
end

local function OwnCity(place, zoneName)
    if zoneName == "" then return false end
    return place == zoneName or HasWord(zoneName, place) or HasWord(place, zoneName)
end

local function Ours(faction)
    if faction == NEUTRAL then return true end
    local side = UnitFactionGroup(PLAYER)
    if side == "Horde" then return faction == HORDE end
    if side == "Alliance" then return faction == ALLIANCE end
    return false
end

local function Mine(create)
    return ns.Shared.CharacterData(STORE, create)
end

local function Kind(node, mine, seen)
    if not (Ours(node.faction) and node.name) then return nil end
    if mine and node.nodeID and mine[node.nodeID] == true then return nil end
    if node.isUndiscovered then return LEARN end
    if seen then
        if mine[node.nodeID] ~= true then return LEARN end
        return nil
    end
    return ASK
end

local function Up(id, mapType)
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType > mapType and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if info and info.mapType == mapType then return info.mapID end
end

local function Learn()
    local mine = Mine(true)
    local taxi = mine and GetTaxiMapID()
    if not taxi then return end
    local continent = Up(taxi, CONTINENT)
    if continent then
        mine.seenMaps = mine.seenMaps or {}
        mine.seenMaps[continent] = true
    end
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxi)) do
        if node.nodeID then mine[node.nodeID] = node.state ~= UNREACHABLE end
    end
end

local function Subzone()
    local text = GetSubZoneText()
    if not text or Secret(text) then return "" end
    return text
end

local function WorldOf(map, pos)
    if not map or not pos then return nil, false end
    if Secret(pos.x) or Secret(pos.y) then return nil, true end
    local _, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not world then return nil, false end
    if Secret(world.x) or Secret(world.y) then return nil, true end
    return world, false
end

local function Yards(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function ForgetNodes()
    cachedZone, cachedMap, cachedNodes = nil, nil, nil
end

local function Prepare(map, nodes)
    local ready = {}
    for i, node in ipairs(nodes) do
        local world, blocked = WorldOf(map, node.position)
        if blocked then return nil, true end
        ready[i] = { node = node, world = world }
    end
    return ready
end

local function NodesFor(zone)
    if cachedZone == zone and cachedNodes then return cachedMap, cachedNodes end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(zone)
    local map = zone
    if not nodes[1] then
        local info = C_Map.GetMapInfo(zone)
        map, nodes = nil, nil
        while info and info.parentMapID and info.parentMapID > 0 do
            local parent = info.parentMapID
            info = C_Map.GetMapInfo(parent)
            local list = C_TaxiMap.GetTaxiNodesForMap(parent)
            if list[1] then
                map, nodes = parent, list
                break
            end
            if not info or info.mapType <= CONTINENT then break end
        end
    end
    if not nodes then
        cachedZone, cachedMap, cachedNodes = zone, nil, {}
        return nil, cachedNodes
    end
    local ready, blocked = Prepare(map, nodes)
    if blocked then return nil, nil, true end
    cachedZone, cachedMap, cachedNodes = zone, map, ready
    return map, ready
end

local function Candidate(entry, map, zone, zoneName, player, subzone, mine, seen)
    local node = entry.node
    local kind = Kind(node, mine, seen)
    if not kind then return nil end
    local dist = player and entry.world and Yards(player, entry.world)
    local place = PlaceName(node.name)
    if ns.TownCapitals[zone] and map == zone then
        if not OwnCity(place, zoneName) then return nil end
    else
        local named = subzone ~= "" and subzone == place
        if not (named or (dist and dist <= TOWN_RANGE)) then return nil end
    end
    return kind, place, dist or math.huge
end

local function Scan(entries, map, zone, zoneName, player, subzone, mine, seen)
    local bestName, bestDist, bestID, ask, askDist, askID
    for _, entry in ipairs(entries) do
        local kind, place, rank = Candidate(entry, map, zone, zoneName, player, subzone, mine, seen)
        local node = entry.node
        if kind == LEARN and (not bestName or rank < bestDist) then
            bestName, bestDist, bestID = place, rank, node.nodeID
        elseif kind == ASK and (not ask or rank < askDist) then
            ask, askDist, askID = true, rank, node.nodeID
        end
    end
    local spoken
    if bestName then spoken = bestID else spoken = askID end
    return bestName, ask, spoken
end

local function Nearest()
    if inCombat or UnitOnTaxi(PLAYER) then return nil end
    local zone = Up(C_Map.GetBestMapForUnit(PLAYER), ZONE)
    if not zone then return nil end
    local here = C_Map.GetBestMapForUnit(PLAYER)
    local player, secret = WorldOf(here, here and C_Map.GetPlayerMapPosition(here, PLAYER))
    if secret then return nil end
    local info = C_Map.GetMapInfo(zone)
    local subzone, mine = Subzone(), Mine()
    local seen = mine and mine.seenMaps and mine.seenMaps[Up(zone, CONTINENT)]
    local map, entries, blocked = NodesFor(zone)
    if blocked or not map then return nil end
    local best, ask, spoken = Scan(entries, map, zone, info and info.name or "", player, subzone, mine, seen)
    if best then return best, nil, spoken end
    return nil, ask, spoken
end

local function Show(place)
    frame.text:SetText(place and TEXT:format(place) or OPEN)
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Update()
    if unlocked then
        Show(SAMPLE_PLACE)
        return
    end
    local place, ask = Nearest()
    if place or ask then Show(place) else frame:Hide() end
end

local function TaxiIcon()
    if taxiIcon ~= nil then return taxiIcon end
    local id = GetFileIDFromPath and GetFileIDFromPath(TAXI_ICON)
    taxiIcon = id and id ~= 0 and id or false
    return taxiIcon
end

local function TaxiGossip()
    local icon = TaxiIcon()
    if not icon then return end
    for _, option in ipairs(C_GossipInfo.GetOptions()) do
        if option.icon == icon then return true end
    end
end

local function Spoke()
    if not TaxiGossip() then return end
    local _, _, nodeID = Nearest()
    if not nodeID then return end
    local mine = Mine(true)
    if not mine then return end
    mine[nodeID] = true
end

local function OnEvent(_, event)
    if REFRESH[event] then ForgetNodes() end
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "TAXIMAP_OPENED" then
        Learn()
    elseif event == "GOSSIP_SHOW" then
        Spoke()
    end
    Update()
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverFlightPoint", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.text = ns.Font(frame, St.TEXT_SIZE, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    ns.AlertStack(frame, STACK_ORDER, TEXT_ALERT, PAGE, PAGE .. ":flightPoint")
end

local function Restyle()
    local size = S.Get("flightPointFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("flightPointBackground"))
    Parts.HudFont(frame.text, S.Get("flightPointFont"), size, S.Get("flightPointOutline"), frame.mode)
    local c = S.Get("flightPointCustom") and S.Get("flightPointColor") or T.accent
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame:SetSize(WIDTH, size + ROOM)
end

local function Apply()
    events:UnregisterAllEvents()
    ForgetNodes()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Restyle()
    inCombat = UnitAffectingCombat(PLAYER)
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    Update()
end

events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^flightPoint") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideUnlockMode", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared.Settings

Settings.Page(PAGE, S):Card({
    id = "flightPoint", name = "Flight Point Reminder", order = 12, switch = "flightPoint",
    help = "Text on screen in a town whose flight point you have not learned.",
    rows = {
        Settings.Look("flightPoint", { text = true, size = St.HUD_TEXT_RANGE, background = "card" }),
        Settings.Group("Colors"),
        { key = "flightPointCustom", label = "Custom Color", toggle = true,
          help = "Your own text color instead of the theme's accent." },
        { key = "flightPointColor", label = "Text Color", colour = true, needs = "flightPointCustom" },
    },
})
