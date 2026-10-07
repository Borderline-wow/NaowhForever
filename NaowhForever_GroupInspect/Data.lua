-------------------------------------------------------------------------------
--  Data.lua -- Group Inspect's data (ns.GroupInspect): a record for you and everyone in your
--  party or raid, pooled and keyed by GUID, with their name, class, level, role, Naowh Score,
--  item level, gear, talents and (from Share.lua) stats, and the walk that inspects them. Only
--  while the window is open (GI.Open, GI.Close): one request at a time through Naowh Score's
--  shared queue (ns.NaowhScore.InspectQueue), at least its gap apart, out of combat, in range,
--  yielding to your own inspect; players running Naowh Forever after the rest, for their gear;
--  out of range looked at again later; stopped once everyone is known. Read on INSPECT_READY
--  for the GUID asked only. GI.Preview shows a fixed party of 5 or raid of 25 instead (the
--  settings preview, screenshots, tests), built the first time it is asked for: each PREVIEW
--  row is name, class, gear (GEAR: slot:item:quality:item level:on their BiS, real items from
--  the BiS data), role, points per tree, level, runs Naowh Forever, stats profile and state.
--  Callbacks (GI.OnChange) come once per burst; Share.lua writes its fields and calls
--  GI.Changed, and replaces GI.StatsFromGear(record).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local Score = ns.NaowhScore
local Queue = Score.InspectQueue
local IP = ns.InspectPanel
local Items = ns.Shared.Items
local Enchants = ns.BiS.Enchants
local GEAR_SLOTS = Items.GEAR_SLOTS

local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local GetItemQualityByID = C_Item.GetItemQualityByID

local GI = {}
ns.GroupInspect = GI

local STALE = 300
local LOAD_SETTLE = 0.2
local EARLY = 0.05
local MAIN, OFF = 16, 17
local ROLE_OF = { Tank = "TANK", Healer = "HEALER", Damage = "DAMAGER" }
local EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED",
    "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED" }
local ENCHANT_SLOTS = Enchants.SLOTS

local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

local open, previewOn, previewMode = false, false, "party"
local records, members, count = {}, {}, 0
local free, freeCount = {}, 0
local gen = 0
local ownGUID
local listeners = {}
local dirty, batch = {}, {}
local rosterDirty, flushQueued, rosterQueued, selfQueued, loadQueued, waiting = false, false, false, false, false, false
local staleQueued = false
local walkAt
local events, hooked
local links = {}

local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end

function GI.On()
    return S.Get("enabled") == true and S.Get("groupInspect") == true
end

function GI.IsOpen()
    return open
end

GI.StatsFromGear = GI.StatsFromGear or function() end

local function Flush()
    flushQueued = false
    if not (open or previewOn) then
        rosterDirty = false
        wipe(dirty)
        return
    end
    if rosterDirty then
        rosterDirty = false
        wipe(dirty)
        for i = 1, #listeners do listeners[i](nil) end
        return
    end
    dirty, batch = batch, dirty
    for guid in pairs(batch) do
        for i = 1, #listeners do listeners[i](guid) end
    end
    wipe(batch)
end

function GI.Changed(guid)
    if not (open or previewOn) then return end
    if guid == nil then rosterDirty = true else dirty[guid] = true end
    if flushQueued then return end
    flushQueued = true
    C_Timer.After(0, Flush)
end
local Changed = GI.Changed

function GI.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function NewRecord()
    if freeCount > 0 then
        local rec = free[freeCount]
        free[freeCount] = nil
        freeCount = freeCount - 1
        return rec
    end
    return { gear = {}, _slots = {}, _talents = { spent = {}, ids = {} } }
end

local function Clear(rec)
    rec.guid, rec.unit, rec.name, rec.classFile, rec.level, rec.role = nil, nil, nil, nil, nil, nil
    rec.online, rec.inRange, rec.state, rec.hasNF, rec.nfVersion = nil, nil, nil, nil, nil
    rec.score, rec.scoreShared, rec.ilvl, rec.talents, rec.stats, rec.statsShared = nil, nil, nil, nil, nil, nil
    rec.updated, rec._seen, rec._read, rec._stale, rec._far, rec._loading = nil, nil, nil, nil, nil, nil
    rec._assigned, rec._statsWait = nil, nil
    wipe(rec.gear)
    for _, entry in pairs(rec._slots) do
        entry.id, entry.link, entry.quality, entry.ilvl, entry.enchanted, entry.bis = nil, nil, nil, nil, nil, nil
    end
    local talents = rec._talents
    wipe(talents.spent)
    talents.tree, talents.role, talents.count, talents.total = nil, nil, nil, nil
