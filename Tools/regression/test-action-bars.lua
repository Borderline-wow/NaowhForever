-- Bar sets against a small fake of the action bars, spellbook, macros and cursor, driven
-- through the /nf bars command the way a player would.
local PATH = arg[1] or "ActionBars/NaowhForever_ActionBars.lua"

-- Spells by id: name, rank and the level it is learned at.
local SPELLS = {
    [2054] = { "Heal", 1, 16 }, [2055] = { "Heal", 2, 22 }, [6064] = { "Heal", 4, 34 },
    [585] = { "Smite", 1, 1 }, [598] = { "Smite", 3, 14 },
}

local function World(known)
    local w = { bars = {}, macros = {}, charMacros = {}, binds = {}, cursor = nil, opts = {}, account = {},
        printed = {}, combat = false }
    local book = {}
    for _, id in ipairs(known) do
        book[#book + 1] = { name = SPELLS[id][1], subName = "Rank " .. SPELLS[id][2], actionID = id,
            itemType = 1, isPassive = false }
    end
    local function Known(id)
        for _, item in ipairs(book) do if item.actionID == id then return true end end
    end
    function w.learn(id)
        book[#book + 1] = { name = SPELLS[id][1], subName = "Rank " .. SPELLS[id][2], actionID = id,
            itemType = 1, isPassive = false }
    end
    w.opts.enabled, w.opts.importMacros, w.opts.importBindings = true, true, true
    local listeners = {}
    local S = {
        Get = function(k) return w.opts[k] end,
        Set = function(k, v)
            w.opts[k] = v
            for _, fn in ipairs(listeners) do fn(k, v) end
        end,
        OnChange = function(fn) listeners[#listeners + 1] = fn end,
        Toggle = function(_, text) return { type = "toggle", text = text } end,
    }
    local fake = {}
    local function Fake(key)
        local f = fake[key]
        if f then return f end
        f = {}
        for _, m in ipairs({ "ClearAllPoints", "SetPoint", "SetShown", "SetHeight", "SetTextColor" }) do
            f[m] = function() end
        end
        f.GetStringHeight = function() return 12 end
        f.SetText = function(_, text)
            if key == "barsName" then w.lastName = text end
            if key == "barsHas" then w.lastHas = text end
        end
        fake[key] = f
        return f
    end
    local WHITE = { r = 1, g = 1, b = 1 }
    local ns = {
        THEME = { fg = WHITE, muted = WHITE },
        Solid = function() return Fake("solid") end,
        AccentBorder = function(f) return f end,
        AccountSettings = function() return w.account end,
        Print = function(m) w.printed[#w.printed + 1] = m end,
        UI = { ModuleSettings = function() return S end, RefreshPage = function() end, CONTENT_PAD = 12,
            Keep = function(_, key) return Fake(key) end,
            KeepFont = function(_, key) return Fake(key) end,
            KeepButton = function(_, key, text, _, _, fn)
                if key == "barsMore" then w.rows[#w.rows + 1] = { name = w.lastName, more = fn }
                else w.buttons[text] = fn end
                return Fake(key)
            end,
            Widgets = {
            Note = function() return nil, 0 end,
            SectionHeader = function() return nil, 0 end,
            Button = function(_, _, text, _, fn) w.buttons[text] = fn; return nil, 0 end,
            DualRow = function(_, _, _, left, right) w.rows[#w.rows + 1] = { left, right }; return nil, 0 end,
        } },
        OpenActionBarsWindow = function() w.opened = "window" end,
        OpenActionBarsBuilder = function(key) w.opened = "builder " .. tostring(key) end,
        OpenActionBarsImport = function(key) w.opened = "import " .. tostring(key) end,
        PromptText = function(_, _, _, accept) accept(w.answer) end,
        Confirm = function(text, yes) w.confirmed = text; yes() end,
    }
    w.ns = ns
    local env = {
        Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } },
        Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } },
        C_GamepadUI = {
            GetFirstGamepadActionStorageSlotIndex = function() return 181 end,
            IsValidGamepadActionStorageSlotIndex = function(slot) return slot <= 190 end,
        },
        C_SpellBook = {
            GetNumSpellBookSkillLines = function() return 1 end,
            GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
            GetSpellBookItemInfo = function(i) return book[i] end,
        },
        C_Spell = {
            GetSpellName = function(id) return SPELLS[id][1] end,
            PickupSpell = function(id) if Known(id) then w.cursor = { kind = "spell", id = id } end end,
            GetSpellLevelLearned = function(id) return SPELLS[id][3] end,
        },
        C_Item = {
            PickupItem = function(id) w.cursor = { kind = "item", id = id } end,
            GetItemNameByID = function(id) return "Item " .. id end,
        },
        C_ActionBar = { GetActionText = function(slot) return w.bars[slot] and w.bars[slot].name end },
        C_EquipmentSet = { GetEquipmentSetID = function() end, PickupEquipmentSet = function() end },
        MenuUtil = { CreateContextMenu = function(_, build)
            w.menu = {}
            build(nil, { CreateButton = function(_, text, fn) w.menu[text] = fn end })
        end },
        GetActionInfo = function(slot)
            local a = w.bars[slot]
            if a then return a.kind, a.id end
        end,
        GetCursorInfo = function() return w.cursor and w.cursor.kind end,
        ClearCursor = function() w.cursor = nil end,
        PlaceAction = function(slot) w.bars[slot], w.cursor = w.cursor, w.bars[slot] end,
        PickupAction = function(slot) w.cursor, w.bars[slot] = w.bars[slot], nil end,
        GetMacroIndexByName = function(name)
            for i, m in ipairs(w.macros) do if m.name == name then return i end end
            for i, m in ipairs(w.charMacros) do if m.name == name then return 120 + i end end
            return 0
        end,
        GetMacroInfo = function(i)
            local m = i > 120 and w.charMacros[i - 120] or w.macros[i]
            if m then return m.name, m.icon, m.body end
        end,
        GetNumMacros = function() return #w.macros + (w.otherMacros or 0), #w.charMacros end,
        CreateMacro = function(name, icon, body, perCharacter)
            local list = perCharacter and w.charMacros or w.macros
            list[#list + 1] = { name = name, icon = icon, body = body }
            return (perCharacter and 120 or 0) + #list
        end,
        PickupMacro = function(i)
            -- A macro slot reports the spell it shows; this one shows nothing.
            local m = i > 120 and w.charMacros[i - 120] or w.macros[i]
            w.cursor = { kind = "macro", id = 0, name = m.name }
        end,
        GetNumBindings = function() return #w.binds end,
        GetBinding = function(i) local b = w.binds[i]; return b[1], "HEADER", b[2], b[3] end,
        SetBinding = function(key, command)
            if command == "NO_SUCH_ADDON" then return false end
            for _, b in ipairs(w.binds) do
                if b[2] == key then b[2] = b[3]; b[3] = nil end
                if b[3] == key then b[3] = nil end
            end
            for _, b in ipairs(w.binds) do
                if b[1] == command then
                    if b[2] then b[3] = key else b[2] = key end
                    return true
                end
            end
            w.binds[#w.binds + 1] = { command, key }
            return true
        end,
        C_KeyBindings = { GetBindingContextForAction = function() return 1 end },
        GetCurrentBindingSet = function() return 2 end,
        SaveBindings = function(set) w.savedBindings = set end,
        InCombatLockdown = function() return w.combat end,
        UnitClass = function() return "Priest", "PRIEST" end,
        UnitName = function() return "Preview" end,
        GetRealmName = function() return "Realm" end,
        CreateFrame = function()
            local f = { registered = {} }
            f.RegisterEvent = function(self, event) self.registered[event] = true end
            f.UnregisterEvent = function(self, event) self.registered[event] = nil end
            f.SetScript = function(self, _, fn)
                self.handler = fn
                w.events = self
            end
            return f
        end,
        strtrim = function(s) return s:match("^%s*(.-)%s*$") end,
        time = os.time, date = os.date,
        print = function(m) w.printed[#w.printed + 1] = m end,
        _G = { NaowhForever = ns },
    }
    env._G.NaowhForever = ns
    setmetatable(env, { __index = _G })
    local chunk = assert(loadfile(PATH)); setfenv(chunk, env); chunk()
    w.run = ns.ActionBarsCommand
    return w
end

local function Spell(id) return { kind = "spell", id = id } end
local function Macro(name) return { kind = "macro", id = 0, name = name } end
local function Bars(w)
    local out = {}
    for slot = 1, 190 do
        local a = w.bars[slot]
        if a then out[#out + 1] = slot .. "=" .. (a.kind == "macro" and a.name or a.kind .. a.id) end
    end
    return table.concat(out, " ")
end

-- The page's rows, then the More menu of the named set.
local function More(w, name)
    w.rows, w.buttons = {}, {}
    w.ns.BuildActionBarsPage(nil, 0)
    for _, row in ipairs(w.rows) do
        if row.name == name then row.more() end
    end
    return w.menu
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("import puts every slot back and clears slots the set left empty", function()
    local w = World({ 2055, 598 })
    w.bars = { [1] = Spell(2055), [3] = Spell(598), [185] = { kind = "item", id = 6948 } }
    w.run("save Raid")
    w.bars = { [1] = Spell(598), [2] = Spell(2055) }
    w.run("import Raid")
    assert(Bars(w) == "1=spell2055 3=spell598 185=item6948", Bars(w))
    assert(w.cursor == nil, "nothing left on the cursor")
end)
Case("a rank no longer known falls back to the highest known", function()
    local w = World({ 2055 })
    w.account.barSets = { PRIEST = { Old = { saved = 0, slots = { [1] = { kind = "spell", id = 6064, name = "Heal" } } } } }
    w.run("restore Old")
    assert(Bars(w) == "1=spell2055", Bars(w))
end)
Case("Highest Rank swaps a known lower rank for the top one", function()
    local w = World({ 2054, 6064 })
    w.bars = { [1] = Spell(2054) }
    w.run("save Low")
    w.opts.highestRank = true
    w.run("restore Low")
    assert(Bars(w) == "1=spell6064", Bars(w))
end)
Case("without Highest Rank a known saved rank stays, for downranking", function()
    local w = World({ 2054, 6064 })
    w.bars = { [1] = Spell(2054), [2] = Spell(6064) }
    w.run("save Heals")
    w.bars = {}
    w.run("restore Heals")
    assert(Bars(w) == "1=spell2054 2=spell6064", Bars(w))
end)
Case("a test import changes nothing and lists what would be left empty", function()
    local w = World({ 2055 })
    w.account.barSets = { PRIEST = { Set = { saved = 0, slots = { [1] = { kind = "spell", id = 585, name = "Smite" } } } } }
    w.bars = { [5] = Spell(2055) }
    w.run("test Set")
    assert(Bars(w) == "5=spell2055", Bars(w))
    assert(w.printed[#w.printed]:find("Smite", 1, true), w.printed[#w.printed])
end)
Case("restore still imports, and macros are found by name", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.bars = { [7] = Macro("Pull") }
    w.run("save M")
    w.bars = {}
    w.run("restore M")
    assert(Bars(w) == "7=Pull", Bars(w))
end)
Case("a missing macro is made on import, and left empty with Import Macros off", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.bars = { [7] = Macro("Pull") }
    w.run("save M")
    w.macros, w.bars = {}, {}
    w.opts.importMacros = false
    w.run("import M")
    assert(Bars(w) == "" and #w.macros == 0)
    w.opts.importMacros = true
    w.run("test M")
    assert(#w.macros == 0, "a test does not make macros")
    w.run("import M")
    assert(Bars(w) == "7=Pull" and w.macros[1].body == "/say pull", Bars(w))
end)
Case("an alt gets the macros it lacks once, and keeps its own", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.charMacros = { { name = "Bop", icon = 2, body = "/cast Blessing of Protection" } }
    w.bars = { [1] = Macro("Pull"), [2] = Macro("Bop") }
    w.run("save Main")
    w.charMacros, w.bars = { { name = "Mine", icon = 3, body = "/dance" } }, {}
    w.run("import Main")
    assert(Bars(w) == "1=Pull 2=Bop", Bars(w))
    assert(#w.macros == 1, "the account macro was already there")
    assert(#w.charMacros == 2 and w.charMacros[1].name == "Mine", "the alt's own macro is kept")
    w.run("import Main")
    assert(#w.macros == 1 and #w.charMacros == 2, "a second import makes nothing")
end)
Case("a macro already here under another name is used, not copied", function()
    local w = World({})
    w.charMacros = { { name = "Bop", icon = 2, body = "/cast Blessing of Protection" } }
    w.bars = { [4] = Macro("Bop") }
    w.run("save Main")
    w.charMacros, w.bars = { { name = "BoP2", icon = 2, body = "/cast Blessing of Protection\r\n" } }, {}
    w.run("import Main")
    assert(#w.charMacros == 1 and Bars(w) == "4=BoP2", Bars(w))
end)
Case("a macro of the same name with other text is never overwritten", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.bars = { [7] = Macro("Pull") }
    w.run("save M")
    w.macros[1].body = "/yell PULLING"
    w.run("import M")
    assert(w.macros[1].body == "/yell PULLING" and w.macros[2].body == "/say pull", "made alongside")
end)
Case("a #showtooltip macro is made with the question mark so it follows its spell", function()
    local w = World({})
    w.charMacros = { { name = "Heal", icon = 135913, body = "#showtooltip\n/cast Heal" } }
    w.run("save M")
    w.charMacros = {}
    w.run("import M")
    assert(w.charMacros[1].icon == 134400, tostring(w.charMacros[1].icon))
end)
Case("keybinds are saved and imported, keys the set leaves free keep theirs", function()
    local w = World({})
    w.binds = { { "ACTIONBUTTON1", "1" }, { "MOVEFORWARD", "W", "UP" }, { "TOGGLEBAG", "B" } }
    w.run("save Keys")
    w.binds = { { "ACTIONBUTTON1", "Q" }, { "STRAFELEFT", "1" }, { "TOGGLEMAP", "M" } }
    w.run("test Keys")
    assert(w.binds[1][2] == "Q" and not w.savedBindings, "a test binds nothing")
    w.run("import Keys")
    local keys = {}
    for _, b in ipairs(w.binds) do
        for i = 2, 3 do if b[i] then keys[b[i]] = b[1] end end
    end
    assert(keys["1"] == "ACTIONBUTTON1" and keys.W == "MOVEFORWARD" and keys.UP == "MOVEFORWARD"
        and keys.B == "TOGGLEBAG", "the set's keys")
    assert(keys.M == "TOGGLEMAP" and keys.Q == "ACTIONBUTTON1", "keys the set leaves free are kept")
    assert(w.savedBindings == 2, "saved to the binding set in use")
    assert(w.printed[#w.printed]:find("4 keybinds", 1, true), w.printed[#w.printed])
end)
Case("Import Keybinds off leaves keys alone", function()
    local w = World({})
    w.binds = { { "ACTIONBUTTON1", "1" } }
    w.run("save Keys")
    w.binds = { { "STRAFELEFT", "1" } }
    w.opts.importBindings = false
    w.run("import Keys")
    assert(w.binds[1][1] == "STRAFELEFT" and w.binds[1][2] == "1" and not w.savedBindings)
end)
Case("a key whose command is not here is not counted", function()
    local w = World({})
    w.account.barSets = { PRIEST = { Old = { saved = 0, slots = {},
        bindings = { ["1"] = "ACTIONBUTTON1", F = "NO_SUCH_ADDON" } } } }
    w.run("import Old")
    assert(w.printed[#w.printed]:find("1 keybind", 1, true), w.printed[#w.printed])
end)
Case("the set row says what it holds", function()
    local w = World({ 598 })
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.binds = { { "ACTIONBUTTON1", "1", "F1" } }
    w.bars = { [2] = Spell(598), [3] = Macro("Pull") }
    w.run("save Raid")
    More(w, "Raid")
    assert(w.lastHas == "2 actions, 1 macro, 2 keybinds", w.lastHas)
end)
Case("set names match whatever the case", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save Dungeon")
    w.bars = {}
    w.run("restore dUNGEON")
    assert(Bars(w) == "2=spell598")
    assert(w.account.barSets.PRIEST.Dungeon and not w.account.barSets.PRIEST.dUNGEON)
end)
Case("nothing saves or restores while the module is off", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save On")
    w.opts.enabled = false
    w.run("save Off")
    w.bars = {}
    w.run("restore On")
    assert(Bars(w) == "" and not w.account.barSets.PRIEST.Off)
    assert(w.printed[#w.printed] == "Action Bars is switched off.")
end)
Case("nothing changes in combat", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save C")
    w.bars, w.combat = {}, true
    w.run("restore C")
    assert(Bars(w) == "")
end)
Case("Save on Logout writes back the last set used, only when on", function()
    local w = World({ 598, 2055 })
    w.bars = { [2] = Spell(598) }
    w.run("save Daily")
    w.bars = { [2] = Spell(2055) }
    w.events.handler(w.events, "PLAYER_LOGOUT")
    assert(w.account.barSets.PRIEST.Daily.slots[2].id == 598, "off: left alone")
    w.opts.saveOnLogout = true
    w.events.handler(w.events, "PLAYER_LOGOUT")
    assert(w.account.barSets.PRIEST.Daily.slots[2].id == 2055, "on: saved again")
end)
Case("renaming a set to its own name keeps it", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save Raid")
    w.answer = "Raid"
    More(w, "Raid").Rename()
    assert(w.account.barSets.PRIEST.Raid, "still there")
end)
Case("a rename moves Save on Logout only for characters of this class", function()
    local w = World({ 598 })
    w.account.barSetLast = { ["Warrior-Realm"] = { class = "WARRIOR", name = "Raid" } }
    w.bars = { [2] = Spell(598) }
    w.run("save Raid")
    w.answer = "Main"
    More(w, "Raid").Rename()
    assert(w.account.barSets.PRIEST.Main and not w.account.barSets.PRIEST.Raid)
    assert(w.account.barSetLast["Preview-Realm"].name == "Main")
    assert(w.account.barSetLast["Warrior-Realm"].name == "Raid", "the warrior keeps its own set")
end)
Case("Save Current Bars opens the builder, and More can edit a set there", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save Raid")
    More(w, "Raid")["Edit and Save Again"]()
    assert(w.opened == "builder Raid", w.opened)
    w.buttons["Save Current Bars"]()
    assert(w.opened == "builder nil", w.opened)
end)
Case("the row's Import opens the preview", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598) }
    w.run("save Raid")
    w.rows, w.buttons = {}, {}
    w.ns.BuildActionBarsPage(nil, 0)
    w.buttons.Import()
    assert(w.opened == "import Raid", w.opened)
end)
Case("slots no set can restore are left as they are", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598), [4] = { kind = "summonmount", id = 5 } }
    w.run("save Mount")
    w.bars = { [4] = Spell(598) }
    w.run("restore Mount")
    assert(Bars(w) == "2=spell598 4=spell598", Bars(w))
    assert(w.printed[#w.printed] == "Imported Mount: 1 of 1 actions, 0 keybinds.", w.printed[#w.printed])
end)
Case("a test counts the macros it would make against the free room", function()
    local w = World({})
    w.macros = { { name = "A", icon = 1, body = "/a" }, { name = "B", icon = 1, body = "/b" } }
    w.bars = { [1] = Macro("A"), [2] = Macro("B") }
    w.run("save M")
    w.macros, w.otherMacros = {}, 119
    w.run("test M")
    assert(w.printed[#w.printed]:find("Slot 2", 1, true), "one free slot, so the second is reported")
    assert(w.printed[#w.printed - 2]:find("No room for 1 macro: B", 1, true), w.printed[#w.printed - 2])
end)
Case("no name opens the window", function()
    local w = World({})
    w.run("")
    assert(w.opened == "window")
end)
local Sets
local function Choices(skip, keys, macros, macroOff)
    return { skip = skip or {}, keys = keys ~= false, macros = macros ~= false, macroOff = macroOff or {} }
end

Case("slots left out are not saved, and an import leaves them as they are", function()
    local w = World({ 598, 2055 })
    Sets = w.ns.ActionBarSets
    w.bars = { [1] = Spell(598), [2] = Spell(2055) }
    Sets.Save("Part", Choices({ [2] = true, [3] = true }))
    local set = w.account.barSets.PRIEST.Part
    assert(set.slots[1] and not set.slots[2], "the left-out slot is not in the set")
    w.bars = { [2] = Spell(598), [3] = Spell(2055) }
    w.run("import Part")
    assert(Bars(w) == "1=spell598 2=spell598 3=spell2055", Bars(w))
end)
Case("a whole bar left out is never touched", function()
    local w = World({ 598 })
    Sets = w.ns.ActionBarSets
    local skip = {}
    for slot = 61, 72 do skip[slot] = true end
    w.bars = { [1] = Spell(598) }
    Sets.Save("NoBar2", Choices(skip))
    w.bars = { [61] = Spell(598), [70] = { kind = "item", id = 6948 } }
    w.run("import NoBar2")
    assert(Bars(w) == "1=spell598 61=spell598 70=item6948", Bars(w))
end)
Case("keybinds switched off are not saved", function()
    local w = World({})
    Sets = w.ns.ActionBarSets
    w.binds = { { "ACTIONBUTTON1", "1" } }
    Sets.Save("NoKeys", Choices(nil, false))
    assert(w.account.barSets.PRIEST.NoKeys.bindings == nil)
end)
Case("macros left out stay out, except ones on a kept slot", function()
    local w = World({})
    Sets = w.ns.ActionBarSets
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" }, { name = "Dance", icon = 1, body = "/dance" },
        { name = "Wave", icon = 1, body = "/wave" } }
    w.bars = { [1] = Macro("Pull") }
    local off = { [Sets.MacroKey("Pull", "/say pull")] = true, [Sets.MacroKey("Dance", "/dance")] = true }
    Sets.Save("M", Choices(nil, true, true, off))
    local names = {}
    for _, m in ipairs(w.account.barSets.PRIEST.M.macros) do names[#names + 1] = m.name end
    assert(table.concat(names, ",") == "Pull,Wave", table.concat(names, ","))
    Sets.Save("OnlyBars", Choices(nil, true, false))
    assert(#w.account.barSets.PRIEST.OnlyBars.macros == 1, "macros off: only the ones on the bars")
end)
Case("saving again, by hand or on logout, keeps the set's choices", function()
    local w = World({ 598, 2055 })
    Sets = w.ns.ActionBarSets
    w.bars = { [1] = Spell(598), [2] = Spell(2055) }
    Sets.Save("Keep", Choices({ [2] = true }, false))
    w.run("save Keep")
    local set = w.account.barSets.PRIEST.Keep
    assert(not set.slots[2] and set.bindings == nil, "slash save keeps the picks")
    w.opts.saveOnLogout = true
    w.events.handler(w.events, "PLAYER_LOGOUT")
    set = w.account.barSets.PRIEST.Keep
    assert(not set.slots[2] and set.bindings == nil and set.choices.skip[2], "logout keeps the picks")
end)
-- The set saved on one character, then the same account on a level 20 alt who knows Smite only.
local function Alt(known)
    local w = World({ 598, 6064 })
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.binds = { { "ACTIONBUTTON1", "1" } }
    w.bars = { [1] = Spell(598), [2] = Spell(6064), [3] = Macro("Pull"), [5] = Spell(598) }
    w.ns.ActionBarSets.Save("P", Choices({ [5] = true }))
    local alt = World(known or { 598 })
    alt.account = w.account
    alt.events.handler(alt.events, "PLAYER_LOGIN")
    return alt
end
Case("the preview says what each slot becomes and changes nothing", function()
    local alt = Alt()
    alt.bars = { [4] = Spell(598), [5] = Spell(598) }
    local r = alt.ns.ActionBarSets.Preview("P")
    assert(r.slots[1].state == "ok" and r.slots[3].state == "new", r.slots[3].state)
    assert(r.slots[2].state == "later" and r.slots[2].level == 34, r.slots[2].state)
    assert(r.slots[4].state == "clear" and r.slots[5].state == "skip")
    assert(r.placed == 2 and r.actions == 3 and r.bound == 1, r.placed .. "/" .. r.actions)
    assert(r.macros[1].fate == "new", r.macros[1].fate)
    assert(Bars(alt) == "4=spell598 5=spell598" and #alt.macros == 0 and not alt.savedBindings, Bars(alt))
end)
Case("a spell learned later goes into its slot when Fill In is on", function()
    local alt = Alt()
    alt.opts.fillLater = true
    alt.run("import P")
    assert(Bars(alt) == "1=spell598 3=Pull", Bars(alt))
    assert(alt.events.registered.LEARNED_SPELL_IN_SKILL_LINE, "waiting for the spell")
    assert(alt.printed[#alt.printed]:find("learn later", 1, true), alt.printed[#alt.printed])
    alt.learn(6064)
    alt.events.handler(alt.events, "LEARNED_SPELL_IN_SKILL_LINE", 6064)
    assert(Bars(alt) == "1=spell598 3=Pull", "not before the spellbook has it")
    alt.events.handler(alt.events, "SPELLS_CHANGED")
    assert(Bars(alt) == "1=spell598 2=spell6064 3=Pull", Bars(alt))
    assert(alt.printed[#alt.printed]:find("Heal is on your bars", 1, true), alt.printed[#alt.printed])
    assert(not alt.events.registered.LEARNED_SPELL_IN_SKILL_LINE, "nothing left to wait for")
    assert(next(alt.account.barSetPending) == nil)
end)
Case("Fill In waits out combat", function()
    local alt = Alt()
    alt.opts.fillLater = true
    alt.run("import P")
    alt.learn(6064)
    alt.combat = true
    alt.events.handler(alt.events, "LEARNED_SPELL_IN_SKILL_LINE", 6064)
    alt.events.handler(alt.events, "SPELLS_CHANGED")
    assert(not alt.bars[2] and alt.events.registered.PLAYER_REGEN_ENABLED, "waits")
    alt.combat = false
    alt.events.handler(alt.events, "PLAYER_REGEN_ENABLED")
    assert(alt.bars[2] and alt.bars[2].id == 6064, Bars(alt))
end)
Case("a slot filled meanwhile is the player's", function()
    local alt = Alt()
    alt.opts.fillLater = true
    alt.run("import P")
    alt.bars[2] = Spell(598)
    alt.learn(6064)
    alt.events.handler(alt.events, "LEARNED_SPELL_IN_SKILL_LINE", 6064)
    alt.events.handler(alt.events, "SPELLS_CHANGED")
    assert(alt.bars[2].id == 598 and next(alt.account.barSetPending) == nil, Bars(alt))
end)
Case("a copy the game put in a slot the set keeps empty is taken off", function()
    local alt = Alt()
    alt.opts.fillLater = true
    alt.run("import P")
    alt.learn(6064)
    alt.bars[7] = Spell(6064)
    alt.events.handler(alt.events, "LEARNED_SPELL_IN_SKILL_LINE", 6064)
    alt.events.handler(alt.events, "SPELLS_CHANGED")
    assert(Bars(alt) == "1=spell598 2=spell6064 3=Pull", Bars(alt))
end)
Case("with Fill In off nothing waits", function()
    local alt = Alt()
    alt.run("import P")
    assert(not alt.events.registered.LEARNED_SPELL_IN_SKILL_LINE and next(alt.account.barSetPending) == nil)
    alt.opts.fillLater = true
    alt.ns.ActionBarSettings.Set("fillLater", true)
    assert(not alt.events.registered.LEARNED_SPELL_IN_SKILL_LINE, "nothing pending, so nothing to wait for")
end)
print(count .. " action bar set regressions passed")
