-- Widgets.lua: the game's top-centre display (battleground scores, capture bars) moved below a Top Bar left in its way, and back (ns.TopBar.Widgets).
local ns = _G.NaowhForever

local TB = ns.TopBar

local WIDGETS_Y, WIDGETS_GAP, WIDGETS_ROOM = -15, 4, 60
local CENTRE = 2
local ROUND = TB.C.ROUND

local widgetsAt

local function ScreenBottom(frame)
    local bottom = frame:GetBottom()
    return bottom and bottom * frame:GetEffectiveScale()
end

local function AtGameSpot(widgets)
    local point, relative, relativePoint, x, y = widgets:GetPoint(1)
    local anchored = widgets:GetNumPoints() == 1 and point == "TOP" and relativePoint == "TOP" and x == 0
        and (relative == nil or relative == UIParent)
    return anchored and (y == WIDGETS_Y or y == widgetsAt), y
end

local function Below(bar, widgets)
    if not (bar and bar:IsShown()) then return end
    local scale, ws = bar:GetEffectiveScale(), widgets:GetEffectiveScale()
    local top = UIParent:GetTop() * UIParent:GetEffectiveScale()
    local centre = UIParent:GetRight() * UIParent:GetEffectiveScale() / CENTRE
    local home = top + WIDGETS_Y * ws
    local left, right, barTop, bottom = bar:GetLeft(), bar:GetRight(), bar:GetTop(), ScreenBottom(bar)
    if bar.sys:IsShown() then bottom = math.min(bottom, ScreenBottom(bar.sys) or bottom) end
    if left and left * scale < centre and right * scale > centre and bottom < home
        and barTop * scale > home - WIDGETS_ROOM * ws then
        return math.floor((bottom - top) / ws - WIDGETS_GAP + ROUND)
    end
end

local Widgets = {}
TB.Widgets = Widgets

function Widgets.Place(bar)
    local widgets = UIWidgetTopCenterContainerFrame
    if not widgets then return end
    local ours, y = AtGameSpot(widgets)
    if not ours then
        widgetsAt = nil
        return
    end
    local below = Below(bar, widgets)
    if below == y or (not below and y == WIDGETS_Y) then return end
    widgets:ClearAllPoints()
    widgets:SetPoint("TOP", UIParent, "TOP", 0, below or WIDGETS_Y)
    widgetsAt = below
end
