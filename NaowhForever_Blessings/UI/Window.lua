-- Window.lua: the Blessings window (/nfbless): every paladin's blessing for each class, Auto-Assign and the preset.
local ns = _G.NaowhForever

local B = ns.Blessings
local Shared = ns.Shared
local Parts, St = Shared.Parts, Shared.Style

local WIDTH, HEIGHT = 720, 560
local HEADER, FOOTER, PAD = St.WINDOW_HEADER, St.WINDOW_FOOTER, St.WINDOW_PAD
local INSET, SCROLLBAR = St.CONTENT_INSET, St.SCROLLBAR
local CARD = 6
local SCROLL_GAP = 4
local TOP_Y = -6
local WINDOW_KEY = "blessingsWindow"
local TEXT_TITLE = ns.L("Blessings")
local TEXT_TITLE_TIP = ns.L("Paladin blessings by class and player, shared with the group's paladins.")

local window, scroll, content
local queued

local function Paint()
    window.backdrop:Paint(1)
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
    window = Parts.Window(WIDTH, HEIGHT, WINDOW_KEY)
    window.backdrop:Card(CARD, HEADER + CARD, CARD, FOOTER + CARD)
    Parts.TitleBar(window, TEXT_TITLE, TEXT_TITLE_TIP, B.PAGE)
    Parts.FooterBrand(window, B.PAGE)
    window.note = Parts.FooterNote(window, "")
    local left, top = CARD + INSET, HEADER + CARD + PAD
    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -(CARD + SCROLLBAR + SCROLL_GAP), FOOTER + CARD + PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - left - CARD - SCROLLBAR - INSET, 1)
    scroll:SetScrollChild(content)
end

function ns.OpenBlessingsWindow()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    Redraw()
end

function ns.ToggleBlessingsWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenBlessingsWindow() end
end

hooksecurefunc(ns.UI, "RefreshPage", RedrawSoon)
hooksecurefunc(ns, "Apply", RedrawSoon)
