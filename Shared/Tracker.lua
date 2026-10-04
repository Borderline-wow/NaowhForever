-------------------------------------------------------------------------------
--  Tracker.lua -- a tracker's small window (ns.Shared.Parts.TrackerPanel): a window's look,
--  a title to click and drag, an optional progress bar and dropdown under it, a scrolling
--  body, pooled rows, a cog for its settings, its place kept and Unlock Mode's mover. Also a
--  list row's bands (Parts.RowBands). Nothing is made until a module builds one.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts = Shared.Parts

local St = Shared.Style
local TRACKER_W, PANEL_PAD, PANEL_HEADER, ACTION = St.TRACKER_W, St.PANEL_PAD, St.PANEL_HEADER, St.ACTION
local SLOT_H, SLOT_GAP, SCROLL_GAP, CLOSE_ROOM = St.TRACKER_SLOT, St.TRACKER_GAP, St.TRACKER_SCROLL, St.CLOSE_ROOM
local ROW_LEFT, WAYPOINT_SLOT, ROW_RIGHT, TICK = St.ROW_LEFT, St.WAYPOINT_SLOT, St.ROW_RIGHT, St.ROW_TICK
local ROW_TOP, ROW_LINE_GAP, ROW_BOTTOM = St.ROW_TOP, St.ROW_LINE_GAP, St.ROW_BOTTOM
local HEAD_GAP = 4
local FOOTER = ACTION + 6
local TEXT_LEFT = ROW_LEFT + WAYPOINT_SLOT + 6
local TEXT_SIZE, SUB_SIZE = 13, 11
local CENTER = { "CENTER", "CENTER", 0, 0 }

-------------------------------------------------------------------------------
--  A list row's bands: every other one striped, lit on hover, a line under each
-------------------------------------------------------------------------------
function Parts.RowBands(row, dividerLeft)
    row.stripe = ns.Solid(row, "BACKGROUND", T.fg, St.STRIPE)
    row.stripe:SetAllPoints()
    row.hover = ns.Solid(row, "BACKGROUND", T.fg, St.ROW_HOVER)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.divider = ns.Solid(row, "BORDER", T.line, St.ROW_DIVIDER)
    row.divider:SetPoint("BOTTOMLEFT", dividerLeft, 0)
    row.divider:SetPoint("BOTTOMRIGHT")
    ns.Hairline(row.divider, "h")
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local Tracker = {}

function Tracker:Paint()
    local opacity = self.opts.opacity
    self.backdrop:Paint(opacity and opacity() or 1)
end

function Tracker:Place()
    local opts = self.opts
    self:ClearAllPoints()
    local point, relativePoint, x, y
    if opts.load then point, relativePoint, x, y = opts.load() end
    if type(point) ~= "string" then
        local place = opts.place or CENTER
        point, relativePoint, x, y = place[1], place[2], place[3], place[4]
    end
    self:SetPoint(point, UIParent, relativePoint, x, y)
end

function Tracker:ScrollGap()
    return self.scrolling and SCROLL_GAP or 0
end

function Tracker:Top()
    local top = PANEL_HEADER + HEAD_GAP
    if self.bar and self.bar:IsShown() then top = top + SLOT_H + SLOT_GAP end
    if self.picker and self.picker:IsShown() then top = top + SLOT_H + SLOT_GAP end
    return top
end

function Tracker:SetTrackerWidth(w)
    local inner = w - PANEL_PAD * 2
    self:SetWidth(w)
    if self.bar then self.bar:SetWidth(inner) end
    if self.picker then self.picker:SetWidth(inner) end
    self.scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD - self:ScrollGap(), PANEL_PAD + self.footer)
    self.body:SetWidth(inner - self:ScrollGap())
end

function Tracker:Fit(height)
    local top = self:Top()
    self.scroll:SetPoint("TOPLEFT", PANEL_PAD, -top)
    local full = top + height + self.footer + PANEL_PAD
    local maxHeight = self.opts.maxHeight and self.opts.maxHeight()
    self:SetHeight(maxHeight and math.min(maxHeight, full) or full)
    local scrolls = maxHeight ~= nil and full > maxHeight
    if scrolls == self.scrolling then return false end
    self.scrolling = scrolls
    return true
