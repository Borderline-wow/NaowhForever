-------------------------------------------------------------------------------
--  Gains.lua -- what your BiS is worth over what you wear (ns.BiS.Gains): the Naowh Score of
--  each (NaowhScore/Score.lua; your BiS's keeps what you wear where the list has no pick), and
--  the stats your BiS adds or takes away where you do not wear it yet. An item's stats are fixed, so each is read once; what you wear is read
--  by its link, as a suffix ("of the Monkey") changes them. Rules only, no frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local Items = ns.Shared.Items

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local NaowhScore = ns.NaowhScore
local Stats = ns.StatWeights.Stats

local G = {}
B.Gains = G

local function Add(into, stats, sign)
    if not stats then return end
    for key, value in pairs(stats) do into[key] = (into[key] or 0) + value * sign end
end

---@class BisGains
---@field now number your Naowh Score, from what you wear
---@field bis number your BiS's, with what you wear where the list has no pick
---@field stats table<string, number> the game's stat key ("ITEM_MOD_AGILITY_SHORT") -> what it adds
---@field waiting boolean an item has not loaded yet: read again once it has

-- The list's slots read for the Naowh Score: its pick's level, quality and whether it takes
-- both hands, else what you wear there.
local readList

local function ReadBis(slot)
    local id = readList.slots[slot]
    if not id or (slot == 17 and B.OffHandIdle(readList)) then
        return NaowhScore.Link(GetInventoryItemLink("player", slot))
    end
    local _, _, quality, level = GetItemInfo(id)
    level = level or B.Rankings.ItemLevel(id)
    return level or 0, level and quality, select(4, GetItemInfoInstant(id)) == "INVTYPE_2HWEAPON"
end

---@param out BisGains filled and returned
function G.Read(list, out)
    local stats = wipe(out.stats)
    local idle = B.OffHandIdle(list)
    local waiting = false
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = list.slots[slot]
        if id and not (slot == 17 and idle) and not Items.Wearing(slot, id) then
            local gain = Stats(id)
            waiting = waiting or gain == nil
            Add(stats, gain, 1)
            local link = GetInventoryItemLink("player", slot)
            if link then Add(stats, Stats(link), -1) end
        end
    end
    local now, nowDone = NaowhScore.Unit("player")
    readList = list
    local bis, bisDone = NaowhScore.Of(ReadBis)
    readList = nil
    out.now, out.bis, out.waiting = now, bis, waiting or not (nowDone and bisDone)
    return out
end
