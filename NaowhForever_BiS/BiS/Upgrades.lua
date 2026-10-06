-------------------------------------------------------------------------------
--  Upgrades.lua -- how much stronger each BiS makes you over what you wear in its slot
--  (ns.BiS.Upgrades), for picking what to farm first: by your list's spec's stat weights
--  (the Stat Weights module's, yours where you changed them), as a share of what your stats
--  are worth now. An estimate, as the weights are: it orders upgrades, it does not promise a
--  number on a meter. Rules only, no frames.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local L = B.Lists
local Items = ns.Shared.Items
local SW = ns.StatWeights

local U = {}
B.Upgrades = U

local gains = {}   -- slot -> its gain in percent, this read

--- Each slot's gain in percent from its BiS over what you wear there, where it is one (above
--- zero); nil where you wear it, it is not yours to gain from, or its data has not loaded.
--- Read again on each draw: your gear and your stats change it.
---@param list table a BiS list
---@return table<number, number> gains slot -> percent, the caller's until the next call
function U.Read(list)
    wipe(gains)
    local spec = L.CurrentSpec()
    local weights = spec and SW.For(spec.key)
    if not weights then return gains end
    local power = SW.Power(weights)
    local idle = B.OffHandIdle(list)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = list.slots[slot]
        if id and not (slot == 17 and idle) and not Items.Wearing(slot, id) then
            local gain = SW.Gain(id, slot, weights, power)
            if gain and gain > 0 then gains[slot] = gain end
        end
    end
    return gains
end

--- One item's gain in percent over what you wear in the slot (a backup pick's), as Read's.
---@return number? gain nil where it is no gain, or you wear it
function U.Gain(itemID, slot)
    if Items.Wearing(slot, itemID) then return nil end
    local spec = L.CurrentSpec()
    local weights = spec and SW.For(spec.key)
    if not weights then return nil end
    local gain = SW.Gain(itemID, slot, weights, SW.Power(weights))
    return gain and gain > 0 and gain or nil
end
