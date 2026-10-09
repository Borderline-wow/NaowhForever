-- BuffReminders.lua: the spells and items behind the Buffs & Consumables reminders (ns.BuffReminderData).
local ns = _G.NaowhForever

local D = {}
ns.BuffReminderData = D

D.WELL_FED = {
    1248406, 1248420, 1248421, 1248422, 1248688, 1249519, 1249520, 1249521, 1249523,
    19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941, 25661, 18125,
}

D.FOOD_SPELLS = {}
for _, range in ipairs({ { 1248377, 1248384 }, { 1248386, 1248401 }, { 1248687, 1248687 },
    { 1249500, 1249517 }, { 1249522, 1249522 } }) do
    for id = range[1], range[2] do D.FOOD_SPELLS[id] = true end
end
for _, id in ipairs({ 5004, 5006, 18124, 21149, 24869, 25660 }) do D.FOOD_SPELLS[id] = true end

D.FLASKS = {
    items = { 13510, 13511, 13512, 13513 },
    auras = { 17626, 17627, 17628, 17629 },
}

D.ELIXIRS = {
    { stat = "Agility", items = { 13452, 9187 }, auras = { 17538, 11334 } },
    { stat = "Strength", items = { 13453, 9206 }, auras = { 17537, 11405 } },
    { stat = "Spell damage", items = { 13454, 9155 }, auras = { 17539, 11390 } },
    { stat = "Shadow Power", items = { 9264 }, auras = { 11474 } },
    { stat = "Holy Power", items = { 21546 }, auras = { 1310077 } },
    { stat = "Fire Power", items = { 6373 }, auras = { 7844 } },
    { stat = "Frost Power", items = { 17708 }, auras = { 21920 } },
    { stat = "Intellect", items = { 13447, 9179 }, auras = { 17535, 11396 } },
    { stat = "Armor", items = { 13445, 8951 }, auras = { 11348, 11349 } },
    { stat = "Mageblood", items = { 20007 }, auras = { 24363 } },
    { stat = "Major Troll's Blood", items = { 20004 }, auras = { 24361 } },
}

D.SCROLLS = {
    { stat = "Agility", items = { 3012, 1477, 4425, 10309 }, auras = { 8115, 8116, 8117, 12174 } },
    { stat = "Intellect", items = { 955, 2290, 4419, 10308 }, auras = { 8096, 8097, 8098, 12176 }, raid = "intellect" },
    { stat = "Protection", items = { 3013, 1478, 4421, 10305 }, auras = { 8091, 8094, 8095, 12175 } },
    { stat = "Spirit", items = { 1181, 1712, 4424, 10306 }, auras = { 8112, 8113, 8114, 12177 }, raid = "spirit" },
    { stat = "Stamina", items = { 1180, 1711, 4422, 10307 }, auras = { 8099, 8100, 8101, 12178 }, raid = "stamina" },
    { stat = "Strength", items = { 954, 2289, 4426, 10310 }, auras = { 8118, 8119, 8120, 12179 } },
}

D.RAID = {
    { key = "intellect", name = "Arcane Intellect", class = "MAGE", skip = { WARRIOR = true, ROGUE = true },
        spells = { 10157, 10156, 1461, 1460, 1459, 23028 } },
    { key = "stamina", name = "Power Word: Fortitude", class = "PRIEST",
        spells = { 10938, 10937, 2791, 1245, 1244, 1243, 21564, 21562 } },
    { key = "spirit", name = "Divine Spirit", class = "PRIEST", talent = true,
        skip = { WARRIOR = true, ROGUE = true },
        spells = { 27841, 14819, 14818, 14752, 27681 } },
    { key = "wild", name = "Mark of the Wild", class = "DRUID",
        spells = { 9885, 9884, 8907, 5234, 6756, 5232, 1126, 21850, 21849 } },
    { key = "blessing", name = "Paladin Blessings", class = "PALADIN",
        spells = { 25291, 19838, 19837, 19836, 19835, 19834, 19740, 25916, 25782,
            25290, 19854, 19853, 19852, 19850, 19742, 25918, 25894,
            20217, 25898, 1038, 25895, 19979, 19978, 19977, 25890 } },
}
