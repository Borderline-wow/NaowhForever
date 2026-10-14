-- Toolbar.lua: the HUD Editor's toolbar, and entering and leaving Unlock Mode.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local H = ns.HudEditor

local placement = H.placement
local GuidesOn, CanUndo, CanRedo, PaintMarks = H.GuidesOn, H.CanUndo, H.CanRedo, H.PaintMarks
local ShowPanel, CurrentLayout, LayoutMenu, LayoutEntries = H.ShowPanel, H.CurrentLayout, H.LayoutMenu, H.LayoutEntries

local C = H.C
local BAR_W, BAR_PAD, BAR_GAP = 352, 14, 10
local BAR_HEAD = 40
local BAR_LOGO = 20
local BAR_Y, BAR_LEVEL = -140, 510
local TITLE_SIZE = 14
local EXIT_W, EXIT_H = 96, 22
local SWITCH_W, SWITCH_H = 28, 14
local SWITCH_ROW = 22
local FOREVER_ROW_GAP = 4
local SWITCH_COLUMNS = 2
local SWITCH_COL = (BAR_W - 2 * BAR_PAD) / SWITCH_COLUMNS
local LABEL_GAP = 8
local OFF_ALPHA = 0.4
local HISTORY_W, ELEMENTS_W = 64, 84
local TOOLBAR_NAME = "NaowhForeverUnlockToolbar"
local TEXT_TITLE = ns.L("HUD Editor")
local TEXT_EXIT = ns.L("Exit Config")
local TEXT_UNDO, TEXT_UNDO_HELP = ns.L("Undo"), ns.L("Puts back the last change. Ctrl + Z.")
local TEXT_REDO, TEXT_REDO_HELP = ns.L("Redo"), ns.L("Makes the change again. Ctrl + Y.")
local TEXT_REVERT, TEXT_REVERT_HELP = ns.L("Revert"), ns.L("Puts back everything changed since the HUD Editor opened.")
local TEXT_ELEMENTS, TEXT_ELEMENTS_HELP = ns.L("Elements"), ns.L("Shows or hides the list of every element.")
local TEXT_GUIDES = ns.L("Guides")
local TEXT_GUIDES_HELP = ns.L("Lines a dragged element up with the others and the screen centre. Hold Alt to drag freely.")
local TEXT_LAYOUTS = ns.L("Layouts")
local TEXT_LAYOUTS_HELP = ns.L("Saves where everything is under a name, to load again later.")
local NO_LAYOUT_VALUES = {}

local configActive, reopenWindowOnExit = false, false
local configToolbar

local function BarRule(f, y)
    local rule = ns.Solid(f, "ARTWORK", ns.Shared.Style.BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -y)
    rule:SetPoint("TOPRIGHT", 0, -y)
    ns.Hairline(rule, "h")
end

local function SwitchRow()
    if ns.foreverSkin then return ns.Shared.Style.FOREVER_CHECK_SIZE + FOREVER_ROW_GAP end
    return SWITCH_ROW
end

local function BarSwitch(f, text, col, y, get, set)
    local switch = UI.BuildToggleControl(f, nil, get, set, SWITCH_W, SWITCH_H)
    switch:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_PAD + col * SWITCH_COL, -y)
    switch.label = ns.Font(f, C.LABEL_SIZE)
    switch.label:SetPoint("LEFT", switch, "RIGHT", LABEL_GAP, 0)
    switch.label:SetText(ns.L(text))
    return switch
end

local function Usable(button, on)
    if button._forever then return button:SetEnabled(on) end
    button:SetAlpha(on and 1 or OFF_ALPHA)
    button:EnableMouse(on)
end

local function PaintHistory()
    local f = configToolbar
    if not f then return end
    Usable(f._undo, CanUndo())
    Usable(f._redo, CanRedo())
    Usable(f._revert, CanUndo())
    local on = ns.UnlockModeSettings.Get("elementsPanel") ~= false
    if f._elements._forever then return ns.Shared.Parts.SetForeverLatched(f._elements, on) end
    local edge = on and T.accent or C.BLACK
    f._elements._rest = edge
    f._elements._border:SetColor(edge.r, edge.g, edge.b, 1)
end

local function PaintLayout()
    if configToolbar then configToolbar._layout.label:SetText(CurrentLayout() or ns.L(TEXT_LAYOUTS)) end
end

local function StartMoving(self) self:StartMoving() end
local function StopMoving(self) self:StopMovingOrSizing() end
local function Exit() ns.HideUnlockMode() end
local function LayoutName() return CurrentLayout() or ns.L(TEXT_LAYOUTS) end
local function Unused() end

local function ToolbarFrame()
    local St = ns.Shared.Style
    local f = CreateFrame("Frame", TOOLBAR_NAME, UIParent)
    f:SetWidth(BAR_W)
    f:SetPoint("TOP", UIParent, "TOP", 0, BAR_Y)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(BAR_LEVEL)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    ns.AllowOffscreen(f)
    ns.Shared.Parts.Backdrop(f):Paint(St.BACKDROP_ALPHA)
    ns.Border(f, St.BORDER_RGB)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", StartMoving)
    f:SetScript("OnDragStop", StopMoving)
    return f
end

