-------------------------------------------------------------------------------
--  NaowhForever_UnlockMode.lua -- Move Elements' movers. An element is placed CENTER on the
--  screen centre and saved there. Clicking one selects it; its tag holds its X and Y and what
--  can be done with it. An element anchored to another follows it, keeping its gap.
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
local MAX_DEPTH = 20           -- anchor chain length followed at most

local placement = { active = false, items = {}, byLabel = {}, unsaved = {} }

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

-- Puts the element's centre (its Box) at (cx, cy) in UIParent units, and saves it; during a
-- drag the save waits for the drop.
local function MoveTo(item, cx, cy)
    local bl, br, bt, bb = Box(item)
    local fl, fr, ft, fb, ratio = Bounds(item.frame)
    if not (bl and fl) then return end
    local es = item.frame:GetEffectiveScale()
    local x = PixelUtil.GetNearestPixelSize((cx - ((bl + br) - (fl + fr)) / 2 - UIParent:GetWidth() / 2) / ratio, es)
    local y = PixelUtil.GetNearestPixelSize((cy - ((bt + bb) - (ft + fb)) / 2 - UIParent:GetHeight() / 2) / ratio, es)
    local point, rel, relPoint, px, py = item.frame:GetPoint(1)
    if point == "CENTER" and rel == UIParent and relPoint == "CENTER" and px == x and py == y then return end
    Place(item, x, y)
    if placement.dragging then
        placement.unsaved[item] = true
    else
        item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
end

-- The element's centre from the screen's centre, in whole pixels, as the tag shows it.
local function Position(item)
    local l, r, t, b = Bounds(item.frame)
    if not l then return end
    local px = Pixel()
    return math.floor((l + r - UIParent:GetWidth()) / 2 / px + 0.5), math.floor((t + b - UIParent:GetHeight()) / 2 / px + 0.5)
end

-------------------------------------------------------------------------------
--  Anchors: anchoredTo[label] = { target, side, x, y }. side is the target's side the element
--  sits off; along it x or y is centre to centre, across it the gap between the facing edges,
--  so a target that grows pushes the element out.
-------------------------------------------------------------------------------
local function Anchors()
    local db = ns.UnlockModeSettings.DB()
    if type(db.anchoredTo) ~= "table" then db.anchoredTo = {} end
    return db.anchoredTo
end

local function AnchorOf(label)
    local info = Anchors()[label]
    if type(info) == "table" and type(info.target) == "string" then return info end
end

-- The target's side the element is furthest out from.
local function SideOf(item, target)
    local cl, cr, ct, cb = Box(item)
    local tl, tr, tt, tb = Box(target)
    if not (cl and tl) then return "BOTTOM" end
    local dx = (cl + cr - tl - tr) / math.max(1, cr - cl + tr - tl)
    local dy = (ct + cb - tt - tb) / math.max(1, ct - cb + tt - tb)
    if math.abs(dx) > math.abs(dy) then return dx > 0 and "RIGHT" or "LEFT" end
    return dy > 0 and "TOP" or "BOTTOM"
end

-- info.x and info.y from where the element is now.
local function Capture(item, info)
    local target = placement.byLabel[info.target]
    if not target then return end
    local tl, tr, tt, tb = Box(target)
    local cl, cr, ct, cb = Box(item)
    if not (tl and cl) then return end
    local side = info.side
    if side == "LEFT" then info.x, info.y = cr - tl, (ct + cb - tt - tb) / 2
    elseif side == "RIGHT" then info.x, info.y = cl - tr, (ct + cb - tt - tb) / 2
    elseif side == "TOP" then info.x, info.y = (cl + cr - tl - tr) / 2, cb - tt
    else info.x, info.y = (cl + cr - tl - tr) / 2, ct - tb end
end

