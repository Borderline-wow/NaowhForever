-- EditZone.lua: a part of a settings preview made editable by drag, wheel, click and right-click (Settings.EditZone, Settings.Snap).
local ns = _G.NaowhForever
local T = ns.THEME
local Settings = ns.Shared.Settings
local SS = Settings.Style

local EDGE_LINE = 2
local DRAG_BUTTON = "LeftButton"
local MENU_BUTTON = "RightButton"

local function ZoneCursor(zone)
    local x, y = GetCursorPosition()
    local scale = zone:GetEffectiveScale()
    return x / scale, y / scale
end

local function ZoneEnter(zone)
    if zone.mark then zone.mark:Show() end
    if zone.enter then zone.enter(zone) end
end

local function ZoneLeave(zone)
    if zone.mark and not zone.dragging then zone.mark:Hide() end
    if zone.leave then zone.leave(zone) end
end

local function ZoneDrag(zone)
    local x, y = ZoneCursor(zone)
    local d = zone.drag.axis == "y" and zone.fromY - y or x - zone.fromX
    local v = Settings.Snap(zone.from + d * (zone.drag.factor or 1), zone.drag.range)
    if v == zone.value then return end
    zone.value = v
    if zone.drag.live then zone.drag.live(v) end
end

local function ZoneStop(zone, commit)
    if not zone.dragging then return end
    zone.dragging = false
    zone:SetScript("OnUpdate", nil)
    if commit and zone.value ~= zone.from then
        zone.drag.set(zone.value)
    elseif zone.drag.live then
        zone.drag.live(zone.from)
    end
    if zone.mark and not zone:IsMouseOver() then zone.mark:Hide() end
end

local function ZoneDown(zone, button)
    if button ~= DRAG_BUTTON or not zone.drag or zone.dragging then return end
    zone.fromX, zone.fromY = ZoneCursor(zone)
    zone.from = zone.drag.get()
    zone.value = zone.from
    zone.dragging = true
    zone:SetScript("OnUpdate", ZoneDrag)
end

local function ZoneUp(zone, button)
    if zone.dragging then
        if button == DRAG_BUTTON then ZoneStop(zone, true) end
        return
    end
    if not zone:IsMouseOver() then return end
    if button == MENU_BUTTON and zone.menu then
        GameTooltip:Hide()
        MenuUtil.CreateContextMenu(zone, zone.menu)
    elseif button == DRAG_BUTTON and zone.click then
        zone.click(zone)
    end
end

local function ZoneWheel(zone, delta)
    if zone.wheel and not zone.dragging then zone.wheel(zone, delta) end
end

local function ZoneHidden(zone)
    ZoneStop(zone, false)
end

local function HoverMark(zone, opts)
    if opts.wash then
        local mark = ns.Solid(zone, "OVERLAY", opts.wash == true and T.accent or opts.wash, SS.TAB_FILL)
        mark:SetAllPoints()
        return mark
    end
    if not opts.edge then return nil end
    local mark = ns.Solid(zone, "OVERLAY", T.accent, 1)
    mark:SetPoint("TOP")
    mark:SetPoint("BOTTOM")
    mark:SetWidth(EDGE_LINE)
    return mark
end

function Settings.Snap(v, range)
    local low, high, step = range[1], range[2], range[3]
    v = low + math.floor((v - low) / step + 0.5) * step
    return math.max(low, math.min(high, v))
end

function Settings.EditZone(parent, opts)
    local zone = CreateFrame("Frame", nil, parent)
    zone.click, zone.menu, zone.wheel, zone.drag = opts.click, opts.menu, opts.wheel, opts.drag
    zone.enter, zone.leave = opts.enter, opts.leave
    zone.mark = HoverMark(zone, opts)
    if zone.mark then zone.mark:Hide() end
    zone:EnableMouse(true)
    zone:EnableMouseWheel(zone.wheel ~= nil)
    zone:SetScript("OnEnter", ZoneEnter)
    zone:SetScript("OnLeave", ZoneLeave)
    zone:SetScript("OnMouseDown", ZoneDown)
    zone:SetScript("OnMouseUp", ZoneUp)
    zone:SetScript("OnMouseWheel", ZoneWheel)
    zone:SetScript("OnHide", ZoneHidden)
    return zone
end
