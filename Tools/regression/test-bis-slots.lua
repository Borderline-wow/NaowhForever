-- The BiS list keeps one item per gear slot. Old flat lists and version 1 share strings must
-- land in the right slots, and a two-hander and an off-hand must never both be listed.
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
    local chunk = assert(loadfile(root .. "/NaowhForever_BiS.lua", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    e.ns, e.vault = ns, vault
    return e
end

local function Slots(e)
    e.ns.IsBisItem(0)   -- any read runs the one-time move into slots
    return e.account.bis["Tester-Realm"].slots
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

Case("adding fills the free ring slot, then replaces the first", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202); e.ns.AddBisItem(203)
    local s = Slots(e)
    assert(s[11] == 203 and s[12] == 202, "third ring replaced Ring 1")
    assert(e.ns.IsBisItem(203) and not e.ns.IsBisItem(201), "lookup follows")
end)

Case("a two-hander clears the off-hand and the reverse", function()
    local e = Fixture()
    e.ns.AddBisItem(303); e.ns.AddBisItem(301)
    local s = Slots(e)
    assert(s[16] == 301 and s[17] == nil, "two-hander cleared off-hand")
    e.ns.AddBisItem(303)
    assert(s[17] == 303 and s[16] == nil, "off-hand cleared two-hander")
end)

Case("a one-hander goes to the off-hand when the main hand is taken", function()
    local e = Fixture()
    e.ns.AddBisItem(302); e.ns.AddBisItem(303)
    local s = Slots(e)
    assert(s[16] == 302 and s[17] == 303, "main and off hand")
end)

Case("a one-hander replaces a listed two-hander instead of pushing it out", function()
    local e = Fixture()
    e.ns.AddBisItem(301); e.ns.AddBisItem(302)
    local s = Slots(e)
    assert(s[16] == 302 and s[17] == nil, "one-hander took the main hand")
    assert(e.printed[#e.printed]:find("Item302 replaces Item301"), "said so")
end)

Case("an off-hand over a two-hander says the two-hander came off", function()
    local e = Fixture()
    e.ns.AddBisItem(301); e.ns.AddBisItem(303)
    local s = Slots(e)
    assert(s[16] == nil and s[17] == 303)
    assert(e.printed[#e.printed]:find("Item301 came off"), "named")
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
    assert(#e.printed == 2, "no 'replaces itself' line")
end)

Case("an item that cannot be equipped is refused", function()
    local e = Fixture()
    e.ns.AddBisItem(999)
    assert(next(Slots(e)) == nil and e.printed[1]:find("not an item you can equip"))
end)

Case("export and import round-trip slots, name and spec", function()
    local e = Fixture()
    e.ns.AddBisItem(101); e.ns.AddBisItem(201)
    local list = e.account.bis["Tester-Realm"]
    list.name, list.spec = "Mine", "fire-mage"
    local text = e.ns.ExportBisList()
    e.ns.AddBisItem(301); list.name, list.spec = "Changed", "frost-mage"
    assert(e.ns.ImportBisList(text, true))
    list = e.account.bis["Tester-Realm"]
    assert(list.name == "Mine" and list.spec == "fire-mage", "name and spec")
    assert(list.slots[1] == 101 and list.slots[11] == 201 and list.slots[16] == nil, "slots")
end)

Case("a version 2 string imports into its slots", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Robin's", spec = "fire-mage", slots = { [1] = 101, [11] = 201, [16] = 301 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local list = e.account.bis["Tester-Realm"]
    assert(list.name == "Robin's" and list.spec == "fire-mage", "name and spec")
    assert(list.slots[1] == 101 and list.slots[11] == 201 and list.slots[16] == 301, "slots")
end)

Case("a version 2 string loses items that do not fit their slot", function()
    local e = Fixture()
    e.vault[1] = { v = 2, name = "Bad", slots = { [1] = 201, [2] = 999, [11] = 1.5, [99] = 101, [12] = 202 } }
    assert(e.ns.ImportBisList("!NBIS1!S1", true))
    local s = e.account.bis["Tester-Realm"].slots
    assert(s[1] == nil and s[2] == nil and s[11] == nil and s[99] == nil and s[12] == 202)
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

Case("removing takes the item out of whichever slot holds it", function()
    local e = Fixture()
    e.ns.AddBisItem(201); e.ns.AddBisItem(202)
    e.ns.RemoveBisItem(202)
    local s = Slots(e)
    assert(s[11] == 201 and s[12] == nil and not e.ns.IsBisItem(202))
end)

print(("%d cases passed"):format(count))
