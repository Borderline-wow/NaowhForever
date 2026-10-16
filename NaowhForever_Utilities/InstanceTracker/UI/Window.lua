-- Window.lua: this hour and the visit history, in Instance Tracker's own window.
local ns = _G.NaowhForever
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 860, 640
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR, TAB_H, TAB_GAP = St.CONTENT_INSET, St.SCROLLBAR, St.TAB_H, St.TAB_GAP
local PAGE = "Instance Tracker/Settings"
local CARD = 6
local TABS_W = 260
local TABS_DROP = 8
local TOP_Y = -6

local TABS = {
    { key = "hour", label = "This Hour", tip = "How many new instances this account has entered this hour." },
    { key = "history", label = "History", tip = "Each visit, with its time, coins, and experience." },
}
local BUILD = {
    hour = ns.BuildInstanceHourPage,
    history = ns.BuildInstanceHistoryPage,
}

local window, scroll
local contents = {}
local shown = "hour"
local queued

local function Note()
    local IT = ns.InstanceTracker
    if not IT then return "" end
    local count, cap = IT.Hour()
    return string.format(ns.L("%d of %d on this account"), count, cap)
end

local function Paint()
    window.backdrop:Paint(1)
    window.note.text:SetText(Note())
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
    Parts.PaintTabs(window.tabs, shown)
end

local function Redraw()
    queued = false
    if not (window and window:IsShown()) then return end
    for key, content in pairs(contents) do content:SetShown(key == shown) end
    local content = contents[shown]
    scroll:SetScrollChild(content)
    ns.UI.BeginReusableRows(content)
    local y = BUILD[shown](content, TOP_Y)
    content:SetHeight(math.abs(y) + PAD)
    Paint()
end

local function RedrawSoon()
    if queued or not (window and window:IsShown()) then return end
    queued = true
    C_Timer.After(0, Redraw)
end

local function PickTab(key)
    shown = key
    scroll:SetVerticalScroll(0)
    Redraw()
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "instanceTrackerWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    Parts.TitleBar(window, "Instance Tracker", ns.L("Visits, and this hour's instances."), PAGE)
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local left, top = CARD + INSET, HEADER + CARD + PAD + 4
    window.tabs = Parts.Tabs(window, TABS_W, TABS, PickTab)
    window.tabs:SetPoint("TOPLEFT", left, -top)
    top = top + TAB_H + TAB_GAP + TABS_DROP
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    for _, tab in ipairs(TABS) do
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(WIDTH - left - CARD - SCROLLBAR - INSET, 1)
        content:Hide()
        contents[tab.key] = content
    end
end

hooksecurefunc(ns.UI, "RefreshPage", RedrawSoon)
hooksecurefunc(ns, "Apply", RedrawSoon)

function ns.OpenInstanceTrackerWindow(tab)
    if not window then Build() end
    if tab and BUILD[tab] then shown = tab end
    window:SetScale(ns.UIScale())
    window:Show()
    Redraw()
end

function ns.ToggleInstanceTrackerWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenInstanceTrackerWindow() end
end
