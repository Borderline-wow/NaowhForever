-------------------------------------------------------------------------------
--  StatWeights/Data/Defaults.lua -- what a point of each stat is worth to each spec, by
--  default (ns.StatWeightDefaults): the class, the spec's key (the BiS List's), its name and
--  its weights, for level 60. Measured in the spec's anchor at 1: its main stat for a fighter,
--  Spell Damage for a caster, Healing for a healer, Stamina for a tank. A percent (hit, crit,
--  haste, dodge, block) is worth that many anchor points per 1%, and dps a point of a weapon's
--  damage per second (14 attack power's worth); an enchant's weapon damage is worked out from
--  it. ns.StatWeightDefaultsUpdated: when they were last set, for the page. Players change them
--  in the module's page. Keys as StatWeights.lua's STATS.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

-- What every spec of a role weighs alike; each spec's own weights go on top.
local MELEE = { sta = 0.1, armor = 0.005 }
local CASTER = { spell = 1, sta = 0.05, armor = 0.005 }
local HEALER = { heal = 1, sta = 0.05, armor = 0.005 }
local TANK = { sta = 1, def = 1.5, armor = 0.06, dodge = 10, threat = 6 }

-- A spec: its role's weights, with its own on top.
local function Spec(class, key, name, role, own)
    local weights = {}
    for stat, worth in pairs(role) do weights[stat] = worth end
    for stat, worth in pairs(own or {}) do weights[stat] = worth end
    return { class = class, key = key, name = name, weights = weights }
end

ns.StatWeightDefaultsUpdated = "5 Oct 2026"

ns.StatWeightDefaults = {
    Spec("DRUID", "balance-druid", "Balance", CASTER, { arcane = 0.6, nature = 0.6, int = 0.35, spi = 0.1,
        mp5 = 0.6, shit = 13, scrit = 10, haste = 9 }),
    Spec("DRUID", "feral-dps-druid", "Feral DPS", MELEE, { str = 1, agi = 0.9, ap = 0.45, crit = 9, hit = 10,
        haste = 4, dps = 6 }),
    Spec("DRUID", "feral-tank-druid", "Feral Tank", TANK, { armor = 0.12, agi = 0.7, str = 0.35, ap = 0.15,
        def = 1.2, dodge = 12, hit = 6, crit = 2.5, dps = 2, threat = 5 }),
    Spec("DRUID", "restoration-druid", "Restoration", HEALER, { int = 0.45, spi = 0.5, mp5 = 1.8, scrit = 3,
        haste = 6 }),
    Spec("HUNTER", "beast-mastery-hunter", "Beast Mastery", MELEE, { agi = 1, rap = 0.38, ap = 0.36, int = 0.15,
        spi = 0.05, crit = 12, hit = 12, haste = 8, dps = 5.5 }),
    Spec("HUNTER", "marksmanship-hunter", "Marksmanship", MELEE, { agi = 1, rap = 0.38, ap = 0.36, int = 0.3,
        spi = 0.05, crit = 12.5, hit = 13, haste = 9, dps = 6.5 }),
    Spec("HUNTER", "survival-hunter", "Survival", MELEE, { agi = 1, rap = 0.38, ap = 0.36, str = 0.1, int = 0.2,
        crit = 11, hit = 10.5, haste = 8, dps = 6 }),
    Spec("MAGE", "arcane-mage", "Arcane", CASTER, { arcane = 1, fire = 0.15, frost = 0.15, int = 0.45, spi = 0.25,
        mp5 = 1, shit = 14, scrit = 10, haste = 11 }),
    Spec("MAGE", "fire-mage", "Fire", CASTER, { fire = 1, int = 0.35, spi = 0.15, mp5 = 0.8, shit = 14,
        scrit = 12.5, haste = 10 }),
    Spec("MAGE", "frost-mage", "Frost", CASTER, { frost = 1, int = 0.35, spi = 0.15, mp5 = 0.8, shit = 14,
        scrit = 11, haste = 11 }),
    Spec("PALADIN", "holy-paladin", "Holy", HEALER, { int = 0.6, spi = 0.1, mp5 = 2, scrit = 6, haste = 5 }),
    Spec("PALADIN", "protection-paladin", "Protection", TANK, { str = 0.45, agi = 0.4, int = 0.3, spell = 0.45,
        holy = 0.45, block = 6, hit = 3, shit = 3, mp5 = 0.6, dps = 3 }),
    Spec("PALADIN", "retribution-paladin", "Retribution", MELEE, { str = 1, agi = 0.5, ap = 0.5, int = 0.25,
        spell = 0.25, holy = 0.25, mp5 = 0.3, crit = 10.5, hit = 12, shit = 2, haste = 6, dps = 8 }),
    Spec("PRIEST", "discipline-priest", "Discipline", HEALER, { spell = 0.15, int = 0.55, spi = 0.4, mp5 = 2,
        scrit = 4, haste = 5 }),
    Spec("PRIEST", "holy-priest", "Holy", HEALER, { int = 0.5, spi = 0.55, mp5 = 2, scrit = 4, haste = 5 }),
    Spec("PRIEST", "shadow-priest", "Shadow", CASTER, { shadow = 1, int = 0.3, spi = 0.2, mp5 = 0.7, shit = 10,
        scrit = 9, haste = 8 }),
    Spec("ROGUE", "assassination-rogue", "Assassination", MELEE, { agi = 1, str = 0.53, ap = 0.53, crit = 13.5,
        hit = 13.5, haste = 9, dps = 8 }),
    Spec("ROGUE", "combat-rogue", "Combat", MELEE, { agi = 1, str = 0.6, ap = 0.6, crit = 12, hit = 16,
        haste = 10.5, dps = 9 }),
    Spec("ROGUE", "subtlety-rogue", "Subtlety", MELEE, { agi = 1, str = 0.6, ap = 0.6, crit = 11, hit = 14.5,
        haste = 9.5, dps = 10 }),
    Spec("SHAMAN", "elemental-shaman", "Elemental", CASTER, { nature = 1, fire = 0.25, frost = 0.1, int = 0.4,
        spi = 0.1, mp5 = 1, shit = 13, scrit = 11, haste = 10 }),
    Spec("SHAMAN", "enhancement-shaman", "Enhancement", MELEE, { str = 1, int = 0.55, agi = 0.5, ap = 0.5,
        spell = 0.15, nature = 0.1, mp5 = 0.3, crit = 10.5, hit = 13, shit = 1.5, haste = 8, dps = 8 }),
    Spec("SHAMAN", "restoration-shaman", "Restoration", HEALER, { int = 0.55, spi = 0.25, mp5 = 2.2, scrit = 4,
        haste = 5 }),
    Spec("WARLOCK", "affliction-warlock", "Affliction", CASTER, { shadow = 1, fire = 0.05, int = 0.25, spi = 0.3,
        sta = 0.1, mp5 = 0.4, shit = 14, scrit = 7, haste = 6 }),
    Spec("WARLOCK", "demonology-warlock", "Demonology", CASTER, { shadow = 1, fire = 0.15, int = 0.3, spi = 0.3,
        sta = 0.1, mp5 = 0.4, shit = 14, scrit = 9, haste = 9 }),
    Spec("WARLOCK", "destruction-warlock", "Destruction", CASTER, { shadow = 1, fire = 0.4, int = 0.25, spi = 0.3,
        sta = 0.1, mp5 = 0.4, shit = 14, scrit = 12, haste = 10 }),
    Spec("WARRIOR", "arms-warrior", "Arms", MELEE, { str = 1, agi = 0.55, ap = 0.5, crit = 11, hit = 12,
        haste = 7, dps = 8 }),
    Spec("WARRIOR", "fury-warrior", "Fury", MELEE, { str = 1, agi = 0.6, ap = 0.5, crit = 12, hit = 15,
        haste = 9, dps = 7.5 }),
    Spec("WARRIOR", "protection-warrior", "Protection", TANK, { str = 0.65, agi = 0.5, ap = 0.3, block = 4,
        hit = 8, crit = 3, dps = 4 }),
}
