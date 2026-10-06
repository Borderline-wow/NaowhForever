-------------------------------------------------------------------------------
--  NaowhForever_UnlockMode.lua -- Unlock Mode's movers. An element is placed CENTER on the
--  screen centre and saved there.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local BLACK = { r = 0, g = 0, b = 0 }
local MENU_W, ITEM_H = 220, 24
local HOVER_DELAY, ANIM_DUR = 0.12, 0.15
local SNAP_THRESH = 6          -- UI units a dragged edge snaps from
local DIM_ALPHA, DIM_FADE = 0.30, 0.5
-- A mover: the theme's background as dark glass over the element, an accent strip across its
-- top, and an edge in the line colour, muted grey under the mouse and the accent once selected.
local MOVER_FILL, MOVER_FILL_LIT = 0.55, 0.75
local MOVER_STRIP = 2          -- the accent strip's height
local GUIDE_ALPHA = 0.6        -- a snapped axis, in the text colour

local placement = { active = false, items = {}, byLabel = {} }

-------------------------------------------------------------------------------
--  Pixels: one physical pixel in UIParent units.
-------------------------------------------------------------------------------
local function Perfect() return PixelUtil.GetPixelToUIUnitFactor() end
local function Mult() return Perfect() / UIParent:GetEffectiveScale() end

local function ToPixels(v) return math.floor(v / Mult() + 0.5 + 0.001) end
local function FromPixels(px) return px * Mult() end

-- A CENTER offset in a frame's own units, snapped so both its edges land on whole pixels: an
-- odd pixel size puts the centre on a half pixel.
local function SnapCenter(v, dim, es)
    local onePx = Perfect() / es
    local vPx = v / onePx
    local clean = math.floor(vPx + 0.5)
    if math.abs(vPx - clean) < 0.001 then vPx = clean end
    local dimPx = math.floor(dim / onePx + 0.5 + 0.001)
    if dimPx % 2 == 1 then return (math.floor(vPx) + 0.5) * onePx end
    return math.floor(vPx + 0.5) * onePx
end

-- Edges in UIParent units, BOTTOMLEFT origin.
local function Bounds(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * ratio, r * ratio, t * ratio, b * ratio, ratio
end

-- The element as the player sees it: its mover's rect, which is the frame's unless a module laid
-- the mover over something else (a reminder's sample hangs below its anchor frame). While the
-- mover is grown on hover, the rect it had before. The ratio is the frame's.
local function Box(item)
    local fl, fr, ft, fb, ratio = Bounds(item.frame)
    if not fl then return end
    local i = item.inset
    if i then return fl + i[1], fr + i[2], ft + i[3], fb + i[4], ratio end
    local hl, hr, ht, hb = Bounds(item.handle)
    if hl then return hl, hr, ht, hb, ratio end
    return fl, fr, ft, fb, ratio
end

-- Puts the element's centre (its Box) at (cx, cy) in UIParent units: its frame CENTER on the
-- screen centre, and saved there.
local function MoveTo(item, cx, cy)
    local frame = item.frame
    local bl, br, bt, bb = Box(item)
    local fl, fr, ft, fb, ratio = Bounds(frame)
    if not (bl and fl) then return end
    local x = (cx - ((bl + br) - (fl + fr)) / 2 - UIParent:GetWidth() / 2) / ratio
    local y = (cy - ((bt + bb) - (ft + fb)) / 2 - UIParent:GetHeight() / 2) / ratio
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
end

-------------------------------------------------------------------------------
--  Unlock Mode visuals shared by every mover: the dimmer.
-------------------------------------------------------------------------------
local Refresh, CancelPick, CloseMenus, ShowPosition

local function Dim(on)
    if not placement.dim then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("BACKGROUND")
        f:SetFrameLevel(0)
        f:SetAllPoints()
        f.tex = f:CreateTexture(nil, "BACKGROUND")
        f.tex:SetAllPoints()
        f.tex:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, 0)
        f.alpha = 0
        placement.dim = f
    end
    local f = placement.dim
    local from, to, elapsed = f.alpha, on and DIM_ALPHA or 0, 0
    f:Show()
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / DIM_FADE, 1)
        self.alpha = from + (to - from) * t
        self.tex:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, self.alpha)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            if to == 0 then self:Hide() end
        end
    end)