local function ToolbarHead(f)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.Shared.Style.LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(BAR_LOGO, BAR_LOGO)
    logo:SetPoint("LEFT", f, "TOPLEFT", BAR_PAD, -BAR_HEAD / 2)
    local title = ns.Font(f, TITLE_SIZE)
    title:SetPoint("LEFT", logo, "RIGHT", LABEL_GAP, 0)
    title:SetText(TEXT_TITLE)
    local exit = ns.AccentBorder(ns.Button(f, TEXT_EXIT, EXIT_W, EXIT_H, Exit))
    exit:SetPoint("RIGHT", f, "TOPRIGHT", -BAR_PAD, -BAR_HEAD / 2)
    BarRule(f, BAR_HEAD)
end

local function ToggleElements()
    local on = ns.UnlockModeSettings.Get("elementsPanel") == false
    ns.UnlockModeSettings.Set("elementsPanel", on)
    ShowPanel(on)
    PaintHistory()
end

local function ToolButton(f, text, w, onClick)
    local btn = ns.Button(f, text, w, EXIT_H, onClick)
    if btn._forever then btn:SetMotionScriptsWhileDisabled(true) end
    return btn
end

local function HistoryButtons(f, y)
    f._undo = ToolButton(f, TEXT_UNDO, HISTORY_W, function() UI.UndoMove() end)
    f._undo:SetPoint("TOPLEFT", BAR_PAD, -y)
    ns.Tooltip(f._undo, TEXT_UNDO, TEXT_UNDO_HELP)
    f._redo = ToolButton(f, TEXT_REDO, HISTORY_W, function() UI.RedoMove() end)
    f._redo:SetPoint("LEFT", f._undo, "RIGHT", BAR_GAP / 2, 0)
    ns.Tooltip(f._redo, TEXT_REDO, TEXT_REDO_HELP)
    f._revert = ToolButton(f, TEXT_REVERT, HISTORY_W, function() UI.RevertMoves() end)
    f._revert:SetPoint("LEFT", f._redo, "RIGHT", BAR_GAP / 2, 0)
    ns.Tooltip(f._revert, TEXT_REVERT, TEXT_REVERT_HELP)
    f._elements = ToolButton(f, TEXT_ELEMENTS, ELEMENTS_W, ToggleElements)
    f._elements:SetPoint("TOPRIGHT", -BAR_PAD, -y)
    ns.Tooltip(f._elements, TEXT_ELEMENTS, TEXT_ELEMENTS_HELP)
    return y + EXIT_H + BAR_GAP
end

local function LayoutPicker(f)
    local picker, label = UI.BuildDropdownControl(f, SWITCH_COL, nil, NO_LAYOUT_VALUES, nil, LayoutName, Unused)
    picker:SetHeight(EXIT_H)
    picker.label = label
    picker._menuFill = LayoutEntries
    return picker
end

local function GuidesRow(f, y)
    f._guides = BarSwitch(f, TEXT_GUIDES, 0, y, GuidesOn, function(v) ns.UnlockModeSettings.Set("guides", v) end)
    ns.Tooltip(f._guides, TEXT_GUIDES, TEXT_GUIDES_HELP)
    if ns.foreverSkin then
        f._layout = LayoutPicker(f)
    else
        f._layout = ns.Button(f, TEXT_LAYOUTS, SWITCH_COL, EXIT_H, function() LayoutMenu(f._layout) end)
    end
    local rowH = math.max(f._guides:GetHeight(), SWITCH_H)
    f._layout:SetPoint("TOPRIGHT", -BAR_PAD, -(y + (rowH - EXIT_H) / 2))
    ns.Tooltip(f._layout, TEXT_LAYOUTS, TEXT_LAYOUTS_HELP)
    return y + math.max(rowH, SwitchRow())
end

local function BuildConfigToolbar()
    if configToolbar then return configToolbar end
    local f = ToolbarFrame()
    local top = BAR_GAP
    if ns.foreverSkin then
        ns.Shared.Parts.ForeverFrame(f, { title = TEXT_TITLE, bare = true, onClose = Exit })
    else
        ToolbarHead(f)
        top = BAR_HEAD + BAR_GAP
    end
    local y = HistoryButtons(f, top)
    y = GuidesRow(f, y)
    f:SetHeight(y)
    configToolbar = f
    return f
end

function ns.ShowUnlockMode()
    local reopen = ns.StashOptionsWindow and ns.StashOptionsWindow() or false
    configActive = true
    UI.BeginMoverMode()
    reopenWindowOnExit = reopen
    local f = BuildConfigToolbar()
    f._guides._refreshValue()
    PaintHistory()
    PaintLayout()
    ShowPanel(ns.UnlockModeSettings.Get("elementsPanel") ~= false)
    for _, item in ipairs(placement.items) do PaintMarks(item) end
    f:Show()
    ns.SetAnchorGridShown(true)
end

function ns.HideUnlockMode(windowClosing)
    configActive = false
    UI.EndMoverMode()
    ns.SetAnchorGridShown(false)
    if configToolbar then configToolbar:Hide() end
    ShowPanel(false)
    if reopenWindowOnExit then
        reopenWindowOnExit = false
        if not windowClosing and ns.OpenOptionsWindow then ns.OpenOptionsWindow() end
    end
end

function ns.IsUnlockModeActive()
    return configActive
end

H.PaintHistory, H.PaintLayout = PaintHistory, PaintLayout
