-- Enchants.lua: the best enchant for what you wear, for your spec and its level (B.Enchants).
local ns = _G.NaowhForever

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant

local B = ns.BiS
local L = B.Lists

local SLOTS = { [2] = true, [5] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true, [17] = true }
local INV_TYPE = { INVTYPE_NECK = 2, INVTYPE_CHEST = 5, INVTYPE_ROBE = 20, INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 16, INVTYPE_SHIELD = 14, INVTYPE_HOLDABLE = 23,
    INVTYPE_WEAPON = 13, INVTYPE_2HWEAPON = 17, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22 }
local SKILL_LEVELS = { { 75, 5 }, { 150, 10 }, { 225, 20 }, { 300, 35 } }
local ENDGAME_LEVEL = 55
local SPECIAL_WORTH = 0.3
local BETTER_BY = 0.01
local KEY_BASE = 100
local WEAPON_DAMAGE = "dmg"
local ANY_SPEC = "any"
local ENCHANT_PATTERN = "item:%d+:(%d*)"
local NONE = {}

local order, byEnchant
local advice = {}
local enchantable = {}

local function LevelFor(skill)
    for i = 1, #SKILL_LEVELS do
        local step = SKILL_LEVELS[i]
        if skill <= step[1] then return step[2] end
    end
    return ENDGAME_LEVEL
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

local function Score(enchant, weights, swing)
    local score = 0
    for stat, value in pairs(enchant.stats or NONE) do
        score = score + (stat == WEAPON_DAMAGE and swing or weights[stat] or 0) * value
    end
    return score
end

local function BySkill(a, b)
    local x, y = ns.BiSEnchants[a].skill, ns.BiSEnchants[b].skill
    if x ~= y then return x < y end
    return a < b
end

local function Index()
    order, byEnchant = {}, {}
    for spell, enchant in pairs(ns.BiSEnchants) do
        order[#order + 1] = spell
        byEnchant[enchant.enchant] = byEnchant[enchant.enchant] or spell
    end
    table.sort(order, BySkill)
end

local function ItemLevel(link)
    local name, _, _, itemLevel, required = GetItemInfo(link)
    if not name then return nil end
    return required and required > 0 and required or itemLevel
end

local function Current(link)
    return tonumber(link:match(ENCHANT_PATTERN) or "") or 0
end

local function Offer(a, spell, enchant, weights, swing, best)
    local special = enchant.special
    if not special then
        local score = Score(enchant, weights, swing)
        if score > best then a.now, best = spell, score end
        return best
    end
    if special == ANY_SPEC or (weights[special] or 0) >= SPECIAL_WORTH then a.specials[#a.specials + 1] = spell end
    return best
end

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
        if LevelFor(enchant.skill) <= level and Fits(enchant, inv, class, subclass) then
            nowScore = Offer(a, spell, enchant, weights, swing, nowScore)
        end
    end
    a.current = Current(link)
    local onIt = byEnchant[a.current]
    a.onIt = onIt
    a.todo = a.now ~= nil and (a.current == 0
        or onIt ~= nil and Score(ns.BiSEnchants[onIt], weights, swing) < nowScore - BETTER_BY)
    return true
end

local function AnyFits(inv, class, subclass)
    for _, enchant in pairs(ns.BiSEnchants) do
        if Fits(enchant, inv, class, subclass) then return true end
    end
    return false
end

local function Forget()
    for _, a in pairs(advice) do a.link = nil end
end

local E = {}
B.Enchants = E
E.SLOTS = SLOTS
E.LevelFor = LevelFor

function E.Enchantable(link)
    local _, _, _, equipLoc, _, class, subclass = GetItemInfoInstant(link)
    local inv = INV_TYPE[equipLoc]
    local current = Current(link)
    if not (inv and class and subclass) then return false, current end
    local key = (inv * KEY_BASE + class) * KEY_BASE + subclass
    local can = enchantable[key]
    if can == nil then
        can = AnyFits(inv, class, subclass)
        enchantable[key] = can
    end
    return can, current
end

function E.Advise(slot)
    local a = advice[slot]
    if not a then
        a = { specials = {}, current = 0, todo = false }
        advice[slot] = a
    end
    local link = SLOTS[slot] and GetInventoryItemLink("player", slot)
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

function E.ToDo(slot)
    return E.Advise(slot).todo
end

ns.StatWeights.OnChange(Forget)