end

-------------------------------------------------------------------------------
--  The cog menu: rebuilt on every open, over a full-screen click catcher that closes it.
-------------------------------------------------------------------------------
local function MenuFrame(level)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(level)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.rows = {}
    f.bg = ns.Solid(f, "BACKGROUND", T.panel, 0.98)
    f.bg:SetAllPoints()
    ns.Border(f, BLACK)
    f:Hide()
    return f
end

local function Catcher()
    if not placement.catcher then
        local c = CreateFrame("Button", nil, UIParent)
        c:SetFrameStrata("FULLSCREEN_DIALOG")
        c:SetFrameLevel(240)
        c:SetAllPoints()
        c:RegisterForClicks("AnyUp")
        c:SetScript("OnClick", function() CloseMenus() end)
        placement.catcher = c
    end
    placement.catcher:Show()
end

-- Rows are pooled per menu; every open hides them all and takes them back in order.
local function ClearMenu(menu, width)
    for _, row in ipairs(menu.rows) do row:Hide() end
    menu.used, menu.y = 0, -4
    menu:SetWidth(width)
end

local function Row(menu)
    menu.used = menu.used + 1
    local row = menu.rows[menu.used]
    if not row then
        row = CreateFrame("Button", nil, menu)
        row:RegisterForClicks("AnyUp")
        row.hl = row:CreateTexture(nil, "ARTWORK")
        row.hl:SetAllPoints()
        row.label = ns.Font(row, 12, nil)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.divider = row:CreateTexture(nil, "ARTWORK")
        menu.rows[menu.used] = row
    end
    row:SetFrameLevel(menu:GetFrameLevel() + 2)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    row:EnableMouse(true)
    row.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetFont(ns.UIFontPath(), 12, "")
    row.label:SetText("")
    row.label:Show()
    row.divider:Hide()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, menu.y)
    row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, menu.y)
    row:SetHeight(ITEM_H)
    row:Show()
    menu.y = menu.y - ITEM_H
    return row
end

local function Divider(menu)
    local row = Row(menu)
    row:EnableMouse(false)
    row:SetHeight(9)
    row.label:Hide()
    row.divider:ClearAllPoints()
    row.divider:SetPoint("LEFT")
    row.divider:SetPoint("RIGHT")
    row.divider:SetHeight(Mult())
    row.divider:SetColorTexture(T.line.r, T.line.g, T.line.b, 1)
    row.divider:Show()
    menu.y = menu.y + ITEM_H - 9
end

-- A clickable row, filled grey on hover.
local function Action(menu, text, onClick)
    local row = Row(menu)
    row.label:SetText(ns.L(text))
    row.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    row:SetScript("OnEnter", function() row.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, 1) end)
    row:SetScript("OnLeave", function() row.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, 0) end)
    row:SetScript("OnClick", onClick)
    return row
end

local function Finish(menu)
    menu:SetHeight(-menu.y + 4)
    menu:Show()
end

function CloseMenus()
    if placement.cogMenu then placement.cogMenu:Hide() end
    if placement.catcher then placement.catcher:Hide() end
    local item = placement.menuItem
    placement.menuItem = nil
    if not item then return end
    ShowPosition()
    item.menuOpen = false
    if not item.handle:IsMouseOver() then
        item.hovered = false
        item.Collapse()
        Refresh(item)
    end
end

-------------------------------------------------------------------------------
--  Moving: nudges, drags and Center on Screen, all ending in a saved CENTER spot.
-------------------------------------------------------------------------------
local function SaveWhereItIs(item)
    local l, r, t, b, ratio = Bounds(item.frame)
    if not l then return end
    local x = ((l + r) / 2 - UIParent:GetWidth() / 2) / ratio
    local y = ((t + b) / 2 - UIParent:GetHeight() / 2) / ratio
    item.frame:ClearAllPoints()
    item.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
end

