-------------------------------------------------------------------------------
--  NaowhForever_BuffReminderData.lua -- the spells and items behind the Buffs &
--  Consumables reminders. Forever keeps the classic IDs for flasks, elixirs, scrolls and
--  class buffs; cooked food moved to Forever-only "Nutritious Food" spells with one shared
--  Well Fed aura per stat. Taken from Wowhead's Forever data (build 1.60.1), not yet
--  confirmed in the client.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local D = {}
ns.BuffReminderData = D

D.WELL_FED = {
    1248406, 1248420, 1248421, 1248422, 1248688, 1249519, 1249520, 1249521, 1249523,
    -- The classic foods Forever did not move over.
    19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941, 25661, 18125,
}

-- The use spells of food that makes you Well Fed, to find it in the bags.
D.FOOD_SPELLS = {}
for _, range in ipairs({ { 1248377, 1248384 }, { 1248386, 1248401 }, { 1248687, 1248687 },
    { 1249500, 1249517 }, { 1249522, 1249522 } }) do
    for id = range[1], range[2] do D.FOOD_SPELLS[id] = true end
end
for _, id in ipairs({ 5004, 5006, 18124, 21149, 24869, 25660 }) do D.FOOD_SPELLS[id] = true end

-- Flask of Petrification is left out: it is a minute of stone form, not a buff to keep up.
D.FLASKS = {
    items = { 13510, 13511, 13512, 13513 },
    auras = { 17626, 17627, 17628, 17629 },
}

-- Grouped by the stat they raise, best first. In classic two elixirs for the same stat do not
-- stack, so one of each group counts; Forever's stacking is unconfirmed.
D.ELIXIRS = {
    { items = { 13452, 9187 }, auras = { 17538, 11334 } },     -- Agility
    { items = { 13453, 9206 }, auras = { 17537, 11405 } },     -- Strength
    { items = { 13454, 9155 }, auras = { 17539, 11390 } },     -- Spell damage
    { items = { 9264 }, auras = { 11474 } },                   -- Shadow Power
    { items = { 21546 }, auras = { 1310077 } },                -- Holy Power
    { items = { 6373 }, auras = { 7844 } },                    -- Fire Power
    { items = { 17708 }, auras = { 21920 } },                  -- Frost Power
    { items = { 13447, 9179 }, auras = { 17535, 11396 } },     -- Intellect
    { items = { 13445, 8951 }, auras = { 11348, 11349 } },     -- Armor
    { items = { 20007 }, auras = { 24363 } },                  -- Mageblood
    { items = { 20004 }, auras = { 24361 } },                  -- Major Troll's Blood
}

-- Ranks I to IV. `raid` names the class buff for the same stat.
D.SCROLLS = {
    { items = { 3012, 1477, 4425, 10309 }, auras = { 8115, 8116, 8117, 12174 } },     -- Agility
    { items = { 955, 2290, 4419, 10308 }, auras = { 8096, 8097, 8098, 12176 }, raid = "intellect" },
    { items = { 3013, 1478, 4421, 10305 }, auras = { 8091, 8094, 8095, 12175 } },     -- Protection
    { items = { 1181, 1712, 4424, 10306 }, auras = { 8112, 8113, 8114, 12177 }, raid = "spirit" },
    { items = { 1180, 1711, 4422, 10307 }, auras = { 8099, 8100, 8101, 12178 }, raid = "stamina" },
    { items = { 954, 2289, 4426, 10310 }, auras = { 8118, 8119, 8120, 12179 } },      -- Strength
}

-- Every rank and the group version, which is also the aura ID. `skip` is the classes the buff
-- does nothing for; `talent` buffs only count when you can cast them, since another
-- player's talents cannot be seen.
D.RAID = {
    { key = "intellect", class = "MAGE", skip = { WARRIOR = true, ROGUE = true },
        spells = { 10157, 10156, 1461, 1460, 1459, 23028 } },
    { key = "stamina", class = "PRIEST",
        spells = { 10938, 10937, 2791, 1245, 1244, 1243, 21564, 21562 } },
    { key = "spirit", class = "PRIEST", talent = true, skip = { WARRIOR = true, ROGUE = true },
        spells = { 27841, 14819, 14818, 14752, 27681 } },
    { key = "wild", class = "DRUID",
        spells = { 9885, 9884, 8907, 5234, 6756, 5232, 1126, 21850, 21849 } },
    { key = "blessing", class = "PALADIN",
        spells = { 25291, 19838, 19837, 19836, 19835, 19834, 19740, 25916, 25782,
            25290, 19854, 19853, 19852, 19850, 19742, 25918, 25894,
            20217, 25898, 1038, 25895, 19979, 19978, 19977, 25890 } },
}
