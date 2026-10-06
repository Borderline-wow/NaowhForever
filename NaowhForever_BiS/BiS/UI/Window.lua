-------------------------------------------------------------------------------
--  UI/Window.lua -- the BiS List's own window (/nfbis, its minimap and top bar button, its
--  key binding, the Dungeon Journal's BiS stat and Open BiS List on its settings page),
--  built from the shared window parts. Down the left your spec's switch, the list you use,
--  the paperdoll and its key; on the right two pages: your list (your progress, a filter,
--  where to run next and a row per slot) and the quests that reward your picks; in the title
--  bar Import, Export, Stat Weights and the opacity. Made the first time it opens; opening it turns
--  the module on, turning it off closes it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local B = ns.BiS
local S = B.Settings
local L, R, A, Q = B.Lists, B.Rankings, B.Actions, B.Quests
local Parts = ns.Shared.Parts

local St = B.Style
local WIDTH, HEIGHT, HEADER, PAD, FOOTER = St.WINDOW_W, St.WINDOW_H, St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER
local SIDE_W, DOLL_W, SCROLLBAR, CONTENT_INSET = St.SIDE_W, St.DOLL_W, St.SCROLLBAR, St.CONTENT_INSET
local TAB_H, TAB_GAP, LIST_BUTTON_H = St.TAB_H, St.TAB_GAP, St.LIST_BUTTON_H
local BAR_GAP, BORDER_RGB = St.BAR_GAP, St.BORDER_RGB

local PAGE = "BiS List"
local SIDE_INNER = SIDE_W - 8
local CONTENT_LEFT = SIDE_W + PAD + 14
local DOLL_GAP = 12
local PAGES_W = 240

local window, view, doll
local scroll, questsView
local scrollLeft, scrollTop   -- where the pages' scroll starts, under the summary on the list
local page = "list"   -- the right side's page: "list" or "quests"

