-------------------------------------------------------------------------------
--  NaowhForever_BlessingsWindow.lua -- Blessings' own window (/nfbless, Assignments on a class
--  button's menu, Open Blessings on its settings page): every paladin's blessing for each
--  class, Auto-Assign and the preset, drawn by ns.BuildBlessingAssignmentsPage.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local B = ns.Blessings
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 720, 560
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR = St.CONTENT_INSET, St.SCROLLBAR
local PAGE = "Blessings/Settings"
local CARD = 6
local TOP_Y = -6

local window, scroll, content
local queued

local function Opacity()
    return math.floor((S.Get("blessWindowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("blessWindowAlpha", value / 100)
end

local function Paint()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    window.note.text:SetText(B.Headline())
    window.note:SetWidth(math.max(1, math.ceil(window.note.text:GetStringWidth())))
end

local function Redraw()
    queued = false
    if not (window and window:IsShown()) then return end
    ns.UI.BeginReusableRows(content)
    local y = ns.BuildBlessingAssignmentsPage(content, TOP_Y)
    content:SetHeight(math.abs(y) + PAD)
    Paint()
end

local function RedrawSoon()
    if queued or not (window and window:IsShown()) then return end
    queued = true
    C_Timer.After(0, Redraw)
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "blessingsWindow")
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    local close = Parts.TitleBar(window, "Blessings",
        "Paladin blessings by class and player, shared with the group's paladins.", PAGE)
    local _, opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.opacity = opacity
    Parts.FooterBrand(window, PAGE)
    window.note = Parts.FooterNote(window, "")

    local left, top = CARD + INSET, HEADER + CARD + PAD
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + 4), FOOTER + CARD + PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - left - CARD - SCROLLBAR - INSET, 1)
    scroll:SetScrollChild(content)
end

S.OnChange(function(key)
    if key == "blessWindowAlpha" and window and window:IsShown() then Paint() end
end)

hooksecurefunc(ns.UI, "RefreshPage", RedrawSoon)
hooksecurefunc(ns, "Apply", RedrawSoon)

function ns.OpenBlessingsWindow()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Redraw()
end

function ns.ToggleBlessingsWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenBlessingsWindow() end
end
