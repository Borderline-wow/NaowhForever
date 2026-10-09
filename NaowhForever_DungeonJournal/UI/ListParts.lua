-- ListParts.lua: what the window's two lists share: their scroll, a row's bands and accent bar, a group's title (J.ListParts).
local ns = _G.NaowhForever

local T = ns.THEME
local J = ns.Journal
local Parts = ns.Shared.Parts
local St = J.Style
local LIST_W, LIST_ROW, GROUP_H, STRIPE = St.LIST_W, St.LIST_ROW, St.GROUP_H, St.STRIPE
local BAR, BAR_GAP, FOREVER_H, HOVER, TINY_SIZE = St.LIST_BAR, St.LIST_BAR_GAP, St.FOREVER_H, St.ITEM_HOVER, St.TINY_SIZE

local LIST_EDGE = 2
local SELECTED_BAR = 3
local MARK_GAP = 9
local SELECTED_BAND = 0.10
local ARROW_SIZE = 10
local ARROW_X, ARROW_Y = 3, 5
local LABEL_X, LABEL_Y = 16, 4
local PLAIN_LABEL_X = 3
local COUNT_GAP = 8
local OPEN_TURN = St.OPEN_TURN

local ListParts = {}
J.ListParts = ListParts

ListParts.ROW_W = LIST_W - BAR - BAR_GAP - LIST_EDGE
ListParts.SELECTED_BAR = SELECTED_BAR
ListParts.MARK_GAP = MARK_GAP
ListParts.NEW_LEFT = SELECTED_BAR + MARK_GAP
ListParts.NAME_LEFT = ListParts.NEW_LEFT + FOREVER_H * 2 + MARK_GAP
ListParts.ICON_DROP = 1
ListParts.GROUP_GAP = 4
ListParts.STRIPE_EVERY = J.C.STRIPE_EVERY

local ROW_W = ListParts.ROW_W

local function HeaderColor(header, color)
    header.label:SetTextColor(color.r, color.g, color.b)
    if header.arrow then header.arrow:SetVertexColor(color.r, color.g, color.b) end
end

local function HeaderEnter(header)
    HeaderColor(header, T.fg)
end

local function HeaderLeave(header)
    HeaderColor(header, T.accentSoft)
end

local function HeaderLine(header)
    local line = ns.Solid(header, "ARTWORK", T.line, 1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.Hairline(line, "h")
end

function ListParts.NewScroll(parent)
    local scroll = ns.UI.SlimScroll(parent, BAR, BAR_GAP)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMLEFT")
    scroll:SetWidth(ROW_W)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(ROW_W)
    scroll:SetScrollChild(content)
    return scroll, content
end

function ListParts.Row(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_W, LIST_ROW)
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, STRIPE)
    row.stripe:SetAllPoints()
    row.band = ns.Solid(row, "BACKGROUND", T.fg, 1)
    row.band:SetAllPoints()
    row.band:SetAlpha(0)
    row.bar = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(SELECTED_BAR)
    return row
end

function ListParts.ForeverMark(row)
    row.new = Parts.ForeverMark(row, FOREVER_H)
    row.new:SetPoint("LEFT", ListParts.NEW_LEFT, 0)
end

function ListParts.Hover(row)
    if not row.selected then row.band:SetAlpha(HOVER) end
end

function ListParts.Leave(row)
    if not row.selected then row.band:SetAlpha(0) end
    GameTooltip:Hide()
end

function ListParts.Select(row, chosen)
    row.selected = chosen
    row.bar:SetShown(chosen)
    row.band:SetAlpha(chosen and SELECTED_BAND or 0)
end

function ListParts.ShowRow(scroll, row)
    if not (row.top and row:IsShown()) then return end
    local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
    if row.top < offset then
        scroll.bar:SetValue(row.top)
    elseif row.top + LIST_ROW > offset + height then
        scroll.bar:SetValue(row.top + LIST_ROW - height)
    end
end

function ListParts.Header(parent, text, onClick)
    local header = CreateFrame(onClick and "Button" or "Frame", nil, parent)
    header:SetSize(ROW_W, GROUP_H)
    header.label = ns.Font(header, TINY_SIZE, nil, T.accentSoft)
    header.label:SetText(text:upper())
    if onClick then
        header.arrow = J.View.Parts.Arrow(header, ARROW_SIZE, T.accentSoft)
        header.arrow:SetPoint("BOTTOMLEFT", ARROW_X, ARROW_Y)
        header.label:SetPoint("BOTTOMLEFT", LABEL_X, LABEL_Y)
        header.count = ns.Font(header, TINY_SIZE, nil, T.muted)
        header.count:SetPoint("LEFT", header.label, "RIGHT", COUNT_GAP, 0)
        header:SetScript("OnClick", onClick)
        header:SetScript("OnEnter", HeaderEnter)
        header:SetScript("OnLeave", HeaderLeave)
    else
        header.label:SetPoint("BOTTOMLEFT", PLAIN_LABEL_X, LABEL_Y)
    end
    HeaderLine(header)
    return header
end

function ListParts.Fold(header, closed, count)
    header.arrow:SetRotation(closed and 0 or OPEN_TURN)
    header.count:SetText(closed and count or "")
end
