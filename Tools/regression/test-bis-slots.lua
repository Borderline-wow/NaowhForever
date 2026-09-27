-- The BiS list keeps one BiS pick and any number of secondary picks per gear slot. Old flat
-- lists and version 1 and 2 share strings must land as BiS picks in the right slots, and a
-- two-hander and an off-hand must never both be BiS picks.
local root = arg[1] or "."

-- itemID -> equip location, standing in for C_Item.GetItemInfoInstant.
local EQUIP = {
    [101] = "INVTYPE_HEAD", [102] = "INVTYPE_HEAD",
    [201] = "INVTYPE_FINGER", [202] = "INVTYPE_FINGER", [203] = "INVTYPE_FINGER",
    [301] = "INVTYPE_2HWEAPON", [302] = "INVTYPE_WEAPON", [303] = "INVTYPE_HOLDABLE",
    [401] = "INVTYPE_WAND",
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
    ns.BiSData = { specs = {}, sources = {} }

    -- A stand-in codec: what these cases care about is the payload, not how it is packed.
    local vault = {}
    local frame = { SetScript = function() end, RegisterEvent = function() end }
    local env = setmetatable({ NaowhForever = ns,
        UnitName = function() return "Tester" end,
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

local function Slots(e)
    e.ns.IsBisItem(0)   -- any read runs the one-time move into slots
    return e.account.bis["Tester-Realm"].slots
end

local function Extra(e, slot)
    e.ns.IsBisItem(0)
    return e.account.bis["Tester-Realm"].extra[slot] or {}
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("an old flat list moves into slots and names what did not fit", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Old", items = { 101, 201, 202, 203, 301, 102 } } })
    local s = Slots(e)
    assert(s[1] == 101 and s[11] == 201 and s[12] == 202 and s[16] == 301, "placed")
    assert(e.account.bis["Tester-Realm"].items == nil, "flat list dropped")
    assert(#e.printed == 1 and e.printed[1]:find("Item203") and e.printed[1]:find("Item102"), "leftovers named")
end)

Case("an old one-item-per-slot list keeps its items as BiS picks", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Mine", slots = { [1] = 101, [16] = 301 } } })
    local s = Slots(e)
    assert(s[1] == 101 and s[16] == 301 and next(e.account.bis["Tester-Realm"].extra) == nil)
    assert(e.ns.IsBisItem(101) == "bis" and e.ns.IsBisItem(301) == "bis")
end)

Case("adding fills the free ring slots, then adds a secondary pick to Ring 1", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202); e.ns.AddBisItem(203)
    local s = Slots(e)
    assert(s[11] == 201 and s[12] == 202, "BiS picks kept")
    assert(Extra(e, 11)[203] and not Extra(e, 12)[203], "secondary in Ring 1")
    assert(e.ns.IsBisItem(203) == "secondary" and e.ns.IsBisItem(201) == "bis", "lookup follows")
    assert(e.printed[#e.printed]:find("as a secondary pick"), "said so")
end)

Case("a slot has one BiS pick: picking another replaces it", function()
    local e = Fixture()
    e.ns.SetBisSlot(1, 101); e.ns.SetBisSlot(1, 102)
    assert(Slots(e)[1] == 102 and not e.ns.IsBisItem(101))
end)

Case("secondary picks toggle, and trade places with the BiS pick", function()
    local e = Fixture()
    e.ns.SetBisSlot(1, 101)
    e.ns.SetBisSecondary(1, 102, true)
    assert(Slots(e)[1] == 101 and Extra(e, 1)[102], "BiS and a secondary")
    e.ns.SetBisSecondary(1, 102, false)
    assert(e.account.bis["Tester-Realm"].extra[1] == nil and not e.ns.IsBisItem(102), "toggled off")
    e.ns.SetBisSecondary(1, 102, true)
    e.ns.SetBisSlot(1, 102)
    assert(Slots(e)[1] == 102 and not Extra(e, 1)[102], "promoted to BiS")
    e.ns.SetBisSecondary(1, 102, true)
    assert(Slots(e)[1] == nil and Extra(e, 1)[102], "demoted to secondary")
end)

Case("clearing a pick takes it out whether BiS or secondary", function()
    local e = Fixture()
    e.ns.SetBisSlot(1, 101); e.ns.SetBisSecondary(1, 102, true)
    e.ns.ClearBisPick(1, 101); e.ns.ClearBisPick(1, 102)
    assert(Slots(e)[1] == nil and e.account.bis["Tester-Realm"].extra[1] == nil)
end)

Case("a two-hander BiS pick clears the off-hand pick and the reverse, and says so", function()
    local e = Fixture()
    e.ns.SetBisSlot(17, 303); e.ns.SetBisSlot(16, 301)
    local s = Slots(e)
    assert(s[16] == 301 and s[17] == nil, "two-hander cleared off-hand")
    assert(e.printed[#e.printed]:find("Item303 came off"), "named")
    e.ns.SetBisSlot(17, 303)
    assert(s[17] == 303 and s[16] == nil, "off-hand cleared two-hander")
    assert(e.printed[#e.printed]:find("Item301 came off"), "named")
end)

Case("secondary picks are not held to the two-hander rule", function()
    local e = Fixture()
    e.ns.SetBisSlot(16, 301); e.ns.SetBisSecondary(17, 303, true)
    assert(Slots(e)[16] == 301 and Extra(e, 17)[303])
end)

Case("Alt+Shift adding never pushes out the other hand's BiS pick", function()
    local e = Fixture()
    e.ns.AddBisItem(301); e.ns.AddBisItem(303); e.ns.AddBisItem(302)
    local s = Slots(e)
    assert(s[16] == 301 and s[17] == nil, "two-hander kept")
    assert(Extra(e, 17)[303] and Extra(e, 16)[302], "off-hand and one-hander as secondary")
    e = Fixture()
    e.ns.AddBisItem(303); e.ns.AddBisItem(301)
    s = Slots(e)
    assert(s[17] == 303 and s[16] == nil and Extra(e, 16)[301], "off-hand kept, two-hander secondary")
end)

Case("a one-hander goes to the off-hand when the main hand is taken", function()
    local e = Fixture()
    e.ns.AddBisItem(302); e.ns.AddBisItem(303)
    local s = Slots(e)
    assert(s[16] == 302 and s[17] == 303, "main and off hand")
end)

Case("an old list with a two-hander and an off-hand keeps the two-hander", function()
    local e = Fixture({ ["Tester-Realm"] = { name = "Old", items = { 301, 303 } } })
    local s = Slots(e)
    assert(s[16] == 301 and s[17] == nil, "off-hand dropped")
    assert(e.printed[1] and e.printed[1]:find("Item303"), "named")
end)

Case("an import cannot list a two-hander with an off-hand, but can list one weapon twice", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Hands", slots = { [16] = 301, [17] = 303 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = e.account.bis["Tester-Realm"].slots
    assert(s[16] == 301 and s[17] == nil, "two-hander kept")
    e.vault[2] = { v = 2, name = "Daggers", slots = { [16] = 302, [17] = 302 } }
    assert(e.ns.ImportBisList("!NBIS1!S2", true))
    s = e.account.bis["Tester-Realm"].slots
    assert(s[16] == 302 and s[17] == 302, "same dagger in both hands")
end)

Case("adding a listed item again does nothing, even with the BiS toggle off", function()
    local e = Fixture()
    e.ns.QoLSettings.Get = function() return false end
    e.ns.AddBisItem(201); e.ns.AddBisItem(201); e.ns.AddBisItem(101); e.ns.AddBisItem(101)
    local s = Slots(e)
    assert(s[11] == 201 and s[12] == nil and s[1] == 101, "no second copy")
    assert(next(e.account.bis["Tester-Realm"].extra) == nil, "not added as secondary either")
    assert(#e.printed == 2, "no second line")
end)

Case("an item that cannot be equipped is refused", function()
    local e = Fixture()
    e.ns.AddBisItem(999)
    assert(next(Slots(e)) == nil and e.printed[1]:find("not an item you can equip"))
end)

Case("export and import round-trip BiS and secondary picks, name and spec", function()
    local e = Fixture()
    e.ns.AddBisItem(101); e.ns.AddBisItem(201); e.ns.SetBisSecondary(1, 102, true)
    local list = e.account.bis["Tester-Realm"]
    list.name, list.spec = "Mine", "fire-mage"
    local text = e.ns.ExportBisList()
    assert(e.vault[1].v == 3, "version 3")
    e.ns.AddBisItem(301); e.ns.SetBisSecondary(1, 102, false)
    list.name, list.spec = "Changed", "frost-mage"
    assert(e.ns.ImportBisList(text, true))
    list = e.account.bis["Tester-Realm"]
    assert(list.name == "Mine" and list.spec == "fire-mage", "name and spec")
    assert(list.slots[1] == 101 and list.slots[11] == 201 and list.slots[16] == nil, "slots")
    assert(list.extra[1][102] and e.ns.IsBisItem(102) == "secondary", "secondary picks")
    assert(e.printed[#e.printed]:find("3 items"), "counted")
end)

Case("a version 2 string imports its items as BiS picks", function()
    local e = Fixture()
    e.ns.SetBisSecondary(1, 102, true)
    e.vault[1] = { v = 2, name = "Robin's", spec = "fire-mage", slots = { [1] = 101, [11] = 201, [16] = 301 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local list = e.account.bis["Tester-Realm"]
    assert(list.name == "Robin's" and list.spec == "fire-mage", "name and spec")
    assert(list.slots[1] == 101 and list.slots[11] == 201 and list.slots[16] == 301, "slots")
    assert(next(list.extra) == nil and not e.ns.IsBisItem(102), "replaced the old secondary picks")
end)

Case("a version 2 string loses items that do not fit their slot", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Bad", slots = { [1] = 201, [2] = 999, [11] = 1.5, [99] = 101, [12] = 202 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = e.account.bis["Tester-Realm"].slots
    assert(s[1] == nil and s[2] == nil and s[11] == nil and s[99] == nil and s[12] == 202)
end)

Case("a version 3 string loses secondary picks that are not items for their slot", function()
    local e = Fixture()
    e.vault[1] = { v = 3, name = "Bad", slots = { [1] = 101 }, extra = {
        [1] = { [101] = true, [102] = true, [201] = true, [999] = true, [1.5] = true },
        [2] = "x", [99] = { [101] = true }, [11] = { [202] = "yes", [203] = true },
    } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local list = e.account.bis["Tester-Realm"]
    assert(list.slots[1] == 101 and list.extra[1][102], "good ones kept")
    assert(not list.extra[1][101] and not list.extra[1][201] and not list.extra[1][999], "misfits dropped")
    assert(list.extra[2] == nil and list.extra[99] == nil, "bad slots dropped")
    assert(list.extra[11][203] and not list.extra[11][202], "only true marks")
end)

Case("a version 1 string is placed like an old saved list", function()
    local e = Fixture()
    e.vault[1] = { v = 1, name = "Old share", items = { 101, 201, 202, 301 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = e.account.bis["Tester-Realm"].slots
    assert(s[1] == 101 and s[11] == 201 and s[12] == 202 and s[16] == 301)
end)

Case("something that is not a BiS string is refused", function()
    local e = Fixture()
    assert(e.ns.ImportBisList("hello", true) == false)
    assert(e.printed[#e.printed]:find("not a Naowh BiS list"))
end)

Case("removing takes the item out of whichever slot holds it, BiS or secondary", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202); e.ns.AddBisItem(203)
    e.ns.RemoveBisItem(202); e.ns.RemoveBisItem(203)
    local s = Slots(e)
    assert(s[11] == 201 and s[12] == nil and not e.ns.IsBisItem(202))
    assert(e.account.bis["Tester-Realm"].extra[11] == nil and not e.ns.IsBisItem(203))
end)

print(("%d cases passed"):format(count))
