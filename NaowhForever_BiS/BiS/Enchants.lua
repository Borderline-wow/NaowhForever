-------------------------------------------------------------------------------
--  Enchants.lua -- the best enchant for what you wear in a slot (ns.BiS.Enchants), for your
--  list's spec and the item's level (no use putting an endgame enchant on a level 19 sword),
--  what is on it now and whether the best beats it. The game puts no level limit on any
--  enchant; this is advice. Enchants from Data/Enchants.lua, ranked by your spec's stat weights
--  (the Stat Weights module's, yours where you changed them).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local L = B.Lists

local E = {}
B.Enchants = E

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant

-- The slots an enchanter can enchant: neck, chest, feet, wrists, hands, back and the weapons.
E.SLOTS = { [2] = true, [5] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true, [17] = true }

local INV_TYPE = { INVTYPE_NECK = 2, INVTYPE_CHEST = 5, INVTYPE_ROBE = 20, INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 16, INVTYPE_SHIELD = 14, INVTYPE_HOLDABLE = 23,
    INVTYPE_WEAPON = 13, INVTYPE_2HWEAPON = 17, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22 }
local SPECIAL_WORTH = 0.3   -- how much a spec must value a special's stat to be shown it
local NONE = {}

--- The level an enchant suits, from the Enchanting it needs: trainers teach up to 75 at 5,
--- 150 at 10, 225 at 20 and 300 at 35; Forever's recipes past 300 come from its endgame.
---@param skill number
---@return number
function E.LevelFor(skill)
    return skill <= 75 and 5 or skill <= 150 and 10 or skill <= 225 and 20 or skill <= 300 and 35 or 55
end

local function Bit(mask, n)
    return math.floor(mask / 2 ^ n) % 2 == 1
end

local function Fits(enchant, inv, class, subclass)
    if enchant.inv ~= 0 then
        return Bit(enchant.inv, inv) and (enchant.sub == 0 or enchant.class ~= class or Bit(enchant.sub, subclass))
    end
    return enchant.class == class and Bit(enchant.sub, subclass)
end

-- Its stats by your weights; weapon damage per swing by what it is worth on this weapon (swing).
local function Score(enchant, weights, swing)
    local score = 0
    for stat, value in pairs(enchant.stats or NONE) do
        score = score + (stat == "dmg" and swing or weights[stat] or 0) * value
    end
    return score
end

-- Recipes by the skill they need, so the cheaper of two as good wins; and by the enchant they put on.
local order, byEnchant

local function Index()
    order, byEnchant = {}, {}
    for spell, enchant in pairs(ns.BiSEnchants) do
        order[#order + 1] = spell
        byEnchant[enchant.enchant] = byEnchant[enchant.enchant] or spell
    end
    table.sort(order, function(a, b)
        local x, y = ns.BiSEnchants[a].skill, ns.BiSEnchants[b].skill
        if x ~= y then return x < y end
        return a < b
    end)
end

---@class EnchantAdvice
---@field now number? the best recipe for the item's level
---@field itemLevel number? the item's level
---@field current number the enchant on it now, 0 for none
---@field onIt number? the recipe that puts the current enchant on, when it is one of ours
---@field todo boolean the best for now beats what is on it
---@field specials number[] recipes that do something no stat can say, for a stat you value

local advice = {}

-- The level the item is for: the level it needs, else its item level; nil until it loads.
local function ItemLevel(link)
    local name, _, _, itemLevel, required = GetItemInfo(link)
    if not name then return nil end
    return required and required > 0 and required or itemLevel
end

-- false while the item's level has not loaded, to be read again.
local function Read(a, link, weights, slot)
    local _, _, _, equipLoc, _, class, subclass = GetItemInfoInstant(link)
    local inv = INV_TYPE[equipLoc]
    if not inv then return true end
    local level = ItemLevel(link)
    if not level then return false end
    a.itemLevel = level
    if not order then Index() end
    local swing = ns.StatWeights.SwingDamage(weights, slot)
    local nowScore = 0
    for _, spell in ipairs(order) do
        local enchant = ns.BiSEnchants[spell]
        if E.LevelFor(enchant.skill) <= level and Fits(enchant, inv, class, subclass) then
            local special = enchant.special
            if special then
                if special == "any" or (weights[special] or 0) >= SPECIAL_WORTH then
                    a.specials[#a.specials + 1] = spell
                end
            else
                local score = Score(enchant, weights, swing)
                if score > nowScore then a.now, nowScore = spell, score end
            end
        end
    end
    a.current = tonumber(link:match("item:%d+:(%d*)") or "") or 0
    local onIt = byEnchant[a.current]
    a.onIt = onIt
    a.todo = a.now ~= nil and (a.current == 0
        or onIt ~= nil and Score(ns.BiSEnchants[onIt], weights, swing) < nowScore - 0.01)
    return true
end

--- What to enchant on what you wear in the slot. Read again when that item or your list's
--- spec changes; the same table until then.
---@param slot number inventory slot
---@return EnchantAdvice
function E.Advise(slot)
    local a = advice[slot]
    if not a then
        a = { specials = {}, current = 0, todo = false }
        advice[slot] = a
    end
    local link = E.SLOTS[slot] and GetInventoryItemLink("player", slot)
    local spec = L.CurrentSpec()
    local key = spec and spec.key
    if a.link == link and a.spec == key then return a end
    a.link, a.spec = link, key
    a.now, a.onIt, a.itemLevel, a.current, a.todo = nil, nil, nil, 0, false
    wipe(a.specials)
    local weights = key and ns.StatWeights.For(key)
    if link and weights and not Read(a, link, weights, slot) then a.link = nil end
    return a
end

-- Changed weights rank the enchants again.
ns.StatWeights.OnChange(function()
    for _, a in pairs(advice) do a.link = nil end
end)

--- Whether the best enchant for the slot's item beats what is on it.
---@param slot number
---@return boolean
function E.ToDo(slot)
    return E.Advise(slot).todo
end
