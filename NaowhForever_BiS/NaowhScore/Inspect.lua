-- Inspect.lua: other players' Naowh Scores: kept, inspected one at a time, on their tooltips.
local ns = _G.NaowhForever

local Score = ns.NaowhScore
local S = ns.QoLSettings
local T = ns.THEME

local INSPECT_GAP = 2
local WAIT_FOR = 4
local KEEP = 300
local RETRY = 5
local USER_WAIT = 8
local MAX_KEPT = 300
local SAVED_MAX = 500
local SAVED_DAYS = 30
local DAY = 86400
local LOAD_SETTLE = 0.2
local WANTED_MIN = 0.1
local INSPECT_DISTANCE = 1
local RAID_SIZE, PARTY_SIZE = 40, 4
local STALE = 0
local VALUE_RGB = { r = 1, g = 1, b = 1 }
local LABEL = "Naowh Score"
local WAITING = "..."
local ASKED, WAIT, FAR = "asked", "wait", "far"
local TOOLTIP_RIGHT = "GameTooltipTextRight"
local AROUND = { "target", "focus", "mouseover" }
local SCAN_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED" }
local NEARBY_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED" }

local RAID, PARTY = {}, {}
for i = 1, RAID_SIZE do RAID[i] = "raid" .. i end
for i = 1, PARTY_SIZE do PARTY[i] = "party" .. i end

local kept = {}
local keptCount = 0
local pending = {}
local lastAsked = 0
local claimed = false
local shownGUID, shownLine
local saved, savedCount
local userAt = -USER_WAIT
local links = {}
local loadQueued = false
local scanQueued = false
local wantedQueued = false
local wantedUnit, wantedGUID
local plates = {}
local far
local hooked, userHooked = false, false
local Scan
local events = CreateFrame("Frame")

local function Feature()
    return S.Get("enabled") == true and S.Get("naowhScore") == true
end

local function TooltipOn() return Feature() and S.Get("naowhScoreTooltip") == true end
local function ScanOn() return Feature() and S.Get("naowhScoreScan") == true end
local function NearbyOn() return Feature() and S.Get("naowhScoreNearby") == true end

local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end

local function Prune()
    if keptCount < MAX_KEPT then return end
    local oldestGUID, oldestAt
    for guid, entry in pairs(kept) do
        local at = entry.at or 0
        if not oldestAt or at < oldestAt then oldestGUID, oldestAt = guid, at end
    end
    kept[oldestGUID] = nil
    keptCount = keptCount - 1
end

local function Entry(guid)
    local entry = kept[guid]
    if not entry then
        Prune()
        entry = { at = GetTime() }
        kept[guid] = entry
        keptCount = keptCount + 1
    end
    return entry
end

local function Saved()
    if saved then return saved end
    local account = ns.AccountSettings()
    if type(account.naowhScoreGuild) ~= "table" then account.naowhScoreGuild = {} end
    saved, savedCount = account.naowhScoreGuild, 0
    local oldest = time() - SAVED_DAYS * DAY
    for guid, entry in pairs(saved) do
        if type(entry) ~= "table" or type(entry.score) ~= "number" or type(entry.at) ~= "number"
            or entry.at < oldest then
            saved[guid] = nil
        else
            savedCount = savedCount + 1
        end
    end
    return saved
end

local function DropOldestSaved(list)
    local oldestGUID, oldestAt
    for key, old in pairs(list) do
        if not oldestAt or old.at < oldestAt then oldestGUID, oldestAt = key, old.at end
    end
    list[oldestGUID] = nil
    savedCount = savedCount - 1
end

local function Save(guid, score, level)
    if not Feature() or not ns.InGuild(guid) then return end
    local list = Saved()
    local entry = list[guid]
    if not entry then
        if savedCount >= SAVED_MAX then DropOldestSaved(list) end
        entry = {}
        list[guid] = entry
        savedCount = savedCount + 1
    end
    entry.score, entry.level, entry.at = score, level, time()
end

local function Refresh(guid, entry)
    if guid ~= shownGUID or not shownLine or GameTooltip:IsForbidden() or not GameTooltip:IsShown() then return end
    local data = GameTooltip:GetPrimaryTooltipData()
    local showing = data and data.guid
    if not Readable(showing) or showing ~= guid then return end
    local right = _G[TOOLTIP_RIGHT .. shownLine]
    if right then
        right:SetText(Score.Tooltip(entry.score, entry.level))
        GameTooltip:Show()
    end
end

local function Remember(guid, score, complete, shared, level)
    local entry = Entry(guid)
    if entry.shared and not shared then return entry end
    entry.score, entry.complete, entry.shared, entry.at = score, complete, shared == true, GetTime()
    entry.level = level or entry.level
    if complete then Save(guid, score, entry.level) end
    Refresh(guid, entry)
    return entry
end

local function Known(guid)
    local entry = kept[guid]
    if entry and entry.score and (entry.shared or GetTime() - entry.at < KEEP) then return entry end