local function Opacity()
    return math.floor((S.Get("bisWindowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("bisWindowAlpha", value / 100)
end

-------------------------------------------------------------------------------
--  The left: your spec, your list, the paperdoll and its key
-------------------------------------------------------------------------------
-- "Fire Mage" -> "Fire".
local function SpecTabs()
    local items = {}
    for _, spec in ipairs(R.ClassSpecs()) do
        items[#items + 1] = { key = spec.key, label = spec.name:match("^(.-)%s+%S+$") or spec.name,
            tip = "Ranked for " .. spec.name .. ". Each spec keeps its own picks on this list." }
    end
    return items
end

local function ListEnter(button)
    button.edge:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
end

local function ListLeave(button)
    button.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
end

local function ListButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(SIDE_INNER, LIST_BUTTON_H)
    ns.Solid(button, "BACKGROUND", T.panel, 1):SetAllPoints()
    button.edge = ns.Border(button, BORDER_RGB)
    button.text = ns.Font(button, 12, nil, T.fg)
    button.text:SetPoint("LEFT", 10, 0)
    button.text:SetPoint("RIGHT", -24, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)
    local arrow = Parts.Arrow(button, 12, T.muted)
    arrow:SetRotation(-math.pi / 2)
    arrow:SetPoint("RIGHT", -8, 0)
    button:SetScript("OnClick", A.ListMenu)
    button:SetScript("OnEnter", ListEnter)
    button:SetScript("OnLeave", ListLeave)
    return button
end

-------------------------------------------------------------------------------
--  The footer's right: when the spec's rankings were last updated
-------------------------------------------------------------------------------
local function PaintUpdated(spec)
    local note = window.updated
    note.text:SetText(spec and spec.updated and "Rankings updated " .. spec.updated or "")
    note:SetWidth(math.max(1, math.ceil(note.text:GetStringWidth())))
end

-------------------------------------------------------------------------------
--  The right side's pages: your list, and the quests that reward your picks
-------------------------------------------------------------------------------
local PAGES = {
    { key = "list", label = "Your List", tip = "Your picks for every slot, and where to run next." },
    { key = "quests", label = "Quests", tip = "The quests that reward a pick you do not have yet." },
}
local questsLabels = {}   -- "Quests (5)", made once each

local function PaintPages(list)
    if not window.pages:IsShown() then return end
    local count = Q.Count(list)
    local label = questsLabels[count]
    if not label then
        label = count > 0 and "Quests (" .. count .. ")" or "Quests"
        questsLabels[count] = label
    end
    PAGES[2].label = label
    Parts.SetTabs(window.pages, PAGES)
    Parts.PaintTabs(window.pages, page)
end

local function DrawPage()
    if page == "quests" then questsView:Redraw() else view:DrawList() end
end

local function ShowPage(key)
    page = key
    if key == "quests" and not questsView then
        questsView = B.View.QuestsPage(scroll)
        questsView:SetWidth(view:GetWidth())
    end
    local shown = key == "quests" and questsView or view
    local hidden = shown == view and questsView or view
    if hidden then hidden:Hide() end
    shown:Show()
    -- The list's summary stays over it, out of the scroll; the quests have none.
    view.summary:SetShown(shown == view)
    scroll:SetPoint("TOPLEFT", scrollLeft, -(scrollTop + (shown == view and B.View.SUMMARY_H or 0)))
    scroll:SetScrollChild(shown)
    scroll:SetVerticalScroll(0)
    Parts.PaintTabs(window.pages, page)
    DrawPage()
end

-- A quest row for the quest, or one of its versions.
local function IsQuest(row, questID)
    local quest = row.quest
    if not quest then return false end
    if quest[1] == questID then return true end
    local alt = quest.alt
    if alt then
        for i = 1, #alt do
            if alt[i] == questID then return true end
        end
    end
    return false
end

-- The Quests page, scrolled to a quest; false when the window is shut or the page does not
-- list it (it is not for you, or you have its reward).
function B.ShowQuest(questID)
    if not (window and window:IsShown()) then return false end
    ShowPage("quests")
    local row = questsView:Find("quest", IsQuest, questID)
    if not row then return false end
    questsView:ScrollToRow(scroll, row)
    return true
end

-- Everything on the left and in the footer, from the list as the view drew it.
local function PaintSide()
    local list, spec = view.list, L.CurrentSpec()
    Parts.PaintTabs(window.specs, spec and spec.key)
    window.list.text:SetText((list.name:gsub("||", "|")))
    doll:Paint(list)
    PaintUpdated(spec)
    PaintPages(list)
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function DollHover(slot)
    view:Light(slot)
    if slot then view:ScrollTo(slot) end
end

local function DollClicked(slot, button)
    B.OpenPicker(slot, button)
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "bisWindow")
    window.backdrop:Card(6, HEADER + 6, WIDTH - SIDE_W - PAD - 6, FOOTER + 6)
    window.backdrop:Card(CONTENT_LEFT, HEADER + 6, 4, FOOTER + 6)

    -- Right to left: close, opacity, Stat Weights, Export and Import.
    local close = Parts.TitleBar(window, "BiS List",
        "Your best gear for every slot, where it drops, and where to go next.", PAGE)
    local opacityIcon
    opacityIcon, window.opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    local weights = Parts.BarButton(window, St.SCALES, "Stat Weights",
        "What each stat is worth to your spec: the upgrade percents and enchants come from them. Set your own.",
        A.StatWeights)
    weights:SetPoint("RIGHT", opacityIcon, "LEFT", -18, 0)
    local export = Parts.BarButton(window, St.EXPORT, "Export this list", "A string to share it with.", A.Export)
    export:SetPoint("RIGHT", weights, "LEFT", -BAR_GAP, 0)
    local import = Parts.BarButton(window, St.IMPORT, "Import a list",
        "Paste a shared list: it is added as a new list.", A.Import)
    import:SetPoint("RIGHT", export, "LEFT", -BAR_GAP, 0)

    Parts.FooterBrand(window, PAGE)
    window.updated = Parts.FooterNote(window, "")

    local y = HEADER + PAD
    window.specs = Parts.Tabs(window, SIDE_INNER, SpecTabs(), ns.SetBisSpec)
    window.specs:SetPoint("TOPLEFT", PAD, -y)
    window.specs:SetShown(#R.ClassSpecs() > 0)
    y = y + TAB_H + TAB_GAP
    window.list = ListButton(window)
    window.list:SetPoint("TOPLEFT", PAD, -y)
    y = y + LIST_BUTTON_H + DOLL_GAP
    doll = B.View.Paperdoll(window, DollHover, DollClicked)
    doll:SetPoint("TOPLEFT", PAD + (SIDE_INNER - DOLL_W) / 2, -y)

    local left = CONTENT_LEFT + CONTENT_INSET
    local top = HEADER + PAD + 4
    window.pages = Parts.Tabs(window, PAGES_W, PAGES, ShowPage)
    window.pages:SetPoint("TOPLEFT", left, -top)
    window.pages:SetShown(Q.Available())
    if Q.Available() then top = top + TAB_H + TAB_GAP + 8 end
    scrollLeft, scrollTop = left, top
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -(top + B.View.SUMMARY_H))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, FOOTER + PAD)
    view = B.View.New(scroll)
    view:SetWidth(WIDTH - left - SCROLLBAR - PAD - 8)
    scroll:SetScrollChild(view)
    -- The summary pinned over the list: the filter and the bar of your slots never scroll away.
    view.summary = B.View.Summary(window, view)
    view.summary:SetPoint("TOPLEFT", left, -top)
    view.summary:SetWidth(view:GetWidth())
    view.onDrawn = PaintSide
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
end

S.OnChange(function(key)
    if key == "bisWindowAlpha" then
        Parts.RepaintSidePanels()
        if window and window:IsShown() then Paint() end
    elseif key == "bis" and window and not B.On() then
        window:Hide()
    end
end)

hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        Paint()
        DrawPage()
    end
end)

-------------------------------------------------------------------------------
--  Handing the screen to the Dungeon Journal or the world map (Run Next) puts the window
--  away; it comes back when that one closes, unless it was opened again meanwhile.
-------------------------------------------------------------------------------
local awayFor   -- "journal" or "map" while put away for it
local mapWatched

local function Back(reason)
    if awayFor ~= reason then return end
    awayFor = nil
    if B.On() then ns.OpenBisWindow() end
end

function B.BackFromJournal() Back("journal") end
local function BackFromMap() Back("map") end

function B.StepAside(reason)
    if not (window and window:IsShown()) then return end
    window.stepAside = true
    window:Hide()
    window.stepAside = nil
    awayFor = reason
    if reason == "map" and not mapWatched and WorldMapFrame then
        mapWatched = true
        WorldMapFrame:HookScript("OnHide", BackFromMap)
    end
end

function ns.OpenBisWindow()
    awayFor = nil
    if not B.On() then
        S.Set("bis", true)
        ns.Print("BiS List turned on. Turn it off in its settings page.")
    end
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    DrawPage()
end

function ns.ToggleBisWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenBisWindow() end
end

function NaowhForever_ToggleBis()
    ns.ToggleBisWindow()
end
