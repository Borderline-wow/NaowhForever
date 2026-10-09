-- PreviewGroup.lua: Group Inspect's preview, a sample party and raid built once from Data/Preview.lua (GI.Preview).
local ns = _G.NaowhForever

local GI = ns.GroupInspect
local C = GI.C
local R = GI.Records
local Score = ns.NaowhScore
local Items = ns.Shared.Items
local Changed = GI.Changed
local WalkSoon = GI.Inspect.WalkSoon

local ENCHANT_SLOTS = ns.BiS.Enchants.SLOTS
local MAIN, TREE_COUNT, TENTHS, ROUND = C.MAIN_HAND, C.TREE_COUNT, C.TENTHS, C.ROUND
local PARTY, RAID = C.PARTY_UNITS, C.RAID_UNITS
local STAT_BASE, STAT_STEP, STAT_SPREAD, STAT_RANGE = 0.9, 7, 11, 50
local UNENCHANTED_EVERY = 3
local GUID_FORMAT = "Player-0-%08X"

local state = GI.state
local preview, previewBy = state.preview, state.previewBy
local D
local reading

local function PreviewRead(slot)
    local entry = reading[slot]
    if not entry then return nil end
    return entry.ilvl, entry.quality, slot == MAIN and Items.IsTwoHand(entry.id)
end

local function PreviewGear(rec, key, nf, index)
    for slot, id, quality, ilvl, bis in D.GEAR[key]:gmatch("(%d+):(%d+):(%d+):(%d+):(%d)") do
        slot = tonumber(slot)
        local enchanted
        if ENCHANT_SLOTS[slot] then enchanted = nf or (slot + index) % UNENCHANTED_EVERY ~= 0 end
        rec.gear[slot] = { id = tonumber(id), link = "item:" .. id, quality = tonumber(quality), ilvl = tonumber(ilvl),
            enchanted = enchanted, bis = nf and bis == "1" or nil }
    end
    reading = rec.gear
    rec.score = Score.Of(PreviewRead)
    rec.ilvl = R.Average(rec.gear)
end

local function PreviewStats(kind, index)
    local scale = STAT_BASE + (index * STAT_STEP % STAT_SPREAD) / STAT_RANGE
    local stats = {}
    for i, key in ipairs(D.STAT_KEYS) do
        local value = D.PROFILES[kind][i] * scale
        if key == "CRIT" or key == "HIT" then
            stats[key] = math.floor(value * TENTHS + ROUND) / TENTHS
        else
            stats[key] = math.floor(value + ROUND)
        end
    end
    return stats
end

local function PreviewMember(def, index, unit)
    local name, class, key, role, spent, level, nf, kind, status = unpack(def)
    local rec = { guid = GUID_FORMAT:format(index), unit = unit, name = name, classFile = class, level = level,
        role = role, online = status ~= "offline", inRange = status ~= "out_of_range", state = status or "ready",
        hasNF = nf, nfVersion = nf and D.VERSION or nil, gear = {}, updated = 0 }
    if index == 1 then rec.state = "self" end
    local known = rec.state == "ready" or rec.state == "self"
    if known or (nf and rec.online) then
        local lead = 1
        for i = 2, TREE_COUNT do if spent[i] > spent[lead] then lead = i end end
        rec.talents = { spent = { spent[1], spent[2], spent[3] }, tree = D.TREES[class][lead], role = D.TALENT_ROLE[role],
            count = TREE_COUNT, total = spent[1] + spent[2] + spent[3] }
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
    D = GI.PreviewData
    for i, def in ipairs(D.PREVIEW) do
        local raid = PreviewMember(def, i, i == 1 and "player" or RAID[i])
        preview.raid[i] = raid
        previewBy[raid.guid] = raid
        if i <= D.PARTY_SIZE then
            local party = PreviewMember(def, i, i == 1 and "player" or PARTY[i - 1])
            party.guid = raid.guid
            preview.party[i] = party
        end
    end
end

function GI.Preview(on)
    on = on == true
    if on == state.previewOn then return end
    if on then BuildPreview() end
    state.previewOn = on
    Changed(nil)
    if not on then WalkSoon(0) end
end

function GI.PreviewMode(mode)
    if (mode == "party" or mode == "raid") and mode ~= state.previewMode then
        state.previewMode = mode
        if state.previewOn then Changed(nil) end
    end
    return state.previewMode
end
