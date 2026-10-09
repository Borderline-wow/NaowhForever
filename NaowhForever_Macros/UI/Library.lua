-- Library.lua: the Library tab of Naowh's Forge: by class, the macros you saved to it and those your profile pack brings.
local ns = _G.NaowhForever
local T = ns.THEME

local M = ns.Macros
local C = M.C
local St = M.Style
local Store = M.Store
local Commands = M.Commands
local P = M.Parts
local F = M.Forge

local QUESTION, LIMIT, NAME_MAX = C.QUESTION, C.LIMIT, C.NAME_MAX
local PAD, ROW_ICON, ICON_EDGES, BUTTON_H = St.PAD, St.ROW_ICON, St.ICON_EDGES, St.BUTTON_H
local BLACK, CARD_GAP, GOLD_CODE = St.BORDER_RGB, St.CARD_GAP, St.GOLD_CODE
local TAG_SIZE, SMALL_SIZE, NOTE_SIZE, CARD_TITLE_SIZE = St.TAG_SIZE, St.SMALL_SIZE, St.NOTE_SIZE, St.CARD_TITLE_SIZE
local CLASS_ROW_H, CLASS_NAME_SIZE = 34, 15
local CARD_H, CARD_COLS, CARD_PAD = 168, 2, St.MACRO_CARD_PAD
local TEXT_GAP, TAG_TOP, NOTE_GAP = St.ICON_TEXT_GAP, 16, 8
local CODE_BOTTOM, CODE_INSET_X, CODE_INSET_Y = 44, 8, 6
local BUTTON_BOTTOM, BUTTON_GAP = 10, St.BUTTON_GAP
local ADD_W, OPEN_W, REMOVE_W = 64, 110, 70
local DISABLED_ALPHA = 0.4

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local TEXT_TOO_BIG = "%s is not a macro the game can hold: a name is 1 to 16 bytes, its text 1 to 255."
local TEXT_IN_COMBAT = "Macros can be added once the fight is over."
local TEXT_NAME_TAKEN = "You already have a different macro called %s. Rename it to add this one."
local TEXT_FULL = "Character macros are full. Delete one to make room."
local TEXT_ADDED = "Added %s to this character. Drag it to a bar from My Macros."
local TEXT_HAVE = "%s is already one of this character's macros."
local TEXT_SCRIPT = "%s runs a script from a shared pack. Open it in the editor to read it first. Add it?"
local TEXT_REMOVE = "Remove %s from your Library? Macros already made from it stay."
local TEXT_COUNT = "%d macros"
local TEXT_YOURS = "YOURS"
local TEXT_NAOWH = GOLD_CODE .. "NAOWH|r"
local TEXT_MINE = "Macros for your class. Open one to change it first, or Add it as it is."
local TEXT_THEIRS = "Another class's macros, to read. Add them on a character of that class."

local libClass
local entries = {}

local function Fits(entry)
    return #entry.name >= 1 and #entry.name <= NAME_MAX and #entry.body >= 1 and #entry.body <= LIMIT
end

local function EntryIcon(entry)
    if entry.own then return entry.icon end
    return ns.MacroEntryIcon(entry)
end

local function Add(entry)
    if InCombatLockdown() then ns.Print(TEXT_IN_COMBAT) return end
    local index = Store.Find(entry.name, entry.body, false)
    local icon = EntryIcon(entry) or QUESTION
    if index then
        ns.Print(TEXT_HAVE:format(entry.name))
    else
        if GetMacroIndexByName(entry.name) > 0 then ns.Print(TEXT_NAME_TAKEN:format(entry.name)) return end
        if not Store.Room(false) then ns.Print(TEXT_FULL) return end
        CreateMacro(entry.name, icon, entry.body, true)
        index = Store.Find(entry.name, entry.body, false)
        ns.Print(TEXT_ADDED:format(entry.name))
    end
    F.Open({ index = index, account = false, name = entry.name, icon = icon, body = entry.body })
    F.Render()
end

local function AddFromPack(entry)
    if not Fits(entry) then
        ns.Print(TEXT_TOO_BIG:format(entry.name))
        return
    end
    if Commands.RunsScript(entry.body) and (entry.pack or not entry.own) then
        ns.Confirm(TEXT_SCRIPT:format(entry.name), function() Add(entry) end)
        return
    end
    Add(entry)
end

local function NewClassRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(CLASS_ROW_H)
    P.ListRow(b)
    b.name = ns.Font(b, CLASS_NAME_SIZE)
    b.name:SetPoint("LEFT", PAD, 0)
    b.count = P.Text(b, SMALL_SIZE, T.muted)
    b.count:SetPoint("RIGHT", -PAD, 0)
    return b
end

local function RemoveEntry(name)
    local saved = Store.OwnMacros(libClass)
    for k, e in ipairs(saved) do
        if e.name == name then table.remove(saved, k) break end
    end
    F.DrawLibrary()
end