end

local function Release(rec)
    records[rec.guid] = nil
    Clear(rec)
    freeCount = freeCount + 1
    free[freeCount] = rec
end

local function Fresh(rec, now)
    return rec._read ~= nil and not rec._stale and now - rec._read < STALE
end

local function State(rec)
    if rec.unit == "player" then return "self" end
    if not rec.online then return "offline" end
    if Queue.Pending() == rec.guid then return "inspecting" end
    if Fresh(rec, GetTime()) then return "ready" end
    if rec._far then return "out_of_range" end
    return "queued"
end

local function SetState(rec, state)
    if rec.state == state then return end
    rec.state = state
    Changed(rec.guid)
end

local function TalentRole(rec)
    local talents = rec.talents
    return talents and ROLE_OF[talents.role]
end

local function Basics(rec, unit)
    local guid = rec.guid
    if not rec.name then rec.name = IP.FullName(unit) end
    local _, classFile = UnitClass(unit)
    if Readable(classFile) then rec.classFile = classFile end
    local level = UnitLevel(unit)
    if Readable(level) and level > 0 then rec.level = level end
    local online = UnitIsConnected(unit)
    rec.online = Readable(online) and online == true
    local role = UnitGroupRolesAssigned(unit)
    rec._assigned = Readable(role) and role ~= "NONE"
    rec.role = rec._assigned and role or TalentRole(rec)
    if unit == "player" then
        rec.state = "self"
        if rec.hasNF == nil then rec.hasNF = true end
        return
    end
    local known = Score.Known(guid)
    if known and known.shared then rec.score, rec.scoreShared, rec.hasNF = known.score, true, true end
    if IP.RunsNaowh(guid) then rec.hasNF = true end
    rec.state = State(rec)
end

local function Add(unit)
    local guid = UnitGUID(unit)
    if not Readable(guid) then return end
    local rec = records[guid]
    if not rec then
        rec = NewRecord()
        rec.guid = guid
        records[guid] = rec
    end
    rec.unit, rec._seen = unit, gen
    count = count + 1
    members[count] = rec
    Basics(rec, unit)
end

local function FillItem(entry, slot)
    local link = entry.link
    entry.quality = GetItemQualityByID(entry.id)
    entry.ilvl = link and GetDetailedItemLevelInfo(link) or nil
    entry.enchanted = nil
    if link and ENCHANT_SLOTS[slot] then
        local can, current = Enchants.Enchantable(link)
        if current ~= 0 then entry.enchanted = true elseif can then entry.enchanted = false end
    end
    return link == nil or entry.quality == nil or entry.ilvl == nil
end

local function Average(gear)
    local sum = 0
    for i = 1, #GEAR_SLOTS do
        local entry = gear[GEAR_SLOTS[i][1]]
        if entry and entry.ilvl then sum = sum + entry.ilvl end
    end
    local main = gear[MAIN]
    if main and main.ilvl and not gear[OFF] and Items.IsTwoHand(main.id) then sum = sum + main.ilvl end
    return sum / #GEAR_SLOTS
end

local function ScoreOf(rec)
    if rec.scoreShared then return end
    wipe(links)
    for slot, entry in pairs(rec.gear) do links[slot] = entry.link end
    rec.score = Score.Links(links)
end

local OnItems

local function ReadGear(rec, unit)
    local gear, slots, guid = rec.gear, rec._slots, rec.guid
    local loading = false
    for i = 1, #GEAR_SLOTS do
        local slot = GEAR_SLOTS[i][1]
        local id = GetInventoryItemID(unit, slot)
        if id and id ~= 0 then
            local entry = slots[slot]
            if not entry then
                entry = {}
                slots[slot] = entry
            end
            entry.id, entry.link = id, GetInventoryItemLink(unit, slot)
            gear[slot] = entry
            if FillItem(entry, slot) then loading = true end
            entry.bis = IP.TheirRank(guid, slot, id) and true or nil
        else
            gear[slot] = nil
        end
    end
    rec._loading = loading
    if loading then OnItems() end
