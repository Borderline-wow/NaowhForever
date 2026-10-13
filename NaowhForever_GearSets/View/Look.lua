-- Look.lua: a gear set or trinket button's look, the same on the bars and their previews.
local ns = _G.NaowhForever

local T = ns.THEME
local G = ns.GearSets
local St = G.Style
local ItemBar = ns.Shared.ItemBar
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

function Look.SetButton(btn, set, i, size, gap, grow)
    btn:SetSize(size, size)
    ItemBar.Place(btn, btn:GetParent(), i, size, gap, grow, ItemBar.ONE_LINE)
    btn.icon:SetTexture(set.icon)
    btn.icon:SetDesaturated(set.lost > 0)
    local edge = set.equipped and T.accent or BLACK
    btn.border:SetColor(edge.r, edge.g, edge.b, 1)
    btn:Show()
end

function Look.Fit(frame, add, count, size, gap, grow)
    add:SetSize(size, size)
    ItemBar.Place(add, frame, count + 1, size, gap, grow, ItemBar.ONE_LINE)
    local long = (count + 1) * (size + gap)
    if ItemBar.Vertical(grow) then
        frame:SetSize(size, long)
    else
        frame:SetSize(long, size)
    end
end

function Look.Trinkets(frame, slots, size, gap, grow)
    frame:SetSize(ItemBar.Size(#TRINKET_SLOTS, size, gap, grow, ItemBar.ONE_LINE))
    for i, button in ipairs(slots) do
        button:SetSize(size, size)
        ItemBar.Place(button, frame, i, size, gap, grow, ItemBar.ONE_LINE)
        button.icon:SetTexture(GetInventoryItemTexture("player", TRINKET_SLOTS[i]) or EMPTY_ICON)
    end
end
