-- OwnStats.lua: your own exact stats and talent points per tree, read for Group Inspect's answers (GI.OwnStats).
local ns = _G.NaowhForever

local GI = ns.GroupInspect
local C = GI.C

local STAT_MAX = C.STAT_MAX
local TENTH_SCALE, ROUND = C.TENTHS, C.ROUND
local PRIMARY_STATS = 5
local AP, SP, CRIT, HIT, ARMOR = 6, 7, 8, 9, 10
local SCHOOLS_FIRST, SCHOOLS_LAST = 2, 7

local mine = { ok = false, stats = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, spent = { 0, 0, 0 } }
local groupIDs = {}

local function Secret(value)
    return value ~= nil and issecretvalue(value)
end

local function Round(value)
    return math.floor(value + ROUND)
end

local function Clamp(value, most)
    value = Round(value)
    if value < 0 then return 0 end
    if value > most then return most end
    return value
end

local function ReadSpent()
    local spent = mine.spent
    spent[1], spent[2], spent[3] = 0, 0, 0
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if type(groups) ~= "table" then return end
    wipe(groupIDs)
    for i = 1, math.min(#groups, #spent) do groupIDs[i] = groups[i].groupID end
    local infos = C_Traits.GetGroupCurrencyInfo(configID, groupIDs)
    if type(infos) ~= "table" then return end
    for _, info in ipairs(infos) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        for i = 1, #groupIDs do
            if currency and info.traitNodeGroupID == groupIDs[i] then spent[i] = currency.spent or 0 end
        end
    end
end

local function Best(a, b, c, d)
    local most = a
    if b > most then most = b end
    if c and c > most then most = c end
    if d and d > most then most = d end
    return most
end

local function SpellBest(read)
    local most = 0
    for school = SCHOOLS_FIRST, SCHOOLS_LAST do
        local value = read(school)
        if Secret(value) then return nil end
        if value > most then most = value end
    end
    return most
end

local function ReadMine()
    if C_Secrets.ShouldUnitStatsBeSecret() then return mine.ok end
    local stats = mine.stats
    for i = 1, PRIMARY_STATS do
        local _, value = UnitStat("player", i)
        if Secret(value) then return mine.ok end
        stats[i] = Clamp(value, STAT_MAX[i])
    end
    local _, class = UnitClass("player")
    local base, up, down
    if class == "HUNTER" then
        base, up, down = UnitRangedAttackPower("player")
    else
        base, up, down = UnitAttackPower("player")
    end
    local healing, meleeCrit = GetSpellBonusHealing(), GetCritChance()
    local spellDamage, spellCrit = SpellBest(GetSpellBonusDamage), SpellBest(GetSpellCritChance)
    local meleeHit = GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier()
    local spellHit = GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier()
    local _, armor = UnitArmor("player")
    if Secret(base) or Secret(up) or Secret(down) or Secret(healing) or Secret(meleeCrit) or not spellDamage
        or not spellCrit or Secret(meleeHit) or Secret(spellHit) or Secret(armor) then
        return mine.ok
    end
    stats[AP] = Clamp(base + up + down, STAT_MAX[AP])
    stats[SP] = Clamp(Best(spellDamage, healing), STAT_MAX[SP])
    stats[CRIT] = Clamp(Best(meleeCrit, spellCrit) * TENTH_SCALE, STAT_MAX[CRIT])
    stats[HIT] = Clamp(Best(meleeHit, spellHit) * TENTH_SCALE, STAT_MAX[HIT])
    stats[ARMOR] = Clamp(armor, STAT_MAX[ARMOR])
    ReadSpent()
    mine.ok = true
    return true
end

GI.OwnStats = { values = mine, Read = ReadMine }
