-- BiS picker: below the spec's ranking it offers every dungeon drop for the slot that the
-- player's class can use and the ranking leaves out, near the player's level unless Show
-- All is on, highest required level first. Sources fall back to the dungeon that drops it.
local root = arg[1] or "."
local f = assert(io.open(root .. "/BiS/NaowhForever_BiS.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function Slice(a, b)
    local first = assert(source:find(a, 1, true))
    return source:sub(first, assert(source:find(b, first + #a, true)) - 1)
end

local EQUIP = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_HEAD", [3] = "INVTYPE_HEAD", [4] = "INVTYPE_HEAD",
    [5] = "INVTYPE_HEAD", [6] = "INVTYPE_CLOAK", [7] = "INVTYPE_SHIELD", [8] = "INVTYPE_RELIC",
    [9] = "INVTYPE_WEAPON", [10] = "INVTYPE_WEAPONMAINHAND", [11] = "INVTYPE_RANGEDRIGHT",
    [12] = "INVTYPE_FINGER", [13] = "INVTYPE_HEAD", [14] = "INVTYPE_2HWEAPON",
}

local LOOT = {
    [1] = { 4, 1, 20, 15, "Boss \194\183 Cloth Place" },
    [2] = { 4, 2, 30, 25, "Boss \194\183 Leather Place" },
    [3] = { 4, 3, 45, 40, "Boss \194\183 Mail Place" },
    [4] = { 4, 3, 35, 30, "Boss \194\183 Early Mail Place" },
    [5] = { 4, 4, 50, 45, "Boss \194\183 Plate Place" },
    [6] = { 4, 0, 25, 20, "Boss \194\183 Cloak Place" },
    [7] = { 4, 6, 25, 20, "Boss \194\183 Shield Place" },
    [8] = { 4, 8, 55, 50, "Boss \194\183 Idol Place" },
    [9] = { 2, 15, 25, 20, "Boss \194\183 Dagger Place" },
    [10] = { 2, 4, 25, 20, "Boss \194\183 Mace Place" },
    [11] = { 2, 19, 25, 20, "Boss \194\183 Wand Place" },
    [12] = { 4, 0, 25, 20, "Boss \194\183 Ring Place" },
    [13] = { 4, 2, 32, 25, "Boss \194\183 Leather Place" },
    [14] = { 2, 6, 40, 35, "Boss \194\183 Polearm Place" },
}

local function Fixture(class, level, sources)
    local ns = { BiSDungeonLoot = LOOT, BiSData = { sources = sources or {} } }
    local env = setmetatable({
        ns = ns,
        UnitClass = function() return class, class end,
        UnitLevel = function() return level end,
        C_Item = {
            GetItemInfoInstant = function(id)
                if EQUIP[id] then return id, "", "", EQUIP[id] end
            end,
        },
    }, { __index = _G })
    local code = Slice("-- Where an item can go, first choice first.", "\nlocal function IsTwoHand")
        .. Slice("-- Where an item comes from:", "\nlocal function SetItemLine")
        .. Slice("-- The armor type a class wears","\nlocal function NewPickRow")
        .. "\nreturn { Usable = Usable, DungeonDrops = DungeonDrops, ns = ns }"
    local chunk = assert(loadstring(code)); setfenv(chunk, env)
    return chunk()
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

local function Can(class, id) return Fixture(class, 30).Usable(class, LOOT[id]) end

Case("armor slots offer only the class's armor type", function()
    assert(Can("MAGE", 1) and not Can("MAGE", 2) and not Can("MAGE", 3))
    assert(Can("ROGUE", 2) and not Can("ROGUE", 1) and not Can("ROGUE", 3))
    assert(Can("PRIEST", 1) and Can("WARLOCK", 1) and Can("DRUID", 2))
end)

Case("hunters and shamans wear mail from 40, warriors and paladins plate", function()
    for _, class in ipairs({ "HUNTER", "SHAMAN" }) do
        assert(Can(class, 2) and Can(class, 13), class .. " leather before 40")
        assert(Can(class, 3) and not Can(class, 4), class .. " mail from 40 only")
    end
    for _, class in ipairs({ "WARRIOR", "PALADIN" }) do
        assert(Can(class, 4) and not Can(class, 3), class .. " mail before 40 only")
        assert(Can(class, 5) and not Can(class, 2), class .. " plate from 40")
    end
end)

Case("cloaks and rings are for everyone, shields and relics are not", function()
    for _, class in ipairs({ "MAGE", "ROGUE", "WARRIOR", "DRUID" }) do
        assert(Can(class, 6) and Can(class, 12), class)
    end
    assert(Can("WARRIOR", 7) and Can("PALADIN", 7) and Can("SHAMAN", 7))
    assert(not Can("MAGE", 7) and not Can("ROGUE", 7) and not Can("DRUID", 7))
    assert(Can("DRUID", 8) and not Can("SHAMAN", 8) and not Can("PALADIN", 8))
end)

Case("weapons follow the class's weapon skills", function()
    assert(Can("MAGE", 9) and Can("MAGE", 11) and not Can("MAGE", 10) and not Can("MAGE", 14))
    assert(Can("PRIEST", 10) and Can("PRIEST", 11))
    assert(Can("ROGUE", 9) and Can("ROGUE", 10) and not Can("ROGUE", 11) and not Can("ROGUE", 14))
    assert(not Can("DRUID", 14) and Can("WARRIOR", 14) and Can("HUNTER", 14) and Can("PALADIN", 14))
    assert(not Can("PALADIN", 9) and not Can("WARRIOR", 11) and not Can("HUNTER", 10))
end)

local function List(t) return table.concat(t, ",") end

Case("the list is the slot's usable drops, highest required level first", function()
    local m = Fixture("HUNTER", 40)
    assert(List(m.DungeonDrops(1, {}, false)) == "3,13,2", List(m.DungeonDrops(1, {}, false)))
    m = Fixture("WARRIOR", 40)
    assert(List(m.DungeonDrops(1, {}, false)) == "5,4")
end)

Case("items in the ranking are left out", function()
    local m = Fixture("HUNTER", 40)
    assert(List(m.DungeonDrops(1, { 13, 99 }, false)) == "3,2")
end)

Case("near keeps drops within 10 levels of yours", function()
    local m = Fixture("HUNTER", 35)
    assert(List(m.DungeonDrops(1, {}, true)) == "3,13,2")
    m = Fixture("HUNTER", 50)
    assert(List(m.DungeonDrops(1, {}, true)) == "3")
    m = Fixture("HUNTER", 10)
    assert(List(m.DungeonDrops(1, {}, true)) == "" and List(m.DungeonDrops(1, {}, false)) == "3,13,2")
end)

Case("a drop is offered in every slot it fits", function()
    local m = Fixture("ROGUE", 20)
    assert(List(m.DungeonDrops(16, {}, true)) == "9,10", "one-hand and main-hand")
    assert(List(m.DungeonDrops(17, {}, true)) == "9", "one-hand in the off hand")
    assert(List(m.DungeonDrops(11, {}, true)) == "12" and List(m.DungeonDrops(12, {}, true)) == "12")
    assert(List(m.DungeonDrops(15, {}, true)) == "6")
    m = Fixture("WARRIOR", 20)
    assert(List(m.DungeonDrops(17, {}, true)) == "7,9")
end)

Case("sources come from wowsrc first, then the dungeon", function()
    local m = Fixture("MAGE", 20, { [1] = "Quest", [99] = "Crafted" })
    assert(m.ns.BiSSource(1) == "Quest" and m.ns.BiSSource(99) == "Crafted")
    assert(m.ns.BiSSource(2) == "Boss \194\183 Leather Place" and m.ns.BiSSource(100) == nil)
end)

Case("the generated loot file is well formed", function()
    local ns = {}
    local chunk = assert(loadfile(root .. "/BiS/NaowhForever_DungeonLoot.lua"))
    setfenv(chunk, setmetatable({ _G = { NaowhForever = ns } }, { __index = _G }))
    chunk()
    local n = 0
    for id, item in pairs(ns.BiSDungeonLoot) do
        n = n + 1
        assert(type(id) == "number" and #item == 5, id)
        assert(item[1] == 2 or item[1] == 4, id)
        assert(type(item[2]) == "number" and item[3] > 0 and item[4] >= 0, id)
        assert(item[5]:find("^.+ \194\183 .+$"), id)
    end
    assert(n > 300, n)
end)

-- Ranked items that neither wowsrc nor Wowhead's Forever database gives a source for.
local UNSOURCED = {}
for _, id in ipairs({ 5821, 263435, 263436, 270039, 270046, 272996, 276727, 277213, 277219,
    277227, 277257, 279392, 279393, 281264, 281290, 281309, 281323, 281660, 281675, 281926,
    284187, 284386, 284668, 285331, 286535 }) do UNSOURCED[id] = true end

Case("every ranked item in the generated data has a source", function()
    local ns = {}
    local env = setmetatable({ _G = { NaowhForever = ns }, ns = ns }, { __index = _G })
    for _, file in ipairs({ "NaowhForever_BiSData.lua", "NaowhForever_DungeonLoot.lua" }) do
        local chunk = assert(loadfile(root .. "/BiS/" .. file))
        setfenv(chunk, env)
        chunk()
    end
    local chunk = assert(loadstring(Slice("-- Where an item comes from:", "\nlocal function SetItemLine")))
    setfenv(chunk, env)
    chunk()
    local missing = {}
    for _, spec in ipairs(ns.BiSData.specs) do
        for _, ids in pairs(spec.slots) do
            for _, id in ipairs(ids) do
                if not ns.BiSSource(id) and not UNSOURCED[id] then missing[#missing + 1] = id end
            end
        end
    end
    assert(#missing == 0, "no source: " .. table.concat(missing, ", "))
end)

print(("%d cases passed"):format(count))
