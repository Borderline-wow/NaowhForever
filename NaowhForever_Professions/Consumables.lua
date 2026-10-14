-- Consumables.lua: the consumables that suit you, by class, mana and level, each kind's best for your level marked (P.Consumables).
local ns = _G.NaowhForever

local P = ns.Professions
local D = P.ConsumableItems
local Items = ns.Shared.Items

local REQUIRED_LEVEL = 5
local MANA = "mana"
local NO_STAT = ""
local SEP = ":"
local EMPTY = {}

local levels = {}
local best, soonest, lowest, highest = {}, {}, {}, {}
local lines = {}
local groups, groupPool, rowPool = {}, {}, {}
local shared = {}

local Consumables = {}
P.Consumables = Consumables

local function Tagged(list, tag)
    local out = {}
    for _, id in ipairs(list or EMPTY) do out[#out + 1] = { id, tag and tag(id) } end
    return out
end

local function WeaponStat(id)
    return D.WEAPON_STATS[id] or D.WEAPON_STAT
end

local function ManaTag()
    return MANA
end

local function SharedList(group)
    if shared[group] then return shared[group] end
    local list
    if group == "potion" then
        list = Tagged(ns.HEALING_POTIONS)
        for _, e in ipairs(Tagged(ns.MANA_POTIONS, ManaTag)) do list[#list + 1] = e end
    elseif group == "weapon" then
        local buffs = ns.BuffReminderData
        list = Tagged(buffs and buffs.WEAPON_ITEMS or D.WEAPON_ITEMS, WeaponStat)
    elseif group == "bandage" then
        local macros = ns.Macros
        list = Tagged(macros and macros.Items and macros.Items.BANDAGES or D.BANDAGES)
    end
    shared[group] = list
    return list
end

local function Entries(group)
    return D.ITEMS[group] or SharedList(group)
end

local function Level(id)
    local level = levels[id]
    if level then return level end
    level = select(REQUIRED_LEVEL, C_Item.GetItemInfo(id))
    levels[id] = level
    return level
end

local function Lines(group, e, stats, mine, mana)
    wipe(lines)
    if #e == 1 then
        lines[1] = group .. SEP .. NO_STAT
        return lines
    end
    for i = 2, #e do
        local stat = e[i]
        if not mine or (stat == MANA and mana) or (stat ~= MANA and stats[stat]) then
            lines[#lines + 1] = group .. SEP .. stat
        end
    end
    return lines
end

local function ByLevel(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function Measure(group, level, stats, mine, mana)
    for _, e in ipairs(Entries(group)) do
        local lv = Level(e[1])
        if lv then
            for _, line in ipairs(Lines(group, e, stats, mine, mana)) do
                if lv <= level then
                    if lv > (best[line] or -1) then best[line] = lv end
                elseif lv < (soonest[line] or math.huge) then
                    soonest[line] = lv
                end
                if lv < (lowest[line] or math.huge) then lowest[line] = lv end
                if lv > (highest[line] or -1) then highest[line] = lv end
            end
        end
    end
end

local function Fill(row, e, lv, level, group, stats, mine, mana)
    local shown, isBest = not mine, false
    for _, line in ipairs(Lines(group, e, stats, mine, mana)) do
        if lv <= level or lv == soonest[line] then shown = true end
        if lv == best[line] and lowest[line] < highest[line] then isBest = true end
    end
    if not shown then return false end
    row.level, row.name = lv, Items.Name(e[1])
    row.best, row.later = isBest, lv > level
    return true
end

local function Collect(group, level, stats, mine, mana, n)
    local out = groupPool[group] or { key = group, rows = {} }
    groupPool[group] = out
    local rows = out.rows
    wipe(rows)
    for _, e in ipairs(Entries(group)) do
        local id, lv = e[1], Level(e[1])
        if lv then
            local row = rowPool[id] or { id = id }
            rowPool[id] = row
            if Fill(row, e, lv, level, group, stats, mine, mana) then rows[#rows + 1] = row end
        end
    end
    if #rows == 0 then return n end
    table.sort(rows, ByLevel)
    groups[n + 1] = out
    return n + 1
end

function Consumables.Pick(level, class, mine, mana)
    local stats = D.CLASS_STATS[class] or EMPTY
    wipe(best)
    wipe(soonest)
    wipe(lowest)
    wipe(highest)
    for _, group in ipairs(D.GROUPS) do Measure(group, level, stats, mine, mana) end
    local n = 0
    for _, group in ipairs(D.GROUPS) do n = Collect(group, level, stats, mine, mana, n) end
    for i = n + 1, #groups do groups[i] = nil end
    return groups
end

function Consumables.IDs()
    local ids = {}
    for _, group in ipairs(D.GROUPS) do
        for _, e in ipairs(Entries(group)) do ids[#ids + 1] = e[1] end
    end
    return ids
end
