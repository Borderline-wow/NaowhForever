-- Selection.lua: the HUD Editor's selection, its drags and the arrow-key nudges.
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local H = ns.HudEditor

local placement = H.placement
local Grouped, Pixel, Bounds, Box = H.Grouped, H.Pixel, H.Bounds, H.Box
local Place, MoveTo, Propagate, Moved = H.Place, H.MoveTo, H.Propagate, H.Moved
local IsHidden, IsLocked = H.IsHidden, H.IsLocked
local Clear, SnapBy, GuidesOn, DrawGuides, DrawOutline = H.Clear, H.SnapBy, H.GuidesOn, H.DrawGuides, H.DrawOutline
local Moves, Snapshot, Checkpoint, Change = H.Moves, H.Snapshot, H.Checkpoint, H.Change
local dragLayer = H.dragLayer

local C = H.C
local NUDGE_FAR = 10
local LIT_RAISE = 100
local KEYS_LEVEL = 500
local DRAG_MOVED = 0.5

local function Nudge(item, dx, dy)
    if InCombatLockdown() or IsLocked(item) then return end
    local l, r, t, b = Box(item)
    if not l then return end
    MoveTo(item, (l + r) / 2 + dx, (t + b) / 2 + dy)
    Moved(item)
    H.Refresh(item)
end

local function DragGroup(item)
    local l, r, t, b = Box(item)
    local dx = (l + r - item.startBox.l - item.startBox.r) / 2
    local dy = (t + b - item.startBox.t - item.startBox.b) / 2
    for _, other in ipairs(placement.group) do
        if other.fromX then
            MoveTo(other, other.fromX + dx, other.fromY + dy)
            Propagate(other.label)
        end
    end
    H.ShowSelection()
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
    Clear(dragLayer)
    local guided = GuidesOn() and not IsAltKeyDown()
    if guided then
        local hw, hh = item.boxW / 2, item.boxH / 2
        local dx, dy = SnapBy(item, cx - hw, cx + hw, cy + hh, cy - hh)
        cx, cy = cx + (dx or 0), cy + (dy or 0)
    end
    Place(item, (cx - item.boxX - w / 2) / ratio, (cy - item.boxY - h / 2) / ratio)
    Propagate(item.label)
    if Grouped() then DragGroup(item) end
    DrawOutline(item)
    if guided then DrawGuides(item) end
    H.ShowTag()
end

local function SaveDrop(item)
    local l, r, t, b, ratio = Bounds(item.frame)
    if not (l and (math.abs(l - item.startL) > DRAG_MOVED or math.abs(t - item.startT) > DRAG_MOVED)) then return end
    Checkpoint(item.before)
    local x, y = Place(item, ((l + r) / 2 - UIParent:GetWidth() / 2) / ratio, ((t + b) / 2 - UIParent:GetHeight() / 2) / ratio)
    item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
end

local function SaveCarried()
    for other in pairs(placement.unsaved) do
        local _, _, _, x, y = other.frame:GetPoint(1)
        other.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    wipe(placement.unsaved)
end

local function StopDrag(item)
    if not item or not item.dragging then return end
    if InCombatLockdown() and item.frame:IsProtected() then placement.pendingDrag = item; return end
    item.dragging = false
    item.dragged = true
    placement.dragging = nil
    placement.driver:SetScript("OnUpdate", nil)
    Clear(dragLayer)
    SaveDrop(item)
    Moved(item)
    SaveCarried()
    item.before = nil
    for _, other in ipairs(placement.group) do
        if other.fromX then
            other.fromX, other.fromY = nil, nil
            Moved(other)
        end
    end
    H.Refresh(item)
    H.ShowSelection()
end

local function Refresh(item)
    if not item then return end
    local h = item.handle
    local picked = item.selected or item.dragging
    local lit = picked or item.hovered
    local edge = picked and T.accent or item.hovered and T.muted or C.BLACK
    h._border:SetColor(edge.r, edge.g, edge.b, 1)
    h._fill:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, lit and C.MOVER_FILL_LIT or C.MOVER_FILL)
    h:SetFrameLevel(item.baseLevel + (lit and LIT_RAISE or 0))
    if item == placement.selected then H.ShowTag() end
    H.RefreshPanel()
end

function UI.ClearMoverSelection()
    StopDrag(placement.dragging)
    local group = placement.group
    placement.selected, placement.picking = nil, nil
    placement.group, placement.groupKey = {}, {}
    for _, item in ipairs(group) do
        item.selected = false
        Refresh(item)
    end
    H.ShowTag()
    H.ShowSelection()
    if placement.keys and not InCombatLockdown() then placement.keys:SetPropagateKeyboardInput(true) end
end

function UI.RefreshMoverSelection()
    local item = placement.selected
    if not item then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    Refresh(item)
end

local function EscapePressed(self)
    if not placement.selected then return end
    if placement.picking then
        placement.picking = nil
        H.ShowTag()
    else
        UI.ClearMoverSelection()
    end
    self:SetPropagateKeyboardInput(false)
end

local function ArrowStep(key)
    local dx = key == "LEFT" and -1 or key == "RIGHT" and 1 or 0
    local dy = key == "DOWN" and -1 or key == "UP" and 1 or 0
    return dx, dy
end