-- An anchored element to its place. A protected one waits for the end of combat.
local function Apply(item)
    local info = not item.ownAnchor and AnchorOf(item.label)
    local target = info and placement.byLabel[info.target]
    if not target then return end
    local tl, tr, tt, tb = Box(target)
    local cl, cr, ct, cb = Box(item)
    if not (tl and cl) then return end
    if InCombatLockdown() and item.frame:IsProtected() then
        placement.parked = true
        return
    end
    local w, h, x, y, side = cr - cl, ct - cb, info.x or 0, info.y or 0, info.side
    if side == "LEFT" then MoveTo(item, tl + x - w / 2, (tt + tb) / 2 + y)
    elseif side == "RIGHT" then MoveTo(item, tr + x + w / 2, (tt + tb) / 2 + y)
    elseif side == "TOP" then MoveTo(item, (tl + tr) / 2 + x, tt + y + h / 2)
    else MoveTo(item, (tl + tr) / 2 + x, tb + y - h / 2) end
end

-- Everything anchored to label, and on down the chain.
local function Propagate(label, visited)
    visited = visited or {}
    if visited[label] then return end
    visited[label] = true
    for child, info in pairs(Anchors()) do
        if type(info) == "table" and info.target == label then
            local item = placement.byLabel[child]
            if item and item ~= placement.dragging then
                Apply(item)
                Propagate(child, visited)
            end
        end
    end
end

local function Depth(label)
    local depth, info = 0, AnchorOf(label)
    while info and depth < MAX_DEPTH do
        depth = depth + 1
        info = AnchorOf(info.target)
    end
    return depth
end

-- Every anchor, parents first so a child never reads its target's old spot.
local function ReapplyAll()
    local list = {}
    for label in pairs(Anchors()) do
        local item = placement.byLabel[label]
        if item then list[#list + 1] = { item = item, depth = Depth(label) } end
    end
    table.sort(list, function(a, b) return a.depth < b.depth end)
    for _, e in ipairs(list) do Apply(e.item) end
end

-- After the element itself moved: its own anchor keeps the new gap, and what follows it comes
-- along.
local function Moved(item)
    local info = not item.ownAnchor and AnchorOf(item.label)
    if info then Capture(item, info) end
    Propagate(item.label)
end

-- Size and position changes from anywhere: one pass a frame. A size change re-places the
-- element itself; a move only takes what is anchored to it along.
local queued, batchQueued = {}, false

local function RunBatch()
    batchQueued = false
    local labels = queued
    queued = {}
    for label, kind in pairs(labels) do
        local item = placement.byLabel[label]
        if kind == "size" and item and item ~= placement.dragging and not item.sizing then Apply(item) end
        Propagate(label)
    end
end

local function Queue(label, kind)
    if queued[label] ~= "size" then queued[label] = kind or "move" end
    if batchQueued then return end
    batchQueued = true
    C_Timer.After(0, RunBatch)
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
    Moved(item)
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
    Propagate(item.label)
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
    Moved(item)
    for other in pairs(placement.unsaved) do
        local _, _, _, x, y = other.frame:GetPoint(1)
        other.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    wipe(placement.unsaved)
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
--  typed to move it), Center, Anchor, and Settings when the element has a page.
-------------------------------------------------------------------------------
local BOX_W, BOX_H = 46, 18
local TAG_PAD, TAG_GAP = 3, 4                    -- inside the tag's edge, from it to the mover
local LETTER_W, AXIS_GAP, PAIR_GAP = 8, 3, 8     -- an axis letter, from it to its box, between the parts
local CENTER_W, ANCHOR_W, SETTINGS_W = 52, 66, 62
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

-- Anchor arms a pick: the next element clicked becomes the target, the element itself or Escape
-- calls it off. A target that already follows the element is refused.
local function PickTarget(target)
    local item = placement.picking
    placement.picking = nil
    if target ~= item then
        local walk, depth = target.label, 0
        while walk and depth < MAX_DEPTH do
            if walk == item.label then
                ns.Print(("%s already moves with %s."):format(target.label, item.label))
                ShowTag()
                return
            end
            local info = AnchorOf(walk)
            walk, depth = info and info.target, depth + 1
        end
        local info = { target = target.label, side = SideOf(item, target) }
        Capture(item, info)
        Anchors()[item.label] = info
    end
    ShowTag()
end

local function AnchorClicked(tag)
    local item = tag.item
    if not item then return end
    if AnchorOf(item.label) then
        Anchors()[item.label] = nil
    else
        placement.picking = placement.picking ~= item and item or nil
    end
    ShowTag()
end