local function NewLibCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(CARD_H)
    ns.Solid(c, "BACKGROUND", T.fg, St.WINDOW_CARD_FILL):SetAllPoints()
    ns.Border(c, BLACK)
    c.icon = P.Icon(c, ROW_ICON)
    c.icon.edge:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    c.title = P.Text(c, CARD_TITLE_SIZE)
    c.title:SetPoint("LEFT", c.icon.edge, "RIGHT", TEXT_GAP, 0)
    c.tag = P.Text(c, TAG_SIZE)
    c.tag:SetPoint("TOPRIGHT", -CARD_PAD, -TAG_TOP)
    c.note = P.Text(c, NOTE_SIZE, T.muted)
    c.note:SetPoint("TOPLEFT", c.icon.edge, "BOTTOMLEFT", 0, -NOTE_GAP)
    c.note:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_PAD + ROW_ICON + ICON_EDGES + NOTE_GAP))
    c.note:SetJustifyH("LEFT")
    local code = CreateFrame("Frame", nil, c)
    code:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -NOTE_GAP)
    code:SetPoint("RIGHT", -CARD_PAD, 0)
    code:SetPoint("BOTTOM", 0, CODE_BOTTOM)
    ns.Solid(code, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(code, BLACK)
    c.body = P.Text(code, SMALL_SIZE)
    c.body:SetPoint("TOPLEFT", CODE_INSET_X, -CODE_INSET_Y)
    c.body:SetPoint("BOTTOMRIGHT", -CODE_INSET_X, CODE_INSET_Y)
    c.body:SetJustifyH("LEFT")
    c.body:SetJustifyV("TOP")
    c.add = ns.AccentBorder(ns.Button(c, "Add", ADD_W, BUTTON_H))
    c.add:SetPoint("BOTTOMRIGHT", -CARD_PAD, BUTTON_BOTTOM)
    c.add._onClick = function() AddFromPack(c.entry) end
    c.open = ns.Button(c, "Open in Editor", OPEN_W, BUTTON_H)
    c.open:SetPoint("RIGHT", c.add, "LEFT", -BUTTON_GAP, 0)
    c.open._onClick = function()
        local entry = c.entry
        F.Open({ name = entry.name, body = entry.body, icon = c.shownIcon, account = false,
            source = entry.own and "library" or "pack" })
        F.SetTab("mine")
    end
    c.remove = ns.Button(c, "Remove", REMOVE_W, BUTTON_H)
    c.remove:SetPoint("BOTTOMLEFT", CARD_PAD, BUTTON_BOTTOM)
    c.remove._onClick = function()
        local name = c.entry.name
        ns.Confirm(TEXT_REMOVE:format(name), function() RemoveEntry(name) end)
    end
    return c
end

local function ClassName(class)
    return RAID_CLASS_COLORS[class]:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[class] or class)
end

local function ClassClick(b)
    libClass = b.class
    F.DrawLibrary()
end

local function DrawClasses(view)
    view.classes.Release()
    local y = 0
    for i, class in ipairs(CLASSES) do
        local b = view.classes.Take()
        b:SetPoint("TOPLEFT", view.classBody, "TOPLEFT", 0, y)
        b:SetPoint("TOPRIGHT", view.classBody, "TOPRIGHT", 0, y)
        b.name:SetText(ClassName(class))
        local n = #Store.OwnMacros(class) + #Store.PackMacros(class)
        b.count:SetText(n > 0 and TEXT_COUNT:format(n) or "")
        b.stripe:SetShown(i % 2 == 0)
        P.Pick(b, class == libClass)
        b.class = class
        b:SetScript("OnClick", ClassClick)
        y = y - CLASS_ROW_H
    end
end

local function Entries()
    wipe(entries)
    for _, entry in ipairs(Store.OwnMacros(libClass)) do
        entries[#entries + 1] = { name = entry.name, note = "", body = entry.body, icon = entry.icon, own = true,
            pack = entry.pack }
    end
    for _, entry in ipairs(Store.PackMacros(libClass)) do
        if type(entry.name) == "string" and type(entry.body) == "string" then
            entries[#entries + 1] = { name = entry.name, note = entry.note or "", body = entry.body, icon = entry.icon }
        end
    end
    return entries
end

local function PaintTag(c, own)
    if own then
        c.tag:SetText(TEXT_YOURS)
        P.Paint(c.tag, T.accent)
    else
        c.tag:SetText(TEXT_NAOWH)
        P.Paint(c.tag, T.fg)
    end
end

local function PaintCard(c, entry, mine)
    c.entry = entry
    c.shownIcon = EntryIcon(entry)
    c.icon:SetTexture(Store.ShownIcon(nil, c.shownIcon, entry.body))
    c.title:SetText(entry.name)
    PaintTag(c, entry.own)
    c.remove:SetShown(entry.own == true)
    c.note:SetText(entry.note or "")
    c.body:SetText(entry.body:gsub("|", "||"))
    c.add:SetEnabled(mine)
    c.add:SetAlpha(mine and 1 or DISABLED_ALPHA)
end

F.NewClassRow, F.NewLibCard = NewClassRow, NewLibCard

function F.DrawLibrary()
    local view = F.window.lib
    local _, myClass = UnitClass("player")
    libClass = libClass or myClass
    DrawClasses(view)
    view.cards.Release()
    local list = Entries()
    view.title:SetText(ClassName(libClass))
    view.lead:SetText(libClass == myClass and TEXT_MINE or TEXT_THEIRS)
    local w = math.floor((view.body:GetWidth() - CARD_GAP) / CARD_COLS)
    for i, entry in ipairs(list) do
        local c = view.cards.Take()
        local col, line = (i - 1) % CARD_COLS, math.floor((i - 1) / CARD_COLS)
        c:SetPoint("TOPLEFT", view.body, "TOPLEFT", col * (w + CARD_GAP), -line * (CARD_H + CARD_GAP))
        c:SetWidth(w)
        PaintCard(c, entry, libClass == myClass)
    end
    view.body:SetHeight(math.max(1, math.ceil(#list / CARD_COLS) * (CARD_H + CARD_GAP)))
    view.lead:SetShown(#list > 0)
end
