-------------------------------------------------------------------------------
--  Inspect.lua -- other players' Naowh Scores: kept by GUID, shown on their tooltips, read from
--  their gear by inspecting it as the game's own Inspect does (they need no addon), and for
--  your group in the background so theirs are ready before you hover.
--
--  A player running Naowh Forever sends theirs as it changes (Share.lua); that one is kept for
--  the session and always wins. Anyone else is inspected: one request at a time, INSPECT_GAP
--  apart, only in inspect range and out of combat, and never while the game's Inspect window
--  (or the talents opened from it, or another request) holds the one inspect the game keeps;
--  that score is kept KEEP seconds, and dropped when they change gear. In the background, your
--  group (Scan Your Group) and the players around you (Scan Players Nearby: your target, focus
--  and mouseover, and every player whose nameplate shows) are read a step at a time, on their
--  own events; while one not known yet is out of inspect range the walk looks again RETRY
--  later, and stops once none is left. A tooltip shows "..." until the gear comes, and fills in
--  when it does. The player you hover goes first: while the inspect is busy they wait at the
--  front of the walk, asked as soon as it is free, for as long as you still hover them. On by default (QoL > Naowh Score); turned off, its events go quiet and its hook
--  does nothing. Group Inspect asks through the same one-at-a-time queue (Score.InspectQueue:
--  Request, Pending, Wait, InRange), and while its window is open it claims it (Claim): its walk goes
--  first and ours waits, and its request is read on INSPECT_READY before the inspect is let go.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Score = ns.NaowhScore
local S = ns.QoLSettings
local T = ns.THEME

local INSPECT_GAP = 2      -- seconds between two requests: the server drops ones that come faster
local WAIT_FOR = 4         -- seconds a request is waited on before another may go
local KEEP = 300           -- seconds an inspected score is kept
local RETRY = 5            -- seconds before looking again at a player not known yet but out of range
local USER_WAIT = 8        -- seconds your own inspect keeps ours waiting while its window loads
local MAX_KEPT = 300       -- players kept at most; the oldest goes first
local SAVED_MAX = 500      -- guildmates' scores saved for the guild list at most; the oldest goes first
local SAVED_DAYS = 30      -- a saved score older than this is dropped
local LOAD_SETTLE = 0.2
local WANTED_MIN = 0.1     -- the soonest a hovered player waiting their turn is looked at again

-- In Naowh's blue, without the logo: that stays with the badge line (Badges), which says who
-- someone is, so the two never stack logos.
local LABEL = "Naowh Score"
local WAITING = "..."

local kept = {}            -- GUID -> { score, complete, at, shared, links? }
local keptCount = 0
local pending = {}         -- guid, unit, at and onReady while a request is out; guid nil when none
local lastAsked = 0
local claimed = false
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
-- The oldest kept score goes to make room when the list is full.
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

-- Guildmates' last scores, saved account-wide for the guild list's offline members.
local saved, savedCount

local function Saved()
    if saved then return saved end
    local account = ns.AccountSettings()
    if type(account.naowhScoreGuild) ~= "table" then account.naowhScoreGuild = {} end
    saved, savedCount = account.naowhScoreGuild, 0
    local oldest = time() - SAVED_DAYS * 86400
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

local function Save(guid, score, level)
    if not Feature() or not ns.InGuild(guid) then return end
    local list = Saved()
    local entry = list[guid]
    if not entry then
        if savedCount >= SAVED_MAX then
            local oldestGUID, oldestAt
            for key, old in pairs(list) do
                if not oldestAt or old.at < oldestAt then oldestGUID, oldestAt = key, old.at end
            end
            list[oldestGUID] = nil
            savedCount = savedCount - 1
        end
        entry = {}
        list[guid] = entry
        savedCount = savedCount + 1
    end
    entry.score, entry.level, entry.at = score, level, time()
end

-- The tooltip's line, filled in now that the score is known, while the tooltip still shows them.
local function Refresh(guid, entry)
    if guid ~= shownGUID or not shownLine or GameTooltip:IsForbidden() or not GameTooltip:IsShown() then return end
    local data = GameTooltip:GetPrimaryTooltipData()
    local showing = data and data.guid
    if not Readable(showing) or showing ~= guid then return end
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
    if complete then Save(guid, score, entry.level) end
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

local userAt = -USER_WAIT

-- Your own inspect: the game's window open, or asked for and waiting for its gear.
local function UserInspecting()
    local talents = PlayerSpellsFrame
    if talents and talents.IsInspecting and talents:IsInspecting() then return true end
    local frame = InspectFrame
    if not frame then return false end
    return frame:IsShown() or (frame.unit ~= nil and GetTime() - userAt < USER_WAIT)
end

-- Your inspect wins: ours is dropped, so its answer can't clear yours, and waits its turn after.
local function UserInspected()
    userAt = GetTime()
    lastAsked = userAt
    pending.guid, pending.onReady = nil, nil
end

-- Your inspect, or a request of ours, holds the inspect the game keeps.
local function Busy()
    return UserInspecting() or (pending.guid ~= nil and GetTime() - pending.at < WAIT_FOR)
end

local function InRange(unit)
    return CanInspect(unit) and CheckInteractDistance(unit, 1)
end

local function CanAsk(unit)
    return not Busy() and not InCombatLockdown() and GetTime() - lastAsked >= INSPECT_GAP and InRange(unit)
end

local function Ask(unit, guid, onReady)
    pending.guid, pending.unit, pending.at, pending.onReady = guid, unit, GetTime(), onReady
    lastAsked = GetTime()
    NotifyInspect(unit)