-- Unanchor while anchored; lit in the accent while a pick is armed.
local function PaintAnchor(button, item)
    local info = AnchorOf(item.label)
    local picking = placement.picking == item
    ns.SetButtonText(button, info and "Unanchor" or "Anchor")
    if info then
        ns.Tooltip(button, "Unanchor", ("Anchored to %s. Lets go of it; it stays where it is."):format(info.target))
    else
        ns.Tooltip(button, "Anchor", "Click another element to anchor to. It then moves with that element.")
    end
    local edge, text = picking and T.accent or BLACK, picking and T.accent or T.fg
    button._rest = edge
    button._border:SetColor(edge.r, edge.g, edge.b, 1)
    button.label:SetTextColor(text.r, text.g, text.b, 1)
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
    tag.anchor = ns.Button(tag, "Anchor", ANCHOR_W, BOX_H, function() AnchorClicked(tag) end)
    tag.anchor:SetPoint("LEFT", tag.center, "RIGHT", AXIS_GAP, 0)
    tag.settings = ns.Button(tag, "Settings", SETTINGS_W, BOX_H, function()
        if tag.item then OpenSettings(tag.item) end
    end)
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
        tag.anchor:SetShown(not item.ownAnchor)
        tag.settings:SetShown(item.page ~= nil)
        tag.settings:ClearAllPoints()
        tag.settings:SetPoint("LEFT", item.ownAnchor and tag.center or tag.anchor, "RIGHT", AXIS_GAP, 0)
        local w = 2 * (LETTER_W + AXIS_GAP + BOX_W) + 2 * PAIR_GAP + CENTER_W + 2 * TAG_PAD
        if not item.ownAnchor then w = w + AXIS_GAP + ANCHOR_W end
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
    if not item.ownAnchor then PaintAnchor(tag.anchor, item) end
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
    placement.selected, placement.picking = nil, nil
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
        if placement.picking then
            placement.picking = nil
            ShowTag()
        else
            UI.ClearMoverSelection()
        end
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
-- it to open, if it has one. ownAnchor: it holds itself to the screen its own way, so it takes
-- no anchor (others can still anchor to it).
function UI.BindMover(handle, frame, label, onMoved, page, feature, ownAnchor)
    local item = { handle = handle, frame = frame, label = label, save = onMoved, page = page, feature = feature,
        ownAnchor = ownAnchor }
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
    -- The mover can cover more than the frame (a reminder's sample), and grows with it.
    frame:HookScript("OnSizeChanged", function() Queue(label, "size") end)
    handle:HookScript("OnSizeChanged", function() Queue(label, "size") end)
    hooksecurefunc(frame, "SetPoint", function()
        if not item.dragging then Queue(label) end
    end)
    -- A module's own resize grip sizes the frame from a corner of its choosing: the anchor
    -- leaves it be until the grip lets go.
    hooksecurefunc(frame, "StartSizing", function() item.sizing = true end)
    hooksecurefunc(frame, "StopMovingOrSizing", function()
        item.sizing = nil
        C_Timer.After(0, function() Moved(item) end)
    end)
    Queue(label, "size")
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
        if placement.picking then
            PickTarget(item)
        elseif placement.selected == item then
            UI.ClearMoverSelection()
        else
            UI.SelectMover(handle)
        end
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

-- Move Elements plate for an on-screen display. Hidden until the caller shows it. page,
-- feature and ownAnchor: as UI.BindMover's.
function UI.AttachMover(frame, label, onMoved, page, feature, ownAnchor)
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
    UI.BindMover(mover, frame, label, onMoved, page, feature, ownAnchor)
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

-- Anchors catch up on entering the world, after every profile switch (ns.Apply) and after
-- combat held a protected one back. The old anchors and snap switch were dropped before; every
-- move they made was saved as the element's own position, so only their keys go.
local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:RegisterEvent("PLAYER_ENTERING_WORLD")
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        hooksecurefunc(ns, "Apply", function()
            local db = ns.UnlockModeSettings.DB()
            db.anchors, db.snap = nil, nil
            C_Timer.After(0, ReapplyAll)
        end)
    elseif event == "PLAYER_ENTERING_WORLD" or placement.parked then
        placement.parked = nil
        C_Timer.After(0, ReapplyAll)
    end
end)