end

-------------------------------------------------------------------------------
--  Rows: a pin column (a tick there once done), the text and a line under it
-------------------------------------------------------------------------------
local function RowEnter(row)
    row.hover:Show()
    local tip = row.entry and row.entry.tip
    if not (tip and Parts.Tip(row, "ANCHOR_LEFT")) then return end
    tip(row)
    GameTooltip:Show()
end

local function RowLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

local function RowClick(row, button)
    local click = row.entry and row.entry.click
    if click then click(row, button) end
end

local function PinClick(pin)
    local entry = pin:GetParent().entry
    if entry and entry.waypoint then entry.waypoint(entry) end
end

function Tracker:Row(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, self.body)
    Parts.RowBands(row, ROW_LEFT)
    row.pin = Parts.IconButton(row, PinClick, St.PIN, 0, "Waypoint")
    row.pin.hint = "Click to mark it on your map."
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(St.CHECK)
    row.tick:SetSize(TICK, TICK)
    row.text = ns.Font(row, TEXT_SIZE, nil, T.fg)
    row.text:SetPoint("TOPLEFT", TEXT_LEFT, -ROW_TOP)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.sub = ns.Font(row, SUB_SIZE, nil, T.muted)
    row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -ROW_LINE_GAP)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClick)
    self.rows[i] = row
    return row
end

function Tracker:SetRows(entries)
    local body = self.body
    local width = body:GetWidth() - TEXT_LEFT - ROW_RIGHT
    local y, count = 0, #entries
    for i = 1, count do
        local entry = entries[i]
        local row = self:Row(i)
        row.entry = entry
        row:SetWidth(body:GetWidth())
        row.stripe:SetShown(i % 2 == 0)
        row.hover:Hide()
        local color = entry.color or T.fg
        row.text:SetTextColor(color.r, color.g, color.b)
        row.text:SetWidth(width)
        row.text:SetText(entry.text)
        local textH = math.ceil(row.text:GetStringHeight())
        local h = ROW_TOP + textH + ROW_BOTTOM
        row.sub:SetWidth(width)
        row.sub:SetText(entry.sub or "")
        row.sub:SetShown(entry.sub ~= nil)
        if entry.sub then h = h + ROW_LINE_GAP + math.ceil(row.sub:GetStringHeight()) end
        local line = -(ROW_TOP + textH / 2)
        row.pin:ClearAllPoints()
        row.pin:SetPoint("CENTER", row, "TOPLEFT", ROW_LEFT + WAYPOINT_SLOT / 2, line)
        row.pin:SetShown(entry.waypoint ~= nil and not entry.done)
        row.tick:ClearAllPoints()
        row.tick:SetPoint("CENTER", row, "TOPLEFT", ROW_LEFT + WAYPOINT_SLOT / 2, line)
        row.tick:SetShown(entry.done == true)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        row.divider:SetShown(i < count)
        row:Show()
        y = y + h
    end
    for i = count + 1, #self.rows do self.rows[i]:Hide() end
    body:SetHeight(math.max(y, 1))
    return y
end

-------------------------------------------------------------------------------
--  Building it
-------------------------------------------------------------------------------
local function DragStart(frame)
    frame:StartMoving()
end

local function SaveWhere(panel)
    local save = panel.opts.save
    if not save then return end
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    save(point, relativePoint, x, y)
end

local function DragStop(frame)
    frame:StopMovingOrSizing()
    SaveWhere(frame)
end

local function TitleDragStart(button)
    button:GetParent():StartMoving()
end

local function TitleDragStop(button)
    DragStop(button:GetParent())
end

local function TitleClick(button)
    local onTitle = button:GetParent().opts.onTitle
    if onTitle then onTitle() end
end