-- dx, dy in UIParent units.
local function Nudge(item, dx, dy)
    if InCombatLockdown() then return end
    if not item.menuOpen then item.Collapse(true) end
    local l, r, t, b = Box(item)
    if not l then return end
    MoveTo(item, (l + r) / 2 + dx, (t + b) / 2 + dy)
    Refresh(item)
end

-- Snapping while dragging: the closest other mover shown, or the one picked as its snap target,
-- lines up an edge or centre within SNAP_THRESH on each axis.
local function SnapPosition(item, cx, cy, halfW, halfH)
    local snap = placement.snapInfo
    wipe(snap)
    if ns.UnlockModeSettings.Get("snap") == false then return cx, cy end
    local dL, dR, dT, dB = cx - halfW, cx + halfW, cy + halfH, cy - halfH
    local target = item.snapTarget and placement.byLabel[item.snapTarget]
    if not (target and target.handle:IsVisible()) then
        target = nil
        local best = math.huge
        for _, other in ipairs(placement.items) do
            if other ~= item and other.handle:IsVisible() then
                local oL, oR, oT, oB = Bounds(other.handle)
                if oL then
                    local gapX = dR < oL and oL - dR or dL > oR and dL - oR or 0
                    local gapY = dB > oT and dB - oT or dT < oB and oB - dT or 0
                    local d = math.sqrt(gapX * gapX + gapY * gapY)
                    if d < best then best, target = d, other end
                end
            end
        end
    end
    snap.target = target
    if not target then return cx, cy end
    local oL, oR, oT, oB = Bounds(target.handle)
    if not oL then return cx, cy end
    local bestX, bestY = SNAP_THRESH, SNAP_THRESH
    local moveX, moveY = 0, 0
    for _, de in ipairs({ dL, cx, dR }) do
        for _, te in ipairs({ oL, (oL + oR) / 2, oR }) do
            if math.abs(de - te) < bestX then bestX, moveX, snap.x = math.abs(de - te), de - te, te end
        end
    end
    for _, de in ipairs({ dT, cy, dB }) do
        for _, te in ipairs({ oT, (oT + oB) / 2, oB }) do
            if math.abs(de - te) < bestY then bestY, moveY, snap.y = math.abs(de - te), de - te, te end
        end
    end
    return cx - moveX, cy - moveY
end

-- Full-screen guides on a snapped axis, and the mover snapped to edged in the soft accent.
local function ShowGuides()
    local g, snap = placement.guides, placement.snapInfo
    if not g then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("BACKGROUND")
        f:SetFrameLevel(2)
        f:SetAllPoints()
        g = { frame = f, x = ns.Solid(f, "OVERLAY", T.fg, GUIDE_ALPHA), y = ns.Solid(f, "OVERLAY", T.fg, GUIDE_ALPHA) }
        placement.guides = g
    end
    g.frame:Show()
    g.x:SetShown(snap.x ~= nil)
    g.y:SetShown(snap.y ~= nil)
    if snap.x then
        g.x:ClearAllPoints()
        g.x:SetSize(Mult(), UIParent:GetHeight())
        g.x:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", snap.x, 0)
    end
    if snap.y then
        g.y:ClearAllPoints()
        g.y:SetSize(UIParent:GetWidth(), Mult())
        g.y:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, snap.y)
    end
    local target = snap.target
    if target ~= g.target then
        if g.target and g.target.handle._snapBorder then g.target.handle._snapBorder:SetColor(1, 1, 1, 0) end
        g.target = target
        if target then
            local h = target.handle
            if not h._snapBorder then
                h._snapBorder = ns.Border(h, T.accentSoft, 0)
                h._snapBorder._frame:SetFrameLevel(h:GetFrameLevel() + 3)
            end
            h._snapBorder:SetColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
        end
    end
end

local function HideGuides()
    local g = placement.guides
    if not g then return end
    g.frame:Hide()
    if g.target and g.target.handle._snapBorder then g.target.handle._snapBorder:SetColor(1, 1, 1, 0) end
    g.target = nil
end