-------------------------------------------------------------------------------
--  Entering and leaving Unlock Mode: the toolbar, the grid and the movers. Every module
--  hooks ns.ShowRaidReminderAnchorConfig and ns.HideRaidReminderAnchorConfig to show and
--  hide its own frames.
-------------------------------------------------------------------------------
-- Unlock Mode's grid, measured out from the screen's centre: faint lines in the text colour,
-- every GRID_MAJOR-th one stronger, and the centre lines in the accent with a square where
-- they cross.
local GRID_SPACING = 32
local GRID_MAJOR = 4
local GRID_LINE_ALPHA = 0.08
local GRID_MAJOR_ALPHA = 0.18
local GRID_CENTER_ALPHA = 0.6
local GRID_MARK = 6        -- the centre square, in pixels
local gridOverlay

local function BuildGridOverlay()
    if gridOverlay then return gridOverlay end
    gridOverlay = CreateFrame("Frame", nil, UIParent)
    gridOverlay:SetFrameStrata("BACKGROUND")
    gridOverlay:SetFrameLevel(1)
    gridOverlay:SetAllPoints(UIParent)
    gridOverlay._lines = {}
    gridOverlay:Hide()

    function gridOverlay:Rebuild()
        for i = 1, #self._lines do self._lines[i]:Hide() end
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        -- One physical pixel: fractional widths blur across two pixels.
        local mult = Pixel()
        local spacing = GRID_SPACING * mult
        local function Snap(v) return math.floor(v / mult + 0.5) * mult end
        local centerX, centerY = Snap(w / 2), Snap(h / 2)
        local idx = 0

        local function Line(isVert, pos, alpha, c)
            c = c or T.fg
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                self._lines[idx] = tex
            end
            tex:SetColorTexture(c.r, c.g, c.b, alpha)
            tex:ClearAllPoints()
            if isVert then
                tex:SetSize(mult, h)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos, 0)
            else
                tex:SetSize(w, mult)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -pos)
            end
            tex:Show()
        end

        local function Lines(isVert, center, size)
            for dir = -1, 1, 2 do
                local n, pos = 1, center + dir * spacing
                while pos > 0 and pos < size do
                    Line(isVert, Snap(pos), n % GRID_MAJOR == 0 and GRID_MAJOR_ALPHA or GRID_LINE_ALPHA)
                    n, pos = n + 1, pos + dir * spacing
                end
            end
        end
        Lines(true, centerX, w)
        Lines(false, centerY, h)
        Line(true, centerX, GRID_CENTER_ALPHA, T.accent)
        Line(false, centerY, GRID_CENTER_ALPHA, T.accent)

        if not self._mark then self._mark = self:CreateTexture(nil, "BACKGROUND", nil, -6) end
        self._mark:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
        self._mark:SetSize(GRID_MARK * mult, GRID_MARK * mult)
        self._mark:ClearAllPoints()
        self._mark:SetPoint("CENTER", UIParent, "TOPLEFT", centerX, -centerY)
    end

    return gridOverlay
end

function ns.SetAnchorGridShown(shown)
    if not shown then
        if gridOverlay then gridOverlay:Hide() end
        return
    end
    local g = BuildGridOverlay()
    g:Rebuild()
    g:Show()
end

