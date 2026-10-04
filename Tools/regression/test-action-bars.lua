-- Bar sets against a small fake of the action bars, spellbook, macros and cursor, driven
-- through the /nf bars command the way a player would.
local PATH = arg[1] or "ActionBars/NaowhForever_ActionBars.lua"

-- Spells by id: name and rank.
local SPELLS = {
    [2054] = { "Heal", 1 }, [2055] = { "Heal", 2 }, [6064] = { "Heal", 4 },
    [585] = { "Smite", 1 }, [598] = { "Smite", 3 },
}

local function World(known)
    local w = { bars = {}, macros = {}, cursor = nil, opts = {}, account = {}, printed = {},
        combat = false }
    local book = {}
    for _, id in ipairs(known) do
        book[#book + 1] = { name = SPELLS[id][1], subName = "Rank " .. SPELLS[id][2], actionID = id,
            itemType = 1, isPassive = false }
    end
    local function Known(id)
        for _, item in ipairs(book) do if item.actionID == id then return true end end
    end
    w.opts.enabled = true
    local S = {
        Get = function(k) return w.opts[k] end,
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
        f.SetText = function(_, text) if key == "barsName" then w.lastName = text end end
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
            return 0
        end,
        GetMacroInfo = function(i) local m = w.macros[i]; return m.name, m.icon, m.body end,
        GetNumMacros = function() return #w.macros + (w.otherMacros or 0), 0 end,
        CreateMacro = function(name, icon, body) w.macros[#w.macros + 1] = { name = name, icon = icon, body = body } end,
        PickupMacro = function(i)
            -- A macro slot reports the spell it shows; this one shows nothing.
            w.cursor = { kind = "macro", id = 0, name = w.macros[i].name }
        end,
        InCombatLockdown = function() return w.combat end,
        UnitClass = function() return "Priest", "PRIEST" end,
        UnitName = function() return "Preview" end,
        GetRealmName = function() return "Realm" end,
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function(f, _, fn) f.handler = fn; w.events = f end }
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

Case("restore puts every slot back and clears slots the set left empty", function()
    local w = World({ 2055, 598 })
    w.bars = { [1] = Spell(2055), [3] = Spell(598), [185] = { kind = "item", id = 6948 } }
    w.run("save Raid")
    w.bars = { [1] = Spell(598), [2] = Spell(2055) }
    w.run("restore Raid")
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
Case("a test restore changes nothing and lists what would be left empty", function()
    local w = World({ 2055 })
    w.account.barSets = { PRIEST = { Set = { saved = 0, slots = { [1] = { kind = "spell", id = 585, name = "Smite" } } } } }
    w.bars = { [5] = Spell(2055) }
    w.run("test Set")
    assert(Bars(w) == "5=spell2055", Bars(w))
    assert(w.printed[#w.printed]:find("Smite", 1, true), w.printed[#w.printed])
end)
Case("macros are found by name and restored", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.bars = { [7] = Macro("Pull") }
    w.run("save M")
    w.bars = {}
    w.run("restore M")
    assert(Bars(w) == "7=Pull", Bars(w))
end)
Case("a deleted macro is left empty unless Recreate Deleted Macros is on", function()
    local w = World({})
    w.macros = { { name = "Pull", icon = 1, body = "/say pull" } }
    w.bars = { [7] = Macro("Pull") }
    w.run("save M")
    w.macros, w.bars = {}, {}
    w.run("restore M")
    assert(Bars(w) == "" and #w.macros == 0)
    w.opts.recreateMacros = true
    w.run("test M")
    assert(#w.macros == 0, "a test does not make macros")
    w.run("restore M")
    assert(Bars(w) == "7=Pull" and w.macros[1].body == "/say pull", Bars(w))
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
    w.events.handler()
    assert(w.account.barSets.PRIEST.Daily.slots[2].id == 598, "off: left alone")
    w.opts.saveOnLogout = true
    w.events.handler()
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
Case("Save Current Bars asks before replacing a set of the same name", function()
    local w = World({ 598, 2055 })
    w.bars = { [2] = Spell(598) }
    w.run("save Raid")
    w.bars = { [2] = Spell(2055) }
    More(w, "Raid")
    w.answer, w.confirmed = "raid", nil
    w.buttons["Save Current Bars"]()
    assert(w.confirmed and w.confirmed:find("Raid", 1, true), "asked")
    assert(w.account.barSets.PRIEST.Raid.slots[2].id == 2055 and not w.account.barSets.PRIEST.raid)
end)
Case("slots no set can restore are left as they are", function()
    local w = World({ 598 })
    w.bars = { [2] = Spell(598), [4] = { kind = "summonmount", id = 5 } }
    w.run("save Mount")
    w.bars = { [4] = Spell(598) }
    w.run("restore Mount")
    assert(Bars(w) == "2=spell598 4=spell598", Bars(w))
    assert(w.printed[#w.printed] == "Restored Mount.", w.printed[#w.printed])
end)
Case("a test counts the macros it would make against the free room", function()
    local w = World({})
    w.macros = { { name = "A", icon = 1, body = "/a" }, { name = "B", icon = 1, body = "/b" } }
    w.bars = { [1] = Macro("A"), [2] = Macro("B") }
    w.run("save M")
    w.macros, w.otherMacros, w.opts.recreateMacros = {}, 119, true
    w.run("test M")
    assert(w.printed[#w.printed]:find("Slot 2", 1, true), "one free slot, so the second is reported")
end)
Case("no name opens the window", function()
    local w = World({})
    w.run("")
    assert(w.opened == "window")
end)
print(count .. " action bar set regressions passed")
