-- Window.lua: Naowh's Forge, shown as the My Macros, Smart Macros and Library tabs of the Macros page (/nfmacros).
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local S = M.Settings
local St = M.Style
local Store = M.Store
local Sharing = M.Sharing
local P = M.Parts
local F = M.Forge
local Parts = ns.Shared.Parts

local PAD, SECTION_H, LIST_W, INSPECTOR_W = St.PAD, St.SECTION_H, St.LIST_W, St.INSPECTOR_W
local SMALL_SIZE, NOTE_SIZE, TEXT_SIZE = St.SMALL_SIZE, St.NOTE_SIZE, St.TEXT_SIZE
local CARD_FILL, BLACK = St.CARD_FILL, St.BORDER_RGB
local GAP, BAR_H = 8, 30
local TOP = BAR_H + GAP
local SEARCH_W, MODE_W, TOOL_GAP, TOOL_W = 220, 170, 8, 80
local SCROLLBAR_ROOM, SCROLL_BOTTOM, LIST_TOP = St.SCROLLBAR_ROOM, 4, 4
local METER_W, METER_H, METER_GAP, METER_SPACE, METER_LABEL_GAP = 54, 3, 12, 14, 6
local SMART_TOP, SIDE_TOP, SIDE_GAP, SIDE_SPACING = 10, 12, 10, 3
local CLASS_W, CLASS_TOP = 200, 4
local LIB_TITLE_SIZE, LIB_LEAD_GAP, LIB_TOP = 22, 6, 64
local SAVE_W, NEW_W, TOOL_BUTTON_GAP = 120, 100, 6
local LIST_NEW_ROOM = St.BUTTON_H + 2 * PAD
local PAGE_KEYS = { mine = "Macros/My Macros", smart = "Macros/Smart Macros", lib = "Macros/Library" }

local TEXT_NEW_MACRO = ns.L("New Macro")
local TEXT_NEW_TIP = ns.L("Write a macro: a name and its text, kept in the Library under your class.")
local TEXT_SAVE_MACRO = ns.L("Save a Macro")
local TEXT_SAVE_TIP = ns.L("Keeps a copy of one of your game macros in the Library under your class, for every character of that class.")
local TEXT_EXPORT, TEXT_IMPORT = ns.L("Export"), ns.L("Import")
local TEXT_EXPORT_TIP = ns.L("Your game macros, not the Smart Macros, as one string to share.")
local TEXT_IMPORT_TIP = ns.L("Add macros someone shared with you.")
local TEXT_NOTHING_TO_EXPORT = ns.L("You have no macros to export yet.")
local TEXT_YOUR_MACROS = ns.L("Your macros")
local TEXT_SMART_NOTE = ns.L("They keep themselves up to date from your bags and gear")
local TEXT_SMART_HOW = ns.L("Each one is an account macro. Put it on a bar once and it keeps itself current: loot a "
    .. "better potion, conjure fresh food or pick up bandages and the macro is rewritten to use the best "
    .. "you carry.\n\nThe game does not let macros change mid-fight, so a change during combat waits "
    .. "until it ends.")
local TEXT_ACCOUNT = ns.L("Account ")
local TEXT_SEARCH = ns.L("Search your macros")
local TEXT_NEW_MINE_TIP = ns.L("Start a new macro in the editor.")

local MODES = {
    { key = "simple", label = "Simple", tip = "A few plain questions, and what one press does." },
    { key = "advanced", label = "Advanced", tip = "The macro text with colors, Build, Reads as and Simulate." },
}

local window

local function Count(n, max)
    local text = n .. "/" .. max
    return n >= max and ns.Color("accent", text) or text
end

local function PaintMeter(meter, n, max)
    meter.fill:SetWidth(math.max(1, METER_W * math.min(1, n / max)))
end