local function DragUpdate()
    local item = placement.dragging
    if not item or InCombatLockdown() then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / scale, my / scale
    local cx, cy = mx + item.dragX, my + item.dragY
    -- Shift holds the drag to the axis it first moved 3 units along.
    if IsShiftKeyDown() then
        if not item.dragAxis then
            local ddx, ddy = math.abs(mx - item.dragStartX), math.abs(my - item.dragStartY)
            if ddx > 3 or ddy > 3 then item.dragAxis = ddx >= ddy and "X" or "Y" end
        end
        if item.dragAxis == "X" then cy = item.dragStartCY elseif item.dragAxis == "Y" then cx = item.dragStartCX end
    else
        item.dragAxis = nil
    end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    cx, cy = math.max(0, math.min(w, cx)), math.max(0, math.min(h, cy))
    local _, _, _, _, ratio = Bounds(item.frame)
    if not ratio then return end
    cx, cy = SnapPosition(item, cx, cy, item.dragHalfW, item.dragHalfH)
    ShowGuides()
    local snap = placement.snapInfo
    local es = item.frame:GetEffectiveScale()
    local x, y = (cx - item.dragBoxX - w / 2) / ratio, (cy - item.dragBoxY - h / 2) / ratio
    if not snap.x then x = SnapCenter(x, item.frame:GetWidth(), es) end
    if not snap.y then y = SnapCenter(y, item.frame:GetHeight(), es) end
    item.frame:ClearAllPoints()
    item.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    ShowPosition()
end

local function StopPlacementDrag(item)
    if not item or not item.dragging then return end
    if InCombatLockdown() and item.frame:IsProtected() then placement.pendingDrag = item; return end
    item.dragging = false
    item.dragged = true
    placement.dragging = nil
    placement.driver:SetScript("OnUpdate", nil)
    HideGuides()
    local l, _, t = Bounds(item.frame)
    if l and (math.abs(l - item.dragStartL) > 0.5 or math.abs(t - item.dragStartT) > 0.5) then
        SaveWhereItIs(item)
    end
    Refresh(item)
end

local function CenterOnScreen(item)
    if InCombatLockdown() then return end
    local l, r = Box(item)
    if not l then return end
    local px = ToPixels((l + r) / 2 - UIParent:GetWidth() / 2)
    if px ~= 0 then Nudge(item, FromPixels(-px), 0) end
end

-- Select Snap Target let go before an element was clicked: the snap target it had stays.
function CancelPick()
    local picker = placement.snapPicker
    if not picker then return end
    placement.snapPicker = nil
    picker.snapTarget = picker.preSnapTarget
    picker.preSnapTarget = nil
    Dim(false)
end

-- Out of Unlock Mode and onto the element's options: the options window draws over the
-- movers, so the two cannot share the screen.
local function OpenElementOptions(item)
    ns.HideRaidReminderAnchorConfig()
    ns.OpenOptionsWindow(item.page)
    if item.feature then UI.GoToSetting(item.page, nil, item.feature) end
end

local function OpenCogMenu(item)
    CloseMenus()
    CancelPick()
    local menu = placement.cogMenu or MenuFrame(250)
    placement.cogMenu = menu
    placement.menuItem = item
    item.menuOpen = true
    ClearMenu(menu, MENU_W)
    menu:Show()

    local hint = Row(menu)
    hint:EnableMouse(false)
    hint.label:ClearAllPoints()
    hint.label:SetPoint("TOPLEFT", hint, "TOPLEFT", 7, -4)
    hint.label:SetPoint("TOPRIGHT", hint, "TOPRIGHT", -7, -4)
    hint.label:SetFont(ns.UIFontPath(), 11, "")
    hint.label:SetJustifyH("CENTER")
    hint.label:SetWordWrap(true)
    hint.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    hint.label:SetText(ns.L("Use arrow keys to move selected element 1px any direction") .. ". "
        .. ns.L("Shift+Right Click to temporarily hide overlay"))
    local hintH = hint.label:GetStringHeight()
    if not hintH or hintH < 1 then hintH = 28 end
    hint:SetHeight(hintH + 10)
    menu.y = menu.y + ITEM_H - (hintH + 10)
    Divider(menu)

    if item.page then
        Action(menu, "Element Options", function()
            CloseMenus()
            OpenElementOptions(item)
        end)
    end

    local picked = item.snapTarget and placement.byLabel[item.snapTarget]
    Action(menu, picked and ns.L("Snap Target: %s"):format(ns.Color("accent", item.snapTarget))
        or "Select Snap Target", function()
        CloseMenus()
        if picked then
            item.snapTarget = nil
        else
            CancelPick()
            item.preSnapTarget = item.snapTarget
            placement.snapPicker = item
            Dim(true)
        end
    end)

    Action(menu, "Center on Screen", function()
        CloseMenus()
        CenterOnScreen(item)
    end)

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", item.cog, "BOTTOMLEFT", 0, -2)
    Catcher()
    Finish(menu)
    ShowPosition()
