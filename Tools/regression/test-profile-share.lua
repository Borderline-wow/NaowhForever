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
            libraryMacros = { PALADIN = { { name = "Seal", body = "/cast Seal", icon = 135 },
                { name = "Packed", body = "/cast Pack", pack = true } } },
            trainingBuilds = { [2] = { { name = "Ret", spec = "Retribution", points = { 11, 12 }, saved = true } } },
        },
    }
    w.active = "Default"
    w.buildsChanged = 0
    local ns = {
        UI = {}, CODE_BUILD = "test",
        MacroText = { LIMIT = 255 },
        TrainingBuilds = { [2] = { talents = {} } },
        -- Points that cannot be taken start with 0 here; the real rules are Training's own test.
        Training = {
            CheckBuild = function(_, points) return points[1] == 0 and "Already at full rank." or nil end,
            BuildName = function(text, default) return type(text) == "string" and text ~= "" and text or default end,
            Changed = function() w.buildsChanged = w.buildsChanged + 1 end,
        },
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

local ALL = { settings = true, macros = true, library = true, smartReminders = true, builds = true,
    bisLists = true, look = true }

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
    assert(parts.library.PALADIN[1].name == "Seal" and parts.library.PALADIN[1].icon == 135)
    assert(#parts.library.PALADIN == 1, "a pack macro's Library copy stays home")
    assert(parts.builds[2][1].name == "Ret" and parts.builds[2][1].points[2] == 12)
    assert(parts.builds[2][1].saved == nil)
    assert(parts.look.themePreset == "slate" and parts.look.windowScale == 1.1)
    assert(parts.barSets == nil and parts.look.barSets == nil, "no personal data")
end)

Case("export: only the ticked parts go in", function()
    local w = World()
    local text, note = w.ns.ExportProfile({ builds = true, library = true })
    local parts = assert(w.ns.DecodeProfile(text)).parts
    assert(parts.builds and parts.library and parts.settings == nil and parts.look == nil)
    assert(note and note:find("copied from a pack", 1, true), tostring(note))
    text, note = w.ns.ExportProfile({})
    assert(text == nil and note == "Tick a part to share.", tostring(note))
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
    assert(table.concat(keys, ",") == "settings:2 modules,macros:1 class macros,library:1 macros,smartReminders,"
        .. "builds:1 builds,bisLists:1 lists,look", table.concat(keys, ","))
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
    assert(added.bisLists == 0 and added.library == 0 and added.builds == 0, "what you have is not added twice")
    assert(#w.db.account.libraryMacros.PALADIN == 2 and #w.db.account.trainingBuilds[2] == 1)
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
    assert(added.bisLists == 2 and #paladin == 2 and paladin[1].slots[1] == 100, "yours kept")
    assert(paladin[2].name == "Prot 2" and paladin[2].id == 2 and w.db.account.bisLists.PALADIN.nextID == 3)
    assert(w.db.account.bisLists.MAGE.lists[1].name == "Fire")
end)

Case("Library macros join yours; a name you have, or one that is no macro, stays out", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    local paladin = payload.parts.library.PALADIN
    paladin[1].body = "/cast Theirs"
    paladin[2] = { name = "Wings|r\n", body = "/cast Wings", icon = { 1 } }
    paladin[3] = { name = "SeventeenLetters!", body = "/x" }
    paladin[4] = { name = "Empty", body = "" }
    paladin[5] = { name = "Long", body = string.rep("x", 256) }
    payload.parts.library.MAGE = { { name = "Blink", body = "/cast Blink" } }
    local _, added = w.ns.ImportProfile(payload, { library = true }, "L")
    local mine = w.db.account.libraryMacros
    assert(added.library == 2, added.library)
    assert(mine.PALADIN[1].body == "/cast Seal", "yours kept")
    assert(mine.PALADIN[3].name == "Wingsr" and mine.PALADIN[3].icon == nil and mine.PALADIN[3].pack == nil)
    assert(mine.MAGE[1].name == "Blink" and #mine.PALADIN == 3)
end)

Case("talent builds join yours when they can be taken; a class with no tree stays out", function()
    local w = World()
    local payload = assert(w.ns.DecodeProfile((w.ns.ExportProfile())))
    local list = payload.parts.builds[2]
    list[2] = { name = "Ret", spec = "Retribution", points = { 11, 13 } }
    list[3] = { name = "", points = { 14 } }
    list[4] = { name = "Broken", points = { 0, 1 } }
    list[5] = { name = "Nothing", points = {} }
    payload.parts.builds[99] = { { name = "Ghost", points = { 1 } } }
    local _, added = w.ns.ImportProfile(payload, { builds = true }, "T")
    local saved = w.db.account.trainingBuilds
    assert(added.builds == 2 and #saved[2] == 3, added.builds)
    assert(saved[2][2].points[2] == 13 and saved[2][2].saved == true)
    assert(saved[2][3].name == "Imported Build" and saved[2][3].spec == "Imported")
    assert(saved[99] == nil and w.buildsChanged == 1)
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

-- Forever raises on 1 / 0, which LibSerialize does to each 0 it writes: none may reach it.
Case("a 0 comes back as 0 and never reaches the serializer", function()
    local w = World()
    w.db.profiles.Default.topBar.mouseoverAlpha = 0
    w.db.profiles.Default.qol.lootFeedPos = { "TOP", 0, -20 }
    local LS = LibStub("LibSerialize")
    local serialize = LS.Serialize
    local function NoZero(v)
        assert(v ~= 0, "Division by zero")
        if type(v) == "table" then for k, val in pairs(v) do NoZero(k); NoZero(val) end end
    end
    LS.Serialize = function(self, ...)
        for i = 1, select("#", ...) do NoZero((select(i, ...))) end
        return serialize(self, ...)
    end
    local text = w.ns.ExportProfile()
    LS.Serialize = serialize
    local parts = assert(w.ns.DecodeProfile(assert(text))).parts
    assert(parts.settings.topBar.mouseoverAlpha == 0 and parts.settings.qol.lootFeedPos[2] == 0)
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

    ns.ShowProfileExport({ settings = true, builds = true })
    local parts = ns.DecodeProfile(boxes[1].text).parts
    assert(parts.settings and parts.builds and parts.library == nil, "only the parts the page ticked")
    ns.ShowProfileExport()
    local text = boxes[1].text
    assert(text:sub(1, 11) == "NFPROFILE1:" and assert(ns.DecodeProfile(text)), "the export box holds the string")

    ns.ShowProfileImport()
    local paste, import = boxes[2], buttons.Import
    assert(import.shown == false, "nothing to import yet")
    paste.text = text
    paste.scripts.OnTextChanged(paste, true)
    assert(import.shown and import.label == "Import" and #toggles == 7, #toggles)
    for _, t in ipairs(toggles) do assert(t._get() == true, "every part ticked to start") end
    toggles[7]._set(false)   -- Look
    paste.scripts.OnTextChanged(paste, true)
    assert(toggles[7]._get() == false, "an untick survives a repaint")
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

    ns.Training.ImportBuild = function(t) opened = t end
    ns.ShowProfileImport()
    paste.text = "  !NFB1!abc\n"
    paste.scripts.OnTextChanged(paste, true)
    assert(import.label == "Add Build" and import.shown)
    import.click()
    assert(opened == "  !NFB1!abc\n", "a build goes to the Training Planner's import")
end)

-- The Profiles page on stub frames and a small stand-in for the row engine.
Case("the page: a row per part with its status, ticks count and go to the export", function()
    local w = World()
    w.db.account.trainingBuilds = nil
    local NOTHING = function() end
    local function Frame()
        return setmetatable({ scripts = {} }, { __index = function(_, k)
            if k == "SetScript" then return function(self, s, fn) self.scripts[s] = fn end end
            if k == "SetText" then return function(self, t) self.text = t end end
            if k == "GetWidth" then return function() return 700 end end
            if k == "CreateTexture" then return function() return Frame() end end
            return NOTHING
        end })
    end
    local ns, exported, links, buttons, toggles = w.ns, nil, {}, {}, {}
    ns.THEME = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    ns.Solid, ns.Border, ns.Font = Frame, Frame, Frame
    ns.Hairline, ns.Print = NOTHING, NOTHING
    ns.AccentBorder = function(f) return f end
    ns.Button = function(_, text, _, _, fn)
        local b = Frame()
        b.click = fn
        buttons[text] = b
        return b
    end
    ns.ListProfiles = function() return { "Default" } end
    ns.UI.CONTENT_PAD = 20
    ns.UI.RefreshPage = NOTHING
    ns.UI.BuildDropdownControl = function()
        local d = Frame()
        d._refreshLabel = NOTHING
        return d
    end
    ns.UI.BuildToggleControl = function(_, _, get, set)
        local t = Frame()
        t._get, t._set, t._refreshValue = get, set, NOTHING
        toggles[#toggles + 1] = t
        return t
    end
    local Engine = {}
    function Engine:Clear() self.cursor, self.left, self.width, self.drawn = 0, 0, 700, {} end
    function Engine:Space(h) self.cursor = self.cursor + h end
    function Engine:OpenCard() return Frame() end
    Engine.CloseCard, Engine.Fit = NOTHING, NOTHING
    function Engine:GetHeight() return self.cursor end
    function Engine:GetWidth() return 700 end
    function Engine:Add(kind, ...)
        local list = self.drawn[kind] or {}
        self.drawn[kind] = list
        local pool = self.pools[kind] or {}
        self.pools[kind] = pool
        local row = pool[#list + 1] or self.kinds[kind].New(self)
        pool[#list + 1], list[#list + 1] = row, row
        self.cursor = self.cursor + self.kinds[kind].Set(row, ...)
        return row
    end
    ns.Shared = {
        Style = { IMPORT = "import", PLUS = "plus", HAVE_RGB = { r = 0, g = 1, b = 0 }, WARN_RGB = { r = 1, g = 0.5, b = 0 } },
        Parts = { Smooth = NOTHING, SetLink = NOTHING,
            Link = function(_, fn)
                local l = Frame()
                l.click = fn
                links[#links + 1] = l
                return l
            end },
        View = { NewKinds = function() return {} end,
            New = function(_, kinds, mixin)
                local view = setmetatable({ kinds = kinds, pools = {} }, { __index = function(_, k)
                    return mixin[k] or Engine[k] or NOTHING
                end })
                return view
            end },
    }
    local env = getfenv(ns.ExportProfile)
    env.CreateFrame = function() return Frame() end
    env.ns = ns
    function ns.ShowProfileExport(ticks) exported = ticks end

    local parent = Frame()
    parent.profilesView = false
    assert(ns.BuildProfileSettings(parent, -10) < -10)
    local view = parent.profilesView
    local rows, foot = view.drawn.part, view.drawn.foot[1]
    assert(#rows == 7 and #view.drawn.action == 2 and #view.drawn.bar == 1, #rows)
    assert(rows[5].key == "builds" and rows[5].status.text == "Nothing yet", tostring(rows[5].status.text))
    assert(rows[1].status.text == "Ready" and rows[1].line.text:find("frames sit", 1, true))
    assert(foot.count.text == "Export will include 6 of 6 parts.", foot.count.text)
    toggles[3]._set(false)   -- Macro Library
    foot = view.drawn.foot[1]
    assert(foot.count.text == "Export will include 5 of 6 parts.", foot.count.text)
    buttons["Export Profile"].click()
    assert(exported.library == nil and exported.settings == true and exported.look == true)
    links[1].click()   -- Deselect All
    assert(view.drawn.foot[1].count.text == "Tick a part to export.")
    links[2].click()   -- Select All
    assert(view.drawn.foot[1].count.text == "Export will include 6 of 6 parts.")

    w.db.profiles.Default.tankReminder.importedPack = { name = "Naowh's Pack" }
    ns.BuildProfileSettings(parent, -10)
    assert(view.drawn.part[4].status.text == "From a pack", view.drawn.part[4].status.text)
end)

print(count .. " profile share regressions passed")