end

local function Stats(rec)
    rec._statsWait = rec.statsShared ~= true and GI.StatsFromGear(rec) == false or nil
    if rec._statsWait then OnItems() end
end

local function ReadTalents(rec, unit, read)
    local own = rec._talents
    if rec.talents and rec.talents ~= own then return end
    local _, classFile = UnitClass(unit)
    if read(classFile, own) then rec.talents = own end
    if not rec._assigned then rec.role = TalentRole(rec) end
end

local function InspectTalents(classFile, out)
    return IP.ReadInspectTalents(classFile, out)
end

local function OwnTalents(classFile, out)
    local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    return config ~= nil and C_Traits ~= nil and IP.ReadTalentTrees(config, classFile, out)
end

local function FillSelf()
    local rec = ownGUID and records[ownGUID]
    if not rec then return end
    ReadGear(rec, "player")
    rec.score, rec.scoreShared = (Score.Unit("player")), false
    if rec.hasNF == nil then rec.hasNF = true end
    local _, equipped = GetAverageItemLevel()
    if Readable(equipped) then rec.ilvl = equipped end
    ReadTalents(rec, "player", OwnTalents)
    Stats(rec)
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
    if not open then return end
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
    ReadGear(rec, unit)
    ScoreOf(rec)
    local level = C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel(unit)
    rec.ilvl = Readable(level) and level > 0 and level or Average(rec.gear)
    ReadTalents(rec, unit, InspectTalents)
    Stats(rec)
    rec._read, rec._stale, rec._far, rec.inRange, rec.updated = now, false, false, true, now
    rec.state = "ready"
    Changed(guid)
    WalkSoon(Queue.Wait())
end

local function Try(rec, now)
    if Fresh(rec, now) then return "known" end
    if Queue.Pending() == rec.guid then return "wait", Queue.WAIT_FOR end
    local unit = rec.unit
    local guid = UnitGUID(unit)
    if not (Readable(guid) and guid == rec.guid) then return "moved" end
    local result = Queue.Request(unit, guid, OnReady)
    if result == "asked" then
        rec.inRange, rec._far = true, false
        SetState(rec, "inspecting")
        return "wait", Queue.WAIT_FOR
    elseif result == "far" then
        rec.inRange, rec._far = false, true
        SetState(rec, "out_of_range")
        return "far"
    end
    SetState(rec, rec._far and "out_of_range" or "queued")
    local wait = Queue.Wait()
    return "wait", wait > 0 and wait or Queue.GAP
end

local RosterSoon

function Walk()
    if not open or previewOn or InCombatLockdown() then return end
    local now = GetTime()
    local far, soonest = false, nil
    for pass = 1, 2 do
        local nf = pass == 2
        for i = 1, count do
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
    if not open then return end
    gen = gen + 1
    local before = count
    count = 0
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
    for i = count + 1, before do members[i] = nil end
    for _, rec in pairs(records) do
        if rec._seen ~= gen then Release(rec) end
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
    if open then FillSelf() end
end

local function SelfSoon()
    if selfQueued then return end
    selfQueued = true
    C_Timer.After(LOAD_SETTLE, SelfDue)
end

local function Loaded()
    loadQueued = false
    if not open then return end
    local still = false
    for i = 1, count do
        local rec = members[i]
        if rec._loading or rec._statsWait then
            local loading = false
            for slot, entry in pairs(rec.gear) do
                if FillItem(entry, slot) then loading = true end
            end
            rec._loading = loading
            if rec.unit == "player" then rec.score = (Score.Unit("player")) else ScoreOf(rec) end
            Stats(rec)
            if loading or rec._statsWait then still = true end
            Changed(rec.guid)
        end
    end
    if not still and waiting then
        waiting = false
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

function OnItems()
    if not open or waiting then return end
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
    SetState(rec, State(rec))
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
    if not open or not shared then return end
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
    if open or not GI.On() then return end
    open = true
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
    if not open then return end
    open = false
    walkAt = nil
    Listen(false)
    Queue.Claim(false)
end

local function Forget(rec)
    if rec.unit == "player" then return end
    rec._read, rec._stale, rec._far = nil, nil, nil
    rec.state = State(rec)
    Changed(rec.guid)
end

