local f = assert(io.open(arg[1] or "NaowhForever_Training/NaowhForever_Training.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

-- uiMapID -> its continent, its corner in world units and its size.
local MAPS = {
    [1411] = { cont = 1, x = 0, y = 0, size = 1000 },      -- Durotar
    [1454] = { cont = 1, x = 200, y = -800, size = 200 },  -- Orgrimmar
    [1413] = { cont = 1, x = -1500, y = 0, size = 2000 },  -- The Barrens
    [1453] = { cont = 0, x = 0, y = 0, size = 300 },       -- Stormwind
    [1429] = { cont = 0, x = 400, y = 0, size = 1000 },    -- Elwynn
    [2521] = { cont = 2, x = 0, y = 0, size = 500 },       -- Zephras Isle
}
local NPCS = {
    [1411] = {
        { 54.2, 42.5, "class", "Tarshaw Jaggedscar", "Warrior Trainer", "WARRIOR", "H" },
        { 52.0, 43.7, "class", "Kaplak", "Rogue Trainer", "ROGUE", "H" },
        { 50.0, 50.0, "vendor", "Duokna", "General Goods", nil, "H" },
    },
    [1454] = {
        { 80.0, 30.0, "class", "Grezz Ragefist", "Warrior Trainer", "WARRIOR", "H" },
        { 43.9, 54.6, "class", "Shenthul", "Rogue Trainer", "ROGUE", "H" },
    },
    [2521] = { { 40.0, 40.0, "class", "Akeri Duskblade", "Rogue Trainer", "ROGUE", "AH" } },
    [1413] = { { 10.0, 10.0, "class", "Far Off", "Warrior Trainer", "WARRIOR", "H" } },
    [1453] = { { 78.0, 45.0, "class", "Wu Shen", "Warrior Trainer", "WARRIOR", "A" } },
    [1429] = { { 41.0, 65.0, "class", "Lyria Du Lac", "Warrior Trainer", "WARRIOR", "A" } },
}

local function Vector(x, y) return { GetXY = function() return x, y end } end

-- The nearest trainer for a character of `class` and `faction` standing at `at` ({ map, x, y }
-- as fractions), or nowhere with a position when `at` is nil.
local function Nearest(class, faction, at)
    local env = {
        ns = { TownNPCs = NPCS, TownCapitals = { [1453] = true, [1454] = true, [2521] = true } },
        Training = {},
        UnitClass = function() return "", class end,
        UnitFactionGroup = function() return faction end,
        CreateVector2D = Vector,
        C_Map = {
            GetBestMapForUnit = function() return at and at[1] or 1411 end,
            GetPlayerMapPosition = function() return at and Vector(at[2], at[3]) end,
            GetWorldPosFromMapPos = function(map, pos)
                local m = MAPS[map]
                local x, y = pos:GetXY()
                return m.cont, Vector(m.x + x * m.size, m.y + y * m.size)
            end,
        },
    }
    setmetatable(env, { __index = _G })
    local code = "local ns, Training = ns, Training\n"
        .. Slice("local function WorldPos", "\nfunction Training.WaypointToTrainer")
        .. "\nreturn Training.NearestTrainer"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    local npc, map = chunk()()
    return npc and (npc[4] .. "@" .. map) or "none"
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("the nearest trainer of your class on your continent", function()
    local got = Nearest("WARRIOR", "Horde", { 1411, 0.5, 0.45 })
    assert(got == "Tarshaw Jaggedscar@1411", got)
    got = Nearest("WARRIOR", "Horde", { 1454, 0.5, 0.5 })
    assert(got == "Grezz Ragefist@1454", got)
    got = Nearest("ROGUE", "Horde", { 1411, 0.5, 0.45 })
    assert(got == "Kaplak@1411", got)
end)
Case("other factions' trainers and other services are left out", function()
    local got = Nearest("WARRIOR", "Alliance", { 1429, 0.4, 0.6 })
    assert(got == "Lyria Du Lac@1429", got)
    got = Nearest("PALADIN", "Alliance", { 1429, 0.4, 0.6 })
    assert(got == "none", got)
end)
Case("with none on your continent, or no position, a capital's trainer", function()
    local got = Nearest("WARRIOR", "Alliance", { 1411, 0.5, 0.5 })
    assert(got == "Wu Shen@1453", got)
    got = Nearest("WARRIOR", "Horde", nil)
    assert(got == "Grezz Ragefist@1454", got)
end)
Case("your faction's capital before one both factions share", function()
    local got = Nearest("ROGUE", "Horde", nil)
    assert(got == "Shenthul@1454", got)
    got = Nearest("ROGUE", "Alliance", nil)
    assert(got == "Akeri Duskblade@2521", got)
end)

print(("%d cases passed"):format(count))
