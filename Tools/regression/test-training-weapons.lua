-- The weapon skills each class learns (NaowhForever_Training/Data/TrainingWeapons.lua): shaped like the
-- other training data, and every master it names stands in Shared/Game/Towns.lua.
local Load = dofile("Tools/regression/load_files.lua")

local ns = {}
local env = setmetatable({ ns = ns, _G = nil }, { __index = _G })
env._G = env
env.NaowhForever = ns
Load({ "Shared/Game/Towns.lua", "NaowhForever_Training/Data/TrainingWeapons.lua" }, env)

local masters = {}
for _, npcs in pairs(ns.TownNPCs) do
    for _, npc in ipairs(npcs) do
        if npc[3] == "profession" and npc[5] == "Weapon Master" then masters[npc[4]] = true end
    end
end

local classes, rows = 0, 0
for classID, list in pairs(ns.TrainingWeapons) do
    classes = classes + 1
    local seen, last = {}, 0
    for _, entry in ipairs(list) do
        rows = rows + 1
        local level, spell, cost = entry[1], entry[2], entry[3]
        assert(level >= 1 and level <= 60, "class " .. classID .. " spell " .. spell .. " level " .. level)
        assert(cost == 0, "class " .. classID .. " spell " .. spell .. " has a price Wowhead does not give")
        assert(not seen[spell], "class " .. classID .. " lists " .. spell .. " twice")
        assert(level >= last, "class " .. classID .. " is not in level order")
        seen[spell], last = true, level
        for _, name in ipairs(entry.masters or {}) do
            assert(masters[name], name .. " is not a Weapon Master in Towns.lua")
        end
    end
end
assert(classes == 9 and rows > 50, classes .. " classes, " .. rows .. " rows")
print(("weapon skills: %d classes, %d rows"):format(classes, rows))
