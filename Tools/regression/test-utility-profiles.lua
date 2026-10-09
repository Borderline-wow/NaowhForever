-- Merging a contributor's profile into one of yours. Several people maintain parts of
-- Robin's setup now, so the question is what a merge takes and, more importantly, what it
-- leaves alone.
local root = arg[1] or "."

local function Fixture()
    local e = { profiles = { Naowh = {}, Other = {} }, refreshed = 0 }
    local ns = {}
    ns.ListProfiles = function()
        local out = {}
        for name in pairs(e.profiles) do out[#out + 1] = name end
        table.sort(out)
        return out
    end
    ns.ProfileExists = function(name) return type(e.profiles[name]) == "table" end
    ns.EnsureProfile = function(name)
        if type(e.profiles[name]) ~= "table" then e.profiles[name] = {} end
        return e.profiles[name]
    end
    ns.RefreshRuntime = function() e.refreshed = e.refreshed + 1 end
    ns.ActiveProfileName = function() return "Naowh" end
    ns.Print = function(msg) e.printed = msg end
    -- ApplySettings only takes a key whose type matches the default, so the fixture has
    -- to answer for the one setting these cases carry.
    ns.SettingDefault = function(k) return k == "leadTime" and 2 or nil end
    ns.Integrations = { ValidRule = function() return true end }
    ns.UI = { Widgets = {} }
    ns.THEME = { accent = {}, muted = {}, fg = {}, panel = {}, bg = {}, line = {} }
    ns.Color = function(token, text) return "|cff" .. ({ accent = "0091ed", muted = "9a9ea6", fg = "f0f1f3", accentSoft = "4db5f5" })[token] .. (text and (text .. "|r") or "") end
    ns.PlainText = dofile(root .. "/Tools/regression/plain_text.lua")(root)

    local env = setmetatable({ NaowhForever = ns,
        CreateFrame = function() return { SetScript = function() end } end,
    }, { __index = _G })
    env._G = env
    local chunk = assert(loadfile(root .. "/Core/NaowhForever_Packs.lua"))
    setfenv(chunk, env); chunk()
    ns.Shared = { Decode = dofile("Tools/regression/load_decode.lua")(env, true) }
    e.ns, e.env = ns, env
    return e
end

-- One spec's worth of lists, plus a boss with one reminder on it. Trash rules and raid
-- reminders too, since those are the two that behave differently under a spec filter.
local function Data(specKey, uid)
    return {
        presets = { [specKey] = { p1 = { list = { 100 } } } },
        activePreset = { [specKey] = "p1" },
        abilityBindings = { [specKey] = { ["2001"] = { [10] = { enabled = true } } } },
        bossLists = { [specKey .. ":123"] = { 7 } },
        integrationRules = { [specKey] = { i1 = { name = "Theirs" } } },
        customReminders = { ["2001"] = {
            [uid] = { name = "Theirs", specID = tonumber(specKey), trigger = {} } } },
        raidReminders = { ["2001"] = { [uid] = { name = "Theirs raid", trigger = {} } } },
        callouts = { ["999"] = "Theirs" },
    }
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end


Case("consumable and class macro definitions survive export, decode and merge", function()
    local e = Fixture()
    local mine = e.ns.EnsureProfile("Naowh")
    mine.utilityReminders = {
        consumables = { { category = "food", itemID = 123, auras = { 456, 789 } } },
        classMacros = { PALADIN = { { name = "Example", body = "/say example", icon = 134400, note = "Says hi" } } },
    }
    local serialized
    local serializer = { Serialize = function(_, payload) serialized = payload; return "payload" end,
        Deserialize = function() return true, serialized end }
    local codec = { CompressDeflate = function(_, v) return v end, EncodeForPrint = function(_, v) return v end,
        DecodeForPrint = function(_, v) return v end, DecompressDeflate = function(_, v) return v end }
    e.env.LibStub = function(name) return name == "LibSerialize" and serializer or codec end
    e.ns.DB = function() return mine end
    local text, err = e.ns.ExportPack("Utilities", "Robin")
    assert(text, err)
    local payload, description = e.ns.DecodePack(text)
    assert(payload, description)
    assert(description:find("consumable and class macro groups", 1, true))
    assert(e.ns.MergeProfileFromPack(payload, nil, "Other"))
    local imported = e.profiles.Other.utilityReminders
    assert(imported.consumables[1].auras[2] == 789)
    assert(imported.classMacros.PALADIN[1].body == "/say example")
    assert(imported.classMacros.PALADIN[1].note == "Says hi")
    imported.consumables[1].itemID = 999
    assert(mine.utilityReminders.consumables[1].itemID == 123)
end)
Case("invalid definitions reject the entire import", function()
    local e = Fixture()
    for _, entry in ipairs({
        { category = "invalid", itemID = 123, auras = { 456 } },
        { category = "food", itemID = -1, auras = { 456 } },
        { category = "food", itemID = 123, auras = {} },
        { category = "food", itemID = 123, auras = { "bad" } },
    }) do
        local ok = e.ns.MergeProfileFromPack({ data = { utilityReminders = { consumables = { entry } } } }, nil, "Other")
        assert(not ok and e.profiles.Other.utilityReminders == nil)
    end
    assert(not e.ns.MergeProfileFromPack({ data = { utilityReminders = { classMacros = {
        PALADIN = { { name = "Bad", body = string.rep("x", 256) } },
    } } } }, nil, "Other"))
    assert(not e.ns.MergeProfileFromPack({ data = { utilityReminders = { classMacros = {
        PALADIN = { { name = "Bad", body = "/say x", note = 5 } },
    } } } }, nil, "Other"))
end)
Case("an entry may leave its buff IDs out", function()
    local e = Fixture()
    local entry = { category = "battle", itemID = 13454 }
    assert(e.ns.MergeProfileFromPack({ data = { utilityReminders = { consumables = { entry } } } }, nil, "Other"))
    assert(e.profiles.Other.utilityReminders.consumables[1].itemID == 13454)
end)
Case("a spec-only merge preserves utility definitions unless extras are selected", function()
    local e = Fixture()
    local data = Data("250", "u1")
    data.utilityReminders = { consumables = { { category = "food", itemID = 123, auras = { 456 } } } }
    assert(e.ns.MergeProfileFromPack({ data = data }, nil, "Other", { specs = { ["250"] = true } }))
    assert(e.profiles.Other.utilityReminders == nil)
    assert(e.ns.MergeProfileFromPack({ data = data }, nil, "Other", { specs = { ["250"] = true }, extras = true }))
    assert(e.profiles.Other.utilityReminders.consumables[1].itemID == 123)
end)
print(count .. " utility profile regressions passed")
