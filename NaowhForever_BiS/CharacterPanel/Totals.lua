-- Totals.lua: your total now for each stat a weight can be set for, plain or kept secret by the game (CP.Totals).
local ns = _G.NaowhForever

local CP = ns.CharacterPanel
local C = CP.C

local MP5_TICK = 5
local SWINGS = 2
local FIRST_SCHOOL, LAST_SCHOOL = 2, 7
local NO_SPEED = "-"
local HIDDEN = "-"
local PERCENT_FORMAT = "%.1f%%"
local WHOLE_FORMAT = "%d"
local DPS_FORMAT = "%.1f"
local SCHOOLS = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }
local PRIMARY = { "str", "agi", "sta", "int", "spi" }

local function Percent(value) return PERCENT_FORMAT:format(value or 0) end
local function Whole(value) return WHOLE_FORMAT:format(math.floor((value or 0) + C.HALF)) end

local function Stat(index)
    return select(2, UnitStat("player", index))
end

local function Armor()
    return select(2, UnitArmor("player"))
end

local function SpellDamage()
    local least
    for school = FIRST_SCHOOL, LAST_SCHOOL do
        local bonus = GetSpellBonusDamage(school)
        if not least or bonus < least then least = bonus end
    end
    return least
end

local function AttackPower()
    local base, up, down = UnitAttackPower("player")
    return Whole(base + up + down)
end

local function RangedAttackPower()
    local base, up, down = UnitRangedAttackPower("player")
    return Whole(base + up + down)
end

local function WeaponDps()
    local low, high = UnitDamage("player")
    local speed = UnitAttackSpeed("player")
    return speed and speed > 0 and DPS_FORMAT:format((low + high) / SWINGS / speed) or NO_SPEED
end

local function Defense()
    local base, modifier = UnitDefenseSkill("player")
    return Whole(base + modifier)
end

local function Rounded(read)
    return function(text) text:SetText(C_StringUtil.FloorToNearestString(read())) end
end

local function Percented(read)
    return function(text) text:SetFormattedText(PERCENT_FORMAT, read()) end
end

local TOTAL = {
    ap = AttackPower,
    rap = RangedAttackPower,
    dps = WeaponDps,
    hit = function() return Percent(GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier()) end,
    shit = function() return Percent(GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier()) end,
    crit = function() return Percent(GetCritChance()) end,
    haste = function() return Percent(GetMeleeHaste()) end,
    spell = function() return Whole(SpellDamage()) end,
    heal = function() return Whole(GetSpellBonusHealing()) end,
    scrit = function() return Percent(GetSpellCritChance()) end,
    mp5 = function() return Whole(GetManaRegen() * MP5_TICK) end,
    def = Defense,
    dodge = function() return Percent(GetDodgeChance()) end,
    block = function() return Percent(GetBlockChance()) end,
    armor = function() return Whole(Armor()) end,
}

local SECRET_TOTAL = {
    armor = Rounded(Armor),
    heal = Rounded(GetSpellBonusHealing),
    crit = Percented(GetCritChance),
    haste = Percented(GetMeleeHaste),
    scrit = Percented(GetSpellCritChance),
    dodge = Percented(GetDodgeChance),
    block = Percented(GetBlockChance),
}

for i, stat in ipairs(PRIMARY) do
    TOTAL[stat] = function() return Whole(Stat(i)) end
    SECRET_TOTAL[stat] = Rounded(function() return Stat(i) end)
end

for school, index in pairs(SCHOOLS) do
    TOTAL[school] = function() return Whole(GetSpellBonusDamage(index)) end
    SECRET_TOTAL[school] = Rounded(function() return GetSpellBonusDamage(index) end)
end

CP.Totals = { Plain = TOTAL, Secret = SECRET_TOTAL, HIDDEN = HIDDEN }