end

local function UserInspecting()
    local talents = PlayerSpellsFrame
    if talents and talents.IsInspecting and talents:IsInspecting() then return true end
    local frame = InspectFrame
    if not frame then return false end
    return frame:IsShown() or (frame.unit ~= nil and GetTime() - userAt < USER_WAIT)
end

local function UserInspected()
    userAt = GetTime()
    lastAsked = userAt
    pending.guid, pending.onReady = nil, nil
end

local function Busy()
    return UserInspecting() or (pending.guid ~= nil and GetTime() - pending.at < WAIT_FOR)
end

local function InRange(unit)
    return CanInspect(unit) and CheckInteractDistance(unit, INSPECT_DISTANCE)
end

local function CanAsk(unit)
    return not Busy() and not InCombatLockdown() and GetTime() - lastAsked >= INSPECT_GAP and InRange(unit)
end

local function Ask(unit, guid, onReady)
    pending.guid, pending.unit, pending.at, pending.onReady = guid, unit, GetTime(), onReady
    lastAsked = GetTime()
    NotifyInspect(unit)
end

local function KeepLinks(entry, complete)
    if complete then
        entry.links = nil
        return
    end
    entry.links = entry.links or {}
    wipe(entry.links)
    for slot, link in pairs(links) do entry.links[slot] = link end
end

local function Ready(guid)
    if pending.guid ~= guid then return false end
    local unit, onReady = pending.unit, pending.onReady
    pending.guid, pending.onReady = nil, nil
    local now = UnitExists(unit) and UnitGUID(unit)
    if not Readable(now) or now ~= guid then return true end
    wipe(links)
    for slot in pairs(Score.SLOTS) do links[slot] = GetInventoryItemLink(unit, slot) end
    local entry = Entry(guid)
    local score, complete = Score.Links(links)
    KeepLinks(entry, complete)
    Score.Remember(guid, score, complete, false, UnitLevel(unit))
    if not complete then events:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    if onReady then onReady(guid, unit) end
    if not UserInspecting() then ClearInspectPlayer() end
    return true
end

local function ReadLoaded(guid, entry)
    local score, complete = Score.Links(entry.links)
    entry.score, entry.complete = score, complete
    if complete then
        entry.links = nil
        Save(guid, score, entry.level)
    end
    Refresh(guid, entry)
    return complete
end

local function ItemsLoaded()
    loadQueued = false
    local waiting = false
    for guid, entry in pairs(kept) do
        if entry.links and not entry.complete and not entry.shared and not ReadLoaded(guid, entry) then
            waiting = true
        end
    end
    if not waiting then events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local function QueueItemsLoaded()
    if loadQueued then return end
    loadQueued = true
    C_Timer.After(LOAD_SETTLE, ItemsLoaded)
end

local function ScanDue()
    scanQueued = false
    Scan()
end

local function WantedDue()
    wantedQueued = false
    Scan()
end

local function Wanted()
    if not wantedGUID then return nil end
    local now = UnitExists(wantedUnit) and UnitGUID(wantedUnit)
    if not Readable(now) or now ~= wantedGUID or Score.Known(wantedGUID) then
        wantedUnit, wantedGUID = nil, nil
        return nil
    end
    return wantedUnit
end

local function ScanSoon(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay, ScanDue)
end

local function Request(unit, guid, onReady)
    if Busy() or InCombatLockdown() or GetTime() - lastAsked < INSPECT_GAP then return WAIT end
    if not InRange(unit) then return FAR end
    Ask(unit, guid, onReady)
    return ASKED
end

