-- Gains.lua: what your BiS gets you over what you wear: Naowh Score and stats (B.Gains).
local ns = _G.NaowhForever

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local B = ns.BiS
local Items = ns.Shared.Items
local NaowhScore = ns.NaowhScore
local Stats = ns.StatWeights.Stats

local OFF_HAND = B.C.OFF_HAND
local TWO_HAND = "INVTYPE_2HWEAPON"

local readList

local function Add(into, stats, sign)
    if not stats then return end
    for key, value in pairs(stats) do into[key] = (into[key] or 0) + value * sign end
end

local function ReadBis(slot)
    local id = readList.slots[slot]
    if not id or (slot == OFF_HAND and B.OffHandIdle(readList)) then
        return NaowhScore.Link(GetInventoryItemLink("player", slot))
    end
    local _, _, quality, level = GetItemInfo(id)
    level = level or B.Rankings.ItemLevel(id)
    local _, _, _, equipLoc = GetItemInfoInstant(id)
    return level or 0, level and quality, equipLoc == TWO_HAND
end

local function AddSlot(stats, slot, id)
    local gain = Stats(id)
    Add(stats, gain, 1)
    local link = GetInventoryItemLink("player", slot)
    if link then Add(stats, Stats(link), -1) end
    return gain == nil
end

local G = {}
B.Gains = G

function G.Read(list, out)
    local stats = wipe(out.stats)
    local idle = B.OffHandIdle(list)
    local waiting = false
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = list.slots[slot]
        if id and not (slot == OFF_HAND and idle) and not Items.Wearing(slot, id) then
            waiting = AddSlot(stats, slot, id) or waiting
        end
    end
    local now, nowDone = NaowhScore.Unit("player")
    readList = list
    local bis, bisDone = NaowhScore.Of(ReadBis)
    readList = nil
    out.now, out.bis, out.waiting = now, bis, waiting or not (nowDone and bisDone)
    return out
end