local configActive, reopenWindowOnExit = false, false
local configToolbar
-- Switches a module adds under the header, each { label, get, set, enabled }, under a
-- section name (Smart Reminders' anchors).
local toolbarChecks, toolbarSection = {}, nil

function ns.AddUnlockModeChecks(section, checks)
    toolbarSection = section
    for _, c in ipairs(checks) do toolbarChecks[#toolbarChecks + 1] = c end
end

-- Move Elements' toolbar: the windows' backdrop and black edge, a header with the logo, the
-- title and Exit Config, then the switches.
local BAR_W, BAR_PAD, BAR_GAP = 352, 14, 10
local BAR_HEAD = 40                   -- the header, down to its rule
local BAR_LOGO = 20
local EXIT_W, EXIT_H = 96, 22
local SWITCH_W, SWITCH_H = 28, 14
local SWITCH_ROW = 22
local SWITCH_COL = (BAR_W - 2 * BAR_PAD) / 2
local LABEL_GAP = 8                   -- a switch to its label
local SECTION_H = 18                  -- a section's muted name over its switches
local OFF_ALPHA = 0.4                 -- a module's switches while it is off

local function BarRule(f, y)
    local rule = ns.Solid(f, "ARTWORK", ns.Shared.Style.BORDER_RGB, 1)
    rule:SetPoint("TOPLEFT", 0, -y)
    rule:SetPoint("TOPRIGHT", 0, -y)
    ns.Hairline(rule, "h")
end

-- A house switch with its label, at y below the toolbar's top in column col (0 or 1).
local function BarSwitch(f, text, col, y, get, set)
    local switch = UI.BuildToggleControl(f, nil, get, set, SWITCH_W, SWITCH_H)
    switch:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_PAD + col * SWITCH_COL, -y)
    switch.label = ns.Font(f, 11)
    switch.label:SetPoint("LEFT", switch, "RIGHT", LABEL_GAP, 0)
    switch.label:SetText(text)
    return switch
end

local function BuildConfigToolbar()
    if configToolbar then return configToolbar end
    local St = ns.Shared.Style
    local f = CreateFrame("Frame", "NaowhForeverRaidReminderAnchorConfig", UIParent)
    f:SetWidth(BAR_W)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(510)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    ns.AllowOffscreen(f)
    ns.Shared.Parts.Backdrop(f):Paint(St.BACKDROP_ALPHA)
    ns.Border(f, St.BORDER_RGB)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(St.LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(BAR_LOGO, BAR_LOGO)
    logo:SetPoint("LEFT", f, "TOPLEFT", BAR_PAD, -BAR_HEAD / 2)
    local title = ns.Font(f, 14)
    title:SetPoint("LEFT", logo, "RIGHT", LABEL_GAP, 0)
    title:SetText("Move Elements")
    local exit = ns.AccentBorder(ns.Button(f, "Exit Config", EXIT_W, EXIT_H, function() ns.HideRaidReminderAnchorConfig() end))
    exit:SetPoint("RIGHT", f, "TOPRIGHT", -BAR_PAD, -BAR_HEAD / 2)
    BarRule(f, BAR_HEAD)

    local y = BAR_HEAD
    local switches = {}
    if #toolbarChecks > 0 then
        y = y + BAR_GAP
        f._section = ns.Font(f, 11, nil, T.muted)
        f._section:SetPoint("TOPLEFT", BAR_PAD, -y)
        y = y + SECTION_H
        for i, c in ipairs(toolbarChecks) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            switches[i] = BarSwitch(f, c.label, col, y + row * SWITCH_ROW, c.get, c.set)
        end
        y = y + math.ceil(#toolbarChecks / 2) * SWITCH_ROW + BAR_GAP / 2
    end
    f:SetHeight(y)

    f._switches = switches
    configToolbar = f
    return f
end

function ns.ShowRaidReminderAnchorConfig()
    -- Stash before arming: hiding the window runs HideRaidReminderAnchorConfig via
    -- OnHide, which disarmed the mode in the same click when armed first.
    local reopen = ns.StashOptionsWindow and ns.StashOptionsWindow() or false
    configActive = true
    UI.BeginMoverMode()
    reopenWindowOnExit = reopen
    local f = BuildConfigToolbar()
    if f._section then f._section:SetText(toolbarSection()) end
    for i, c in ipairs(toolbarChecks) do
        local switch, on = f._switches[i], c.enabled()
        switch._refreshValue()
        switch:EnableMouse(on)
        switch:SetAlpha(on and 1 or OFF_ALPHA)
        switch.label:SetAlpha(on and 1 or OFF_ALPHA)
    end
    f:Show()
    ns.SetAnchorGridShown(true)
end

-- windowClosing: called from the options window's own OnHide, which must not reopen it.
function ns.HideRaidReminderAnchorConfig(windowClosing)
    configActive = false
    UI.EndMoverMode()
    ns.SetAnchorGridShown(false)
    if configToolbar then configToolbar:Hide() end
    if reopenWindowOnExit then
        reopenWindowOnExit = false
        if not windowClosing and ns.OpenOptionsWindow then ns.OpenOptionsWindow() end
    end
end

function ns.IsRaidReminderAnchorConfigActive()
    return configActive
end