local function NudgeSelection(item, dx, dy)
    local step = Pixel() * (IsShiftKeyDown() and NUDGE_FAR or 1)
    if Grouped() then
        Checkpoint(nil, placement.groupKey)
        for _, member in ipairs(placement.group) do
            if Moves(member) then Nudge(member, dx * step, dy * step) end
        end
        H.ShowSelection()
        return
    end
    if not Change(item, item) then return end
    Nudge(item, dx * step, dy * step)
end

local function PlacementKey(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(true)
    if not placement.active or GetCurrentKeyBoardFocus() then return end
    if key == "ESCAPE" then return EscapePressed(self) end
    if IsControlKeyDown() and (key == "Z" or key == "Y") then
        self:SetPropagateKeyboardInput(false)
        if key == "Y" or IsShiftKeyDown() then UI.RedoMove() else UI.UndoMove() end
        return
    end
    local item = placement.selected
    if not item or item.dragging then return end
    local dx, dy = ArrowStep(key)
    if dx == 0 and dy == 0 then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    self:SetPropagateKeyboardInput(false)
    NudgeSelection(item, dx, dy)
end

local function OnKeysUp(self)
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
end

local function OnKeysEvent(keys, event)
    if event == "PLAYER_REGEN_DISABLED" then
        UI.ClearMoverSelection()
        keys:Hide()
        return
    end
    StopDrag(placement.pendingDrag)
    placement.pendingDrag = nil
    if placement.active then UI.BeginMoverMode() else keys:UnregisterAllEvents() end
end

local function Keys()
    local keys = CreateFrame("Frame", nil, UIParent)
    keys:SetFrameStrata("FULLSCREEN_DIALOG")
    keys:SetFrameLevel(KEYS_LEVEL)
    keys:SetAllPoints()
    keys:SetScript("OnKeyDown", PlacementKey)
    keys:SetScript("OnKeyUp", OnKeysUp)
    keys:SetScript("OnEvent", OnKeysEvent)
    return keys
end

function UI.BeginMoverMode()
    placement.active = true
    if not placement.keys then
        placement.keys = Keys()
        placement.driver = CreateFrame("Frame")
    end
    if not InCombatLockdown() then
        placement.keys:EnableKeyboard(true)
        placement.keys:SetPropagateKeyboardInput(true)
    end
    UI.ClearMoverSelection()
    H.ResetHistory()
    H.PaintHistory()
    placement.keys:RegisterEvent("PLAYER_REGEN_DISABLED")
    placement.keys:RegisterEvent("PLAYER_REGEN_ENABLED")
    placement.keys:SetShown(not InCombatLockdown())
end

function UI.EndMoverMode()
    placement.active = false
    UI.ClearMoverSelection()
    Clear(dragLayer)
    if placement.keys then
        placement.keys:Hide()
        if not InCombatLockdown() then placement.keys:EnableKeyboard(false) end
        if not placement.pendingDrag then placement.keys:UnregisterAllEvents() end
    end
end

local function Join(item)
    local group = placement.group
    group[#group + 1] = item
    placement.groupKey = {}
    item.selected = true
    local last = placement.selected
    placement.selected = item
    if last and last ~= item then Refresh(last) end
    Refresh(item)
    H.ShowSelection()
end

local function Unselect(item)
    local group = placement.group
    for i, member in ipairs(group) do
        if member == item then table.remove(group, i); break end
    end
    if #group == 0 then return UI.ClearMoverSelection() end
    placement.groupKey = {}
    item.selected = false
    placement.selected = group[#group]
    Refresh(item)
    Refresh(placement.selected)
    H.ShowSelection()
end

function UI.SelectMover(handle, add)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item or IsHidden(item) then return end
    if add and placement.selected then
        if item.selected then Unselect(item) else Join(item) end
        return
    end
    if placement.selected ~= item or Grouped() then UI.ClearMoverSelection() end
    if item.selected then Refresh(item) else Join(item) end
end

local function GrabGroup(item)
    for _, other in ipairs(placement.group) do
        other.fromX, other.fromY = nil, nil
        if other ~= item and Moves(other) then
            local ol, oright, ot, ob = Box(other)
            if ol then other.fromX, other.fromY = (ol + oright) / 2, (ot + ob) / 2 end
        end
    end
end

local function Grab(item, l, r, t, b, fl, fr, ft, fb)
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    item.grabX, item.grabY = (l + r) / 2 - mx / scale, (t + b) / 2 - my / scale
    item.boxX, item.boxY = (l + r - fl - fr) / 2, (t + b - ft - fb) / 2
    item.boxW, item.boxH = r - l, t - b
    item.startL, item.startT = fl, ft
    item.startBox = item.startBox or {}
    item.startBox.l, item.startBox.r, item.startBox.t, item.startBox.b = l, r, t, b
end

function UI.StartMoverDrag(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item or IsHidden(item) then return end
    if not item.selected then UI.SelectMover(handle) end
    if IsLocked(item) then return end
    item.before = Snapshot()
    local l, r, t, b = Box(item)
    local fl, fr, ft, fb = Bounds(item.frame)
    if not (l and fl) then return end
    Grab(item, l, r, t, b, fl, fr, ft, fb)
    GrabGroup(item)
    item.dragging = true
    placement.dragging = item
    placement.driver:SetScript("OnUpdate", DragUpdate)
    Refresh(item)
end

function UI.StopMoverDrag(handle)
    StopDrag(handle._placement)
    UI.RefreshMoverSelection()
end

H.Nudge, H.StopDrag, H.Refresh = Nudge, StopDrag, Refresh
