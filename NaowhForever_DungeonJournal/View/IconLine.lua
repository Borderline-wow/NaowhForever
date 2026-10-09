-- IconLine.lua: a line under a faction's standing: an icon in a black border, a line of text, a muted figure on the right.
local ns = _G.NaowhForever

local T = ns.THEME
local J = ns.Journal
local Kinds, Parts = J.View.Kinds, J.View.Parts
local Tip = Parts.Tip
local St = J.Style
local BORDER_RGB, TEXT_SIZE, SMALL_SIZE, TIP_X = St.BORDER_RGB, St.TEXT_SIZE, St.SMALL_SIZE, St.CURSOR_TIP_X
local CROP_LOW, CROP_HIGH = St.ICON_CROP, St.ICON_CROP_HIGH

local LINE_H, LINE_ICON = 26, 20
local TEXT_GAP, RIGHT_GAP = 8, 12

local function LineEnter(row)
    if not row.itemID then return end
    if not Tip(row, "ANCHOR_CURSOR_RIGHT", TIP_X, 0) then return end
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

Kinds.line = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        local frame = CreateFrame("Frame", nil, row)
        frame:SetSize(LINE_ICON, LINE_ICON)
        frame:SetPoint("LEFT", 0, 0)
        ns.Border(frame, BORDER_RGB)
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        ns.PixelInset(row.icon, 1)
        row.icon:SetTexCoord(CROP_LOW, CROP_HIGH, CROP_LOW, CROP_HIGH)
        row.right = ns.Font(row, SMALL_SIZE, nil, T.muted)
        row.right:SetPoint("RIGHT", 0, 0)
        row.right:SetJustifyH("RIGHT")
        row.text = ns.Font(row, TEXT_SIZE, nil, T.fg)
        row.text:SetPoint("LEFT", frame, "RIGHT", TEXT_GAP, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -RIGHT_GAP, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", LineEnter)
        row:SetScript("OnLeave", GameTooltip_Hide)
        return row
    end,
    Set = function(row, icon, text, right, itemID)
        row.icon:SetTexture(icon)
        row.text:SetText(text)
        row.right:SetText(right or "")
        row.itemID = itemID
        return LINE_H
    end,
}
