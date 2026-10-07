-------------------------------------------------------------------------------
--  NaowhForever_SmartRemindersWindow.lua -- Smart Reminders' own window (/nfreminders, its
--  minimap and top bar button, Open Smart Reminders on its settings page): the cooldown presets
--  and the dungeon and raid boss pages, drawn by their own builders.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 1040, 720
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR, TAB_H, TAB_GAP = St.CONTENT_INSET, St.SCROLLBAR, St.TAB_H, St.TAB_GAP
local PAGE = "Smart Reminders/Settings"
local CARD = 6
local TABS_W = 420
local TABS_DROP = 4
local TABS_SPACE = 8
local BUILD_TOP = -6
local BUILD_SPARE = 30

local TABS = {
    { key = "presets", label = "Cooldown Presets", build = "BuildPresetsPage",
      tip = "Your defensives in the order they are called, in named presets for each spec." },
    { key = "dungeons", label = "Dungeon Bosses", build = "BuildBossTabPage", arg = false,
      tip = "This season's dungeon bosses, their abilities and the reminders you set for them." },
    { key = "raids", label = "Raid Bosses", build = "BuildBossTabPage", arg = true,
      tip = "This season's raid bosses, their abilities and the reminders you set for them." },
}
local TAB_BY_KEY = {}
for _, tab in ipairs(TABS) do TAB_BY_KEY[tab.key] = tab end

local window, scroll, content
local pages = {}
local shown = "presets"
local queued = false

local function Store() return ns.SmartReminderSettings end

local function Opacity()
    return math.floor(Store().Get("windowAlpha") * 100 + 0.5)
end

local function SetOpacity(value)
    Store().Set("windowAlpha", value / 100)
end

local function Draw(key)
    local wrapper = pages[key]
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, content)
        wrapper:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        wrapper:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        wrapper:SetHeight(1)
        wrapper._dirty = true
        pages[key] = wrapper
    end
    for other, page in pairs(pages) do page:SetShown(other == key) end
    if wrapper._dirty then
        wrapper._dirty = nil
        wrapper._pageKey = "Smart Reminders/" .. key
        UI.BeginReusableRows(wrapper)
        local tab = TAB_BY_KEY[key]
        local used = ns[tab.build](wrapper, BUILD_TOP, tab.arg)
        wrapper:SetHeight(math.abs(used) + BUILD_SPARE)
    end
    content:SetHeight(wrapper:GetHeight())
end

local function MarkDirty()
    for _, page in pairs(pages) do page._dirty = true end
end

local function Rebuild()
    queued = false
    if not (window and window:IsShown()) then return end
    local at = scroll:GetVerticalScroll()
    Draw(shown)
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(at, scroll:GetVerticalScrollRange()))
end

local function Pick(key)
    shown = key
    Parts.PaintTabs(window.tabs, shown)
    scroll:SetVerticalScroll(0)
    Draw(shown)
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "smartRemindersWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    local close = Parts.TitleBar(window, "Smart Reminders",
        "Calls out what to press when a boss ability is about to land.", PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)

    local left, top = CARD + INSET, HEADER + CARD + PAD + TABS_DROP
    window.tabs = Parts.Tabs(window, TABS_W, TABS, Pick)
    window.tabs:SetPoint("TOPLEFT", left, -top)
    top = top + TAB_H + TAB_GAP + TABS_SPACE
    scroll = UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - left - CARD - SCROLLBAR - INSET, 1)
    scroll:SetScrollChild(content)
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    Parts.PaintTabs(window.tabs, shown)
end

Store().OnChange(function(key)
    if key == "windowAlpha" and window and window:IsShown() then Paint() end
end)

hooksecurefunc(UI, "RefreshPage", function()
    if not window then return end
    MarkDirty()
    if window:IsShown() and not queued then
        queued = true
        C_Timer.After(0, Rebuild)
    end
end)

function ns.OpenSmartRemindersWindow()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Paint()
    MarkDirty()
    Draw(shown)
end

function ns.ToggleSmartRemindersWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenSmartRemindersWindow() end
end
