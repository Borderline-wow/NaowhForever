-- BuffCell.lua: a Buffs & Consumables reminder icon, the same on screen and on the card's preview.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local St = A.Style
local Parts = ns.Shared.Parts

local GAP = St.BUFF_GAP
local CROP = St.BUFF_CROP
local COUNT_SIZE, COUNT_INSET = St.BUFF_COUNT_SIZE, St.BUFF_COUNT_INSET

local Cell = {}
A.BuffCell = Cell

function Cell.New(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    ns.Border(cell, St.BLACK)
    cell.count = ns.Font(cell, COUNT_SIZE, "OUTLINE")
    cell.count:SetPoint("BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)
    return cell
end

function Cell.Place(cell, parent, i, size, icon, count)
    cell:SetSize(size, size)
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", parent, "LEFT", (i - 1) * (size + GAP), 0)
    cell.icon:SetTexture(icon)
    Parts.HudFont(cell.count, S.Get("buffsFont"), S.Get("buffsFontSize"), S.Get("buffsOutline"))
    cell.count:SetText(count or "")
end

function Cell.Fit(parent, n, size)
    parent:SetSize(math.max(n, 1) * (size + GAP) - GAP, size)
end