end

-------------------------------------------------------------------------------
--  Position: a tag just outside the selected mover with its X and Y in whole pixels, its
--  centre from the screen's centre as it is saved, live while it moves, and typed to move it.
-------------------------------------------------------------------------------
local BOX_W, BOX_H = 46, 18
local TAG_PAD, TAG_GAP = 3, 4                    -- inside the tag's edge, from it to the mover
local LETTER_W, AXIS_GAP, PAIR_GAP = 8, 3, 8     -- an axis letter, from it to its box, between the pairs
local TAG_W = 2 * (LETTER_W + AXIS_GAP + BOX_W + TAG_PAD) + PAIR_GAP
local TAG_H = BOX_H + 2 * TAG_PAD
local TAG_LEVEL = 230                            -- over the movers, under the cog menu's catcher

local function Position(item)
    local l, r, t, b = Bounds(item.frame)
    if not l then return end
    return ToPixels((l + r - UIParent:GetWidth()) / 2), ToPixels((t + b - UIParent:GetHeight()) / 2)
end

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
    if box.axis == "X" then Nudge(item, FromPixels(d), 0) else Nudge(item, 0, FromPixels(d)) end
end

local function Revert(box)
    box.border:SetColor(0, 0, 0, 1)
    box.value = nil
    ShowPosition()
end

local function PositionTag()
    local tag = CreateFrame("Frame", nil, UIParent)
    tag:SetSize(TAG_W, TAG_H)
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
    return tag
end

-- Below the mover, above it when the screen ends first; hidden while its cog menu is open,
-- which drops down over the same spot.
function ShowPosition()
    local item = placement.selected
    local x, y
    if item and placement.menuItem ~= item then x, y = Position(item) end
    local tag = placement.tag
    if not x then
        if tag then
            tag:Hide()
            tag.item = nil
        end
        return
    end
    if not tag then
        tag = PositionTag()
        placement.tag = tag
    end
    local _, _, _, bottom = Bounds(item.handle)
    local above = bottom ~= nil and bottom - TAG_GAP - TAG_H < 0
    if tag.item ~= item or tag.above ~= above then
        tag.item, tag.above = item, above
        tag.x.value, tag.y.value = nil, nil
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
    if item.cog then item.cog:SetFrameLevel(h:GetFrameLevel() + 10) end
    if item == placement.selected then ShowPosition() end
end

function UI.ClearMoverSelection()
    local item = placement.selected
    StopPlacementDrag(item)
    placement.selected = nil
    if item then
        item.selected = false
        Refresh(item)
    end
    ShowPosition()
    if placement.snapPicker then CancelPick() end
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
        if placement.cogMenu and placement.cogMenu:IsShown() then
            CloseMenus()
        elseif placement.snapPicker then
            CancelPick()
        elseif placement.selected then
            UI.ClearMoverSelection()
        else
            return
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
    local step = Mult() * (IsShiftKeyDown() and 100 or 1)
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
                CloseMenus()
                CancelPick()
                UI.ClearMoverSelection()
                keys:Hide()
            else
                StopPlacementDrag(placement.pendingDrag)
                placement.pendingDrag = nil
                if placement.active then UI.BeginMoverMode() else keys:UnregisterAllEvents() end
            end
        end)
        placement.driver = CreateFrame("Frame")
        placement.snapInfo = {}
    end
    if not InCombatLockdown() then
        placement.keys:EnableKeyboard(true)
        placement.keys:SetPropagateKeyboardInput(true)
    end
    UI.ClearMoverSelection()
    for _, item in ipairs(placement.items) do item.tempHidden = nil end
    placement.keys:RegisterEvent("PLAYER_REGEN_DISABLED")
    placement.keys:RegisterEvent("PLAYER_REGEN_ENABLED")
    placement.keys:SetShown(not InCombatLockdown())
