-- Inspect.lua: Group Inspect's scan while the window is open: the roster, the inspect walk, item data and its events (GI.Open, GI.Close).
local ns = _G.NaowhForever

local GI = ns.GroupInspect
local C = GI.C
local R = GI.Records
local S = ns.QoLSettings
local Score = ns.NaowhScore
local Queue = Score.InspectQueue
local Readable, Changed = GI.Readable, GI.Changed

local STALE = C.STALE
local LOAD_SETTLE = 0.2
local EARLY = 0.05
local EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED",
    "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED" }
local PARTY, RAID = C.PARTY_UNITS, C.RAID_UNITS

local state = GI.state
local records, members = state.records, state.members
local gen = 0
local ownGUID
local rosterQueued, selfQueued, loadQueued, waiting = false, false, false, false
local staleQueued = false
local walkAt
local events, hooked

local function Add(unit)
    local guid = UnitGUID(unit)
    if not Readable(guid) then return end
    local rec = records[guid]
    if not rec then
        rec = R.New()
        rec.guid = guid
        records[guid] = rec
    end
    rec.unit, rec._seen = unit, gen
    local count = state.count + 1
    state.count = count
    members[count] = rec
    R.Basics(rec, unit)
end

local function FillSelf()
    local rec = ownGUID and records[ownGUID]
    if not rec then return end
    R.ReadGear(rec, "player")
    rec.score, rec.scoreShared = (Score.Unit("player")), false
    if rec.hasNF == nil then rec.hasNF = true end
    local _, equipped = GetAverageItemLevel()
    if Readable(equipped) then rec.ilvl = equipped end
    R.ReadTalents(rec, "player", R.OwnTalents)
    R.Stats(rec)
    rec.updated, rec.state = GetTime(), "self"
    Changed(rec.guid)
end

local Walk

local function WalkDue()
    if not walkAt or walkAt - GetTime() > EARLY then return end
    walkAt = nil
    Walk()
end

local function WalkSoon(delay)
    if not state.open then return end
    local at = GetTime() + delay
    if walkAt and walkAt <= at then return end
    walkAt = at
    C_Timer.After(delay, WalkDue)
end

local function StaleDue()
    staleQueued = false
    WalkSoon(0)
end

local function StaleSoon(delay)
    if staleQueued then return end
    staleQueued = true
    C_Timer.After(delay, StaleDue)
end

local function OnReady(guid, unit)
    local rec = records[guid]
    if not rec then return end
    local now = GetTime()
    R.ReadGear(rec, unit)
    R.ScoreOf(rec)
    local level = C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel(unit)
    rec.ilvl = Readable(level) and level > 0 and level or R.Average(rec.gear)
    R.ReadTalents(rec, unit, R.InspectTalents)
    R.Stats(rec)
    rec._read, rec._stale, rec._far, rec.inRange, rec.updated = now, false, false, true, now
    rec.state = "ready"
    Changed(guid)
    WalkSoon(Queue.Wait())
end

local function Try(rec, now)
    if R.Fresh(rec, now) then return "known" end
    if Queue.Pending() == rec.guid then return "wait", Queue.WAIT_FOR end
    local unit = rec.unit
    local guid = UnitGUID(unit)
    if not (Readable(guid) and guid == rec.guid) then return "moved" end
    local result = Queue.Request(unit, guid, OnReady)
    if result == "asked" then
        rec.inRange, rec._far = true, false
        R.SetState(rec, "inspecting")
        return "wait", Queue.WAIT_FOR
    elseif result == "far" then
        rec.inRange, rec._far = false, true
        R.SetState(rec, "out_of_range")
        return "far"
    end
    R.SetState(rec, rec._far and "out_of_range" or "queued")
    local wait = Queue.Wait()
    return "wait", wait > 0 and wait or Queue.GAP
end

local RosterSoon

function Walk()
    if not state.open or state.previewOn or InCombatLockdown() then return end
    local now = GetTime()
    local far, soonest = false, nil
    for pass = 1, 2 do
        local nf = pass == 2
        for i = 1, state.count do
            local rec = members[i]
            if rec.unit ~= "player" and rec.online and (rec.hasNF == true) == nf then
                local result, delay = Try(rec, now)
                if result == "wait" then return WalkSoon(delay) end
                if result == "moved" then return RosterSoon() end
                if result == "far" then
                    far = true
                elseif result == "known" then
                    local due = rec._read + STALE - now
                    if not soonest or due < soonest then soonest = due end
                end
            end
        end
    end
    if far then
        WalkSoon(Queue.RETRY)
    elseif soonest then
        StaleSoon(soonest)
    end
