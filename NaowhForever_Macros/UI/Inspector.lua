-- Inspector.lua: the Forge's Advanced side panel: Build, what the macro reads as line by line, Simulate, and the icon picker.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local M = ns.Macros
local St = M.Style
local Text = M.Text
local P = M.Parts
local F = M.Forge
local Parts = ns.Shared.Parts

local PAD, BLACK = St.PAD, St.BORDER_RGB
local SMALL_SIZE, TEXT_SIZE = St.SMALL_SIZE, St.TEXT_SIZE
local SCROLLBAR_ROOM = St.SCROLLBAR_ROOM
local WIDTH = St.INSPECTOR_W - 2 * PAD
local PANE_GAP = 12
local NUMBER_BOX, NUMBER_RISE, TEXT_INDENT, LINE_SPACING = 20, 1, 30, 2
local SAID_MIN_H, SAID_GAP = 18, 10
local ICON_COLS, ICON_ROWS, ICON_SIZE, ICON_GAP = 8, 6, 36, 6
local ICONS_PER_PAGE = ICON_COLS * ICON_ROWS
local PICKER_PAD, PICKER_HEAD, PICKER_DROP, PICKER_LEVEL = 10, 22, 6, 40
local PICKER_W = ICON_COLS * ICON_SIZE + (ICON_COLS - 1) * ICON_GAP + 2 * PICKER_PAD
local PICKER_H = ICON_ROWS * ICON_SIZE + (ICON_ROWS - 1) * ICON_GAP + 2 * PICKER_PAD + 2 * PICKER_HEAD
local STAR_SIZE, STAR_NUDGE, STAR = 12, 1, "*"

local TEXT_SAYS_NOTHING = ns.L("Write a line and this says what it does.")
local TEXT_ICON_HINT = ns.L("Right-click to star an icon. Scroll for more.")
local TEXT_PAGE = ns.L("Page %d of %d")

local TABS = {
    { key = "build", label = "Build" }, { key = "reads", label = "Reads as" }, { key = "sim", label = "Simulate" },
}

local inspector, panes, picker
local iconPage = 1
local iconList = {}

local function Show(key)
    Parts.PaintTabs(inspector.tabs, key)
    for k, pane in pairs(panes) do pane:SetShown(k == key) end
    inspector.shown = key
    F.DrawInspector(F.issues or {})
end

local function Pane()
    local pane = CreateFrame("Frame", nil, inspector)
    pane:SetPoint("TOPLEFT", inspector.tabs, "BOTTOMLEFT", 0, -PANE_GAP)
    pane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    pane:Hide()
    return pane
end

local function BodySized(scroll, w)
    scroll.body:SetWidth(w)
end

local function Scroller(pane)
    local scroll = UI.SlimScroll(pane)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_ROOM, 0)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll.body = body
    scroll:SetScript("OnSizeChanged", BodySized)
    return body
end