end

function UI.EndMoverMode()
    placement.active = false
    CloseMenus()
    CancelPick()
    UI.ClearMoverSelection()
    for _, item in ipairs(placement.items) do
        item.snapTarget = nil
        if item.Collapse then item.Collapse(true) end
    end
    HideGuides()
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
    if not item or placement.snapPicker then return end
    CloseMenus()
    item.Collapse(true)
    UI.SelectMover(handle)
    local l, r, t, b = Box(item)
    local fl, fr, ft, fb = Bounds(item.frame)
    if not (l and fl) then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / scale, my / scale
    item.dragStartX, item.dragStartY = mx, my
    item.dragStartCX, item.dragStartCY = (l + r) / 2, (t + b) / 2
    item.dragHalfW, item.dragHalfH = (r - l) / 2, (t - b) / 2
    item.dragBoxX, item.dragBoxY = (l + r - fl - fr) / 2, (t + b - ft - fb) / 2
    item.dragStartL, item.dragStartT = fl, ft
    item.dragX, item.dragY = item.dragStartCX - mx, item.dragStartCY - my
    item.dragAxis = nil
    item.dragging = true
    placement.dragging = item
    placement.driver:SetScript("OnUpdate", DragUpdate)
    Refresh(item)
end

function UI.StopMoverDrag(handle)
    StopPlacementDrag(handle._placement)
    UI.RefreshMoverSelection()
end

-------------------------------------------------------------------------------
--  Movers
-------------------------------------------------------------------------------
-- The cog at the top right, grown in over ANIM_DUR once the cursor has rested HOVER_DELAY on
-- the mover.
local function BuildChrome(item)
    local h, text = item.handle, item.handle.text
    local frame = item.frame

    local cog = CreateFrame("Button", nil, h)
    cog:SetSize(16, 16)
    cog:SetPoint("TOPRIGHT", h, "TOPRIGHT", -3, -3)
    cog:RegisterForClicks("AnyUp")
    cog.icon = cog:CreateTexture(nil, "ARTWORK")
    cog.icon:SetAllPoints()
    cog.icon:SetTexture(UI.COGS_ICON)
    cog.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    cog:Hide()
    item.cog = cog

    local state, goal, anim = 0, 0, CreateFrame("Frame", nil, h)
    local hoverW, hoverH = 0, 0
    local rest   -- the mover's own points while it is grown, to put back after

    local function Over()
        return h:IsMouseOver() or cog:IsMouseOver()
    end

    -- s from 0 (at rest, the mover covering the element) to 1 (grown to fit name and cog).
    local function SetState(s)
        cog:SetAlpha(s)
        cog:SetShown(s > 0.01)
        -- Grown around its own centre, held to the element so it moves with it.
        if s > 0 and not rest then
            local w, hh = h:GetWidth(), h:GetHeight()
            local hx, hy = h:GetCenter()
            local fx, fy = frame:GetCenter()
            if (hoverW > w or hoverH > hh) and hx and fx then
                local hl, hr, ht, hb = Bounds(h)
                local fl, fr, ft, fb = Bounds(frame)
                item.inset = { hl - fl, hr - fr, ht - ft, hb - fb }
                rest = { w = w, h = hh }
                for i = 1, h:GetNumPoints() do rest[i] = { h:GetPoint(i) } end
                h:ClearAllPoints()
                h:SetPoint("CENTER", frame, "CENTER", hx - fx, hy - fy)
            end
        end
        if rest then
            if s > 0 then
                h:SetSize(rest.w + (math.max(rest.w, hoverW) - rest.w) * s, rest.h + (math.max(rest.h, hoverH) - rest.h) * s)
            else
                h:ClearAllPoints()
                for _, p in ipairs(rest) do h:SetPoint(unpack(p)) end
                if #rest == 1 then h:SetSize(rest.w, rest.h) end
                rest = nil
                item.inset = nil
            end
        end
    end

    local function AnimateTo(target)
        goal = target
        anim:SetScript("OnUpdate", function(self, dt)
            local dir = goal > state and 1 or -1
            state = state + dir * dt / ANIM_DUR
            if (dir == 1 and state >= goal) or (dir == -1 and state <= goal) then
                state = goal
                self:SetScript("OnUpdate", nil)
            end
            SetState(state)
        end)
    end

    function item.Expand()
        Refresh(item)
        hoverW = (text:GetStringWidth() or 0) + 16
        hoverH = (text:GetStringHeight() or 10) + 16
        AnimateTo(1)
    end

    function item.Collapse(now)
        if now then
            anim:SetScript("OnUpdate", nil)
            state, goal = 0, 0
            SetState(0)
        else
            AnimateTo(0)
        end
    end

    cog:SetScript("OnEnter", function()
        cog.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
        item.hovered = true
        Refresh(item)
    end)
    cog:SetScript("OnLeave", function()
        cog.icon:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    end)
    cog:SetScript("OnClick", function()
        if item.menuOpen then CloseMenus() else UI.SelectMover(h); OpenCogMenu(item) end
    end)

    h:SetScript("OnEnter", function()
        if not placement.active then return end
        item.hovered = true
        Refresh(item)
        if placement.snapPicker then return end
        item.hoverPending = true
        C_Timer.After(HOVER_DELAY, function()
            if item.hoverPending and Over() then item.Expand() end
            item.hoverPending = false
        end)
    end)
    h:SetScript("OnLeave", function()
        if item.dragging then return end
        C_Timer.After(HOVER_DELAY, function()
            if item.dragging or Over() or item.menuOpen then return end
            item.hoverPending = false
            item.hovered = false
            item.Collapse()
            Refresh(item)
        end)
    end)
