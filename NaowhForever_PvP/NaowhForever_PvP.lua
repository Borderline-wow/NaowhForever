-------------------------------------------------------------------------------
--  NaowhForever_PvP.lua -- the PvP module's settings (ns.PvPSettings), off until switched on
--  in the options window; PvP Auras (NaowhForever_PvPAuras.lua) reads them. Each crowd control
--  ability and each debuff in Data/NaowhForever_PvPSpells.lua has its own switch: "cc_<key>",
--  on by default, and "debuff_<key>", off.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local DEFAULTS = {
    enabled = false,
    auras = true, size = 36, timer = true, count = true,
    warn = true, warnAt = 3, warnBlink = true,
    pos = { point = "CENTER", relPoint = "CENTER", x = 240, y = -60 },
    buffs = true, buffLength = 30, buffMagicOnly = false, buffMax = 6, absorb = true,
    cc = true, ccMax = 4, ccOther = true,
    debuffs = false, debuffMax = 4, debuffExtra = "",
    focus = true, focusName = true, focusBuffs = false, focusCC = true, focusDebuffs = false,
    focusPos = { point = "CENTER", relPoint = "CENTER", x = 240, y = -180 },
    scoresPos = false, timerPos = false,
}
for _, entry in ipairs(ns.PvPSpells.crowdControl) do DEFAULTS["cc_" .. entry.key] = true end
for _, entry in ipairs(ns.PvPSpells.debuffs) do DEFAULTS["debuff_" .. entry.key] = false end

ns.PvPSettings = ns.UI.ModuleSettings("pvp", DEFAULTS)