end

local function Rebuild()
    rosterQueued = false
    if not state.open then return end
    gen = gen + 1
    local before = state.count
    state.count = 0
    ownGUID = ownGUID or UnitGUID("player")
    Add("player")
    if IsInRaid() then
        for i = 1, math.min(GetNumGroupMembers(), #RAID) do
            local unit = RAID[i]
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then Add(unit) end
        end
    else
        for i = 1, math.min(GetNumSubgroupMembers(), #PARTY) do
            if UnitExists(PARTY[i]) then Add(PARTY[i]) end
        end
    end
    for i = state.count + 1, before do members[i] = nil end
    for _, rec in pairs(records) do
        if rec._seen ~= gen then R.Release(rec) end
    end
    Changed(nil)
    WalkSoon(0)
end

function RosterSoon()
    if rosterQueued then return end
    rosterQueued = true
    C_Timer.After(0, Rebuild)
end

local function SelfDue()
    selfQueued = false
    if state.open then FillSelf() end
end

local function SelfSoon()
    if selfQueued then return end
    selfQueued = true
    C_Timer.After(LOAD_SETTLE, SelfDue)
end

local function Loaded()
    loadQueued = false
    if not state.open then return end
    local still = false
    for i = 1, state.count do
        local rec = members[i]
        if rec._loading or rec._statsWait then
            local loading = false
            for slot, entry in pairs(rec.gear) do
                if R.FillItem(entry, slot) then loading = true end
            end
            rec._loading = loading
            if rec.unit == "player" then rec.score = (Score.Unit("player")) else R.ScoreOf(rec) end
            R.Stats(rec)
            if loading or rec._statsWait then still = true end
            Changed(rec.guid)
        end
    end
    if not still and waiting then
        waiting = false
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function OnItems()
    if not state.open or waiting then return end
    waiting = true
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function LoadSoon()
    if loadQueued then return end
    loadQueued = true
    C_Timer.After(LOAD_SETTLE, Loaded)
end

local function Worn(unit)
    if not Readable(unit) or UnitIsUnit(unit, "player") then return end
    local guid = UnitGUID(unit)
    local rec = Readable(guid) and records[guid]
    if not rec then return end
    rec._stale = true
    R.SetState(rec, R.State(rec))
    WalkSoon(Queue.GAP)
end

local function OnEvent(_, event, arg)
    if event == "UNIT_INVENTORY_CHANGED" then
        Worn(arg)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        LoadSoon()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        SelfSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        WalkSoon(0)
    else
        RosterSoon()
    end
end

local function OnRemember(guid, score, _, shared)
    if not state.open or not shared then return end
    local rec = records[guid]
    if not rec or rec.unit == "player" then return end
    rec.score, rec.scoreShared, rec.hasNF = score, true, true
    Changed(guid)
end

local function Listen(on)
    if on and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if not events then return end
    for i = 1, #EVENTS do
        if on then events:RegisterEvent(EVENTS[i]) else events:UnregisterEvent(EVENTS[i]) end
    end
    if not on then
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        waiting = false
    end
end

function GI.Open()
    if state.open or not GI.On() then return end
    state.open = true
    if not hooked then
        hooked = true
        hooksecurefunc(Score, "Remember", OnRemember)
    end
    Listen(true)
    Queue.Claim(true)
    Rebuild()
    FillSelf()
end

function GI.Close()
    if not state.open then return end
    state.open = false
    walkAt = nil
    Listen(false)
    Queue.Claim(false)
end

function GI.Refresh(guid)
    local rec = guid and records[guid]
    if not (state.open and rec) then return end
    if rec.unit == "player" then return SelfSoon() end
    R.Forget(rec)
    WalkSoon(0)
end

function GI.RefreshAll()
    if not state.open then return end
    for i = 1, state.count do R.Forget(members[i]) end
    SelfSoon()
    WalkSoon(0)
end

GI.Inspect = { WalkSoon = WalkSoon }

local function OnSettingChanged(key)
    if (key == "enabled" or key == "groupInspect") and not GI.On() then GI.Close() end
end

R.OnLoading(OnItems)
S.OnChange(OnSettingChanged)