local function Subtitle()
    local accountCount, characterCount = GetNumMacros()
    local maxAccount, maxCharacter = Store.Limits()
    local _, class = UnitClass("player")
    local className = LOCALIZED_CLASS_NAMES_MALE[class] or class
    local classColor = RAID_CLASS_COLORS[class]
    window.subtitle:SetText(classColor:WrapTextInColorCode(UnitName("player") .. ", " .. className))
    local meters = window.meters
    PaintMeter(meters[1], accountCount, maxAccount)
    meters[1].label:SetText(TEXT_ACCOUNT .. Count(accountCount, maxAccount))
    PaintMeter(meters[2], characterCount, maxCharacter)
    meters[2].fill:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    meters[2].label:SetText(className .. " " .. Count(characterCount, maxCharacter))
end

local function Render()
    if not (window and window:IsVisible()) then return end
    Subtitle()
    if not F.draft then F.NewDraft() end
    if F.tab == "mine" then
        F.DrawList()
        F.RenderEditor()
    elseif F.tab == "smart" then
        F.DrawSmart()
    else
        F.DrawLibrary()
    end
end

local function PlaceMine()
    local simple = F.Simple()
    window.editorArea:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", simple and 0 or -(INSPECTOR_W + GAP), 0)
    window.inspectorArea:SetShown(not simple)
    Parts.PaintTabs(window.mode, simple and "simple" or "advanced")
end

local function SetTab(key)
    F.tab = key
    window.mine:SetShown(key == "mine")
    window.smartView:SetShown(key == "smart")
    window.libView:SetShown(key == "lib")
    window.search:SetShown(key == "mine")
    window.mode:SetShown(key == "mine")
    Render()
end

local function Card(f)
    ns.Solid(f, "BACKGROUND", T.fg, CARD_FILL):SetAllPoints()
    ns.Border(f, BLACK)
    return f
end

local function Area(parent, left, width, right)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", window, "TOPLEFT", left, -TOP)
    if width then
        f:SetPoint("BOTTOM", window, "BOTTOM")
        f:SetWidth(width)
    else
        f:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(right or 0), 0)
    end
    return Card(f)
end

local function RightArea(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -TOP)
    f:SetPoint("BOTTOM", window, "BOTTOM")
    f:SetWidth(width)
    return Card(f)
end

local function BodySized(scroll, w)
    scroll.body:SetWidth(w)
end

local function Scroller(parent, top)
    local scroll = UI.SlimScroll(parent)
    scroll:SetPoint("TOPLEFT", 0, -(top or 0))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, SCROLL_BOTTOM)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll.body = body
    scroll:SetScript("OnSizeChanged", BodySized)
    return scroll, body
end

local function View()
    local view = CreateFrame("Frame", nil, window)
    view:SetAllPoints()
    return view
end

local function Section(parent, title, note)
    local h = P.NewSection(parent)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    P.SetSection(h, title, nil, note)
    return h
end