local function Try(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player")
        or not UnitIsConnected(unit) then
        return nil
    end
    local guid = UnitGUID(unit)
    if not Readable(guid) or Score.Known(guid) then return nil end
    return Request(unit, guid)
end

local function Step(unit)
    local result = Try(unit)
    if result == ASKED then
        ScanSoon(WAIT_FOR)
        return true
    elseif result == WAIT then
        ScanSoon(INSPECT_GAP)
        return true
    elseif result == FAR then
        far = true
    end
    return false
end

local function StepGroup()
    local raid = IsInRaid()
    local units = raid and RAID or PARTY
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, math.min(count, #units) do
        if Step(units[i]) then return true end
    end
    return false
end

local function StepNearby()
    for i = 1, #AROUND do
        if Step(AROUND[i]) then return true end
    end
    for unit in pairs(plates) do
        if Step(unit) then return true end
    end
    return false
end

function Scan()
    if InCombatLockdown() or claimed then return end
    far = false
    local wanted = Wanted()
    if wanted and Step(wanted) then return end
    if ScanOn() and StepGroup() then return end
    if NearbyOn() and StepNearby() then return end
    if far then ScanSoon(RETRY) end
end

local function GearChanged(unit)
    if not Readable(unit) then return end
    local isMe = UnitIsUnit(unit, "player")
    if not Readable(isMe) or isMe then return end
    local guid = UnitGUID(unit)
    local entry = Readable(guid) and kept[guid]
    if entry and not entry.shared then entry.at = STALE end
    ScanSoon(INSPECT_GAP)
end

local function OnEvent(_, event, arg)
    if event == "INSPECT_READY" then
        if Readable(arg) and Ready(arg) and (ScanOn() or wantedGUID) then ScanSoon(INSPECT_GAP) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        QueueItemsLoaded()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if Readable(arg) and UnitIsPlayer(arg) then
            plates[arg] = true
            ScanSoon(INSPECT_GAP)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if Readable(arg) then plates[arg] = nil end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        GearChanged(arg)
    else
        ScanSoon(INSPECT_GAP)
    end
end

local function WantNext(unit, guid)
    wantedUnit, wantedGUID = unit, guid
    if wantedQueued then return end
    wantedQueued = true
    C_Timer.After(math.max(WANTED_MIN, INSPECT_GAP - (GetTime() - lastAsked)), WantedDue)
end

local function TheirValue(unit, guid, level)
    local entry = Score.Known(guid)
    if entry then return Score.Tooltip(entry.score, level) end
    if CanAsk(unit) then
        Ask(unit, guid)
    elseif pending.guid ~= guid then
        WantNext(unit, guid)
    end
    return WAITING
end

local function OnUnit(tooltip)
    if not TooltipOn() or tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if not Readable(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not Readable(guid) then return end
    local level = UnitLevel(unit)
    local value
    if UnitIsUnit(unit, "player") then
        value = Score.Tooltip((Score.Unit("player")), level)
    else
        value = TheirValue(unit, guid, level)
    end
    local a, v = T.accent, VALUE_RGB
    tooltip:AddDoubleLine(LABEL, value, a.r, a.g, a.b, v.r, v.g, v.b)
    shownGUID, shownLine = guid, tooltip:NumLines()
end

local function RosterScore(guid, info)
    if guid == UnitGUID("player") then return (Score.Unit("player")) end
    if info.presence == Enum.ClubMemberPresence.Offline then
        local entry = Saved()[guid]
        if entry then return entry.score, entry.level, entry.at end
        return nil
    end
    local entry = Score.Known(guid)
    return entry and entry.score
end

local function OnRoster(tooltip, guid, info)
    if not TooltipOn() then return end
    local score, level, when = RosterScore(guid, info)
    if not score then return end
    local text = Score.Tooltip(score, level or info.level)
    if when then text = text .. " " .. ns.Color("muted", "(" .. ns.Shared.Ago(when) .. ")") end
    local a, v = T.accent, VALUE_RGB
    tooltip:AddDoubleLine(LABEL, text, a.r, a.g, a.b, v.r, v.g, v.b)
    return true
end

local function HookUser()
    if userHooked or not InspectUnit then return end
    userHooked = true
    hooksecurefunc("InspectUnit", UserInspected)
end

local function Hook()
    HookUser()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
    ns.Shared.Roster.AddTooltip(OnRoster)
end

local function ReadPlates()
    wipe(plates)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if Readable(unit) and UnitIsPlayer(unit) then plates[unit] = true end
    end
end

local function ListenReady()
    if Feature() or claimed then events:RegisterEvent("INSPECT_READY") else events:UnregisterEvent("INSPECT_READY") end
end

local function ListenNearby()
    for _, event in ipairs(NEARBY_EVENTS) do
        if NearbyOn() then
            events:RegisterEvent(event)
        elseif not (ScanOn() and event == "PLAYER_REGEN_ENABLED") then
            events:UnregisterEvent(event)
        end
    end
end

local function Apply()
    local on = Feature()
    if on and not hooked then
        hooked = true
        C_Timer.After(0, Hook)
    end
    ListenReady()
    for _, event in ipairs(SCAN_EVENTS) do
        if ScanOn() then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    ListenNearby()
    if NearbyOn() then ReadPlates() else wipe(plates) end
    if ScanOn() or NearbyOn() then ScanSoon(INSPECT_GAP) end
end

local function OnSetting(key)
    if key == "enabled" or key:find("^naowhScore") then Apply() end
end

local Queue = { GAP = INSPECT_GAP, WAIT_FOR = WAIT_FOR, RETRY = RETRY }
Queue.Request = Request
Queue.InRange = InRange

Score.On = Feature
Score.Remember = Remember
Score.Known = Known
Score.Scan = Scan
Score.InspectQueue = Queue

function Queue.Pending()
    if pending.guid and GetTime() - pending.at < WAIT_FOR then return pending.guid end
end

function Queue.Wait()
    return math.max(0, INSPECT_GAP - (GetTime() - lastAsked))
end

function Queue.Claim(on)
    claimed = on == true
    if claimed then HookUser() end
    ListenReady()
    if not claimed and (ScanOn() or NearbyOn()) then ScanSoon(INSPECT_GAP) end
end

events:SetScript("OnEvent", OnEvent)
S.OnChange(OnSetting)
hooksecurefunc(ns, "Apply", Apply)
