-- AuraRows.lua: PvP Auras' panels and their rows, and the buff, crowd control and debuff filters the rows pick by (P.Displays, P.RowOn).
local ns = _G.NaowhForever

local P = ns.PvP
local S = P.Settings
local SPELLS = ns.PvPSpells

local MAGIC = { Magic = true }
local ROWS = { "buffs", "cc", "debuffs" }
local MAX_KEY = { buffs = "buffMax", cc = "ccMax", debuffs = "debuffMax" }
local FILTER = { buffs = "HELPFUL", cc = "HARMFUL", debuffs = "HARMFUL" }

local DISPLAYS = {
    { key = "target", unit = "target", frame = "NaowhForeverPvPAuras", name = "PvP Auras", posKey = "pos",
      changed = "PLAYER_TARGET_CHANGED", rows = { buffs = "buffs", cc = "cc", debuffs = "debuffs" } },
    { key = "focus", unit = "focus", frame = "NaowhForeverPvPAurasFocus", name = "PvP Auras: Focus",
      posKey = "focusPos", changed = "PLAYER_FOCUS_CHANGED", switch = "focus", nameKey = "focusName",
      rows = { buffs = "focusBuffs", cc = "focusCC", debuffs = "focusDebuffs" } },
}

local buffFilters = {}
local pickParts = {}
local lists = {
    cc = { ids = {}, filters = {}, version = 0 },
    debuffs = { ids = {}, filters = {}, version = 0 },
}

local function Pick(entries, prefix, ids)
    wipe(pickParts)
    wipe(ids)
    for _, entry in ipairs(entries) do
        local on = S.Get(prefix .. entry.key) == true
        pickParts[#pickParts + 1] = on and "1" or "0"
        if on then
            for id in pairs(entry.ids) do ids[id] = true end
        end
    end
    return table.concat(pickParts)
end

local function AddTyped(text, ids)
    for id in tostring(text or ""):gmatch("%d+") do ids[tonumber(id)] = true end
end

local function RefreshCrowdControl()
    local cc = lists.cc
    local signature = Pick(SPELLS.crowdControl, P.CC_PREFIX, cc.ids) .. (S.Get("ccOther") and "1" or "0")
    if S.Get("ccOther") then
        for id in pairs(SPELLS.otherCrowdControl) do cc.ids[id] = true end
    end
    if signature == cc.signature then return end
    cc.signature, cc.version = signature, cc.version + 1
    cc.filters.includeSpellIDs = cc.ids
end

local function RefreshDebuffs()
    local debuffs = lists.debuffs
    local extra = S.Get("debuffExtra") or ""
    local signature = Pick(SPELLS.debuffs, P.DEBUFF_PREFIX, debuffs.ids) .. "|" .. extra
    AddTyped(extra, debuffs.ids)
    if signature == debuffs.signature then return end
    debuffs.signature, debuffs.version = signature, debuffs.version + 1
    debuffs.filters.includeSpellIDs = debuffs.ids
end

function P.DisplayOn(d)
    return d.switch == nil or S.Get(d.switch) == true
end

function P.RowOn(d, row)
    return S.Get(d.rows[row]) == true
end

function P.BuffFilters()
    buffFilters.maxDuration = S.Get("buffLength")
    buffFilters.includeDispelTypes = S.Get("buffMagicOnly") and MAGIC or nil
    return buffFilters
end

function P.RefreshLists()
    RefreshCrowdControl()
    RefreshDebuffs()
end

P.Displays = DISPLAYS
P.ROWS = ROWS
P.MAX_KEY = MAX_KEY
P.FILTER = FILTER
P.AuraLists = lists