local function ExportAll()
    local all, smart = {}, {}
    for _, m in ipairs(ns.MacroSmart.list) do smart[m.name] = true end
    for _, m in ipairs(Store.GameMacros()) do
        if not smart[m.name] then all[#all + 1] = m end
    end
    if #all == 0 then ns.Print(TEXT_NOTHING_TO_EXPORT) return end
    ns.ShowCopyBox(TEXT_YOUR_MACROS, Sharing.Export(all))
end

local function NewMacro()
    F.NewDraft()
    F.Render()
    if not F.Simple() then window.code:SetFocus() end
end

local function Search()
    if F.tab == "mine" then F.DrawList() end
end

local function SetMode(key)
    S.Set("forgeMode", key)
end

local function BuildMeters()
    window.subtitle = P.Text(window, NOTE_SIZE)
    window.subtitle:SetPoint("LEFT", window, "TOPLEFT", 0, -BAR_H / 2)
    window.meters = {}
    local after = window.subtitle
    for i = 1, 2 do
        local track = ns.Solid(window, "ARTWORK", T.line, 1)
        track:SetSize(METER_W, METER_H)
        track:SetPoint("LEFT", after, "RIGHT", i == 1 and METER_GAP or METER_SPACE, 0)
        local fill = ns.Solid(window, "OVERLAY", T.accent, 1)
        fill:SetPoint("TOPLEFT", track)
        fill:SetHeight(METER_H)
        local label = P.Text(window, SMALL_SIZE, T.muted)
        label:SetPoint("LEFT", track, "RIGHT", METER_LABEL_GAP, 0)
        window.meters[i] = { fill = fill, label = label }
        after = label
    end
end

local function BuildBar()
    local export = ns.Button(window, TEXT_EXPORT, TOOL_W, St.BUTTON_H, ExportAll)
    export:SetPoint("RIGHT", window, "TOPRIGHT", 0, -BAR_H / 2)
    ns.Tooltip(export, TEXT_EXPORT, TEXT_EXPORT_TIP)
    local import = ns.Button(window, TEXT_IMPORT, TOOL_W, St.BUTTON_H, Sharing.Prompt)
    import:SetPoint("RIGHT", export, "LEFT", -TOOL_GAP, 0)
    ns.Tooltip(import, TEXT_IMPORT, TEXT_IMPORT_TIP)
    window.search = Parts.SearchBox(window, TEXT_SEARCH, Search)
    window.search:SetSize(SEARCH_W, St.SEARCH_H)
    window.search:SetPoint("RIGHT", import, "LEFT", -TOOL_GAP, 0)
    window.mode = Parts.Tabs(window, MODE_W, MODES, SetMode)
    window.mode:SetPoint("RIGHT", window.search, "LEFT", -TOOL_GAP, 0)
end

local function BuildMine()
    window.mine = View()
    local listArea = Area(window.mine, 0, LIST_W)
    local list = { area = listArea }
    list.scroll, list.body = Scroller(listArea, LIST_TOP)
    list.scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, LIST_NEW_ROOM)
    list.rows = P.Pool(function() return F.NewMacroRow(list.body) end)
    list.sections = P.Pool(function() return P.NewSection(list.body) end)
    list.empty = P.Text(listArea, NOTE_SIZE, T.muted)
    list.empty:SetPoint("TOP", 0, -PAD)
    list.new = ns.AccentBorder(ns.Button(listArea, TEXT_NEW_MACRO, LIST_W - 2 * PAD, St.BUTTON_H, NewMacro))
    list.new:SetPoint("BOTTOM", 0, PAD)
    ns.Tooltip(list.new, TEXT_NEW_MACRO, TEXT_NEW_MINE_TIP)
    window.list = list
    window.editorArea = Area(window.mine, LIST_W + GAP, nil, INSPECTOR_W + GAP)
    F.BuildEditor(window.editorArea)
    window.inspectorArea = RightArea(window.mine, INSPECTOR_W)
    F.BuildInspector(window.inspectorArea)
end

local function BuildSmartSide(sideArea)
    Section(sideArea, ns.L("How They Work"))
    window.smartSummary = P.Text(sideArea, TEXT_SIZE)
    window.smartSummary:SetPoint("TOPLEFT", PAD, -(SECTION_H + SIDE_TOP))
    window.smartSummary:SetPoint("RIGHT", -PAD, 0)
    window.smartSummary:SetJustifyH("LEFT")
    local sideNote = P.Text(sideArea, NOTE_SIZE, T.muted)
    sideNote:SetPoint("TOPLEFT", window.smartSummary, "BOTTOMLEFT", 0, -SIDE_GAP)
    sideNote:SetPoint("RIGHT", -PAD, 0)
    sideNote:SetJustifyH("LEFT")
    sideNote:SetSpacing(SIDE_SPACING)
    sideNote:SetText(TEXT_SMART_HOW)
end

local function BuildSmart()
    window.smartView = View()
    local smartArea = Area(window.smartView, 0, nil, INSPECTOR_W + GAP)
    Section(smartArea, "Smart Macros", TEXT_SMART_NOTE)
    local smart = {}
    smart.scroll, smart.body = Scroller(smartArea, SECTION_H + SMART_TOP)
    smart.scroll:SetPoint("TOPLEFT", PAD, -(SECTION_H + SMART_TOP))
    smart.cards = P.Pool(function() return F.NewSmartCard(smart.body) end)
    window.smart = smart
    BuildSmartSide(RightArea(window.smartView, INSPECTOR_W))