end

local links = {}   -- slot -> link, read once the gear arrives, reused

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
    -- An item's data still loading: worked out again when it comes.
    if not complete then
        entry.links = entry.links or {}
        wipe(entry.links)
        for slot, link in pairs(links) do entry.links[slot] = link end
    else
        entry.links = nil
    end
    Score.Remember(guid, score, complete, false, UnitLevel(unit))
    if not complete then events:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    if onReady then onReady(guid, unit) end
    -- Let the inspect go, unless it is yours now.
    if not UserInspecting() then ClearInspectPlayer() end
    return true
end

local loadQueued = false

local function ItemsLoaded()
    loadQueued = false
    local waiting = false
    for guid, entry in pairs(kept) do
        if entry.links and not entry.complete and not entry.shared then
            local score, complete = Score.Links(entry.links)
            entry.score, entry.complete = score, complete
            if complete then
                entry.links = nil
                Save(guid, score, entry.level)
            end
            Refresh(guid, entry)
            if not complete then waiting = true end
        end
    end
    if not waiting then events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local function QueueItemsLoaded()
    if loadQueued then return end
    loadQueued = true
    C_Timer.After(LOAD_SETTLE, ItemsLoaded)
end

-------------------------------------------------------------------------------
--  Your group, in the background: the first member in range whose score is not known, then
--  the next INSPECT_GAP later, until none is left
-------------------------------------------------------------------------------
local scanQueued = false
local wantedQueued = false
local wantedUnit, wantedGUID   -- the player hovered, waiting for the inspect to come free
local Scan

local function ScanDue()
    scanQueued = false
    Scan()
end

local function WantedDue()
    wantedQueued = false
    Scan()
end

-- The hovered player, while they are still the one that unit is and not known yet.
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

-- The unit names walked, made once: the walk makes no strings of its own.
local RAID, PARTY = {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end
local AROUND = { "target", "focus", "mouseover" }
local plates = {}   -- nameplate unit -> true while a player's nameplate shows

local function Request(unit, guid, onReady)
    if Busy() or InCombatLockdown() or GetTime() - lastAsked < INSPECT_GAP then return "wait" end
    if not InRange(unit) then return "far" end
    Ask(unit, guid, onReady)
    return "asked"
end

-- One player looked at: "asked" (their gear asked for), "wait" (the inspect is busy, or too
-- soon after the last), "far" (not known yet, out of range), or nil (known, or no one to ask).
local function Try(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player")
        or not UnitIsConnected(unit) then
        return nil
    end
    local guid = UnitGUID(unit)
    if not Readable(guid) or Score.Known(guid) then return nil end
    return Request(unit, guid)
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
    if InCombatLockdown() or claimed then return end
    far = false
    local wanted = Wanted()
    if wanted and Step(wanted) then return end
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
        -- A member's gear changed: an inspected score of theirs goes stale.
        if not Readable(arg) then return end
        local isMe = UnitIsUnit(arg, "player")
        if not Readable(isMe) or isMe then return end
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
            if CanAsk(unit) then
                Ask(unit, guid)
            elseif pending.guid ~= guid then
                wantedUnit, wantedGUID = unit, guid
                if not wantedQueued then
                    wantedQueued = true
                    C_Timer.After(math.max(WANTED_MIN, INSPECT_GAP - (GetTime() - lastAsked)), WantedDue)
                end
            end
        end
    end
    tooltip:AddDoubleLine(LABEL, value, T.accent.r, T.accent.g, T.accent.b, 1, 1, 1)
    shownGUID, shownLine = guid, tooltip:NumLines()
end

local function OnRoster(tooltip, guid, info)
    if not TooltipOn() then return end
    local score, level, when
    if guid == UnitGUID("player") then
        score = Score.Unit("player")
    elseif info.presence == Enum.ClubMemberPresence.Offline then
        local entry = Saved()[guid]
        if entry then score, level, when = entry.score, entry.level, entry.at end
    else
        local entry = Score.Known(guid)
        score = entry and entry.score
    end
    if not score then return end
    local text = Score.Tooltip(score, level or info.level)
    if when then text = text .. " " .. ns.Color("muted", "(" .. ns.Shared.Ago(when) .. ")") end
    tooltip:AddDoubleLine(LABEL, text, T.accent.r, T.accent.g, T.accent.b, 1, 1, 1)
    return true
end

local hooked, userHooked = false, false

local function HookUser()
    if userHooked or not InspectUnit then return end
    userHooked = true
    hooksecurefunc("InspectUnit", UserInspected)
end

-- The tooltip hook goes in a frame after Apply, once every module's Apply has run: tooltip
-- post-calls run in the order they were added, so the badge line (Badges, added in its Apply)
-- comes first, and the score under it, as one Naowh block.
local function Hook()
    HookUser()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
    ns.Shared.Roster.AddTooltip(OnRoster)
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

local function ListenReady()
    if Feature() or claimed then events:RegisterEvent("INSPECT_READY") else events:UnregisterEvent("INSPECT_READY") end
end

-- Hooks go in the first time the feature is on, and stay inert while it is off; the events
-- are listened to only while it is on.
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

local Queue = { GAP = INSPECT_GAP, WAIT_FOR = WAIT_FOR, RETRY = RETRY }
Score.InspectQueue = Queue
Queue.Request = Request
Queue.InRange = InRange

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

S.OnChange(function(key)
    if key == "enabled" or key:find("^naowhScore") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
