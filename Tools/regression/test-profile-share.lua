-- Run with Lua 5.1 from the repository root: the Profiles page's whole-profile Export and
-- Import, through the real LibSerialize and LibDeflate. What a string carries, what a
-- profile from someone's pack keeps back, and what Import lands, part by part, without
-- touching an existing profile.
strmatch = string.match   -- LibStub's, as the game has it
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/LibSerialize/LibSerialize.lua")

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

local DEFAULTS = {
    qol = { enabled = true, fastLoot = false, bisSlots = {} },
    macros = { enabled = true, classMacros = {}, foodBar = false },
    topBar = { enabled = true, mouseoverAlpha = 0 },
}

-- A fresh account: one profile, Default, with something in every part.
local function World()
    local w = { switched = nil, refreshed = 0 }
    w.db = {
        profiles = {
            Default = {
                qol = { fastLoot = true, bisSlots = { [1] = 6948 }, lootFeedPos = { "TOP", 10, -20 } },
                topBar = { mouseoverAlpha = 0.4 },
                macros = { foodBar = true },
                tankReminder = { leadTime = 5, presets = { { name = "Mine" } },
                    utilityReminders = { classMacros = { PALADIN = { { name = "BoP", body = "/cast BoP" } } },
                        other = 1 } },
                notAModule = { secret = "x" },
            },
        },
        account = {
            themePreset = "slate", uiFont = "Naowh", windowScale = 1.1,
            bisLists = { PALADIN = { lists = { { id = 1, name = "Prot", slots = { [1] = 100 } } }, nextID = 2 } },
            barSets = { PALADIN = { Raid = {} } },
        },
    }
    w.active = "Default"
    local ns = {
        UI = {}, CODE_BUILD = "test",
        SettingsRoot = function() return w.db.profiles[w.active] end,
        AccountSettings = function() return w.db.account end,
        ModuleDefaults = function(key) return DEFAULTS[key] end,
        ActiveProfileName = function() return w.active end,
        ProfileExists = function(name) return w.db.profiles[name] ~= nil end,
        ProfileRoot = function(name)
            w.db.profiles[name] = w.db.profiles[name] or { tankReminder = {} }
            return w.db.profiles[name]
        end,
        SwitchProfile = function(name) w.switched, w.active = name, name end,
        RefreshRuntime = function() w.refreshed = w.refreshed + 1 end,
    }
    w.ns = ns
    local env = setmetatable({ _G = { NaowhForever = ns }, UnitName = function() return "Glyadin" end,
        date = os.date }, { __index = _G })
    local chunk = assert(loadfile("Core/NaowhForever_ProfileShare.lua"))
    setfenv(chunk, env)
    chunk()
    return w
end

local ALL = { settings = true, macros = true, smartReminders = true, bisLists = true, look = true }

Case("export: one string with every part, personal data left home", function()
    local w = World()
    local text = assert(w.ns.ExportProfile())
    assert(text:sub(1, 11) == "NFPROFILE1:", text:sub(1, 20))
    local payload = assert(w.ns.DecodeProfile(text))
    local parts = payload.parts
    assert(payload.name == "Default" and payload.author == "Glyadin")
    assert(parts.settings.qol.fastLoot == true and parts.settings.qol.bisSlots[1] == 6948)
    assert(parts.settings.qol.lootFeedPos[2] == 10, "positions travel")
    assert(parts.settings.notAModule == nil and parts.settings.macros == nil and parts.settings.tankReminder == nil)
    assert(parts.macros.module.foodBar == true and parts.macros.classMacros.PALADIN[1].name == "BoP")
    assert(parts.smartReminders.leadTime == 5 and parts.smartReminders.utilityReminders.other == 1)
    assert(parts.smartReminders.utilityReminders.classMacros == nil, "class macros only as Macros")
    assert(parts.bisLists.PALADIN[1].name == "Prot")
    assert(parts.look.themePreset == "slate" and parts.look.windowScale == 1.1)
    assert(parts.barSets == nil and parts.look.barSets == nil, "no personal data")
end)

Case("the string survives being wrapped and pasted with spaces", function()
    local w = World()
    local text = assert(w.ns.ExportProfile())
    local wrapped = text:sub(1, 30) .. "\n  " .. text:sub(31, 70) .. "\r\n" .. text:sub(71)
    assert(w.ns.DecodeProfile(wrapped))
end)

