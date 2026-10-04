-------------------------------------------------------------------------------
--  NaowhForever_DiscoveryNearby.lua -- the nearby alert: a sound and a chat line when you
--  come within range of a library book you still need.
--
--  The game says when you start and stop moving but not where you are, so while you move this
--  checks your distance once a second, and once more as you stop. Only while the alert is on
--  and the zone you are in has a book left to find; standing still nothing runs.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.DiscoverySettings
local L = ns.Library

local INTERVAL = 1
-- Past this much of the range the alert rearms, so standing at its edge does not repeat it.
local REARM = 1.5

local ticker, zoneEvents, bagEvents, moveEvents
local zone, targets   -- the zone being watched and its books: { book, spot, worldPos }
local alerted = {}    -- quest ID -> true while you are still inside its range

local function On()
    return S.Get("enabled") and S.Get("nearbySound")
end

-- A spot's place on the continent, in yards, which is what distances are measured in.
local function WorldPos(mapID, x, y)
    local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    return pos
end

local function Check()
    local here = C_Map.GetPlayerMapPosition(zone, "player")
    local me = here and WorldPos(zone, here:GetXY())
    if not me then return end
    local range = S.Get("nearbyRange")
    local mx, my = me:GetXY()
    for _, t in ipairs(targets) do
        local tx, ty = t[3]:GetXY()
        local dist = math.sqrt((tx - mx) ^ 2 + (ty - my) ^ 2)
        local quest = t[1].quest
        if dist <= range and not alerted[quest] then
            alerted[quest] = true
            if S.Get("nearbyPing") then PlaySound(SOUNDKIT.MAP_PING, "Master") end
            if S.Get("nearbyChat") then
                ns.Print(("Library book nearby: %s, %d yards%s"):format(t[1].name, math.floor(dist),
                    t[2][4] and (" - " .. t[2][4]) or ""))
            end
        elseif dist > range * REARM then
            alerted[quest] = nil
        end
    end
end

local function StopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

local function Stop()
    StopTicker()
    zone, targets = nil, nil
    if bagEvents then bagEvents:UnregisterAllEvents() end
    if moveEvents then moveEvents:UnregisterAllEvents() end
end

local function Refresh()
    if not On() or IsInInstance() then return Stop() end
    local id = L.PlayerZone()
    local list = {}
    for _, item in ipairs(L.OnMap(id)) do
        local pos = WorldPos(id, item[2][2] / 100, item[2][3] / 100)
        if pos then list[#list + 1] = { item[1], item[2], pos } end
    end
    if #list == 0 then return Stop() end
    zone, targets = id, list
    -- Looting a book takes it off the list, and a zone with nothing left stops the ticker.
    bagEvents:RegisterEvent("BAG_UPDATE_DELAYED")
    bagEvents:RegisterEvent("QUEST_TURNED_IN")
    moveEvents:RegisterEvent("PLAYER_STARTED_MOVING")
    moveEvents:RegisterEvent("PLAYER_STOPPED_MOVING")
    Check()
    if IsPlayerMoving() then
        ticker = ticker or C_Timer.NewTicker(INTERVAL, Check)
    else
        StopTicker()
    end
end

local function Apply()
    if On() then
        if not zoneEvents then
            zoneEvents = CreateFrame("Frame")
            zoneEvents:SetScript("OnEvent", Refresh)
            bagEvents = CreateFrame("Frame")
            bagEvents:SetScript("OnEvent", Refresh)
            moveEvents = CreateFrame("Frame")
            moveEvents:SetScript("OnEvent", function(_, event)
                if event == "PLAYER_STARTED_MOVING" then
                    ticker = ticker or C_Timer.NewTicker(INTERVAL, Check)
                else
                    StopTicker()
                    Check()
                end
            end)
        end
        zoneEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    elseif zoneEvents then
        zoneEvents:UnregisterAllEvents()
    end
    Refresh()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "nearbySound" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