local function NewSaidRow(body)
    local row = CreateFrame("Frame", nil, body)
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(NUMBER_BOX, NUMBER_BOX)
    row.box:SetPoint("TOPLEFT", 0, NUMBER_RISE)
    ns.Solid(row.box, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(row.box, BLACK)
    row.number = P.Text(row.box, SMALL_SIZE, T.muted)
    row.number:SetPoint("CENTER")
    row.text = P.Text(row, TEXT_SIZE)
    row.text:SetPoint("TOPLEFT", TEXT_INDENT, 0)
    row.text:SetWidth(WIDTH - SCROLLBAR_ROOM - TEXT_INDENT)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.text:SetSpacing(LINE_SPACING)
    return row
end

local function BuildReads()
    panes.reads = Pane()
    local body = Scroller(panes.reads)
    panes.reads.body = body
    panes.reads.rows = P.Pool(function() return NewSaidRow(body) end)
end

local function BuildSim()
    panes.sim = Pane()
    local body = Scroller(panes.sim)
    panes.sim.body = body
    panes.sim.tester = F.NewTester(body)
    panes.sim.tester:SetPoint("TOPLEFT")
end

local function BuildBuild()
    panes.build = Pane()
    panes.build.view = F.BuildBuilder(panes.build)
end

local function SaidRow(pane, y)
    local row = pane.rows.Take()
    row:SetPoint("TOPLEFT", pane.body, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", pane.body, "TOPRIGHT", 0, -y)
    return row
end

local function DrawReads()
    local pane = panes.reads
    pane.rows.Release()
    local y = 0
    for _, said in ipairs(Text.Explain(F.draft.body)) do
        local row = SaidRow(pane, y)
        row.number:SetText(said.line)
        row.box:Show()
        row.text:SetText(said.text)
        local h = math.max(SAID_MIN_H, row.text:GetStringHeight())
        row:SetHeight(h)
        y = y + h + SAID_GAP
    end
    if y == 0 then
        local row = SaidRow(pane, y)
        row.box:Hide()
        row.text:SetText(ns.Color("muted", TEXT_SAYS_NOTHING))
        row:SetHeight(SAID_MIN_H)
        y = SAID_MIN_H
    end
    pane.body:SetHeight(y)
end

local function DrawSim()
    local pane = panes.sim
    pane.body:SetHeight(F.DrawTester(pane.tester, math.max(1, pane.body:GetWidth())))
end

function F.DrawInspector(issues)
    if not (inspector and F.draft) then return end
    local shown = inspector.shown
    if shown == "build" then
        F.DrawBuilderView(panes.build.view, issues)
    elseif shown == "reads" then
        DrawReads()
    elseif shown == "sim" then
        DrawSim()
    end
end

function F.BuildInspector(parent)
    inspector = CreateFrame("Frame", nil, parent)
    inspector:SetAllPoints()
    F.window.inspector = inspector
    panes = {}
    inspector.tabs = Parts.Tabs(inspector, WIDTH, TABS, Show)
    inspector.tabs:SetPoint("TOPLEFT", PAD, -PAD)
    BuildBuild()
    BuildReads()
    BuildSim()
    inspector.shown = "build"
    Parts.PaintTabs(inspector.tabs, "build")
    panes.build:Show()
end

local function Favorites()
    local account = ns.AccountSettings()
    account.macroFavoriteIcons = account.macroFavoriteIcons or {}
    return account.macroFavoriteIcons
end

local function IconList()
    wipe(iconList)
    local favorites = Favorites()
    for fileID in pairs(favorites) do iconList[#iconList + 1] = fileID end
    table.sort(iconList)
    for _, fileID in ipairs(ns.MacroIconList()) do
        if not favorites[fileID] then iconList[#iconList + 1] = fileID end
    end
    return iconList, favorites
end

local function DrawIcons()
    local list, favorites = IconList()
    local pages = math.max(1, math.ceil(#list / ICONS_PER_PAGE))
    iconPage = math.min(iconPage, pages)
    picker.pageLabel:SetText(TEXT_PAGE:format(iconPage, pages))
    for i, b in ipairs(picker.buttons) do
        local fileID = list[(iconPage - 1) * ICONS_PER_PAGE + i]
        b.fileID = fileID
        b:SetShown(fileID ~= nil)
        if fileID then
            b.icon:SetTexture(fileID)
            b.star:SetShown(favorites[fileID] == true)
        end
    end
end

local function PickIcon(fileID)
    local draft = F.draft
    draft.icon, draft.picked = fileID, true
    local index = F.Current()
    if index and not InCombatLockdown() then EditMacro(index, draft.savedName, draft.icon, draft.saved) end
    picker:Hide()
    F.Render()
end

local function IconClick(b, button)
    if not b.fileID then return end
    if button == "RightButton" then
        Favorites()[b.fileID] = not Favorites()[b.fileID] or nil
        DrawIcons()
        return
    end
    PickIcon(b.fileID)
end

local function IconWheel(_, delta)
    iconPage = math.max(1, iconPage - delta)
    DrawIcons()
end

local function NewIconButton(i)
    local b = CreateFrame("Button", nil, picker)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = P.Icon(b, ICON_SIZE - St.ICON_EDGES)
    b.icon.edge:SetPoint("TOPLEFT")
    b.star = P.Text(b, STAR_SIZE, St.TIP_RGB)
    b.star:SetPoint("TOPRIGHT", STAR_NUDGE, STAR_NUDGE)
    b.star:SetText(STAR)
    local col, row = (i - 1) % ICON_COLS, math.floor((i - 1) / ICON_COLS)
    b:SetPoint("TOPLEFT", PICKER_PAD + col * (ICON_SIZE + ICON_GAP),
        -(PICKER_PAD + PICKER_HEAD + row * (ICON_SIZE + ICON_GAP)))
    b:SetScript("OnClick", IconClick)
    return b
end

local function BuildPicker()
    picker = CreateFrame("Frame", nil, F.window)
    picker:SetSize(PICKER_W, PICKER_H)
    picker:SetFrameLevel(F.window:GetFrameLevel() + PICKER_LEVEL)
    picker:EnableMouse(true)
    ns.Solid(picker, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(picker, BLACK)
    picker.pageLabel = P.Text(picker, SMALL_SIZE, T.muted)
    picker.pageLabel:SetPoint("TOPLEFT", PICKER_PAD, -PICKER_PAD)
    local hint = P.Text(picker, SMALL_SIZE, T.muted)
    hint:SetPoint("BOTTOMLEFT", PICKER_PAD, PICKER_PAD)
    hint:SetText(TEXT_ICON_HINT)
    picker.buttons = {}
    for i = 1, ICONS_PER_PAGE do picker.buttons[i] = NewIconButton(i) end
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", IconWheel)
    picker:Hide()
    F.picker = picker
end

function F.OpenIconPicker(owner)
    if not picker then BuildPicker() end
    if picker:IsShown() then picker:Hide() return end
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -PICKER_DROP)
    DrawIcons()
    picker:Show()
end