end

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
    BuildChrome(item)
    handle:SetScript("OnMouseDown", function() item.dragged = nil end)
    handle:SetScript("OnMouseUp", function(_, button)
        if not placement.active or InCombatLockdown() or item.dragging or item.dragged then return end
        if button == "LeftButton" then
            if placement.snapPicker then
                local picker = placement.snapPicker
                if picker ~= item then
                    placement.snapPicker = nil
                    picker.snapTarget, picker.preSnapTarget = item.label, nil
                    Dim(false)
                end
            elseif placement.selected == item then
                UI.ClearMoverSelection()
            else
                UI.SelectMover(handle)
            end
        elseif button == "RightButton" then
            if placement.snapPicker then return end
            if IsShiftKeyDown() then
                item.tempHidden = true
                if placement.selected == item then UI.ClearMoverSelection() end
                handle:Hide()
                return
            end
            UI.SelectMover(handle)
            OpenCogMenu(item)
        end
    end)
    handle:SetScript("OnDragStart", function() UI.StartMoverDrag(handle) end)
    handle:SetScript("OnDragStop", function() UI.StopMoverDrag(handle) end)
    handle:HookScript("OnShow", function(self)
        if item.tempHidden and placement.active then self:Hide() end
    end)
    handle:HookScript("OnHide", function()
        StopPlacementDrag(item)
        if placement.selected == item then UI.ClearMoverSelection() end
        if placement.menuItem == item then CloseMenus() end
        item.Collapse(true)
    end)
    Refresh(item)
end

-- Unlock Mode plate for an on-screen display. Hidden until the caller shows it. page and
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

--- The position to save for a window that drags itself outside Unlock Mode: CENTER on the
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

-- Element anchors were dropped; every move an anchor made was saved as the element's own
-- position, so only the old table goes. ns.Apply runs at login and on a profile switch.
local forget = CreateFrame("Frame")
forget:RegisterEvent("PLAYER_LOGIN")
forget:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    hooksecurefunc(ns, "Apply", function() ns.UnlockModeSettings.DB().anchors = nil end)
end)
