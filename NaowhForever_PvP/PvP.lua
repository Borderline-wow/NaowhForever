-- PvP.lua: the PvP module's settings (ns.PvPSettings) and its table (ns.PvP).
local ns = _G.NaowhForever

local F = ns.FEATURES.pvp
local SPELLS = ns.PvPSpells

local CC_PREFIX, DEBUFF_PREFIX = "cc_", "debuff_"

local DEFAULTS = {
    enabled = F.enabled,
    auras = F.auras, size = 36, timer = true, count = true,
    warn = true, warnAt = 3, warnBlink = true,
    pos = { point = "CENTER", relPoint = "CENTER", x = 240, y = -60 },
    buffs = F.buffs, buffLength = 30, buffMagicOnly = false, buffMax = 6, absorb = true,
    cc = F.cc, ccMax = 4, ccOther = true,
    debuffs = F.debuffs, debuffMax = 4, debuffExtra = "",
    focus = F.focus, focusName = true, focusBuffs = false, focusCC = true, focusDebuffs = false,
    focusPos = { point = "CENTER", relPoint = "CENTER", x = 240, y = -180 },
    scoresPos = false, timerPos = false,
}
for _, entry in ipairs(SPELLS.crowdControl) do DEFAULTS[CC_PREFIX .. entry.key] = true end
for _, entry in ipairs(SPELLS.debuffs) do DEFAULTS[DEBUFF_PREFIX .. entry.key] = false end

local S = ns.UI.ModuleSettings("pvp", DEFAULTS)
ns.PvPSettings = S

local P = { Settings = S, CC_PREFIX = CC_PREFIX, DEBUFF_PREFIX = DEBUFF_PREFIX }
ns.PvP = P

function P.Enabled()
    return S.Get("enabled") == true
end

function P.Readable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

function P.Needs(key)
    return function() return S.Get("enabled") == true and S.Get(key) == true end
end
