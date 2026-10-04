-------------------------------------------------------------------------------
--  StatWeights/Data/Defaults.lua -- what a point of each stat is worth to each spec, by
--  default (ns.StatWeightDefaults): the class, the spec's key (the BiS List's), its name and
--  its weights. One of its main stat is 1; a percent (crit, hit, dodge) is worth a point of
--  it each, and dps a point of a weapon's damage per second (14 attack power's worth); an
--  enchant's weapon damage is worked out from it. ns.StatWeightDefaultsUpdated: when they were
--  last set, for the page. Rough on purpose: they only have to tell items and enchants
--  apart, and players change them in the module's page. Keys as StatWeights.lua's STATS.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local STRENGTH = { str = 1, agi = 0.7, sta = 0.15, ap = 0.5, crit = 14, hit = 12, haste = 10, dps = 7,
    armor = 0.01 }
local AGILITY = { agi = 1, str = 0.5, sta = 0.15, ap = 0.5, crit = 14, hit = 12, haste = 10, dps = 7,
    armor = 0.01 }
local HUNTER = { agi = 1, int = 0.2, sta = 0.15, rap = 0.5, ap = 0.1, crit = 14, hit = 12, haste = 6,
    dps = 7, armor = 0.01 }
local TANK = { sta = 1, def = 1.5, armor = 0.08, agi = 0.6, str = 0.5, dodge = 12, block = 4, threat = 6,
    hit = 6, dps = 3 }
local CASTER = { spell = 1, int = 0.4, spi = 0.1, sta = 0.15, scrit = 12, mp5 = 1, haste = 8, armor = 0.01 }
local HEALER = { heal = 1, spell = 0.1, int = 0.5, spi = 0.4, mp5 = 2, sta = 0.1, scrit = 8, haste = 6,
    armor = 0.01 }

-- A spec: its role's weights, with its own on top.
local function Spec(class, key, name, role, own)
    local weights = {}
    for stat, worth in pairs(role) do weights[stat] = worth end
    for stat, worth in pairs(own or {}) do weights[stat] = worth end
    return { class = class, key = key, name = name, weights = weights }
end

ns.StatWeightDefaultsUpdated = "3 Oct 2026"

ns.StatWeightDefaults = {
    Spec("DRUID", "balance-druid", "Balance", CASTER, { nature = 0.6, arcane = 0.6 }),
    Spec("DRUID", "feral-dps-druid", "Feral DPS", AGILITY, { str = 1, dps = 0 }),
    Spec("DRUID", "feral-tank-druid", "Feral Tank", TANK, { agi = 0.8, dps = 0 }),
    Spec("DRUID", "restoration-druid", "Restoration", HEALER, { spi = 0.5 }),
    Spec("HUNTER", "beast-mastery-hunter", "Beast Mastery", HUNTER),
    Spec("HUNTER", "marksmanship-hunter", "Marksmanship", HUNTER),
    Spec("HUNTER", "survival-hunter", "Survival", HUNTER, { agi = 1.1 }),
    Spec("MAGE", "arcane-mage", "Arcane", CASTER, { arcane = 1, fire = 0.2, frost = 0.2 }),
    Spec("MAGE", "fire-mage", "Fire", CASTER, { fire = 1 }),
    Spec("MAGE", "frost-mage", "Frost", CASTER, { frost = 1 }),
    Spec("PALADIN", "holy-paladin", "Holy", HEALER, { int = 0.7, spi = 0.1 }),
    Spec("PALADIN", "protection-paladin", "Protection", TANK, { spell = 0.3, holy = 0.3, int = 0.2 }),
    Spec("PALADIN", "retribution-paladin", "Retribution", STRENGTH, { int = 0.1, spell = 0.15 }),
    Spec("PRIEST", "discipline-priest", "Discipline", HEALER, { spell = 0.3 }),
    Spec("PRIEST", "holy-priest", "Holy", HEALER),
    Spec("PRIEST", "shadow-priest", "Shadow", CASTER, { shadow = 1, spi = 0.25 }),
    Spec("ROGUE", "assassination-rogue", "Assassination", AGILITY),
    Spec("ROGUE", "combat-rogue", "Combat", AGILITY),
    Spec("ROGUE", "subtlety-rogue", "Subtlety", AGILITY),
    Spec("SHAMAN", "elemental-shaman", "Elemental", CASTER, { nature = 0.9, fire = 0.2, frost = 0.1 }),
    Spec("SHAMAN", "enhancement-shaman", "Enhancement", STRENGTH, { agi = 0.8, int = 0.1 }),
    Spec("SHAMAN", "restoration-shaman", "Restoration", HEALER, { mp5 = 2.5, spi = 0.15 }),
    Spec("WARLOCK", "affliction-warlock", "Affliction", CASTER, { shadow = 1 }),
    Spec("WARLOCK", "demonology-warlock", "Demonology", CASTER, { shadow = 0.9, fire = 0.2 }),
    Spec("WARLOCK", "destruction-warlock", "Destruction", CASTER, { shadow = 0.8, fire = 0.5 }),
    Spec("WARRIOR", "arms-warrior", "Arms", STRENGTH),
    Spec("WARRIOR", "fury-warrior", "Fury", STRENGTH),
    Spec("WARRIOR", "protection-warrior", "Protection", TANK),
}
