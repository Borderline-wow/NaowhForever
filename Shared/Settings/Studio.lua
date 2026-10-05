-------------------------------------------------------------------------------
--  Studio.lua -- a settings card's live preview: a stage and the moments it can be seen in,
--  painted by the module's own drawing code. A moment with `needs` (a setting's key, or a
--  function) only has its tab while that is on. Used by every settings card with a preview.
--  Settings.EditZone makes a part of a preview editable: drag, wheel, click and right-click.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Settings, Parts = Shared.Settings, Shared.Parts

local St = Shared.Style
local BORDER_RGB = St.BORDER_RGB

local PAD = 14
local TOP = 12
local TABS_MARGIN = 24
local TABS_GAP = 8
local DEFAULT_H = 150

local shownState = {}

local function Shown(card, state)
    local needs = state.needs
    if not needs then return true end
    if type(needs) == "function" then return needs() and true or false end
    return card.store.Get(needs) and true or false
end

local function StateOf(card, states)
    local key = shownState[card.uid]
    for i = 1, #states do
        if states[i].key == key then return key end
    end
    return states[1].key
end

local function TabPicked(row, key)
    shownState[row.card.uid] = key
    row:GetParent():QueueSettingsRedraw()
end

local function NewStudio(view)
    local row = CreateFrame("Frame", nil, view)
    row.stage = CreateFrame("Frame", nil, row)
    row.stage:SetPoint("BOTTOMLEFT", PAD, PAD)
    row.stage:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ns.Solid(row.stage, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(row.stage, BORDER_RGB)
    row.stage:SetClipsChildren(true)
    row.previews = {}
    row.states = {}
    return row
end

local function SetStudio(row, card)
    local studio = card.studio
    row.card = card
    local height = studio.height or DEFAULT_H
    if type(height) == "function" then height = height() end
    for owner, preview in pairs(row.previews) do preview:SetShown(owner == card) end
    local preview = row.previews[card]
    if not preview then
        preview = studio.new(row.stage)
        row.previews[card] = preview
    end
    preview:Show()
    local states = row.states
    wipe(states)
    for _, s in ipairs(studio.states) do
        if Shown(card, s) then states[#states + 1] = s end
    end
    if #states == 0 then states[1] = studio.states[1] end
    local state = StateOf(card, states)
    if #states > 1 and not row.tabs then
        row.tabs = Parts.Tabs(row, 1, states, function(key) TabPicked(row, key) end)
        row.tabs:SetPoint("TOPRIGHT", -PAD, -TOP)
    end
    if row.tabs then
        row.tabs:SetShown(#states > 1)
        if #states > 1 then
            Parts.FitTabs(row.tabs, states, TABS_MARGIN)
            Parts.PaintTabs(row.tabs, state)
        end
    end
    local tabsH = #states > 1 and (row.tabs:GetHeight() + TABS_GAP) or 0
    row.stage:SetHeight(height)
    studio.paint(preview, state)
    return TOP + tabsH + height + PAD
end

Settings.kinds.studio = { New = NewStudio, Set = SetStudio }

local EDGE_LINE = 2

function Settings.Snap(v, range)
    local low, high, step = range[1], range[2], range[3]
    v = low + math.floor((v - low) / step + 0.5) * step
    return math.max(low, math.min(high, v))
end

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
    if button ~= "LeftButton" or not zone.drag or zone.dragging then return end
    zone.fromX, zone.fromY = ZoneCursor(zone)
    zone.from = zone.drag.get()
    zone.value = zone.from
    zone.dragging = true
    zone:SetScript("OnUpdate", ZoneDrag)
end

local function ZoneUp(zone, button)
    if zone.dragging then
        if button == "LeftButton" then ZoneStop(zone, true) end
        return
    end
    if not zone:IsMouseOver() then return end
    if button == "RightButton" and zone.menu then
        GameTooltip:Hide()
        MenuUtil.CreateContextMenu(zone, zone.menu)
    elseif button == "LeftButton" and zone.click then
        zone.click(zone)
    end
end

local function ZoneWheel(zone, delta)
    if zone.wheel and not zone.dragging then zone.wheel(zone, delta) end
end

local function ZoneHidden(zone)
    ZoneStop(zone, false)
end

function Settings.EditZone(parent, opts)
    local zone = CreateFrame("Frame", nil, parent)
    zone.click, zone.menu, zone.wheel, zone.drag = opts.click, opts.menu, opts.wheel, opts.drag
    zone.enter, zone.leave = opts.enter, opts.leave
    if opts.wash then
        zone.mark = ns.Solid(zone, "OVERLAY", opts.wash == true and T.accent or opts.wash, St.TAB_FILL)
        zone.mark:SetAllPoints()
    elseif opts.edge then
        zone.mark = ns.Solid(zone, "OVERLAY", T.accent, 1)
        zone.mark:SetPoint("TOP")
        zone.mark:SetPoint("BOTTOM")
        zone.mark:SetWidth(EDGE_LINE)
    end
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