local function TitleEnter(button)
    local panel = button:GetParent()
    local opts = panel.opts
    panel.title:SetTextColor(T.accent.r, T.accent.g, T.accent.b)
    if not opts.titleTip then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(opts.titleTip)
    if opts.titleHint then GameTooltip:AddLine(opts.titleHint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b) end
    GameTooltip:Show()
end

local function TitleLeave(button)
    button:GetParent().title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Hide()
end

local function CogClick(button)
    local settings = button:GetParent().opts.settings
    ns.OpenOptionsWindow(settings.page)
    if settings.card then ns.UI.GoToSetting(settings.page, nil, settings.page .. ":" .. settings.card) end
end

function Parts.TrackerPanel(title, opts)
    local panel = Parts.Panel(title, true)
    Mixin(panel, Tracker)
    panel.opts, panel.rows, panel.scrolling = opts, {}, false
    panel.backdrop:Card(4, PANEL_HEADER, 4, 4)
    panel.title:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    panel.title:SetPoint("RIGHT", -CLOSE_ROOM - (opts.titleRoom or 0), 0)
    panel:SetFrameStrata("MEDIUM")
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", DragStart)
    panel:SetScript("OnDragStop", DragStop)
    if opts.onClose then panel.close:SetScript("OnClick", opts.onClose) end
    local titleBtn = CreateFrame("Button", nil, panel)
    titleBtn:SetPoint("TOPLEFT", panel.title, "TOPLEFT", -4, 4)
    titleBtn:SetPoint("BOTTOMRIGHT", panel.title, "BOTTOMRIGHT", 0, -4)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnClick", TitleClick)
    titleBtn:SetScript("OnDragStart", TitleDragStart)
    titleBtn:SetScript("OnDragStop", TitleDragStop)
    titleBtn:SetScript("OnEnter", TitleEnter)
    titleBtn:SetScript("OnLeave", TitleLeave)
    panel.titleButton = titleBtn
    local width = opts.width or TRACKER_W
    local under = -PANEL_HEADER - HEAD_GAP
    if opts.bar then
        local bar = CreateFrame("StatusBar", nil, panel)
        bar:SetSize(width - PANEL_PAD * 2, SLOT_H)
        bar:SetPoint("TOPLEFT", PANEL_PAD, under)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar.bg = ns.Solid(bar, "BACKGROUND", ns.ThemeTint("panel", St.TRACKER_BAR_RGB), 1)
        bar.bg:SetAllPoints()
        ns.Border(bar, St.BORDER_RGB)
        bar.text = ns.Font(bar, 12, "OUTLINE")
        bar.text:SetPoint("CENTER", 0, 0)
        panel.bar = bar
    end
    local picker = opts.picker
    if picker then
        panel.picker = ns.UI.BuildDropdownControl(panel, width - PANEL_PAD * 2, panel:GetFrameLevel() + 3,
            picker.values, picker.order, picker.get, picker.set)
        if panel.bar then
            panel.picker:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", 0, -SLOT_GAP)
        else
            panel.picker:SetPoint("TOPLEFT", PANEL_PAD, under)
        end
        panel.picker._menuHeight = picker.menuHeight
    end
    local settings = opts.settings
    panel.footer = settings and FOOTER or 0
    if settings then
        panel.settings = Parts.IconButton(panel, CogClick, ns.UI.COGS_ICON, 0, settings.tip)
        panel.settings:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD)
        panel.settings.hint = settings.hint
    end
    panel.scroll = ns.UI.SlimScroll(panel)
    panel.scroll:SetPoint("TOPLEFT", PANEL_PAD, -panel:Top())
    panel.body = opts.newBody and opts.newBody(panel.scroll) or CreateFrame("Frame", nil, panel.scroll)
    panel:SetTrackerWidth(width)
    panel.scroll:SetScrollChild(panel.body)
    if opts.mover then
        panel.mover = opts.mover(panel, function(pos)
            if opts.save then opts.save(pos.point, pos.relPoint, pos.x, pos.y) end
        end)
    end
    return panel
end