function GI.Refresh(guid)
    local rec = guid and records[guid]
    if not (open and rec) then return end
    if rec.unit == "player" then return SelfSoon() end
    Forget(rec)
    WalkSoon(0)
end

function GI.RefreshAll()
    if not open then return end
    for i = 1, count do Forget(members[i]) end
    SelfSoon()
    WalkSoon(0)
end

S.OnChange(function(key)
    if (key == "enabled" or key == "groupInspect") and not GI.On() then GI.Close() end
end)

local TREES = {
    WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}
local TALENT_ROLE = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local STAT_KEYS = { "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "CRIT", "HIT", "ARMOR" }
local PROFILES = {
    plate = { 118, 64, 214, 38, 46, 296, 0, 6.2, 2.0, 4280 },
    melee = { 186, 92, 158, 24, 52, 432, 0, 12.4, 5.0, 2960 },
    rogue = { 78, 188, 132, 28, 44, 418, 0, 14.6, 5.0, 1480 },
    hunter = { 52, 196, 138, 92, 58, 436, 0, 13.2, 4.0, 1880 },
    bear = { 112, 128, 196, 70, 64, 380, 0, 9.8, 3.0, 5120 },
    caster = { 30, 36, 118, 188, 112, 30, 188, 7.6, 6.0, 690 },
    healer = { 34, 32, 112, 176, 158, 34, 164, 5.4, 0, 880 },
}
local GEAR = {
    ["protection-paladin:0"] = "1:250532:3:25:1 2:23169:3:35:1 3:273028:3:33:1 15:279835:3:36:1 5:250520:3:27:1 9:251965:3:36:1 10:270025:3:27:1 6:250558:3:35:1 7:250525:3:30:1 8:250505:3:22:1 11:273806:3:26:1 12:271670:3:33:1 13:8663:2:40:1 14:21120:3:33:1 16:17039:3:38:1 17:280696:3:40:1 18:249397:3:25:1",
    ["holy-priest:1"] = "1:284401:3:29:0 2:281321:3:32:0 3:7684:3:35:0 15:7004:3:26:0 5:253961:3:27:0 9:4744:2:39:0 10:270030:3:28:0 6:6392:3:28:0 7:253937:3:25:0 8:6998:3:27:0 11:281635:3:35:0 12:2043:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:271767:3:33:0 17:276898:3:38:0 18:5249:2:40:0",
    ["combat-rogue:2"] = "1:6720:2:37:0 2:274068:3:34:0 3:5964:2:35:0 15:2805:2:34:0 5:252508:3:27:0 9:270076:2:40:0 10:3754:2:33:0 6:20152:3:33:0 7:9509:3:30:0 8:7952:2:36:0 11:270052:2:35:0 12:277210:3:25:0 13:280766:3:33:0 14:21119:3:33:0 16:6692:3:35:0 17:7683:3:34:0 18:3463:2:37:0",
    ["frost-mage:0"] = "1:253977:3:30:1 2:23169:3:35:1 3:7684:3:35:1 15:7053:2:35:1 5:17043:3:38:1 9:4744:2:39:1 10:4319:2:29:1 6:20099:3:33:1 7:253989:3:30:1 8:254003:3:35:1 11:281635:3:35:1 12:2043:2:35:1 13:8663:2:40:1 14:21120:3:33:1 16:281312:3:32:1 17:249394:3:30:1 18:7514:3:40:1",
    ["marksmanship-hunter:3"] = "1:277219:2:30:0 2:281290:2:29:0 3:277051:2:35:0 15:6745:2:33:0 5:274942:2:42:0 9:270032:3:29:0 10:6727:2:41:0 6:20191:3:33:0 7:6690:3:34:0 8:20123:3:33:0 11:281634:3:35:0 12:6748:3:32:0 13:21119:3:33:0 14:276895:2:31:0 16:274944:2:42:0 17:281314:3:32:0 18:273029:3:33:0",
    ["protection-warrior:1"] = "1:250499:3:30:0 2:13087:3:33:0 3:13131:3:29:0 15:18427:3:35:0 5:250520:3:27:0 9:4745:2:40:0 10:250509:3:20:0 6:250558:3:35:0 7:250525:3:30:0 8:20129:3:33:0 11:276899:3:38:0 12:281320:3:32:0 13:21120:3:33:0 14:280766:3:33:0 16:274920:2:40:0 17:17508:3:40:0 18:17042:3:38:0",
    ["fury-warrior:0"] = "1:7915:2:35:1 2:13084:3:35:1 3:2278:3:31:1 15:271720:3:30:1 5:6773:2:42:1 9:270080:2:40:1 10:4107:2:37:1 6:250556:3:35:1 7:250523:3:30:1 8:284403:3:29:1 11:285190:3:34:1 12:13097:3:29:1 13:8663:2:40:1 14:21120:3:33:1 16:6692:3:35:1 17:274920:2:40:0 18:273829:3:31:1",
    ["arms-warrior:2"] = "1:252455:3:30:0 2:285331:3:25:0 3:7913:2:32:0 15:279848:3:36:0 5:250518:3:27:0 9:270073:2:40:0 10:4075:2:34:0 6:20090:3:33:0 7:6690:3:34:0 8:20129:3:33:0 11:18585:3:35:0 12:7686:3:35:0 13:280766:3:33:0 14:21119:3:33:0 16:6977:3:40:0 18:2098:3:27:0",
    ["holy-paladin:0"] = "1:2721:3:32:1 2:23169:3:35:1 3:3324:3:27:1 15:9605:3:32:1 5:9623:3:37:1 9:271740:3:33:1 10:7049:2:30:1 6:250559:3:35:1 7:250526:3:30:1 8:254001:3:35:1 11:274746:2:35:1 12:281635:3:35:1 13:8663:2:40:1 14:21120:3:33:1 16:2816:3:33:1 17:17508:3:40:1 18:249397:3:25:1",
    ["retribution-paladin:1"] = "1:6686:3:34:0 2:285331:3:25:0 3:15698:2:38:0 15:282658:2:32:0 5:2870:3:29:0 9:270068:2:39:0 10:3754:2:33:0 6:252459:3:35:0 7:274939:2:42:0 8:4464:2:34:0 11:13097:3:29:0 12:18585:3:35:0 13:21120:3:33:0 14:280766:3:33:0 16:274940:2:42:0 18:249397:3:25:1",
    ["restoration-druid:0"] = "1:2721:3:32:1 2:23169:3:35:1 3:3324:3:27:1 15:9605:3:32:1 5:9623:3:37:1 9:271740:3:33:1 10:7049:2:30:1 6:252523:3:35:1 7:253987:3:30:1 8:254001:3:35:1 11:274746:2:35:1 12:281635:3:35:1 13:8663:2:40:1 14:21120:3:33:1 16:280605:3:40:1 17:249395:3:30:1 18:249396:3:25:1",
    ["feral-tank-druid:2"] = "1:277042:2:35:0 2:15200:3:35:0 3:277043:2:35:0 15:281319:3:32:0 5:270054:3:38:0 9:270032:3:29:0 10:1978:3:27:0 6:20191:3:33:0 7:252445:3:25:0 8:20102:3:33:0 11:281634:3:35:0 12:271911:3:33:0 13:280766:3:33:0 14:21119:3:33:0 16:13045:3:35:0 18:263435:2:10:0",
    ["balance-druid:1"] = "1:2721:3:32:0 2:13084:3:35:0 3:4197:3:36:0 15:274149:3:30:0 5:270082:2:42:0 9:271740:3:33:0 10:270029:3:28:0 6:20099:3:33:0 7:6903:3:28:0 8:9454:3:32:0 11:2043:2:35:0 12:270051:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:281312:3:32:0 17:7749:3:40:0 18:263411:1:6:0",
    ["assassination-rogue:0"] = "1:7953:2:42:1 2:13084:3:35:1 3:2278:3:31:1 15:14593:2:35:1 5:7950:2:42:1 9:270080:2:40:1 10:270072:2:40:1 6:252520:3:35:1 7:9624:3:37:1 8:284403:3:29:1 11:285190:3:34:1 12:7686:3:35:1 13:8663:2:40:1 14:21120:3:33:1 16:9520:2:41:1 17:280805:3:33:0 18:273829:3:31:1",
    ["fire-mage:1"] = "1:2721:3:32:0 2:13084:3:35:0 3:4197:3:36:0 15:274149:3:30:0 5:270082:2:42:0 9:4744:2:39:0 10:9609:3:32:0 6:20164:3:33:0 7:253941:3:25:0 8:254001:3:35:0 11:2043:2:35:0 12:270051:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:6691:3:35:0 17:249394:3:30:0 18:5249:2:40:0",
    ["arcane-mage:3"] = "1:4322:2:33:0 2:271920:3:33:0 3:7750:3:35:0 15:279835:3:36:0 5:253969:3:27:0 9:6407:2:33:0 10:10654:2:30:0 6:215366:2:30:0 7:270056:2:37:0 8:4320:3:25:0 11:9622:2:35:0 12:273806:3:26:0 13:21119:3:33:0 14:276895:2:31:0 16:272086:3:33:0 17:273027:3:31:0 18:6729:2:38:0",
    ["affliction-warlock:0"] = "1:253981:3:30:1 2:23169:3:35:1 3:7684:3:35:1 15:277206:2:41:1 5:17043:3:38:1 9:4744:2:39:1 10:7047:2:29:1 6:20099:3:33:1 7:253993:3:30:1 8:254007:3:35:1 11:281635:3:35:1 12:2043:2:35:1 13:8663:2:40:1 14:21120:3:33:1 16:281312:3:32:1 17:249394:3:30:1 18:274919:2:40:1",
    ["destruction-warlock:2"] = "1:4323:2:34:0 2:5003:2:31:0 3:6685:3:32:0 15:9605:3:32:0 5:274941:2:42:0 9:13106:3:31:0 10:9609:3:32:0 6:6392:3:28:0 7:253943:3:25:0 8:9454:3:32:0 11:270051:2:35:0 12:9622:2:35:0 13:280766:3:33:0 14:21119:3:33:0 16:271931:3:33:0 17:6898:3:25:0 18:6729:2:38:0",
    ["shadow-priest:1"] = "1:2721:3:32:0 2:13084:3:35:0 3:4197:3:36:0 15:274149:3:30:0 5:270082:2:42:0 9:271740:3:33:0 10:270029:3:28:0 6:20164:3:33:0 7:2277:3:35:0 8:254001:3:35:0 11:2043:2:35:0 12:270051:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:281312:3:32:0 17:2944:2:31:0 18:5249:2:40:0",
    ["discipline-priest:0"] = "1:2721:3:32:1 2:23169:3:35:1 3:3324:3:27:1 15:9605:3:32:1 5:9623:3:37:1 9:271740:3:33:1 10:7049:2:30:1 6:253925:3:22:1 7:253987:3:30:1 8:254001:3:35:1 11:274746:2:35:1 12:281635:3:35:1 13:8663:2:40:1 14:21120:3:33:1 16:6689:3:34:1 17:249395:3:30:1 18:16789:2:36:1",
    ["beast-mastery-hunter:1"] = "1:6720:2:37:0 2:274068:3:34:0 3:2264:3:30:0 15:14593:2:35:0 5:2041:3:24:0 9:6198:2:33:0 10:274159:3:33:0 6:20152:3:33:0 7:9509:3:30:0 8:7751:3:35:0 11:7686:3:35:0 12:270052:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:6679:2:29:0 17:285346:3:27:0 18:274748:3:35:0",
    ["survival-hunter:0"] = "1:252512:3:30:1 2:282653:2:32:1 3:2278:3:31:1 15:13108:3:34:1 5:7374:2:35:1 9:6410:2:33:1 10:270072:2:40:1 6:20090:3:33:1 7:9624:3:37:1 8:284403:3:29:1 11:285190:3:34:1 12:7686:3:35:1 13:8663:2:40:1 14:21120:3:33:1 16:274920:2:40:1 17:9520:2:41:0 18:273829:3:31:1",
    ["restoration-shaman:1"] = "1:284401:3:29:0 2:281321:3:32:0 3:7684:3:35:0 15:7004:3:26:0 5:253961:3:27:0 9:4744:2:39:0 10:888:3:27:0 6:252522:3:35:0 7:252519:3:30:0 8:6998:3:27:0 11:281635:3:35:0 12:2043:2:35:0 13:21120:3:33:0 14:280766:3:33:0 16:6689:3:34:0 17:249395:3:30:0 18:263436:2:10:0",
    ["enhancement-shaman:0"] = "1:252455:3:30:1 2:13084:3:35:1 3:2278:3:31:1 15:271716:3:33:1 5:270054:3:38:1 9:270080:2:40:1 10:6732:2:38:1 6:252459:3:35:1 7:6690:3:34:1 8:284403:3:29:1 11:285190:3:34:1 12:13097:3:29:1 13:8663:2:40:1 14:21120:3:33:1 16:280604:3:40:1 18:249398:3:25:1",
    ["elemental-shaman:2"] = "1:252456:3:30:0 2:5003:2:31:0 3:6685:3:32:0 15:9605:3:32:0 5:274941:2:42:0 9:271202:3:20:0 10:9609:3:32:0 6:20164:3:33:0 7:270031:3:29:0 8:4320:3:25:0 11:270051:2:35:0 12:9622:2:35:0 13:280766:3:33:0 14:21119:3:33:0 16:281312:3:32:0 17:17508:3:40:0 18:263412:1:6:0",
}
local PREVIEW = {
    { "Aldren Brightmoor", "PALADIN", "protection-paladin:0", "TANK", { 5, 26, 0 }, 40, true, "plate" },
    { "Maeve Thornwick", "PRIEST", "holy-priest:1", "HEALER", { 11, 20, 0 }, 40, true, "healer" },
    { "Corin Ashvale", "ROGUE", "combat-rogue:2", "DAMAGER", { 10, 21, 0 }, 39, false, "rogue" },
    { "Isolde Frostmere", "MAGE", "frost-mage:0", "DAMAGER", { 10, 0, 21 }, 40, true, "caster" },
    { "Garrick Stonebrook", "HUNTER", "marksmanship-hunter:3", "DAMAGER", { 5, 21, 5 }, 38, false, "hunter" },
    { "Brann Ironvale", "WARRIOR", "protection-warrior:1", "TANK", { 5, 5, 21 }, 40, true, "plate" },
    { "Tamsin Redfern", "WARRIOR", "fury-warrior:0", "DAMAGER", { 10, 21, 0 }, 40, true, "melee" },
    { "Hector Graymane", "WARRIOR", "arms-warrior:2", "DAMAGER", { 21, 10, 0 }, 39, false, "melee" },
    { "Liora Dawnmere", "PALADIN", "holy-paladin:0", "HEALER", { 21, 10, 0 }, 40, true, "healer" },
    { "Osric Vantor", "PALADIN", "retribution-paladin:1", "DAMAGER", { 5, 5, 21 }, 40, false, "melee" },
    { "Fenna Willowbrook", "DRUID", "restoration-druid:0", "HEALER", { 0, 10, 21 }, 40, true, "healer" },
    { "Rowan Thistledown", "DRUID", "feral-tank-druid:2", "TANK", { 0, 21, 10 }, 39, false, "bear" },
    { "Elowen Starfall", "DRUID", "balance-druid:1", "DAMAGER", { 21, 0, 10 }, 40, true, "caster" },
    { "Silas Nightbrook", "ROGUE", "assassination-rogue:0", "DAMAGER", { 21, 10, 0 }, 40, true, "rogue" },
    { "Ember Calloway", "MAGE", "fire-mage:1", "DAMAGER", { 10, 21, 0 }, 40, false, "caster" },
    { "Quill Ashgrove", "MAGE", "arcane-mage:3", "DAMAGER", { 21, 10, 0 }, 37, false, "caster" },
    { "Mordecai Blackwood", "WARLOCK", "affliction-warlock:0", "DAMAGER", { 21, 10, 0 }, 40, true, "caster" },
    { "Vesper Kane", "WARLOCK", "destruction-warlock:2", "DAMAGER", { 5, 5, 21 }, 39, false, "caster" },
    { "Orla Grimsby", "PRIEST", "shadow-priest:1", "DAMAGER", { 10, 0, 21 }, 40, true, "caster", "out_of_range" },
    { "Cedric Lumen", "PRIEST", "discipline-priest:0", "HEALER", { 21, 10, 0 }, 40, false, "healer" },
    { "Wren Hollister", "HUNTER", "beast-mastery-hunter:1", "DAMAGER", { 21, 10, 0 }, 40, true, "hunter" },
    { "Dorian Marsh", "HUNTER", "survival-hunter:0", "DAMAGER", { 5, 5, 21 }, 40, false, "hunter" },
    { "Talia Stormcaller", "SHAMAN", "restoration-shaman:1", "HEALER", { 5, 5, 21 }, 40, true, "healer", "offline" },
    { "Bram Thunderhoof", "SHAMAN", "enhancement-shaman:0", "DAMAGER", { 5, 21, 5 }, 40, false, "melee" },
    { "Nyra Cloudsong", "SHAMAN", "elemental-shaman:2", "DAMAGER", { 21, 5, 5 }, 38, false, "caster", "queued" },
}
local PARTY_SIZE, VERSION = 5, "0.5.24"

local preview = { party = {}, raid = {} }
local previewBy = {}
local reading

local function PreviewRead(slot)
    local entry = reading[slot]
    if not entry then return nil end
    return entry.ilvl, entry.quality, slot == MAIN and Items.IsTwoHand(entry.id)
end

local function PreviewGear(rec, key, nf, index)
    for slot, id, quality, ilvl, bis in GEAR[key]:gmatch("(%d+):(%d+):(%d+):(%d+):(%d)") do
        slot = tonumber(slot)
        local enchanted
        if ENCHANT_SLOTS[slot] then enchanted = nf or (slot + index) % 3 ~= 0 end
        rec.gear[slot] = { id = tonumber(id), link = "item:" .. id, quality = tonumber(quality), ilvl = tonumber(ilvl),
            enchanted = enchanted, bis = nf and bis == "1" or nil }
    end
    reading = rec.gear
    rec.score = Score.Of(PreviewRead)
    rec.ilvl = Average(rec.gear)
end

local function PreviewStats(kind, index)
    local scale = 0.9 + (index * 7 % 11) / 50
    local stats = {}
    for i, key in ipairs(STAT_KEYS) do
        local value = PROFILES[kind][i] * scale
        if key == "CRIT" or key == "HIT" then
            stats[key] = math.floor(value * 10 + 0.5) / 10
        else
            stats[key] = math.floor(value + 0.5)
        end
    end
    return stats
end

local function PreviewMember(def, index, unit)
    local name, class, key, role, spent, level, nf, kind, state = unpack(def)
    local rec = { guid = ("Player-0-%08X"):format(index), unit = unit, name = name, classFile = class, level = level,
        role = role, online = state ~= "offline", inRange = state ~= "out_of_range", state = state or "ready",
        hasNF = nf, nfVersion = nf and VERSION or nil, gear = {}, updated = 0 }
    if index == 1 then rec.state = "self" end
    local known = rec.state == "ready" or rec.state == "self"
    if known or (nf and rec.online) then
        local lead = 1
        for i = 2, 3 do if spent[i] > spent[lead] then lead = i end end
        rec.talents = { spent = { spent[1], spent[2], spent[3] }, tree = TREES[class][lead], role = TALENT_ROLE[role],
            count = 3, total = spent[1] + spent[2] + spent[3] }
        rec.stats, rec.statsShared = PreviewStats(kind, index), nf
    end
    if known then
        PreviewGear(rec, key, nf, index)
        rec.scoreShared = nf and index ~= 1
    elseif nf and rec.online then
        PreviewGear(rec, key, nf, index)
        wipe(rec.gear)
        rec.ilvl, rec.scoreShared = nil, true
    end
    return rec
end

local function BuildPreview()
    if #preview.raid > 0 then return end
    for i, def in ipairs(PREVIEW) do
        local raid = PreviewMember(def, i, i == 1 and "player" or RAID[i])
        preview.raid[i] = raid
        previewBy[raid.guid] = raid
        if i <= PARTY_SIZE then
            local party = PreviewMember(def, i, i == 1 and "player" or PARTY[i - 1])
            party.guid = raid.guid
            preview.party[i] = party
        end
    end
end

function GI.Preview(on)
    on = on == true
    if on == previewOn then return end
    if on then BuildPreview() end
    previewOn = on
    Changed(nil)
    if not on then WalkSoon(0) end
end

function GI.PreviewMode(mode)
    if (mode == "party" or mode == "raid") and mode ~= previewMode then
        previewMode = mode
        if previewOn then Changed(nil) end
    end
    return previewMode
end

function GI.Mode()
    if previewOn then return previewMode end
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

function GI.Members()
    if previewOn then return preview[previewMode] end
    return members
end

function GI.Count()
    return #GI.Members()
end

function GI.Member(guid)
    if previewOn then
        if previewMode == "raid" then return previewBy[guid] end
        for _, rec in ipairs(preview.party) do
            if rec.guid == guid then return rec end
        end
        return nil
    end
    return records[guid]
end
