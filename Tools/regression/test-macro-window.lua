-- Run with Lua 5.1 from the repository root: Naowh's Forge, the Macros module's window, built
-- on the Shared kit and opened against stubs and a stand-in for the game's macros. Every tab is
-- drawn and its controls used: a macro is created, edited, renamed and deleted in the game's
-- store, the Library starts empty and fills from the pack, and a share string round-trips.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

-------------------------------------------------------------------------------
--  Stubs: a frame keeps its scripts, size, text and shown state; Show runs OnShow.
-------------------------------------------------------------------------------
local NOTHING = function() end
local Frame
local frames = {}
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    GetScript = function(f, script) return f.scripts[script] end,
    HookScript = function(f, script, fn) f.scripts[script] = fn end,
    GetParent = function(f) return rawget(f, "parent") end,
    SetWidth = function(f, w) f.w = w end,
    SetHeight = function(f, h) f.h = h end,
    SetSize = function(f, w, h) f.w, f.h = w, h end,
    GetWidth = function(f) return rawget(f, "w") or 600 end,
    GetHeight = function(f) return rawget(f, "h") or 24 end,
    SetText = function(f, text)
        f.text = text
        if f.scripts.OnTextChanged then f.scripts.OnTextChanged(f, false) end
    end,
    GetText = function(f) return rawget(f, "text") or "" end,
    Insert = function(f, text) f:SetText(f:GetText() .. text) end,
    GetStringWidth = function() return 40 end,
    GetStringHeight = function() return 16 end,
    GetFrameLevel = function() return 1 end,
    Show = function(f)
        local was = rawget(f, "shown")
        f.shown = true
        if was == false and f.scripts.OnShow then f.scripts.OnShow(f) end
    end,
    Hide = function(f)
        local was = rawget(f, "shown")
        f.shown = false
        if was ~= false and f.scripts.OnHide then f.scripts.OnHide(f) end
    end,
    SetShown = function(f, shown) if shown then f:Show() else f:Hide() end end,
    IsShown = function(f) return rawget(f, "shown") ~= false end,
    IsVisible = function(f) return rawget(f, "shown") ~= false end,
    SetEnabled = function(f, on) f.enabled = on end,
    SetClipsChildren = function(f, on) f.clips = on end,
    SetCursorPosition = function(f, at) f.cursor = at end,
    GetCursorPosition = function(f) return rawget(f, "cursor") or #(rawget(f, "text") or "") end,
    CreateTexture = function(f) return Frame(f) end,
    CreateFontString = function(f) return Frame(f) end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent)
    local f = setmetatable({ scripts = {}, parent = parent }, META)
    frames[#frames + 1] = f
    return f
end
local function Click(f, ...) assert(f.scripts.OnClick, "clickable")(f, ...) end

-------------------------------------------------------------------------------
--  The game's macros: account 1-120, character 121-138, sorted by name as the game does.
-------------------------------------------------------------------------------
local MAX_ACCOUNT, MAX_CHARACTER = 120, 18
local store = { account = {}, character = {} }
local picked
local function Sort(list) table.sort(list, function(a, b) return a.name < b.name end) end
local function At(index)
    if index <= MAX_ACCOUNT then return store.account[index], store.account, index end
    return store.character[index - MAX_ACCOUNT], store.character, index - MAX_ACCOUNT
end
local macroAPI = {
    GetNumMacros = function() return #store.account, #store.character end,
    -- As the game does, a question mark macro reports the icon #showtooltip shows.
    GetMacroInfo = function(index)
        local m = At(index)
        if m then return m.name, (m.icon == 134400 and m.body:find("^#showtooltip")) and 135846 or m.icon, m.body end
    end,
    GetMacroSpell = function() return nil end,
    CreateMacro = function(name, icon, body, perCharacter)
        local list = perCharacter and store.character or store.account
        list[#list + 1] = { name = name, icon = icon, body = body }
        Sort(list)
    end,
    EditMacro = function(index, name, icon, body)
        local m, list = At(index)
        m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
        Sort(list)
    end,
    DeleteMacro = function(index)
        local _, list, i = At(index)
        table.remove(list, i)
    end,
    PickupMacro = function(index) picked = index end,
    GetMacroIndexByName = function(name)
        for i, m in ipairs(store.account) do if m.name == name then return i end end
        for i, m in ipairs(store.character) do if m.name == name then return MAX_ACCOUNT + i end end
        return 0
    end,
}

-------------------------------------------------------------------------------
--  The addon around it
-------------------------------------------------------------------------------
local WHITE = { r = 1, g = 1, b = 1 }
local account, printed, settings, packMacros = {}, {}, {}, {}
local setHooks, applyHooks = {}, {}
local UI = {
    STATUS = { untested = "" },
    CONTENT_PAD = 10,
    Keep = function(parent, key, make)
        local kept = rawget(parent, key)
        if not kept then kept = make(parent); parent[key] = kept end
        return kept
    end,
    RefreshPage = NOTHING,
    CloseOnEscape = NOTHING,
    SlimScroll = function(parent) return Frame(parent) end,
    BuildSliderCore = function(parent)
        local slider = Frame(parent)
        for _, k in ipairs({ "rail", "fill", "thumb", "valueBox", "valueFill" }) do slider[k] = Frame(slider) end
        slider.valueBorder = { _frame = Frame(slider) }
        slider._refreshValue = NOTHING
        return slider
    end,
    BuildToggleControl = function(parent, _, get, set)
        local t = Frame(parent)
        t._get, t._set = get, set
        t._refreshValue = NOTHING
        t.scripts.OnClick = function() set(not get()) end
        return t
    end,
    BuildDropdownControl = function(parent, _, _, _, _, get, set)
        local d = Frame(parent)
        d._get, d._set = get, set
        return d
    end,
    ModuleSettings = function(_, defaults)
        local S = {}
        function S.Get(k) if settings[k] == nil then return defaults[k] end return settings[k] end
        function S.Set(k, v)
            settings[k] = v
            for _, fn in ipairs(setHooks) do fn(k, v) end
        end
        return S
    end,
    Widgets = {
        Note = function() return nil, 20 end, DualRow = function() return nil, 50 end,
        SectionHeader = function() return nil, 30 end, Feature = function() return nil, 30 end,
        Button = function() return nil, 30 end,
    },
}
local ns = {
    THEME = setmetatable({}, { __index = function() return WHITE end }),
    UI = UI,
    Color = function(_, text) return tostring(text) end,
    Font = function(parent) return Frame(parent) end,
    Solid = function(parent) return Frame(parent) end,
    Border = function(parent) return { SetColor = NOTHING, _frame = Frame(parent) } end,
    AllowOffscreen = NOTHING,
    AccentBorder = function(b) return b end,
    Button = function(parent, _, _, _, onClick)
        local b = Frame(parent)
        b.label, b._border, b._rest, b._onClick = Frame(b), { SetColor = NOTHING }, WHITE, onClick
        b.scripts.OnClick = function() if b._onClick then b._onClick() end end
        return b
    end,
    NewEditBox = function(parent) return Frame(parent) end,
    NewSearchBox = function(parent)
        local box = Frame(parent)
        box.hint, box.border = Frame(box), { SetColor = NOTHING }
        return box
    end,
    SetButtonText = NOTHING, Tooltip = NOTHING, Hairline = NOTHING, PixelInset = NOTHING,
    UIFontPath = function() return "font" end,
    UIScale = function() return 1 end,
    AccountSettings = function() return account end,
    Print = function(m) printed[#printed + 1] = m end,
    Confirm = function(text, yes) account.lastConfirm = text; yes() end,
    ShowCopyBox = function(_, text) account.lastCopy = text end,
    StashOptionsWindow = NOTHING, OpenOptionsWindow = NOTHING, Apply = NOTHING,
    DB = function() return { utilityReminders = { classMacros = packMacros } } end,
    HEALTHSTONES = { 5509 }, HEALING_POTIONS = { 13446 },
}
local lastPrompt
local vault = {}
ns.PromptText = function(_, _, _, accept) lastPrompt = accept end
local env = setmetatable({
    NaowhForever = ns,
    UIParent = {},
    GameTooltip = Frame(),
    GameTooltip_Hide = NOTHING,
    CreateFrame = function(_, _, parent) return Frame(parent) end,
    CreateColor = function() return { SetRGBA = NOTHING } end,
    hooksecurefunc = function(t, name, fn)
        if type(t) == "table" and name == "Set" then setHooks[#setHooks + 1] = fn end
        if t == ns and name == "Apply" then applyHooks[#applyHooks + 1] = fn end
    end,
    InCombatLockdown = function() return false end,
    IsMouseButtonDown = function() return false end,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    UnitClass = function() return "Mage", "MAGE", 8 end,
    UnitName = function() return "Glyalith" end,
    IsInRaid = function() return false end,
    IsInGroup = function() return false end,
    LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end }),
    RAID_CLASS_COLORS = setmetatable({}, { __index = function()
        return { WrapTextInColorCode = function(_, text) return text end }
    end }),
    Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = MAX_ACCOUNT, MAX_CHARACTER_MACROS = MAX_CHARACTER } },
    GetLooseMacroIcons = function(t) t[#t + 1] = 136243 end,
    GetLooseMacroItemIcons = NOTHING,
    GetMacroIcons = function(t) t[#t + 1] = 134400; t[#t + 1] = 135846 end,
    GetMacroItemIcons = NOTHING,
    GetMacroBody = function() return nil end,
    GetInventoryItemID = function() return 19949 end,
    NUM_BAG_SLOTS = 0,
    C_Container = { GetContainerNumSlots = function() return 0 end },
    C_Item = { GetItemCount = function(id) return id == 5509 and 1 or 0 end, GetItemIconByID = function() return 133939 end,
        GetItemNameByID = function(id) return "Item " .. id end, GetItemSpell = NOTHING, GetItemInfo = NOTHING },
    C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function() return 135846 end },
    LibStub = function()
        return {
            Serialize = function(_, v) vault[1] = v; return "S" end,
            Deserialize = function() return true, vault[1] end,
            CompressDeflate = function(_, v) return v end, DecompressDeflate = function(_, v) return v end,
            EncodeForPrint = function(_, v) return v end, DecodeForPrint = function(_, v) return v end,
        }
    end,
}, { __index = _G })
for k, v in pairs(macroAPI) do env[k] = v end
env._G = env

Load({
    "Shared/Shared.lua", "Shared/Data/Forever.lua", "Shared/Style.lua", "Shared/Items.lua", "Shared/Places.lua",
    "Shared/Parts.lua", "Shared/Window.lua", "Shared/View.lua", "Shared/Kinds.lua",
    "NaowhForever_Macros/NaowhForever_MacroText.lua", "NaowhForever_Macros/NaowhForever_Macros.lua", "NaowhForever_Macros/NaowhForever_MacroWindow.lua",
}, env)

local function Window()
    for _, f in ipairs(frames) do
        if rawget(f, "positionKey") == "macroWindow" then return f end
    end
end
local function Shown(test)
    local out = {}
    for _, f in ipairs(frames) do
        if rawget(f, "shown") ~= false and test(f) then out[#out + 1] = f end
    end
    return out
end

-------------------------------------------------------------------------------
--  My Macros
-------------------------------------------------------------------------------
store.account[1] = { name = "Hearth", icon = 134400, body = "#showtooltip\n/use Hearthstone" }
store.character[1] = { name = "Sheep", icon = 134400, body = "#showtooltip Polymorph\n/cast [@focus,harm][] Polymorph" }

ns.OpenMacroWindow()
local window = Window()
check("Naowh's Forge is built by the kit", window and window.backdrop and window.switch)
check("its title is Naowh's Forge", window.title:GetText() == "Naowh's Forge")
check("the subtitle names the character and meters the slots", window.subtitle:GetText() == "Glyalith, MAGE"
    and window.meters[1].label:GetText() == "Account 1/120" and window.meters[2].label:GetText() == "MAGE 1/18")
check("a new macro waits in the editor", window.name:GetText() == "New Macro")

local rows = Shown(function(f) return rawget(f, "macro") ~= nil end)
check("both macros are listed", #rows == 2)
local sheepRow
for _, r in ipairs(rows) do if r.macro.name == "Sheep" then sheepRow = r end end
Click(sheepRow)
check("clicking one opens it", window.name:GetText() == "Sheep" and ns.MacroText.Strip(window.code:GetText()):find("Polymorph"))
sheepRow.scripts.OnDragStart(sheepRow)
check("dragging a row picks the macro up", picked == MAX_ACCOUNT + 1)

-- Edit and rename: the game re-sorts, the editor follows it.
window.name:SetText("Asheep")
window.code:SetText("#showtooltip Polymorph\n/stopcasting\n/cast [@focus,harm][] Polymorph")
-- The editor's buttons, in the order they are made: Save, Shorten, Export, Revert, To Library, Delete.
local editorButtons = {}
for _, f in ipairs(frames) do
    if rawget(f, "_onClick") and f.parent == window.editor then editorButtons[#editorButtons + 1] = f end
end
check("the editor has Save, Shorten, Export, Revert, To Library and Delete", #editorButtons == 6)
Click(editorButtons[1])
check("saving edits the game's macro", store.character[1].name == "Asheep"
    and store.character[1].body:find("/stopcasting", 1, true))
check("and says so", printed[#printed]:find("Saved Asheep", 1, true))

-- Shorten, Export.
window.code:SetText("/cast [ target=focus ] Polymorph ; Frostbolt")
Click(editorButtons[2])
check("Shorten rewrites it", ns.MacroText.Strip(window.code:GetText()) == "/cast [@focus] Polymorph;Frostbolt")
Click(editorButtons[3])
check("Export gives a share string", (account.lastCopy or ""):find("^!NFM1!"))

-- New macro on the account, then delete it.
local newButton
local importButton, exportAllButton
for _, f in ipairs(frames) do
    local tip = rawget(f, "tip")
    if tip == "New Macro" then newButton = f elseif tip == "Import" then importButton = f
    elseif tip == "Export" then exportAllButton = f end
end
Click(newButton)
check("New starts an empty macro", window.name:GetText() == "New Macro")
Click(window.editor.scopeAccount)
window.name:SetText("Mount")
window.code:SetText("#showtooltip\n/use Swift Brown Steed")
Click(editorButtons[1])
check("Create makes an account macro", #store.account == 2 and store.account[2].name == "Mount")
Click(editorButtons[6])
check("Delete removes it from the game", #store.account == 1)

-- Problems show on the right line.
window.code:SetText("#showtooltip\n/castsequnce Scorch, Fire Blast")
check("an unknown command is caught", window.editor.issueLines[1]:GetText():find("^L2", 1) ~= nil)

-- In the game, sizing the edit box fires its OnTextChanged, and the editor sizes it when the
-- text changes: at the same height it must leave it alone, or that runs every frame.
local sized = 0
window.code.SetHeight = function(f, h)
    f.h = h
    sized = sized + 1
    if sized < 50 then f.scripts.OnTextChanged(f, false) end
end
window.code:SetText("/cast Frostbolt")
check("sizing the code box does not draw it over and over", sized <= 2)
window.code.SetHeight = nil

-- The first draw can come while the page is 1 pixel wide, wrapping every line; once the scroll
-- frame has its width, the editor must draw again at it.
local measure, page = window.editor.measure, window.editor.page
measure.GetStringHeight = function() return page:GetWidth() < 100 and 1000 or 16 end
page:SetWidth(1)
window.code:SetText("/cast Frostbolt")
local narrow = window.code.h
window.editor.scroll.scripts.OnSizeChanged(window.editor.scroll, 600)
check("the editor draws again once the page has its width", page.w == 600 and window.code.h < narrow)
measure.GetStringHeight = nil

-- One cursor, the game's own: the editor draws no caret of its own and runs nothing every frame.
check("one cursor: no caret of our own, nothing every frame", window.code.scripts.OnEditFocusGained == nil
    and window.code.scripts.OnUpdate == nil and window.code.scripts.OnCursorChanged ~= nil)

-- The inspector's panes.
for _, key in ipairs({ "conditions", "commands", "icons", "explain" }) do window.inspector.Show(key) end

-------------------------------------------------------------------------------
--  Smart Macros and Library
-------------------------------------------------------------------------------
window.switch.onPick("smart")
local cards = Shown(function(f) return rawget(f, "key") ~= nil and rawget(f, "uses") ~= nil end)
check("one card per Smart Macro", #cards == 8)
local health
for _, c in ipairs(cards) do if c.key == "health" then health = c end end
check("the health card says what it will use", health.uses[1].text.text == "Item 5509")
Click(health.toggle)
check("its switch turns the macro on", settings.health == true)

window.switch.onPick("lib")
check("the Library starts empty, with nothing but the class name", not window.lib.lead:IsShown()
    and #Shown(function(f) return rawget(f, "open") ~= nil and rawget(f, "add") ~= nil end) == 0)
packMacros.MAGE = { { name = "Naowh Sheep", body = "#showtooltip Polymorph\n/cast Polymorph", note = "Naowh's" } }
window.switch.onPick("mine")
window.switch.onPick("lib")
local libCards = Shown(function(f) return rawget(f, "open") ~= nil and rawget(f, "add") ~= nil end)
check("the pack's macros fill it", #libCards == 1 and window.lib.lead:IsShown())
Click(libCards[1].add)
check("Add makes a character macro", store.character[2] and store.character[2].name == "Naowh Sheep")

-------------------------------------------------------------------------------
--  Import
-------------------------------------------------------------------------------
Click(importButton)
lastPrompt(account.lastCopy)
check("a macro whose name you already have is not imported again", #store.character == 2
    and printed[#printed]:find("Added 0 of 1: 1 uses a name you already have", 1, true))
store.character[1].name = "Bsheep"
Click(importButton)
lastPrompt(account.lastCopy)
check("a share string imports as character macros", #store.character == 3)
lastPrompt("not a string")
check("anything else is turned away", printed[#printed]:find("not a Naowh Forever macro string", 1, true))

-------------------------------------------------------------------------------
--  The game moves macros: the editor follows the one it has open
-------------------------------------------------------------------------------
local function OpenNamed(name)
    window.switch.onPick("mine")
    for _, r in ipairs(Shown(function(f) return rawget(f, "macro") ~= nil end)) do
        if r.macro.name == name then return Click(r) end
    end
    error("no row for " .. name)
end

store.account = { { name = "Zed", icon = 136243, body = "/cast Zed" } }
OpenNamed("Zed")
macroAPI.CreateMacro("Abc", 134400, "/cast Abc", false)   -- a Smart Macro made meanwhile sorts before it
window.code:SetText("/cast Zed 2")
Click(editorButtons[1])
check("Save follows the open macro to its new slot", store.account[1].body == "/cast Abc"
    and store.account[2].name == "Zed" and store.account[2].body == "/cast Zed 2")
macroAPI.CreateMacro("Aaa", 134400, "/cast Aaa", false)
Click(editorButtons[6])
check("Delete removes the open macro, not whatever moved into its slot", #store.account == 2
    and store.account[1].name == "Aaa" and store.account[2].name == "Abc")

OpenNamed("Abc")
macroAPI.DeleteMacro(2)   -- removed outside the Forge
window.code:SetText("/cast Abc 2")
Click(editorButtons[1])
check("a macro gone from under it is not saved over another", #store.account == 1 and store.account[1].name == "Aaa"
    and printed[#printed]:find("changed or removed outside", 1, true))
Click(editorButtons[1])
check("Save then makes it again as a new macro", #store.account == 2 and store.account[2].body == "/cast Abc 2")

-- Saving text leaves a question mark icon alone, so it keeps following #showtooltip.
store.character = { { name = "Show", icon = 134400, body = "#showtooltip Polymorph\n/cast Polymorph" } }
OpenNamed("Show")
window.code:SetText("#showtooltip Polymorph\n/stopcasting\n/cast Polymorph")
Click(editorButtons[1])
check("the icon stays the question mark", store.character[1].icon == 134400
    and store.character[1].body:find("/stopcasting", 1, true))

-- Import: any number, as many as fit; a script in any case is called out.
local twenty = {}
for i = 1, 20 do twenty[i] = { name = "M" .. i, body = "/cast Spell " .. i } end
vault[1] = { v = 1, macros = twenty }
Click(importButton)
lastPrompt("!NFM1!S")
check("all 20 are read, as many added as fit", #store.character == 18
    and printed[#printed]:find("Added 17 of 20", 1, true))
store.character = {}
for _, body in ipairs({ "/RUN print(1)", "/dump GetTime()" }) do
    vault[1] = { v = 1, macros = { { name = "X", body = body } } }
    Click(importButton)
    lastPrompt("!NFM1!S")
    check("a script is called out: " .. body, account.lastConfirm:find("runs a script", 1, true))
end

window.switch.onPick("mine")
window.code:SetText(string.rep("/cast A\n", 12))
check("the text scrolls inside the editor box", window.code.parent == window.editor.page
    and window.editor.page.parent == window.editor.scroll and window.code.h == window.editor.page.h
    and window.editor.page.h > 12 * 17)

-------------------------------------------------------------------------------
--  Second review
-------------------------------------------------------------------------------
-- The list lights the open macro after the game re-sorts.
store.account = { { name = "Zed", icon = 136243, body = "/cast Zed" } }
OpenNamed("Zed")
macroAPI.CreateMacro("Abc", 134400, "/cast Abc", false)
window.switch.onPick("smart")
window.switch.onPick("mine")
local lit = Shown(function(f) return rawget(f, "macro") ~= nil and f.picked end)
check("the open macro's row is lit, not its old slot", #lit == 1 and lit[1].macro.name == "Zed")

-- Switching tabs keeps what you typed.
window.name:SetText("Zed Renamed")
window.code:SetText("/cast Zed 3")
window.switch.onPick("lib")
window.switch.onPick("mine")
check("a tab switch keeps an unsaved name and text", window.name:GetText() == "Zed Renamed"
    and ns.MacroText.Strip(window.code:GetText()) == "/cast Zed 3")

-- Export only what Import takes.
account.lastCopy = nil
window.code:SetText(string.rep("x", 300))
Click(editorButtons[3])
check("an oversize macro is not exported", account.lastCopy == nil and printed[#printed]:find("1 to 255", 1, true))

-- Library Add: the pack's checks.
store.character = {}
packMacros.MAGE = {
    { name = "Scripted", body = "/run print(1)\n/cast Polymorph" },
    { name = "A name far too long", body = "/cast Frostbolt" },
    { name = "Plain", body = "/cast Frost Nova" },
}
account.lastConfirm = nil
window.switch.onPick("lib")
local function LibCard(name)
    for _, c in ipairs(Shown(function(f) return rawget(f, "add") ~= nil end)) do
        if c.title.text == name then return c end
    end
end
Click(LibCard("Scripted").add)
check("a pack script needs the player's yes", (account.lastConfirm or ""):find("runs a script from a shared pack", 1, true))
Click(LibCard("A name far too long").add)
check("a name the game cannot hold is turned away", printed[#printed]:find("not a macro the game can hold", 1, true)
    and #store.character == 1)
window.switch.onPick("lib")
Click(LibCard("Plain").add)
window.switch.onPick("lib")
Click(LibCard("Plain").add)
check("adding it twice makes one macro", #store.character == 2 and printed[#printed]:find("already", 1, true))

-------------------------------------------------------------------------------
--  Third review
-------------------------------------------------------------------------------
-- A pack import refreshes the Library.
packMacros.MAGE = {}
window.switch.onPick("lib")
packMacros.MAGE = { { name = "Iconic", body = "/cast Blink", icon = 135736 } }
for _, fn in ipairs(applyHooks) do fn() end
check("a pack import fills the open Library", LibCard("Iconic") ~= nil and window.lib.lead:IsShown())

-- Pack macros keep the pack's icon.
store.character = {}
Click(LibCard("Iconic").add)
check("Add makes it with the pack's icon", store.character[1] and store.character[1].icon == 135736)
store.character = {}
window.switch.onPick("lib")
Click(LibCard("Iconic").open)
Click(editorButtons[1])
check("Create from the pack uses its icon too", store.character[1] and store.character[1].icon == 135736)

-- A name already in use is not taken twice.
Click(newButton)
window.name:SetText("Iconic")
window.code:SetText("/cast Frostbolt")
Click(editorButtons[1])
check("Save will not make a second macro of a name", #store.character == 1
    and printed[#printed]:find("already have a macro called Iconic", 1, true))
store.character = { { name = "Iconic", icon = 134400, body = "/cast Something Else" } }
packMacros.MAGE = { { name = "Iconic", body = "/cast Blink", icon = 135736 } }
window.switch.onPick("lib")
Click(LibCard("Iconic").add)
check("Library Add will not take a name in use", #store.character == 1
    and printed[#printed]:find("different macro called Iconic", 1, true))

-- Revert puts the name back as well.
OpenNamed("Iconic")
window.name:SetText("Typed")
window.code:SetText("/cast Typed")
Click(editorButtons[4])
check("Revert restores the name and the text", window.name:GetText() == "Iconic"
    and ns.MacroText.Strip(window.code:GetText()) == "/cast Something Else")

-- A name that is only stripped characters is turned away.
vault[1] = { v = 1, macros = { { name = "|", body = "/cast X" } } }
Click(importButton)
lastPrompt("!NFM1!S")
check("an import name stripped to nothing is turned away", #store.character == 1
    and printed[#printed]:find("not a Naowh Forever macro string", 1, true))

-- Nothing to export.
store.account, store.character = {}, {}
account.lastCopy = nil
Click(exportAllButton)
check("with no macros, Export says so", account.lastCopy == nil and printed[#printed]:find("no macros to export", 1, true))

-------------------------------------------------------------------------------
--  Last review
-------------------------------------------------------------------------------
-- Export everything: an empty macro still imports, the Smart Macros stay home.
store.account = { { name = "NF Health", icon = 134400, body = "/use item:5509" },
    { name = "Blank", icon = 134400, body = "" } }
store.character = { { name = "Mine", icon = 134400, body = "/cast Blink" } }
Click(exportAllButton)
local exported = vault[1].macros
check("Export leaves the Smart Macros out", #exported == 2 and exported[1].name == "Blank"
    and exported[2].name == "Mine")
store.account, store.character = {}, {}
Click(importButton)
lastPrompt(account.lastCopy)
check("an export with an empty macro imports whole", #store.character == 2
    and printed[#printed]:find("Added 2.", 1, true))

-- A macro opens at its first line.
OpenNamed("Mine")
check("an opened macro starts at the top", window.code.cursor == 0)

-------------------------------------------------------------------------------
--  Looks: colours in the code box, never in the game's macros
-------------------------------------------------------------------------------
store.account, store.character = {}, {}
Click(newButton)
window.name:SetText("Coloured")
window.code:SetText("#showtooltip\n/cast [@focus,harm] Polymorph")
check("the code box shows the macro in colour", window.code:GetText():find("|cff6cc4ff/cast|r", 1, true) ~= nil)
Click(editorButtons[1])
check("what is saved has no colour codes", store.character[1].body == "#showtooltip\n/cast [@focus,harm] Polymorph")
window.code.cursor = nil
window.code:Insert("\n/stopcasting")
check("text put in is coloured too", window.code:GetText():find("|cff6cc4ff/stopcasting|r", 1, true) ~= nil
    and ns.MacroText.Strip(window.code:GetText()):find("Polymorph\n/stopcasting$") ~= nil)

-------------------------------------------------------------------------------
--  Your own Library
-------------------------------------------------------------------------------
store.account, store.character = {}, {}
packMacros.MAGE = { { name = "Pack One", body = "/cast Arcane Missiles" } }
Click(newButton)
window.name:SetText("My Blink")
window.code:SetText("/cast Blink")
Click(editorButtons[5])
check("To Library keeps a copy under your class, not a game macro", account.libraryMacros.MAGE[1].name == "My Blink"
    and account.libraryMacros.MAGE[1].body == "/cast Blink" and #store.character == 0)
window.code:SetText("/cast [@cursor] Blink")
Click(editorButtons[5])
check("saving it again replaces it", #account.libraryMacros.MAGE == 1
    and account.libraryMacros.MAGE[1].body == "/cast [@cursor] Blink" and printed[#printed]:find("Updated", 1, true))
window.name:SetText("")
Click(editorButtons[5])
check("a macro with no name is turned away", #account.libraryMacros.MAGE == 1)

window.switch.onPick("lib")
local mine, packed = LibCard("My Blink"), LibCard("Pack One")
check("yours shows in the Library beside the pack's", mine and mine.tag.text == "YOURS" and mine.remove:IsShown()
    and packed and packed.tag.text:find("NAOWH", 1, true) and not packed.remove:IsShown())
Click(mine.open)
check("Open in Editor brings it to the editor", window.name:GetText() == "My Blink"
    and window.editor.where:GetText():find("From your Library", 1, true))

account.libraryMacros.MAGE[2] = { name = "My Script", body = "/run print(1)" }
account.lastConfirm = nil
window.switch.onPick("lib")
Click(LibCard("My Script").add)
check("your own script is added without a warning", account.lastConfirm == nil
    and store.character[1] and store.character[1].name == "My Script")

window.switch.onPick("lib")
Click(LibCard("My Blink").remove)
window.switch.onPick("lib")
check("Remove takes it out of the Library", #account.libraryMacros.MAGE == 1 and LibCard("My Blink") == nil
    and LibCard("My Script") ~= nil)

-- A pack script copied to the Library keeps the pack's warning.
store.character = {}
packMacros.MAGE = { { name = "Pack Run", body = "/run print(2)" } }
window.switch.onPick("lib")
Click(LibCard("Pack Run").open)
Click(editorButtons[5])
check("a pack macro's copy is marked as from the pack", account.libraryMacros.MAGE[2].pack == true)
account.lastConfirm = nil
packMacros.MAGE = {}
window.switch.onPick("lib")
Click(LibCard("Pack Run").add)
check("and its script still asks first", (account.lastConfirm or ""):find("runs a script from a shared pack", 1, true))

print(("test-macro-window: %d checks passed"):format(checks))
