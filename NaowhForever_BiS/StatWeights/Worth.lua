-- Worth.lua: what an item is worth to your weights, and how much stronger it makes you (SW.Gain, SW.BestGain).
local ns = _G.NaowhForever

local GetItemStats = C_Item.GetItemStats
local IsItemDataCachedByID = C_Item.IsItemDataCachedByID
local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant

local SW = ns.StatWeights
local Items = ns.Shared.Items
local GAME_KEYS, PER_PERCENT = SW.GAME_KEYS, SW.PER_PERCENT

local MAIN_HAND, OFF_HAND = 16, 17
local CACHE_MAX = 600
local SPEED = 2.6
local MIN_GAIN = 0.5
local PERCENT = SW.PERCENT
local ANY_SUBCLASS = 0
local CLOAK = "INVTYPE_CLOAK"
local HUNTER = "HUNTER"
local DPS = "dps"
local FACT_CLASS, FACT_SUBCLASS, FACT_REQUIRED = 1, 2, 4
local DPS_SHARE = { [16] = 1, [17] = 0.5 }
local HUNTER_DPS_SHARE = { [18] = 1 }
local PRIMARY = { "str", "agi", "sta", "int", "spi" }
local PRIMARY_KEY = { str = true, agi = true, sta = true, int = true, spi = true }
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local statsOf, cached = {}, 0
local lastMain, lastOff
local lastPower = setmetatable({}, { __mode = "k" })
local forgetter
local facts = {}
local myClass

local function Forget()
    wipe(lastPower)
    lastMain, lastOff = nil, nil
end

local function Remembering()
    if forgetter then return end
    forgetter = CreateFrame("Frame")
    forgetter:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    forgetter:RegisterEvent("PLAYER_LEVEL_UP")
    forgetter:SetScript("OnEvent", Forget)
end

local function Stats(item)
    local stats = statsOf[item]
    if stats then return stats end
    if type(item) == "number" and not IsItemDataCachedByID(item) then return nil end
    stats = GetItemStats(type(item) == "number" and "item:" .. item or item) or {}
    if cached >= CACHE_MAX then
        wipe(statsOf)
        cached = 0
    end
    statsOf[item], cached = stats, cached + 1
    return stats
end

local function Worth(stats, weights, dpsShare, skipPrimary)
    local worth = 0
    for key, value in pairs(stats) do
        local mine = GAME_KEYS[key]
        local per = PER_PERCENT[key]
        if per then value = value / per end
        if type(mine) == "table" then
            for i = 1, #mine do worth = worth + (weights[mine[i]] or 0) * value end
        elseif mine == DPS then
            worth = worth + (weights.dps or 0) * value * (dpsShare or 0)
        elseif mine and not (skipPrimary and PRIMARY_KEY[mine]) then
            worth = worth + (weights[mine] or 0) * value
        end
    end
    return worth
end

local function DpsShare(slot)
    local shares = select(2, UnitClass("player")) == HUNTER and HUNTER_DPS_SHARE or DPS_SHARE
    return shares[slot] or 0
end

local function WornWorth(slot, weights)
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end
    local worn = Stats(link)
    return worn and Worth(worn, weights, DpsShare(slot))
end

local function Usable(id, link)
    local canUse = ns.ClassCanUse
    if not canUse then return true end
    local _, _, _, equipLoc, _, itemClass, subclass = GetItemInfoInstant(id)
    local _, _, _, _, required = GetItemInfo(link or id)
    if not (itemClass and required) then return nil end
    myClass = myClass or select(2, UnitClass("player"))
    if equipLoc == CLOAK then subclass = ANY_SUBCLASS end
    facts[FACT_CLASS], facts[FACT_SUBCLASS], facts[FACT_REQUIRED] = itemClass, subclass, required
    return canUse(myClass, facts)
end

local function Wearing(id, slots)
    for i = 1, #slots do
        if Items.Wearing(slots[i], id) then return true end
    end
    return false
end

SW.MIN_GAIN = MIN_GAIN
SW.Stats = Stats
SW.Worth = Worth
SW.DpsShare = DpsShare

function SW.SwingDamage(weights, slot)
    local main, off = lastMain, lastOff
    if not C_Secrets.ShouldUnitStatsBeSecret() then
        main, off = UnitAttackSpeed("player")
        lastMain, lastOff = main, off
        Remembering()
    end
    local speed = (slot == OFF_HAND and off or main) or SPEED
    return (weights.dps or 0) * DpsShare(slot) / (speed > 0 and speed or SPEED)
end

function SW.Power(weights)
    if C_Secrets.ShouldUnitStatsBeSecret() then return lastPower[weights] end
    local power = 0
    for i, key in ipairs(PRIMARY) do power = power + (weights[key] or 0) * select(2, UnitStat("player", i)) end
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        local stats = link and Stats(link)
        if stats then power = power + Worth(stats, weights, DpsShare(slot), true) end
    end
    lastPower[weights] = power
    Remembering()
    return power
end

function SW.Gain(item, slot, weights, power, also)
    if not (weights and power and power > 0) then return nil end
    local stats = Stats(item)
    local worn = WornWorth(slot, weights)
    local other = also and WornWorth(also, weights) or 0
    if not (stats and worn and other) then return nil end
    return PERCENT * (Worth(stats, weights, DpsShare(slot)) - worn - other) / power
end

function SW.BestGain(id, link, weights, power)
    local slots = Items.SlotsFor(id)
    if not (slots and weights) then return nil end
    if Wearing(id, slots) or not Usable(id, link) then return nil end
    local twoHand = Items.IsTwoHand(id)
    local best
    for i = 1, #slots do
        local slot = slots[i]
        local gain = SW.Gain(link or id, slot, weights, power, twoHand and slot == MAIN_HAND and OFF_HAND or nil)
        if gain and (not best or gain > best) then best = gain end
    end
    return best and best >= MIN_GAIN and best or nil
end
