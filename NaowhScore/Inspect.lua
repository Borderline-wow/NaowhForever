-------------------------------------------------------------------------------
--  Inspect.lua -- other players' Naowh Scores: kept by GUID, shown on their tooltips, read from
--  their gear by inspecting it as the game's own Inspect does (they need no addon), and for
--  your group in the background so theirs are ready before you hover.
--
--  A player running Naowh Forever sends theirs as it changes (Share.lua); that one is kept for
--  the session and always wins. Anyone else is inspected: one request at a time, INSPECT_GAP
--  apart, only in inspect range and out of combat, and never while the game's Inspect window
--  (or another request) holds the one inspect the game keeps; that score is kept KEEP seconds,
--  and dropped when they change gear. In the background, your group (Scan Your Group) and the
--  players around you (Scan Players Nearby: your target, focus and mouseover, and every player
--  whose nameplate shows) are read a step at a time, on their own events; while one not known
--  yet is out of inspect range the walk looks again RETRY later, and stops once none is left.
--  A tooltip shows "..." until the gear comes, and fills in when it does. On by default (QoL >
--  Naowh Score); turned off, its events go quiet and its hook does nothing.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Score = ns.NaowhScore
local S = ns.QoLSettings
local T = ns.THEME

local INSPECT_GAP = 2      -- seconds between two requests: the server drops ones that come faster
local WAIT_FOR = 4         -- seconds a request is waited on before another may go
local KEEP = 300           -- seconds an inspected score is kept
local RETRY = 5            -- seconds before looking again at a player not known yet but out of range
local MAX_KEPT = 300       -- players kept at most; the oldest goes first

-- In Naowh's blue, without the logo: that stays with the badge line (Badges), which says who
-- someone is, so the two never stack logos.
local LABEL = "Naowh Score"
local WAITING = "..."

local kept = {}            -- GUID -> { score, complete, at, shared, links? }
local keptCount = 0
local pending              -- { guid, unit, at } while a request is out
local lastAsked = 0
local shownGUID, shownLine -- the tooltip's player and the line our value is on

local function Feature()
    return S.Get("enabled") == true and S.Get("naowhScore") == true
end

local function TooltipOn() return Feature() and S.Get("naowhScoreTooltip") == true end
local function ScanOn() return Feature() and S.Get("naowhScoreScan") == true end
local function NearbyOn() return Feature() and S.Get("naowhScoreNearby") == true end
Score.On = Feature

local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end

-------------------------------------------------------------------------------
--  What is kept
-------------------------------------------------------------------------------
-- The oldest kept score goes when there are too many.
local function Prune()
    if keptCount <= MAX_KEPT then return end
    local oldestGUID, oldestAt
    for guid, entry in pairs(kept) do
        if not oldestAt or entry.at < oldestAt then oldestGUID, oldestAt = guid, entry.at end
    end
    kept[oldestGUID] = nil
    keptCount = keptCount - 1
end

local function Entry(guid)
    local entry = kept[guid]
    if not entry then
        entry = {}
        kept[guid] = entry
        keptCount = keptCount + 1
        Prune()
    end
    return entry
end

-- The tooltip's line, filled in now that the score is known.
local function Refresh(guid, entry)
    if guid ~= shownGUID or not shownLine or not GameTooltip:IsShown() then return end
    local right = _G["GameTooltipTextRight" .. shownLine]
    if right then
        right:SetText(Score.Tooltip(entry.score, entry.level))
        GameTooltip:Show()
    end
end

--- Keeps a player's score and level (for grading against their level): shared (sent by their
--- Naowh Forever, kept for the session and never replaced by an inspect) or inspected.
function Score.Remember(guid, score, complete, shared, level)
    local entry = Entry(guid)
    if entry.shared and not shared then return entry end
    entry.score, entry.complete, entry.shared, entry.at = score, complete, shared == true, GetTime()
    entry.level = level or entry.level
    Refresh(guid, entry)
    return entry
end

--- A player's kept score, while it is good: shared, or inspected within KEEP.
function Score.Known(guid)
    local entry = kept[guid]
    if entry and entry.score and (entry.shared or GetTime() - entry.at < KEEP) then return entry end
end

-------------------------------------------------------------------------------
--  Inspecting
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

-- The game's Inspect window, or a request of ours, holds the inspect the game keeps.
local function Busy()
    return (InspectFrame and InspectFrame:IsShown()) or (pending and GetTime() - pending.at < WAIT_FOR)
end

local function CanAsk(unit)
    return not Busy() and not InCombatLockdown() and GetTime() - lastAsked >= INSPECT_GAP
        and CanInspect(unit) and CheckInteractDistance(unit, 1)
end

local function Ask(unit, guid)
    pending = { guid = guid, unit = unit, at = GetTime() }
    lastAsked = GetTime()
    NotifyInspect(unit)
end

local links = {}   -- slot -> link, read once the gear arrives, reused

local function Ready(guid)
    if not (pending and pending.guid == guid) then return false end
    local unit = pending.unit
    pending = nil
    if not UnitExists(unit) or UnitGUID(unit) ~= guid then return true end
    wipe(links)
    for slot in pairs(Score.SLOTS) do links[slot] = GetInventoryItemLink(unit, slot) end
    local entry = Entry(guid)
    entry.links = entry.links or {}
    wipe(entry.links)
    for slot, link in pairs(links) do entry.links[slot] = link end
    local score, complete = Score.Links(entry.links)
    Score.Remember(guid, score, complete, false, UnitLevel(unit))
    -- An item's data still loading: worked out again when it comes.
    if not complete then events:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    -- Let the inspect go, unless the game's own window is using it.
    if not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
    return true
end

