-- The BiS list keeps a ranked list of picks per gear slot, #1 being the BiS. Old flat lists,
-- the unordered secondary picks of the 0.5.12 test builds and version 1 to 3 share strings
-- must land in the right slots and order, and a two-hander and an off-hand must never both
-- be #1.
local root = arg[1] or "."

-- itemID -> equip location, standing in for C_Item.GetItemInfoInstant.
local EQUIP = {
    [101] = "INVTYPE_HEAD", [102] = "INVTYPE_HEAD", [103] = "INVTYPE_HEAD", [104] = "INVTYPE_HEAD",
    [105] = "INVTYPE_HEAD",
    [201] = "INVTYPE_FINGER", [202] = "INVTYPE_FINGER", [203] = "INVTYPE_FINGER",
    [301] = "INVTYPE_2HWEAPON", [302] = "INVTYPE_WEAPON", [303] = "INVTYPE_HOLDABLE",
    [304] = "INVTYPE_SHIELD",
    [401] = "INVTYPE_WAND",
}

local SPECS = {
    { class = "MAGE", key = "fire-mage", name = "Fire Mage", slots = { [1] = { 103, 102, 104 }, [11] = { 202, 201 } } },
    { class = "MAGE", key = "frost-mage", name = "Frost Mage", slots = { [1] = { 104, 103, 102 } } },
}

