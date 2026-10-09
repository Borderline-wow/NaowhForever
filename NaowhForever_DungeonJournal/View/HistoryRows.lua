-- HistoryRows.lua: a boss history's kill header (a badge, when, how long) and its small GROUP and LOOT labels.
local ns = _G.NaowhForever

local T = ns.THEME
local J = ns.Journal
local Kinds = J.View.Kinds
local St = J.Style
local BADGE, BADGE_ALPHA, BORDER_RGB, BAG = St.BADGE, St.BADGE_ALPHA, St.BORDER_RGB, St.BAG
local HEADING_SIZE, SMALL_SIZE, TINY_SIZE = St.HEADING_SIZE, St.SMALL_SIZE, St.TINY_SIZE

local HEAD_H = 34
local HEAD_ICON = 14
local HEAD_GAP = 8
local LABEL_H = 22
local LABEL_BOTTOM = 6

local TEXT_COUNT = "  "

Kinds.historyHead = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.badge = CreateFrame("Frame", nil, row)
        row.badge:SetSize(BADGE, BADGE)
        row.badge:SetPoint("LEFT")
        ns.Solid(row.badge, "BACKGROUND", T.bg, BADGE_ALPHA):SetAllPoints()
        ns.Border(row.badge, BORDER_RGB)
        row.number = ns.Font(row.badge, SMALL_SIZE, nil, T.fg)
        row.number:SetPoint("CENTER")
        row.bag = row.badge:CreateTexture(nil, "ARTWORK")
        row.bag:SetTexture(BAG)
        row.bag:SetSize(HEAD_ICON, HEAD_ICON)
        row.bag:SetPoint("CENTER")
        row.bag:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        row.right = ns.Font(row, SMALL_SIZE, nil, T.muted)
        row.right:SetPoint("RIGHT")
        row.left = ns.Font(row, HEADING_SIZE, nil, T.fg)
        row.left:SetPoint("LEFT", row.badge, "RIGHT", HEAD_GAP, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -HEAD_GAP, 0)
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        return row
    end,
    Set = function(row, number, left, right)
        row.number:SetText(number or "")
        row.bag:SetShown(number == nil)
        row.left:SetText(left)
        row.right:SetText(right or "")
        return HEAD_H
    end,
}

Kinds.label = {
    New = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = ns.Font(row, TINY_SIZE, nil, T.muted)
        row.text:SetPoint("BOTTOMLEFT", 0, LABEL_BOTTOM)
        return row
    end,
    Set = function(row, text, count)
        row.text:SetText(text:upper() .. (count and TEXT_COUNT .. count or ""))
        return LABEL_H
    end,
}