end

local function BuildLibrary()
    window.libView = View()
    local classArea = Area(window.libView, 0, CLASS_W)
    local lib = {}
    Section(classArea, "Classes")
    lib.classScroll, lib.classBody = Scroller(classArea, SECTION_H + CLASS_TOP)
    lib.classes = P.Pool(function() return F.NewClassRow(lib.classBody) end)
    local libArea = Area(window.libView, CLASS_W + GAP)
    lib.title = ns.Font(libArea, LIB_TITLE_SIZE)
    lib.title:SetPoint("TOPLEFT", PAD, -PAD)
    lib.lead = P.Text(libArea, NOTE_SIZE, T.muted)
    lib.lead:SetPoint("TOPLEFT", lib.title, "BOTTOMLEFT", 0, -LIB_LEAD_GAP)
    lib.save = ns.Button(libArea, TEXT_SAVE_MACRO, SAVE_W, St.BUTTON_H, function() F.SavePicker(lib.save) end)
    lib.save:SetPoint("TOPRIGHT", libArea, "TOPRIGHT", -PAD, -PAD)
    ns.Tooltip(lib.save, TEXT_SAVE_MACRO, TEXT_SAVE_TIP)
    lib.new = ns.Button(libArea, TEXT_NEW_MACRO, NEW_W, St.BUTTON_H, function() F.NewMacro() end)
    lib.new:SetPoint("RIGHT", lib.save, "LEFT", -TOOL_BUTTON_GAP, 0)
    ns.Tooltip(lib.new, TEXT_NEW_MACRO, TEXT_NEW_TIP)
    lib.scroll, lib.body = Scroller(libArea, LIB_TOP)
    lib.scroll:SetPoint("TOPLEFT", PAD, -LIB_TOP)
    lib.cards = P.Pool(function() return F.NewLibCard(lib.body) end)
    window.lib = lib
end

local function OnShow(self)
    self:RegisterEvent("UPDATE_MACROS")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    Render()
end

local function OnHide(self)
    self:UnregisterAllEvents()
    if F.picker then F.picker:Hide() end
    if F.spellPopup then F.spellPopup:Hide() end
end

local function Build(parent)
    window = CreateFrame("Frame", nil, parent)
    F.window = window
    BuildMeters()
    BuildBar()
    BuildMine()
    BuildSmart()
    BuildLibrary()
    window:SetScript("OnShow", OnShow)
    window:SetScript("OnHide", OnHide)
    window:SetScript("OnEvent", Render)
    PlaceMine()
    window:Hide()
end

local function SettingChanged(key)
    if not window then return end
    if key == "forgeMode" then PlaceMine() end
    Render()
end

F.Render = Render
M.Redraw = Render

local function Host(page)
    local scroll = page:GetParent():GetParent()
    window:SetParent(page)
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", page, "TOPLEFT", 0, page.forgeY)
    window:SetPoint("RIGHT", page, "RIGHT")
    window:SetPoint("BOTTOM", scroll, "BOTTOM", 0, PAD)
    window:Show()
    SetTab(page.forgeView)
end

function ns.BuildForgePage(page, y, view)
    if not window then Build(page) end
    page.forgeView, page.forgeY = view, y
    if not page.forgeHooked then
        page.forgeHooked = true
        page:HookScript("OnShow", Host)
    end
    Host(page)
    return y
end

function ns.ForgeSearchTerms(add)
    for _, mode in ipairs(MODES) do add(mode.label, mode.tip) end
    add(TEXT_IMPORT, TEXT_IMPORT_TIP)
    add(TEXT_EXPORT, TEXT_EXPORT_TIP)
end

function ns.OpenMacroWindow(view)
    ns.OpenOptionsWindow(PAGE_KEYS[view or F.tab or "mine"])
end

hooksecurefunc(ns, "Apply", function() Render() end)
hooksecurefunc(S, "Set", SettingChanged)