local function ItemsLoaded()
    local waiting = false
    for guid, entry in pairs(kept) do
        if entry.links and not entry.complete and not entry.shared then
            local score, complete = Score.Links(entry.links)
            entry.score, entry.complete = score, complete
            Refresh(guid, entry)
            if not complete then waiting = true end
        end
    end
    if not waiting then events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

-------------------------------------------------------------------------------
--  Your group, in the background: the first member in range whose score is not known, then
--  the next INSPECT_GAP later, until none is left
-------------------------------------------------------------------------------
local scanQueued = false
local Scan

local function ScanSoon(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay, function()
        scanQueued = false
        Scan()
    end)
end

-- The unit names walked, made once: the walk makes no strings of its own.
local RAID, PARTY = {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end
local AROUND = { "target", "focus", "mouseover" }
local plates = {}   -- nameplate unit -> true while a player's nameplate shows

-- One player looked at: "asked" (their gear asked for), "wait" (the inspect is busy, or too
-- soon after the last), "far" (not known yet, out of range), or nil (known, or no one to ask).
local function Try(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player")
        or not UnitIsConnected(unit) then
        return nil
    end
    local guid = UnitGUID(unit)
    if not Readable(guid) or Score.Known(guid) then return nil end
    if Busy() or GetTime() - lastAsked < INSPECT_GAP then return "wait" end
    if CanInspect(unit) and CheckInteractDistance(unit, 1) then
        Ask(unit, guid)
        return "asked"
    end
    return "far"
end

local far   -- a player not known yet was out of range, this walk

-- true once the walk is over for now: someone was asked, or the inspect is busy.
local function Step(unit)
    local result = Try(unit)
    if result == "asked" then
        ScanSoon(WAIT_FOR)
        return true
    elseif result == "wait" then
        ScanSoon(INSPECT_GAP)
        return true
    elseif result == "far" then
        far = true
    end
    return false
end

function Scan()
    if InCombatLockdown() then return end
    far = false
    if ScanOn() then
        local raid = IsInRaid()
        local units = raid and RAID or PARTY
        local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
        for i = 1, math.min(count, #units) do
            if Step(units[i]) then return end
        end
    end
    if NearbyOn() then
        for i = 1, #AROUND do
            if Step(AROUND[i]) then return end
        end
        for unit in pairs(plates) do
            if Step(unit) then return end
        end
    end
    if far then ScanSoon(RETRY) end
end
Score.Scan = Scan

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
events:SetScript("OnEvent", function(_, event, arg)
    if event == "INSPECT_READY" then
        if Readable(arg) and Ready(arg) and ScanOn() then ScanSoon(INSPECT_GAP) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ItemsLoaded()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if Readable(arg) and UnitIsPlayer(arg) then
            plates[arg] = true
            ScanSoon(INSPECT_GAP)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if Readable(arg) then plates[arg] = nil end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        -- A member's gear changed: an inspected score of theirs goes stale.
        if not Readable(arg) or UnitIsUnit(arg, "player") then return end
        local guid = UnitGUID(arg)
        local entry = Readable(guid) and kept[guid]
        if entry and not entry.shared then entry.at = 0 end
        ScanSoon(INSPECT_GAP)
    else   -- GROUP_ROSTER_UPDATE, PLAYER_REGEN_ENABLED
        ScanSoon(INSPECT_GAP)
    end
end)

-------------------------------------------------------------------------------
--  The tooltip: their score, kept or yours; else "..." while their gear is asked for
-------------------------------------------------------------------------------
local function OnUnit(tooltip)
    if not TooltipOn() or tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if not Readable(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not Readable(guid) then return end
    local value
    local level = UnitLevel(unit)
    if UnitIsUnit(unit, "player") then
        value = Score.Tooltip((Score.Unit("player")), level)
    else
        local entry = Score.Known(guid)
        if entry then
            value = Score.Tooltip(entry.score, level)
        else
            value = WAITING
            if CanAsk(unit) then Ask(unit, guid) end
        end
    end
    tooltip:AddDoubleLine(LABEL, value, T.accent.r, T.accent.g, T.accent.b, 1, 1, 1)
    shownGUID, shownLine = guid, tooltip:NumLines()
end

local hooked = false

-- The tooltip hook goes in a frame after Apply, once every module's Apply has run: tooltip
-- post-calls run in the order they were added, so the badge line (Badges, added in its Apply)
-- comes first, and the score under it, as one Naowh block.
local function Hook()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
    GameTooltip:HookScript("OnTooltipCleared", function() shownGUID, shownLine = nil, nil end)
end
local SCAN_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED" }
local NEARBY_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED" }

-- The players' nameplates already shown when Scan Players Nearby is turned on.
local function ReadPlates()
    wipe(plates)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if Readable(unit) and UnitIsPlayer(unit) then plates[unit] = true end
    end
end

-- Hooks go in the first time the feature is on, and stay inert while it is off; the events
-- are listened to only while it is on.
local function Apply()
    local on = Feature()
    if on and not hooked then
        hooked = true
        C_Timer.After(0, Hook)
    end
    if on then events:RegisterEvent("INSPECT_READY") else events:UnregisterEvent("INSPECT_READY") end
    for _, event in ipairs(SCAN_EVENTS) do
        if ScanOn() then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    for _, event in ipairs(NEARBY_EVENTS) do
        if NearbyOn() then
            events:RegisterEvent(event)
        elseif not (ScanOn() and event == "PLAYER_REGEN_ENABLED") then
            events:UnregisterEvent(event)
        end
    end
    if NearbyOn() then ReadPlates() else wipe(plates) end
    if ScanOn() or NearbyOn() then ScanSoon(INSPECT_GAP) end
end

S.OnChange(function(key)
    if key == "enabled" or key:find("^naowhScore") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