local function Fixture(saved)
    local e = { account = { bis = saved }, printed = {} }
    local ns = {}
    ns.Print = function(m) e.printed[#e.printed + 1] = m end
    ns.AccountSettings = function() return e.account end
    ns.QoLSettings = { Get = function() return true end }
    ns.THEME = { accent = {}, muted = {}, panel = {}, line = {} }
    ns.UI = { RefreshPage = function() end }
    ns.Confirm = function(_, yes) yes() end
    ns.BiSData = { specs = SPECS, sources = {} }

    -- A stand-in codec: what these cases care about is the payload, not how it is packed.
    local vault = {}
    local frame = { SetScript = function() end, RegisterEvent = function() end }
    local env = setmetatable({ NaowhForever = ns,
        UnitName = function() return "Tester" end,
        UnitClass = function() return "Mage", "MAGE" end,
        GetRealmName = function() return "Realm" end,
        C_Item = {
            GetItemInfoInstant = function(id)
                if EQUIP[id] then return id, "", "", EQUIP[id] end
            end,
            GetItemNameByID = function(id) return "Item" .. id end,
        },
        TooltipDataProcessor = { AddTooltipPostCall = function() end },
        Enum = { TooltipDataType = { Item = 0 } },
        hooksecurefunc = function() end,
        CreateFrame = function() return frame end,
        LibStub = function(name)
            if name == "LibSerialize" then
                return {
                    Serialize = function(_, v)
                        local function Copy(t)
                            if type(t) ~= "table" then return t end
                            local out = {}
                            for k, x in pairs(t) do out[k] = Copy(x) end
                            return out
                        end
                        vault[#vault + 1] = Copy(v); return "S" .. #vault
                    end,
                    Deserialize = function(_, str)
                        local k = tonumber(tostring(str):match("^S(%d+)$"))
                        if not k or not vault[k] then return false end
                        return true, vault[k]
                    end,
                }
            end
            local same = function(_, v) return v end
            return { CompressDeflate = same, DecompressDeflate = same,
                EncodeForPrint = same, DecodeForPrint = same }
        end,
    }, { __index = _G })
    env._G = env
    local chunk = assert(loadfile(root .. "/BiS/NaowhForever_BiS.lua", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    e.ns, e.vault = ns, vault
    return e
end

local function Saved(e)
    e.ns.IsBisItem(0)   -- any read runs the one-time moves
    return e.account.bis["Tester-Realm"]
end

-- A slot's picks in order, #1 first.
local function Picks(e, slot)
    local list = Saved(e)
    local out = { list.slots[slot] }
    for _, id in ipairs(list.extra[slot] or {}) do out[#out + 1] = id end
    return table.concat(out, ",")
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("an old flat list moves into slots and names what did not fit", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Old", items = { 101, 201, 202, 203, 301, 102 } } })
    local s = Saved(e).slots
    assert(s[1] == 101 and s[11] == 201 and s[12] == 202 and s[16] == 301, "placed")
    assert(Saved(e).items == nil, "flat list dropped")
    assert(#e.printed == 1 and e.printed[1]:find("Item203") and e.printed[1]:find("Item102"), "leftovers named")
end)

Case("an old one-item-per-slot list keeps its items as BiS picks", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Mine", slots = { [1] = 101, [16] = 301 } } })
    assert(Picks(e, 1) == "101" and Picks(e, 16) == "301" and next(Saved(e).extra) == nil)
    assert(e.ns.IsBisItem(101) == 1 and e.ns.IsBisItem(301) == 1 and #e.printed == 0)
end)

Case("unordered secondary picks become ranked picks behind the BiS, once", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Mine", spec = "fire-mage",
        slots = { [1] = 101, [16] = 301 },
        extra = { [1] = { [104] = true, [105] = true, [102] = true, [103] = true },
            [11] = { [201] = true, [202] = true }, [17] = { [303] = true } } } })
    assert(Picks(e, 1) == "101,103,102,104,105", "ranked order, unranked last")
    assert(Picks(e, 11) == "202,201", "first ranked secondary becomes #1")
    assert(Picks(e, 16) == "301" and Picks(e, 17) == "", "off-hand cannot be #1 beside a two-hander")
    assert(#e.printed == 1 and e.printed[1]:find("Item303"), "named")
    assert(e.ns.IsBisItem(101) == 1 and e.ns.IsBisItem(103) == 2 and e.ns.IsBisItem(105) == 5)
    Saved(e).extra[1][1] = 104
    e.ns.RemoveBisItem(999)   -- any change reads the list again
    assert(Picks(e, 1) == "101,104,102,104,105" and #e.printed == 1, "arrays are left alone")
end)

Case("picks append in order, #1 first, and a pick is listed once per slot", function()
    local e = Fixture()
    e.ns.AddBisPick(1, 101); e.ns.AddBisPick(1, 102); e.ns.AddBisPick(1, 103); e.ns.AddBisPick(1, 102)
    assert(Picks(e, 1) == "101,102,103")
    assert(e.ns.IsBisItem(101) == 1 and e.ns.IsBisItem(102) == 2 and e.ns.IsBisItem(103) == 3)
end)

Case("an item in two slots reports its best pick number", function()
    local e = Fixture()
    e.ns.AddBisPick(11, 201); e.ns.AddBisPick(12, 202); e.ns.AddBisPick(12, 201)
    assert(e.ns.IsBisItem(201) == 1 and e.ns.IsBisItem(202) == 1)
end)

Case("picks move up and down, and stop at the ends", function()
    local e = Fixture()
    e.ns.AddBisPick(1, 101); e.ns.AddBisPick(1, 102); e.ns.AddBisPick(1, 103)
    e.ns.MoveBisPick(1, 103, -1)
    assert(Picks(e, 1) == "101,103,102")
    e.ns.MoveBisPick(1, 103, -1)
    assert(Picks(e, 1) == "103,101,102" and e.ns.IsBisItem(103) == 1, "new BiS")
    e.ns.MoveBisPick(1, 103, -1); e.ns.MoveBisPick(1, 102, 1)
    assert(Picks(e, 1) == "103,101,102", "ends")
    e.ns.MoveBisPick(1, 103, 1)
    assert(Picks(e, 1) == "101,103,102")
end)

Case("removing a pick closes the gap, and removing #1 moves #2 up", function()
    local e = Fixture()
    e.ns.AddBisPick(1, 101); e.ns.AddBisPick(1, 102); e.ns.AddBisPick(1, 103)
    e.ns.RemoveBisPick(1, 102)
    assert(Picks(e, 1) == "101,103")
    e.ns.RemoveBisPick(1, 101)
    assert(Picks(e, 1) == "103" and Saved(e).extra[1] == nil)
    e.ns.RemoveBisPick(1, 103)
    assert(Saved(e).slots[1] == nil and Saved(e).extra[1] == nil and not e.ns.IsBisItem(103))
end)

Case("a two-hander #1 clears the off-hand picks and the reverse, and says so", function()
    local e = Fixture()
    e.ns.AddBisPick(17, 303); e.ns.AddBisPick(17, 304); e.ns.AddBisPick(16, 301)
    assert(Picks(e, 16) == "301" and Picks(e, 17) == "", "two-hander cleared the off-hand")
    assert(e.printed[#e.printed]:find("Item303, Item304 came off"), "named")
    e.ns.AddBisPick(17, 303)
    assert(Picks(e, 17) == "303" and Picks(e, 16) == "", "off-hand cleared the two-hander")
    assert(e.printed[#e.printed]:find("Item301 came off"), "named")
end)

Case("the rule is on #1 only: a two-hander further down sits beside an off-hand", function()
    local e = Fixture()
    e.ns.AddBisPick(16, 302); e.ns.AddBisPick(16, 301); e.ns.AddBisPick(17, 303)
    assert(Picks(e, 16) == "302,301" and Picks(e, 17) == "303" and #e.printed == 0)
    e.ns.MoveBisPick(16, 301, -1)
    assert(Picks(e, 16) == "301,302" and Picks(e, 17) == "", "moved up to #1")
    e.ns.AddBisPick(17, 303)
    assert(Picks(e, 16) == "302" and Picks(e, 17) == "303", "off-hand #1 takes the two-hander out")
    e.ns.AddBisPick(16, 301); e.ns.RemoveBisPick(16, 302)
    assert(Picks(e, 16) == "301" and Picks(e, 17) == "", "promoted by a removal")
end)

Case("Alt+Shift fills the free ring slots, then appends to Ring 1", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202); e.ns.AddBisItem(203)
    assert(Picks(e, 11) == "201,203" and Picks(e, 12) == "202")
    assert(e.ns.IsBisItem(203) == 2, "lookup follows")
    assert(e.printed[#e.printed]:find("as #2"), "said so")
end)

Case("Alt+Shift adding never pushes out the other hand's BiS pick", function()
    local e = Fixture()
    e.ns.AddBisItem(301); e.ns.AddBisItem(303); e.ns.AddBisItem(302)
    assert(Picks(e, 16) == "301,302" and Picks(e, 17) == "", "two-hander kept, one-hander appended")
    assert(not e.ns.IsBisItem(303) and e.printed[2]:find("Item303 was not added"), "off-hand refused")
    e = Fixture()
    e.ns.AddBisItem(303); e.ns.AddBisItem(301)
    assert(Picks(e, 17) == "303" and Picks(e, 16) == "", "off-hand kept")
    assert(e.printed[2]:find("Item301 was not added"), "two-hander refused")
end)

Case("a one-hander goes to the off-hand when the main hand is taken", function()
    local e = Fixture()
    e.ns.AddBisItem(302); e.ns.AddBisItem(303)
    assert(Picks(e, 16) == "302" and Picks(e, 17) == "303")
end)

Case("an old list with a two-hander and an off-hand keeps the two-hander", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Old", items = { 301, 303 } } })
    assert(Picks(e, 16) == "301" and Picks(e, 17) == "", "off-hand dropped")
    assert(e.printed[1] and e.printed[1]:find("Item303"), "named")
end)

Case("an import cannot list a two-hander with an off-hand, but can list one weapon twice", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Hands", slots = { [16] = 301, [17] = 303 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    assert(Picks(e, 16) == "301" and Picks(e, 17) == "", "two-hander kept")
    e.vault[2] = { v = 2, name = "Daggers", slots = { [16] = 302, [17] = 302 } }
    assert(e.ns.ImportBisList("!NBIS1!S2", true))
    assert(Picks(e, 16) == "302" and Picks(e, 17) == "302", "same dagger in both hands")
end)

Case("adding a listed item again does nothing, even with the BiS toggle off", function()
    local e = Fixture()
    e.ns.QoLSettings.Get = function() return false end
    e.ns.AddBisItem(201); e.ns.AddBisItem(201); e.ns.AddBisItem(101); e.ns.AddBisItem(101)
    assert(Picks(e, 11) == "201" and Picks(e, 12) == "" and Picks(e, 1) == "101", "no second copy")
    assert(#e.printed == 2, "no second line")
end)

Case("an item that cannot be equipped is refused", function()
    local e = Fixture()
    e.ns.AddBisItem(999)
    assert(next(Saved(e).slots) == nil and e.printed[1]:find("not an item you can equip"))
end)

Case("export and import round-trip the ordered picks, name and spec", function()
    local e = Fixture()
    e.ns.AddBisPick(1, 104); e.ns.AddBisPick(1, 101); e.ns.AddBisPick(1, 103); e.ns.AddBisItem(201)
    local list = Saved(e)
    list.name, list.spec = "Mine", "fire-mage"
    local text = e.ns.ExportBisList()
    assert(e.vault[1].v == 4, "version 4")
    e.ns.AddBisItem(301); e.ns.RemoveBisPick(1, 101)
    list.name, list.spec = "Changed", "frost-mage"
    assert(e.ns.ImportBisList(text, true))
    list = Saved(e)
    assert(list.name == "Mine" and list.spec == "fire-mage", "name and spec")
    assert(Picks(e, 1) == "104,101,103" and Picks(e, 11) == "201" and Picks(e, 16) == "", "picks")
    assert(e.ns.IsBisItem(103) == 3)
    assert(e.printed[#e.printed]:find("4 items"), "counted")
end)

Case("a version 2 string imports its items as BiS picks", function()
    local e = Fixture()
    e.ns.AddBisPick(1, 101); e.ns.AddBisPick(1, 102)
    e.vault[1] = { v = 2, name = "Robin's", spec = "fire-mage", slots = { [1] = 101, [11] = 201, [16] = 301 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local list = Saved(e)
    assert(list.name == "Robin's" and list.spec == "fire-mage", "name and spec")
    assert(Picks(e, 1) == "101" and Picks(e, 11) == "201" and Picks(e, 16) == "301", "slots")
    assert(next(list.extra) == nil and not e.ns.IsBisItem(102), "replaced the old picks")
end)

Case("a version 2 string loses items that do not fit their slot", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Bad", slots = { [1] = 201, [2] = 999, [11] = 1.5, [99] = 101, [12] = 202 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = Saved(e).slots
    assert(s[1] == nil and s[2] == nil and s[11] == nil and s[99] == nil and s[12] == 202)
end)

Case("a version 3 string ranks its secondary picks by the string's spec and drops misfits", function()
    local e = Fixture()
    e.vault[1] = { v = 3, name = "Old", spec = "frost-mage", slots = { [1] = 101 }, extra = {
        [1] = { [101] = true, [102] = true, [103] = true, [104] = true, [201] = true, [999] = true, [1.5] = true },
        [2] = "x", [99] = { [101] = true }, [11] = { [202] = "yes", [203] = true },
    } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local list = Saved(e)
    assert(Picks(e, 1) == "101,104,103,102", "frost ranking, BiS not repeated")
    assert(list.extra[2] == nil and list.extra[99] == nil, "bad slots dropped")
    assert(Picks(e, 11) == "203", "only true marks, moved up to #1")
end)

Case("a version 4 string drops misfits and repeats and fills a missing #1", function()
    local e = Fixture()
    e.vault[1] = { v = 4, name = "New", slots = { [1] = 101 }, extra = {
        [1] = { 103, 101, 201, 103, 1.5, 102 }, [12] = { 202, 201 }, [17] = { 303 }, [3] = "x",
    } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    assert(Picks(e, 1) == "101,103,102" and Picks(e, 12) == "202,201" and Picks(e, 17) == "303")
    assert(Saved(e).extra[3] == nil)
end)

Case("a version 1 string is placed like an old saved list", function()
    local e = Fixture()
    e.vault[1] = { v = 1, name = "Old share", items = { 101, 201, 202, 301 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = Saved(e).slots
    assert(s[1] == 101 and s[11] == 201 and s[12] == 202 and s[16] == 301)
end)

Case("something that is not a BiS string is refused", function()
    local e = Fixture()
    assert(e.ns.ImportBisList("hello", true) == false)
    assert(e.printed[#e.printed]:find("not a Naowh BiS list"))
end)

Case("removing takes the item out of every slot that holds it", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202); e.ns.AddBisItem(203); e.ns.AddBisPick(12, 203)
    e.ns.RemoveBisItem(201); e.ns.RemoveBisItem(203)
    assert(Picks(e, 11) == "" and Picks(e, 12) == "202" and not e.ns.IsBisItem(203))
end)

print(("%d cases passed"):format(count))
