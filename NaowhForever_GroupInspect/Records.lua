-- Records.lua: a group member's record, pooled and keyed by GUID: who they are, their gear, score, talents and stats (GI.Records).
local ns = _G.NaowhForever

local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local GetItemQualityByID = C_Item.GetItemQualityByID

local GI = ns.GroupInspect
local C = GI.C
local Score = ns.NaowhScore
local Queue = Score.InspectQueue
local IP = ns.InspectPanel
local Items = ns.Shared.Items
local Enchants = ns.BiS.Enchants
local Readable, Changed = GI.Readable, GI.Changed

local GEAR_SLOTS, ENCHANT_SLOTS = Items.GEAR_SLOTS, Enchants.SLOTS
local STALE, MAIN, OFF = C.STALE, C.MAIN_HAND, C.OFF_HAND
local ROLE_OF = { Tank = "TANK", Healer = "HEALER", Damage = "DAMAGER" }

local records = GI.state.records
local free, freeCount = {}, 0
local links = {}
local onLoading

local R = {}
GI.Records = R

function R.OnLoading(fn)
    onLoading = fn
end

function R.New()
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

function R.Release(rec)
    records[rec.guid] = nil
    Clear(rec)
    freeCount = freeCount + 1
    free[freeCount] = rec
end

local function Fresh(rec, now)
    return rec._read ~= nil and not rec._stale and now - rec._read < STALE
end
R.Fresh = Fresh

local function State(rec)
    if rec.unit == "player" then return "self" end
    if not rec.online then return "offline" end
    if Queue.Pending() == rec.guid then return "inspecting" end
    if Fresh(rec, GetTime()) then return "ready" end
    if rec._far then return "out_of_range" end
    return "queued"
end
R.State = State

function R.SetState(rec, state)
    if rec.state == state then return end
    rec.state = state
    Changed(rec.guid)
end

local function TalentRole(rec)
    local talents = rec.talents
    return talents and ROLE_OF[talents.role]
end

function R.Basics(rec, unit)
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
R.FillItem = FillItem

function R.Average(gear)
    local sum = 0
    for i = 1, #GEAR_SLOTS do
        local entry = gear[GEAR_SLOTS[i][1]]
        if entry and entry.ilvl then sum = sum + entry.ilvl end
    end
    local main = gear[MAIN]
    if main and main.ilvl and not gear[OFF] and Items.IsTwoHand(main.id) then sum = sum + main.ilvl end
    return sum / #GEAR_SLOTS
end

function R.ScoreOf(rec)
    if rec.scoreShared then return end
    wipe(links)
    for slot, entry in pairs(rec.gear) do links[slot] = entry.link end
    rec.score = Score.Links(links)
end

function R.ReadGear(rec, unit)
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
    if loading then onLoading() end
end

function R.Stats(rec)
    rec._statsWait = rec.statsShared ~= true and GI.StatsFromGear(rec) == false or nil
    if rec._statsWait then onLoading() end
end

function R.ReadTalents(rec, unit, read)
    local own = rec._talents
    if rec.talents and rec.talents ~= own then return end
    local _, classFile = UnitClass(unit)
    if read(classFile, own) then rec.talents = own end
    if not rec._assigned then rec.role = TalentRole(rec) end
end

function R.InspectTalents(classFile, out)
    return IP.ReadInspectTalents(classFile, out)
end

function R.OwnTalents(classFile, out)
    local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    return config ~= nil and C_Traits ~= nil and IP.ReadTalentTrees(config, classFile, out)
end

function R.Forget(rec)
    if rec.unit == "player" then return end
    rec._read, rec._stale, rec._far = nil, nil, nil
    rec.state = State(rec)
    Changed(rec.guid)
end
