-------------------------------------------------------------------------------
--  NaowhForever_UnlockMode.lua -- Move Elements' movers. An element is placed CENTER on the
--  screen centre and saved there. Clicking one selects it; its tag holds its X and Y and what
--  can be done with it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local BLACK = { r = 0, g = 0, b = 0 }
-- A mover: the theme's background as dark glass over the element, an accent strip across its
-- top, and an edge in the line colour, muted grey under the mouse and the accent once selected.
local MOVER_FILL, MOVER_FILL_LIT = 0.55, 0.75
local MOVER_STRIP = 2          -- the accent strip's height
local NUDGE_FAR = 10           -- pixels a Shift + arrow moves

local placement = { active = false, items = {}, byLabel = {} }

-------------------------------------------------------------------------------
--  Geometry
-------------------------------------------------------------------------------
-- One physical pixel in UIParent units.
local function Pixel() return PixelUtil.GetPixelToUIUnitFactor() / UIParent:GetEffectiveScale() end

-- Edges in UIParent units, BOTTOMLEFT origin.
local function Bounds(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * ratio, r * ratio, t * ratio, b * ratio, ratio
end

-- The element as the player sees it: its mover's rect, which is the frame's unless a module laid
-- the mover over something else (a reminder's sample hangs below its anchor frame). The ratio is
-- the frame's.
local function Box(item)
    local fl, fr, ft, fb, ratio = Bounds(item.frame)
    if not fl then return end
    local hl, hr, ht, hb = Bounds(item.handle)
    if hl then return hl, hr, ht, hb, ratio end
    return fl, fr, ft, fb, ratio
end

-- The frame CENTER on the screen centre at (x, y) in its own units, on whole pixels.
local function Place(item, x, y)
    local es = item.frame:GetEffectiveScale()
    x, y = PixelUtil.GetNearestPixelSize(x, es), PixelUtil.GetNearestPixelSize(y, es)
    item.frame:ClearAllPoints()
    item.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    return x, y
end

-- Puts the element's centre (its Box) at (cx, cy) in UIParent units, and saves it.
local function MoveTo(item, cx, cy)
    local bl, br, bt, bb = Box(item)
    local fl, fr, ft, fb, ratio = Bounds(item.frame)
    if not (bl and fl) then return end
    local x = (cx - ((bl + br) - (fl + fr)) / 2 - UIParent:GetWidth() / 2) / ratio
    local y = (cy - ((bt + bb) - (ft + fb)) / 2 - UIParent:GetHeight() / 2) / ratio
    x, y = Place(item, x, y)
    item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
end

-- The element's centre from the screen's centre, in whole pixels, as the tag shows it.
local function Position(item)
    local l, r, t, b = Bounds(item.frame)
    if not l then return end
    local px = Pixel()
    return math.floor((l + r - UIParent:GetWidth()) / 2 / px + 0.5), math.floor((t + b - UIParent:GetHeight()) / 2 / px + 0.5)
end

-------------------------------------------------------------------------------
--  Moving: arrow keys, typed numbers, drags and Center, all ending in a saved CENTER spot.
-------------------------------------------------------------------------------
local Refresh, ShowTag

-- dx, dy in UIParent units.
local function Nudge(item, dx, dy)
    if InCombatLockdown() then return end
    local l, r, t, b = Box(item)
    if not l then return end
    MoveTo(item, (l + r) / 2 + dx, (t + b) / 2 + dy)
    Refresh(item)
end

local function DragUpdate()
    local item = placement.dragging
    if not item or InCombatLockdown() then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx = math.max(0, math.min(w, mx / scale + item.grabX))
    local cy = math.max(0, math.min(h, my / scale + item.grabY))
    local _, _, _, _, ratio = Bounds(item.frame)
    if not ratio then return end
    Place(item, (cx - item.boxX - w / 2) / ratio, (cy - item.boxY - h / 2) / ratio)
    ShowTag()
end

local function StopDrag(item)
    if not item or not item.dragging then return end
    if InCombatLockdown() and item.frame:IsProtected() then placement.pendingDrag = item; return end
    item.dragging = false
    item.dragged = true
    placement.dragging = nil
    placement.driver:SetScript("OnUpdate", nil)
    local l, r, t, b, ratio = Bounds(item.frame)
    if l and (math.abs(l - item.startL) > 0.5 or math.abs(t - item.startT) > 0.5) then
        local x, y = Place(item, ((l + r) / 2 - UIParent:GetWidth() / 2) / ratio, ((t + b) / 2 - UIParent:GetHeight() / 2) / ratio)
        item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    Refresh(item)
end

-- Across to the middle of the screen; its height stays.
local function CenterAcross(item)
    local x = Position(item)
    if x and x ~= 0 then Nudge(item, -x * Pixel(), 0) end
end

-- Out of Move Elements and onto the element's settings: the options window draws over the
-- movers, so the two cannot share the screen.
local function OpenSettings(item)
    ns.HideRaidReminderAnchorConfig()
    ns.OpenOptionsWindow(item.page)
    if item.feature then UI.GoToSetting(item.page, nil, item.feature) end
end

-------------------------------------------------------------------------------
--  The tag: just outside the selected mover, its X and Y in whole pixels (live while it moves,
--  typed to move it), Center, and Settings when the element has a page.
-------------------------------------------------------------------------------
local BOX_W, BOX_H = 46, 18
local TAG_PAD, TAG_GAP = 3, 4                    -- inside the tag's edge, from it to the mover
local LETTER_W, AXIS_GAP, PAIR_GAP = 8, 3, 8     -- an axis letter, from it to its box, between the parts
local CENTER_W, SETTINGS_W = 52, 62
local TAG_H = BOX_H + 2 * TAG_PAD
local TAG_LEVEL = 230                            -- over the movers

local function SetBox(box, v)
    if box:HasFocus() or box.value == v then return end
    box.value = v
    box:SetText(tostring(v))
end

-- Enter moves the element by what the typed number differs from where it is.
local function Typed(box)
    local v = tonumber(box:GetText())
    box:ClearFocus()
    local item = placement.selected
    if not (item and v) then return end
    local x, y = Position(item)
    if not x then return end
    local d = math.floor(v + 0.5) - (box.axis == "X" and x or y)
    if d == 0 then return end
    if box.axis == "X" then Nudge(item, d * Pixel(), 0) else Nudge(item, 0, d * Pixel()) end
end

local function Revert(box)
    box.border:SetColor(0, 0, 0, 1)
    box.value = nil
    ShowTag()
end

local function BuildTag()
    local tag = CreateFrame("Frame", nil, UIParent)
    tag:SetHeight(TAG_H)
    tag:SetFrameStrata("FULLSCREEN_DIALOG")
    tag:SetFrameLevel(TAG_LEVEL)
    tag:SetClampedToScreen(true)
    tag:EnableMouse(true)
    ns.Solid(tag, "BACKGROUND", T.panel, 0.98):SetAllPoints()
    ns.Border(tag, BLACK)
    local left
    for _, axis in ipairs({ "X", "Y" }) do
        local letter = ns.Font(tag, 11, nil, T.muted)
        letter:SetText(axis)
        letter:SetWidth(LETTER_W)
        if left then
            letter:SetPoint("LEFT", left, "RIGHT", PAIR_GAP, 0)
        else
            letter:SetPoint("LEFT", tag, "LEFT", TAG_PAD, 0)
        end
        local box = ns.NewEditBox(tag)
        box.axis = axis
        box:SetSize(BOX_W, BOX_H)
        box:SetPoint("LEFT", letter, "RIGHT", AXIS_GAP, 0)
        box:SetFont(ns.UIFontPath(), 12, "")
        box:SetJustifyH("CENTER")
        box:SetMaxLetters(6)
        box:SetScript("OnEnterPressed", Typed)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        box:SetScript("OnEditFocusGained", function() box.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
        box:SetScript("OnEditFocusLost", Revert)
        box:HookScript("OnLeave", function()
            if box:HasFocus() then box.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end
        end)
        tag[axis:lower()] = box
        left = box
    end
    tag.x:SetScript("OnTabPressed", function() tag.y:SetFocus() end)
    tag.y:SetScript("OnTabPressed", function() tag.x:SetFocus() end)

    tag.center = ns.Button(tag, "Center", CENTER_W, BOX_H, function()
        if tag.item then CenterAcross(tag.item) end
    end)
    tag.center:SetPoint("LEFT", left, "RIGHT", PAIR_GAP, 0)
    ns.Tooltip(tag.center, "Center", "Moves it to the middle of the screen, left to right.")
    tag.settings = ns.Button(tag, "Settings", SETTINGS_W, BOX_H, function()
        if tag.item then OpenSettings(tag.item) end
    end)
    tag.settings:SetPoint("LEFT", tag.center, "RIGHT", AXIS_GAP, 0)
    ns.Tooltip(tag.settings, "Settings", "Opens its settings and leaves Move Elements.")
    return tag
end

-- Below the mover, above it when the screen ends first.
function ShowTag()
    local item = placement.selected
    local x, y
    if item then x, y = Position(item) end
    local tag = placement.tag
    if not x then
        if tag then
            tag:Hide()
            tag.item = nil
        end
        return
    end
    if not tag then
        tag = BuildTag()
        placement.tag = tag
    end
    local _, _, _, bottom = Bounds(item.handle)
    local above = bottom ~= nil and bottom - TAG_GAP - TAG_H < 0
    if tag.item ~= item or tag.above ~= above then
        tag.item, tag.above = item, above
        tag.x.value, tag.y.value = nil, nil
        tag.settings:SetShown(item.page ~= nil)
        local w = 2 * (LETTER_W + AXIS_GAP + BOX_W) + 2 * PAIR_GAP + CENTER_W + 2 * TAG_PAD
        if item.page then w = w + AXIS_GAP + SETTINGS_W end
        tag:SetWidth(w)
        tag:ClearAllPoints()
        if above then
            tag:SetPoint("BOTTOM", item.handle, "TOP", 0, TAG_GAP)
        else
            tag:SetPoint("TOP", item.handle, "BOTTOM", 0, -TAG_GAP)
        end
    end
    tag:Show()
    SetBox(tag.x, x)
    SetBox(tag.y, y)
end

-------------------------------------------------------------------------------
--  Selection and the arrow keys
-------------------------------------------------------------------------------
-- The mover's edge and fill for its state (see MOVER_FILL).
function Refresh(item)
    if not item then return end
    local h = item.handle
    local picked = item.selected or item.dragging
    local lit = picked or item.hovered
    local edge = picked and T.accent or item.hovered and T.muted or T.line
    h._border:SetColor(edge.r, edge.g, edge.b, 1)
    h._fill:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, lit and MOVER_FILL_LIT or MOVER_FILL)
    h:SetFrameLevel(item.baseLevel + (lit and 100 or 0))
    if item == placement.selected then ShowTag() end
end

function UI.ClearMoverSelection()
    local item = placement.selected
    StopDrag(item)
    placement.selected = nil
    if item then
        item.selected = false
        Refresh(item)
    end
    ShowTag()
    if placement.keys and not InCombatLockdown() then placement.keys:SetPropagateKeyboardInput(true) end
end

function UI.RefreshMoverSelection()
    local item = placement.selected
    if not item then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    Refresh(item)
end

local function PlacementKey(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(true)
    if not placement.active or GetCurrentKeyBoardFocus() then return end
    if key == "ESCAPE" then
        if not placement.selected then return end
        UI.ClearMoverSelection()
        self:SetPropagateKeyboardInput(false)
        return
    end
    local item = placement.selected
    if not item or item.dragging then return end
    local dx = key == "LEFT" and -1 or key == "RIGHT" and 1 or 0
    local dy = key == "DOWN" and -1 or key == "UP" and 1 or 0
    if dx == 0 and dy == 0 then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    self:SetPropagateKeyboardInput(false)
    local step = Pixel() * (IsShiftKeyDown() and NUDGE_FAR or 1)
    Nudge(item, dx * step, dy * step)
end

function UI.BeginMoverMode()
    placement.active = true
    if not placement.keys then
        local keys = CreateFrame("Frame", nil, UIParent)
        placement.keys = keys
        keys:SetFrameStrata("FULLSCREEN_DIALOG")
        keys:SetFrameLevel(500)
        keys:SetAllPoints()
        keys:SetScript("OnKeyDown", PlacementKey)
        keys:SetScript("OnKeyUp", function(self)
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end)
        keys:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                UI.ClearMoverSelection()
                keys:Hide()
            else
                StopDrag(placement.pendingDrag)
                placement.pendingDrag = nil
                if placement.active then UI.BeginMoverMode() else keys:UnregisterAllEvents() end
            end
        end)
        placement.driver = CreateFrame("Frame")
    end
    if not InCombatLockdown() then
        placement.keys:EnableKeyboard(true)
        placement.keys:SetPropagateKeyboardInput(true)
    end
    UI.ClearMoverSelection()
    placement.keys:RegisterEvent("PLAYER_REGEN_DISABLED")
    placement.keys:RegisterEvent("PLAYER_REGEN_ENABLED")
    placement.keys:SetShown(not InCombatLockdown())
end

function UI.EndMoverMode()
    placement.active = false
    UI.ClearMoverSelection()
    if placement.keys then
        placement.keys:Hide()
        if not InCombatLockdown() then placement.keys:EnableKeyboard(false) end
        if not placement.pendingDrag then placement.keys:UnregisterAllEvents() end
    end
end

function UI.SelectMover(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item then return end
    if placement.selected ~= item then UI.ClearMoverSelection() end
    placement.selected = item
    item.selected = true
    Refresh(item)
end

function UI.StartMoverDrag(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item then return end
    UI.SelectMover(handle)
    local l, r, t, b = Box(item)
    local fl, fr, ft, fb = Bounds(item.frame)
    if not (l and fl) then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    item.grabX, item.grabY = (l + r) / 2 - mx / scale, (t + b) / 2 - my / scale
    item.boxX, item.boxY = (l + r - fl - fr) / 2, (t + b - ft - fb) / 2
    item.startL, item.startT = fl, ft
    item.dragging = true
    placement.dragging = item
    placement.driver:SetScript("OnUpdate", DragUpdate)
    Refresh(item)
end

function UI.StopMoverDrag(handle)
    StopDrag(handle._placement)
    UI.RefreshMoverSelection()
end

-------------------------------------------------------------------------------
--  Movers
-------------------------------------------------------------------------------
-- page: the options page that sets the element up ("QoL/General"); feature: the section on
-- it to open, if it has one.
function UI.BindMover(handle, frame, label, onMoved, page, feature)
    local item = { handle = handle, frame = frame, label = label, save = onMoved, page = page, feature = feature }
    item.baseLevel = handle:GetFrameLevel()
    handle._placement = item
    local old = placement.byLabel[label]
    if old then
        for i, other in ipairs(placement.items) do
            if other == old then table.remove(placement.items, i); break end
        end
    end
    placement.items[#placement.items + 1] = item
    placement.byLabel[label] = item
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnEnter", function()
        if not placement.active then return end
        item.hovered = true
        Refresh(item)
    end)
    handle:SetScript("OnLeave", function()
        item.hovered = false
        Refresh(item)
    end)
    handle:SetScript("OnMouseDown", function() item.dragged = nil end)
    handle:SetScript("OnMouseUp", function(_, button)
        if not placement.active or InCombatLockdown() or item.dragging or item.dragged then return end
        if button ~= "LeftButton" then return end
        if placement.selected == item then UI.ClearMoverSelection() else UI.SelectMover(handle) end
    end)
    handle:SetScript("OnDragStart", function() UI.StartMoverDrag(handle) end)
    handle:SetScript("OnDragStop", function() UI.StopMoverDrag(handle) end)
    handle:HookScript("OnHide", function()
        StopDrag(item)
        item.hovered = false
        if placement.selected == item then UI.ClearMoverSelection() end
    end)
    Refresh(item)
end

-- Move Elements plate for an on-screen display. Hidden until the caller shows it. page and
-- feature: as UI.BindMover's.
function UI.AttachMover(frame, label, onMoved, page, feature)
    local mover = CreateFrame("Frame", nil, frame)
    mover:SetAllPoints()
    mover:SetFrameLevel(frame:GetFrameLevel() + 20)
    mover._fill = ns.Solid(mover, "BACKGROUND", T.bg, MOVER_FILL)
    mover._fill:SetAllPoints()
    local strip = ns.Solid(mover, "ARTWORK", T.accent, 1)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(MOVER_STRIP)
    mover._border = ns.Border(mover, T.line)
    local text = ns.Shared.Parts.HudText(ns.Font(mover, 12))
    text:SetPoint("CENTER", mover, "CENTER")
    text:SetText(label)
    mover.text = text
    UI.BindMover(mover, frame, label, onMoved, page, feature)
    mover:Hide()
    return mover
end

--- The position to save for a window that drags itself outside Move Elements: CENTER on the
--- screen centre, where it is now. Nil before it has a size.
function UI.CenterPosition(frame)
    local l, r, t, b, ratio = Bounds(frame)
    if not l then return end
    local x = ((l + r) / 2 - UIParent:GetWidth() / 2) / ratio
    local y = ((t + b) / 2 - UIParent:GetHeight() / 2) / ratio
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

-- Element anchors and snapping were dropped; every move an anchor made was saved as the
-- element's own position, so only the old keys go. ns.Apply runs at login and on a profile
-- switch.
local forget = CreateFrame("Frame")
forget:RegisterEvent("PLAYER_LOGIN")
forget:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    hooksecurefunc(ns, "Apply", function()
        local db = ns.UnlockModeSettings.DB()
        db.anchors, db.snap = nil, nil
    end)
end)