Case("a profile from someone's pack keeps their Smart Reminders and class macros back", function()
    local w = World()
    w.db.profiles.Default.tankReminder.importedPack = { name = "Naowh's Pack", author = "Naowh", licensed = true }
    local text, note = w.ns.ExportProfile()
    local parts = assert(w.ns.DecodeProfile(text)).parts
    assert(parts.smartReminders == nil and parts.macros.classMacros == nil)
    assert(parts.macros.module.foodBar == true and parts.settings.qol, "the rest still goes")
    assert(note and note:find("Naowh's Pack", 1, true), tostring(note))
end)

Case("the parts a string holds, for the import's ticks", function()
    local w = World()
    local list = w.ns.ProfileStringParts(assert(w.ns.DecodeProfile((w.ns.ExportProfile()))))
    local keys = {}
    for _, part in ipairs(list) do keys[#keys + 1] = part.key .. (part.detail and (":" .. part.detail) or "") end
    assert(table.concat(keys, ",") == "settings:2 modules,macros:1 class macros,smartReminders,bisLists:1 lists,look",
        table.concat(keys, ","))
end)

Case("import: a new profile with every part, switched to, the old one untouched", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    local before = w.db.profiles.Default.qol.fastLoot
    w.db.account.themePreset = "midnight"
    local name, added = w.ns.ImportProfile(payload, ALL, "Default")
    assert(name == "Default 2" and w.switched == "Default 2" and w.refreshed == 1, name)
    local p = w.db.profiles["Default 2"]
    assert(p.qol.fastLoot == true and p.topBar.mouseoverAlpha == 0.4 and p.macros.foodBar == true)
    assert(p.tankReminder.leadTime == 5 and p.tankReminder.utilityReminders.classMacros.PALADIN[1].name == "BoP")
    assert(w.db.account.themePreset == "slate", "the look comes in")
    assert(added == 0, "the same BiS list is not added twice")
    assert(w.db.profiles.Default.qol.fastLoot == before)
end)

Case("import: unticked parts stay out", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    w.db.account.themePreset = "midnight"
    w.ns.ImportProfile(payload, { settings = true }, "Fresh")
    local p = w.db.profiles.Fresh
    assert(p.qol.fastLoot == true and p.macros == nil and p.tankReminder.leadTime == nil)
    assert(w.db.account.themePreset == "midnight", "the look stays")
end)

Case("Macros without Smart Reminders still brings the class macros", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    w.ns.ImportProfile(payload, { macros = true }, "Macros Only")
    local sr = w.db.profiles["Macros Only"].tankReminder
    assert(sr.utilityReminders.classMacros.PALADIN[1].body == "/cast BoP" and sr.leadTime == nil)
end)

Case("BiS lists join yours under a free name, never over them", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    payload.parts.bisLists.PALADIN[1].slots[1] = 200
    payload.parts.bisLists.MAGE = { { name = "Fire", slots = { [5] = 300 } } }
    local _, added = w.ns.ImportProfile(payload, { bisLists = true }, "B")
    local paladin = w.db.account.bisLists.PALADIN.lists
    assert(added == 2 and #paladin == 2 and paladin[1].slots[1] == 100, "yours kept")
    assert(paladin[2].name == "Prot 2" and paladin[2].id == 2 and w.db.account.bisLists.PALADIN.nextID == 3)
    assert(w.db.account.bisLists.MAGE.lists[1].name == "Fire")
end)

Case("a value of the wrong type, or for no module, is not taken in", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    payload.parts.settings.qol.fastLoot = "yes"
    payload.parts.settings.bogus = { x = 1 }
    payload.parts.smartReminders.importedPack = { name = "fake", licensed = true }
    w.ns.ImportProfile(payload, ALL, "Checked")
    local p = w.db.profiles.Checked
    assert(p.qol.fastLoot == nil and p.qol.bisSlots[1] == 6948 and p.bogus == nil)
    assert(p.tankReminder.importedPack == nil, "a string cannot claim a pack")
end)

Case("pack strings go to the pack import; damaged or newer ones are refused", function()
    local w = World()
    local _, err = w.ns.DecodeProfile("NSRPACK2:abcdef")
    assert(err == "pack")
    _, err = w.ns.DecodeProfile("NFPROFILE1:%%%not-a-string")
    assert(err and err:find("damaged", 1, true), tostring(err))
    _, err = w.ns.DecodeProfile("hello")
    assert(err and err:find("not a Naowh Forever", 1, true), tostring(err))
    local LS, LD = LibStub("LibSerialize"), LibStub("LibDeflate")
    local newer = "NFPROFILE1:" .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({ format = 2, parts = {} })))
    _, err = w.ns.DecodeProfile(newer)
    assert(err and err:find("newer", 1, true), tostring(err))
    assert(w.ns.DecodeProfile("") == nil)
end)

