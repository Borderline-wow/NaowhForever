-- Look.lua: a gear set or trinket button's look, the same on the bars and their previews.
local ns = _G.NaowhForever

local T = ns.THEME
local G = ns.GearSets
local St = G.Style
local TRINKET_SLOTS = G.C.TRINKET_SLOTS

local ICON_CROP, ICON_INSET, EMPTY_ICON, BLACK = St.ICON_CROP, St.ICON_INSET, St.EMPTY_ICON, St.BLACK

local Look = {}
G.Look = Look

function Look.Dress(frame)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(icon, ICON_INSET)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    return icon, ns.Border(frame, BLACK)
end

function Look.SetButton(btn, set, i, size, gap)
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", (i - 1) * (size + gap), 0)
    btn.icon:SetTexture(set.icon)
    btn.icon:SetDesaturated(set.lost > 0)
    local edge = set.equipped and T.accent or BLACK
    btn.border:SetColor(edge.r, edge.g, edge.b, 1)
    btn:Show()
end

function Look.Fit(frame, add, count, size, gap)
    add:SetSize(size, size)
    add:ClearAllPoints()
    add:SetPoint("LEFT", count * (size + gap), 0)
    frame:SetSize((count + 1) * (size + gap), size)
end

function Look.Trinkets(frame, slots, size, gap)
    frame:SetSize(size * #TRINKET_SLOTS + gap, size)
    for i, button in ipairs(slots) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", (i - 1) * (size + gap), 0)
        button.icon:SetTexture(GetInventoryItemTexture("player", TRINKET_SLOTS[i]) or EMPTY_ICON)
    end
end
