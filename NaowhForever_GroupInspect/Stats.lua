-- Stats.lua: a member's stats added up from the gear they wear (GI.StatsFromGear).
local ns = _G.NaowhForever

local IsItemDataCachedByID, GetItemInfoInstant = C_Item.IsItemDataCachedByID, C_Item.GetItemInfoInstant

local GI = ns.GroupInspect
local C = GI.C
local SW = ns.StatWeights
local GEAR_SLOTS = ns.Shared.Items.GEAR_SLOTS

local PRIMARY, AP, RAP, POWER, SPELL_DAMAGE, HEALING, CRIT, SPELL_CRIT, HIT, SPELL_HIT = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
local KIND = {
    ITEM_MOD_STRENGTH_SHORT = PRIMARY, ITEM_MOD_AGILITY_SHORT = PRIMARY, ITEM_MOD_STAMINA_SHORT = PRIMARY,
    ITEM_MOD_INTELLECT_SHORT = PRIMARY, ITEM_MOD_SPIRIT_SHORT = PRIMARY, RESISTANCE0_NAME = PRIMARY,
    ITEM_MOD_ATTACK_POWER_SHORT = AP, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = RAP,
    ITEM_MOD_SPELL_POWER_SHORT = POWER, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = SPELL_DAMAGE,
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = HEALING,
    ITEM_MOD_CRIT_RATING_SHORT = CRIT, ITEM_MOD_CRIT_SPELL_RATING_SHORT = SPELL_CRIT,
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = SPELL_CRIT,
    ITEM_MOD_HIT_RATING_SHORT = HIT, ITEM_MOD_HIT_SPELL_RATING_SHORT = SPELL_HIT,
}
local PRIMARY_KEY = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
}

local TENTHS, ROUND = C.TENTHS, C.ROUND

local sums = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local primary = { STR = 0, AGI = 0, STA = 0, INT = 0, SPI = 0, ARMOR = 0 }

local function Secret(value)
    return value ~= nil and issecretvalue(value)
end

local function Tenth(value)
    return math.floor(value * TENTHS + ROUND) / TENTHS
end

local function AddItem(stats, hunter)
    for key, amount in pairs(stats) do
        local kind = KIND[key]
        if kind and type(amount) == "number" and not Secret(amount) then
            if kind == PRIMARY then
                local name = PRIMARY_KEY[key]
                primary[name] = primary[name] + amount
            elseif kind == RAP then
                if hunter then sums[AP] = sums[AP] + amount end
            elseif kind == CRIT or kind == SPELL_CRIT or kind == HIT or kind == SPELL_HIT then
                sums[kind] = sums[kind] + SW.KeyAmount(key, amount)
            else
                sums[kind] = sums[kind] + amount
            end
        end
    end
end

function GI.StatsFromGear(record)
    if type(record) ~= "table" or record.statsShared == true or type(record.gear) ~= "table" then return false end
    for i = 1, #sums do sums[i] = 0 end
    for key in pairs(primary) do primary[key] = 0 end
    local hunter = record.classFile == "HUNTER"
    local gear, complete = record.gear, true
    for i = 1, #GEAR_SLOTS do
        local entry = gear[GEAR_SLOTS[i][1]]
        local link = entry and entry.link
        if type(link) == "string" and not Secret(link) then
            local id = entry.id or GetItemInfoInstant(link)
            local stats = id and IsItemDataCachedByID(id) and SW.Stats(link)
            if stats then AddItem(stats, hunter) else complete = false end
        end
    end
    local into = record.stats
    if type(into) ~= "table" then
        into = {}
        record.stats = into
    end
    into.STR, into.AGI, into.STA = primary.STR, primary.AGI, primary.STA
    into.INT, into.SPI, into.ARMOR = primary.INT, primary.SPI, primary.ARMOR
    into.AP = sums[AP]
    into.SP = sums[POWER] + math.max(sums[SPELL_DAMAGE], sums[HEALING])
    into.CRIT = Tenth(sums[CRIT] + sums[SPELL_CRIT])
    into.HIT = Tenth(sums[HIT] + sums[SPELL_HIT])
    record.statsShared = false
    return complete
end
