-- Plan.lua: your class's spells sorted by what stands between you and each, and what they cost.
local ns = _G.NaowhForever

local Training = ns.Training
local Ignored = Training.Ignored
local ClassSpells = Training.ClassSpells
local Price = Training.Price
local Changed = Training.Changed

local SOON = Training.SOON
local LEVEL, SPELL = Training.C.ENTRY_LEVEL, Training.C.ENTRY_SPELL

local function ForMyRace(entry, race)
    if not entry.races then return true end
    for _, r in ipairs(entry.races) do
        if r == race then return true end
    end
    return false
end

local function MySpells(race)
    local mine, after = {}, {}
    for _, entry in ipairs(ClassSpells()) do
        if ForMyRace(entry, race) then
            mine[#mine + 1] = entry
            if entry.needs then after[entry.needs] = entry[SPELL] end
        end
    end
    return mine, after
end

local function Known(mine, after)
    local known = {}
    for i = #mine, 1, -1 do
        local spell = mine[i][SPELL]
        known[spell] = C_SpellBook.IsSpellKnown(spell) or known[after[spell]] or false
    end
    return known
end

local function StateOf(entry, level, known, ignored)
    if ignored[entry[SPELL]] then return "ignored" end
    if entry.talent and not C_SpellBook.IsSpellKnown(entry.talent) then return "talent" end
    if entry[LEVEL] > level + SOON then return "later" end
    if entry[LEVEL] > level then return "soon" end
    if entry.needs and not (known[entry.needs] or known[entry.needs] == nil
        and C_SpellBook.IsSpellKnown(entry.needs)) then
        return "rank"
    end
    return "now"
end

function Training.Plan(level)
    local _, _, race = UnitRace("player")
    local ignored = Ignored()
    level = level or UnitLevel("player")
    local mine, after = MySpells(race)
    local known = Known(mine, after)
    local plan = { now = {}, rank = {}, soon = {}, later = {}, talent = {}, ignored = {}, learned = {},
        byLevel = {}, known = known, level = level }
    for _, entry in ipairs(mine) do
        local group = plan.byLevel[entry[LEVEL]]
        if not group then
            group = {}
            plan.byLevel[entry[LEVEL]] = group
        end
        group[#group + 1] = entry
        if not known[entry[SPELL]] then
            local list = plan[StateOf(entry, level, known, ignored)]
            list[#list + 1] = entry
        else
            plan.learned[#plan.learned + 1] = entry
        end
    end
    return plan
end

function Training.Total(entries)
    local total = 0
    for _, entry in ipairs(entries) do total = total + Price(entry) end
    return total
end

function Training.ToSixty(plan)
    return Training.Total(plan.now) + Training.Total(plan.rank) + Training.Total(plan.soon)
        + Training.Total(plan.later)
end

function Training.SetIgnored(spell, allRanks, on)
    local ignored = Ignored()
    local name = C_Spell.GetSpellName(spell)
    for _, entry in ipairs(ClassSpells()) do
        if entry[SPELL] == spell or allRanks and C_Spell.GetSpellName(entry[SPELL]) == name then
            ignored[entry[SPELL]] = on or nil
        end
    end
    Changed()
end