-- The dialogs on stub frames: every method a no-op unless kept here.
Case("the dialogs: export shows the string, import ticks parts and lands what is ticked", function()
    local w = World()
    local NOTHING = function() end
    local function Frame()
        local f = { scripts = {} }
        return setmetatable(f, { __index = function(_, k)
            if k == "SetScript" then return function(self, s, fn) self.scripts[s] = fn end end
            if k == "SetText" then return function(self, t) self.text = t end end
            if k == "GetText" then return function(self) return self.text or "" end end
            if k == "GetParent" then return function() return Frame() end end
            if k == "GetWidth" then return function() return 500 end end
            if k == "Show" then return function(self) self.shown = true end end
            if k == "Hide" then return function(self) self.shown = false end end
            if k == "SetShown" then return function(self, on) self.shown = on end end
            return NOTHING
        end })
    end
    local ns, opened, reload = w.ns, nil, nil
    local buttons, boxes, toggles = {}, {}, {}
    ns.THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    ns.MakeModal = function() return Frame(), Frame() end
    ns.MakeMultilineBox = function()
        local box = Frame()
        boxes[#boxes + 1] = box
        return box
    end
    ns.Font = function() return Frame() end
    ns.NewEditBox = function() return Frame() end
    ns.Button = function(_, text, _, _, fn)
        local b = Frame()
        b.label, b.click = text, fn
        buttons[text] = b
        return b
    end
    ns.AccentBorder = function(f) return f end
    ns.SetButtonText = function(b, t) b.label = t end
    ns.WrapForDisplay = function(s) return s end
    ns.ConfirmReload = function(text) reload = text end
    ns.ShowPackImport = function(text) opened = text end
    ns.UI.KeepFont = function() return Frame() end
    ns.UI.BuildToggleControl = function(_, _, get, set)
        local t = Frame()
        t._get, t._set, t._refreshValue = get, set, NOTHING
        toggles[#toggles + 1] = t
        return t
    end
    local env = getfenv(ns.ExportProfile)
    env.CreateFrame = function() return Frame() end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    ns.ShowProfileExport()
    local text = boxes[1].text
    assert(text:sub(1, 11) == "NFPROFILE1:" and assert(ns.DecodeProfile(text)), "the export box holds the string")

    ns.ShowProfileImport()
    local paste, import = boxes[2], buttons.Import
    assert(import.shown == false, "nothing to import yet")
    paste.text = text
    paste.scripts.OnTextChanged(paste, true)
    assert(import.shown and import.label == "Import" and #toggles == 5, #toggles)
    for _, t in ipairs(toggles) do assert(t._get() == true, "every part ticked to start") end
    toggles[5]._set(false)   -- Look
    paste.scripts.OnTextChanged(paste, true)
    assert(toggles[5]._get() == false, "an untick survives a repaint")
    w.db.account.themePreset = "midnight"
    import.click()
    assert(w.switched == "Default 2" and w.db.profiles["Default 2"].qol.fastLoot == true)
    assert(w.db.account.themePreset == "midnight", "Look left out")
    assert(reload and reload:find("Default 2", 1, true), tostring(reload))

    ns.ShowProfileImport()
    paste.text = "NSRPACK2:abcdef"
    paste.scripts.OnTextChanged(paste, true)
    assert(import.label == "Open Pack Import")
    import.click()
    assert(opened == "NSRPACK2:abcdef", "the pack goes to the pack import")
end)

print(count .. " profile share regressions passed")
