-- Upgrades.lua: how much stronger each BiS makes you, in percent, by your weights (B.Upgrades).
local ns = _G.NaowhForever

local B = ns.BiS
local L = B.Lists
local Items = ns.Shared.Items
local SW = ns.StatWeights

local OFF_HAND = B.C.OFF_HAND

local gains = {}

local function Weights()
    local spec = L.CurrentSpec()
    return spec and SW.For(spec.key)
end

local U = {}
B.Upgrades = U

function U.Read(list)
    wipe(gains)
    local weights = Weights()
    if not weights then return gains end
    local power = SW.Power(weights)
    local idle = B.OffHandIdle(list)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = list.slots[slot]
        if id and not (slot == OFF_HAND and idle) and not Items.Wearing(slot, id) then
            local gain = SW.Gain(id, slot, weights, power)
            if gain and gain > 0 then gains[slot] = gain end
        end
    end
    return gains
end

function U.Gain(itemID, slot)
    if Items.Wearing(slot, itemID) then return nil end
    local weights = Weights()
    if not weights then return nil end
    local gain = SW.Gain(itemID, slot, weights, SW.Power(weights))
    return gain and gain > 0 and gain or nil
end
