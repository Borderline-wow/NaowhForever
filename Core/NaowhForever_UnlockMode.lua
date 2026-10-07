-------------------------------------------------------------------------------
--  NaowhForever_UnlockMode.lua -- The HUD Editor's movers. An element is placed CENTER on the
--  screen centre and saved there. Clicking one selects it; its tag holds its X and Y and what
--  can be done with it. An element anchored to another follows it from the side picked on the
--  tag, keeping its gap. A drag lines up with other elements and the screen centre on guides.
--  The Elements panel lists them all, to find, hide while editing and lock in place, and every
--  change by hand can be undone.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local BLACK = { r = 0, g = 0, b = 0 }
-- A mover: the theme's background as dark glass over the element, an accent strip across its
-- top, and a black edge, muted grey under the mouse and the accent once selected.
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

-- Elements kept out of the way while editing (hidden) and held in place (locked), by label.
local function Marks(key)
    local db = ns.UnlockModeSettings.DB()
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

local function IsHidden(item) return Marks("hidden")[item.label] == true end
local function IsLocked(item) return Marks("locked")[item.label] == true end

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

-- The gap between the facing edges, in UIParent units: what info keeps across its side.
local function Gap(info)
    local side = info.side
    if side == "LEFT" then return -(info.x or 0) end
    if side == "RIGHT" then return info.x or 0 end
    if side == "TOP" then return info.y or 0 end
    return -(info.y or 0)
end

local function SetGap(info, gap)
    local side = info.side
    if side == "LEFT" then info.x = -gap
    elseif side == "RIGHT" then info.x = gap
    elseif side == "TOP" then info.y = gap
    else info.y = -gap end
end

-- Whether label's anchors lead, one after another, to root.
local function Follows(label, root)
    local info, depth = AnchorOf(label), 0
    while info and depth < MAX_DEPTH do
        if info.target == root then return true end
        info, depth = AnchorOf(info.target), depth + 1
    end
    return false
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
--  Guides: lines and numbers drawn over the screen in layers, each a pool its owner clears and
--  redraws. While an element is dragged its left, middle and right are pulled onto another
--  element's left, middle or right within GUIDE_SNAP pixels (its top, middle and bottom the
--  same), and onto the screen's centre lines. Each one it lands on is drawn from it to the
--  other element, with the gap between the two written on it. Alt holds them off for a drag,
--  the toolbar's Guides switch for good.
-------------------------------------------------------------------------------
local GUIDE_SNAP = 6           -- physical pixels an edge is pulled from
local GUIDE_LEVEL = 220        -- over the movers, under the tag
local LABEL_PAD, LABEL_H, LABEL_SIZE = 4, 16, 11
local OUTLINE_ALPHA = 0.45     -- the outline of where a drag started
local overlay

local function NewLayer() return { lines = {}, labels = {}, used = 0, usedLabels = 0 } end
local dragLayer, anchorLayer = NewLayer(), NewLayer()

local function Overlay()
    if not overlay then
        overlay = CreateFrame("Frame", nil, UIParent)
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(GUIDE_LEVEL)
    end
    return overlay
end

local function Clear(layer)
    for i = 1, layer.used do layer.lines[i]:Hide() end
    for i = 1, layer.usedLabels do layer.labels[i]:Hide() end
    layer.used, layer.usedLabels = 0, 0
end

-- A level or upright line from (x1, y1) to (x2, y2), in UIParent units.
local function DrawLine(layer, x1, y1, x2, y2, c, alpha)
    layer.used = layer.used + 1
    local tex = layer.lines[layer.used]
    if not tex then
        tex = Overlay():CreateTexture(nil, "OVERLAY")
        layer.lines[layer.used] = tex
    end
    local px = Pixel()
    tex:SetColorTexture(c.r, c.g, c.b, alpha or 1)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.min(x1, x2), math.min(y1, y2))
    tex:SetSize(math.max(px, math.abs(x2 - x1)), math.max(px, math.abs(y2 - y1)))
    tex:Show()
end

-- A length in UIParent units, written in whole pixels on a c plate centred at (x, y).
local function DrawLabel(layer, x, y, length, c, textColor)
    layer.usedLabels = layer.usedLabels + 1
    local label = layer.labels[layer.usedLabels]
    if not label then
        label = CreateFrame("Frame", nil, Overlay())
        label.fill = ns.Solid(label, "BACKGROUND", c, 1)
        label.fill:SetAllPoints()
        label.text = ns.Font(label, LABEL_SIZE)
        label.text:SetPoint("CENTER")
        layer.labels[layer.usedLabels] = label
    end
    label.fill:SetColorTexture(c.r, c.g, c.b, 1)
    label.text:SetTextColor(textColor.r, textColor.g, textColor.b, 1)
    label.text:SetText(tostring(math.floor(length / Pixel() + 0.5)))
    label:SetSize(label.text:GetStringWidth() + 2 * LABEL_PAD, LABEL_H)
    label:ClearAllPoints()
    label:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    label:Show()
end

local function GuidesOn() return ns.UnlockModeSettings.Get("guides") ~= false end

-- The elements a drag lines up with: shown, and not carried along by it.
local function Guiding(item, other)
    return other ~= item and other.handle:IsVisible() and not IsHidden(other) and not Follows(other.label, item.label)
end

-- best, or theirs - ours when that is nearer and within reach.
local function Nearer(best, ours, theirs, reach)
    local d = theirs - ours
    if math.abs(d) <= reach and (not best or math.abs(d) < math.abs(best)) then return d end
    return best
end

-- The nearest pull of three edges (a1..a3) onto three others (b1..b3).
local function Pull(best, reach, a1, a2, a3, b1, b2, b3)
    best = Nearer(Nearer(Nearer(best, a1, b1, reach), a1, b2, reach), a1, b3, reach)
    best = Nearer(Nearer(Nearer(best, a2, b1, reach), a2, b2, reach), a2, b3, reach)
    return Nearer(Nearer(Nearer(best, a3, b1, reach), a3, b2, reach), a3, b3, reach)
end

-- How far the box l, r, t, b moves to land on the nearest guide, nil on an axis with none.
local function SnapBy(item, l, r, t, b)
    local reach = GUIDE_SNAP * Pixel()
    local cx, cy = (l + r) / 2, (t + b) / 2
    local dx = Nearer(nil, cx, UIParent:GetWidth() / 2, reach)
    local dy = Nearer(nil, cy, UIParent:GetHeight() / 2, reach)
    for _, other in ipairs(placement.items) do
        if Guiding(item, other) then
            local ol, oright, ot, ob = Box(other)
            if ol then
                dx = Pull(dx, reach, l, cx, r, ol, (ol + oright) / 2, oright)
                dy = Pull(dy, reach, b, cy, t, ob, (ot + ob) / 2, ot)
            end
        end
    end
    return dx, dy
end

-- The first of a1..a3 on one of b1..b3, half a pixel either way.
local function OnOne(near, a1, a2, a3, b1, b2, b3)
    for i = 1, 3 do
        local a = i == 1 and a1 or i == 2 and a2 or a3
        if math.abs(a - b1) <= near or math.abs(a - b2) <= near or math.abs(a - b3) <= near then return a end
    end
end

-- The guides the dragged element sits on, and the gap to each element it lines up with.
local function DrawGuides(item)
    local l, r, t, b = Box(item)
    if not l then return end
    local St, px = ns.Shared.Style, Pixel()
    local c, near = St.GUIDE_RGB, px / 2
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = (l + r) / 2, (t + b) / 2
    if math.abs(cx - w / 2) <= near then DrawLine(dragLayer, w / 2, 0, w / 2, h, c) end
    if math.abs(cy - h / 2) <= near then DrawLine(dragLayer, 0, h / 2, w, h / 2, c) end
    for _, other in ipairs(placement.items) do
        if Guiding(item, other) then
            local ol, oright, ot, ob = Box(other)
            if ol then
                local x = OnOne(near, l, cx, r, ol, (ol + oright) / 2, oright)
                if x then
                    DrawLine(dragLayer, x, math.min(b, ob), x, math.max(t, ot), c)
                    if ob - t > near then DrawLabel(dragLayer, x, (t + ob) / 2, ob - t, c, T.bg)
                    elseif b - ot > near then DrawLabel(dragLayer, x, (ot + b) / 2, b - ot, c, T.bg) end
                end
                local y = OnOne(near, b, cy, t, ob, (ot + ob) / 2, ot)
                if y then
                    DrawLine(dragLayer, math.min(l, ol), y, math.max(r, oright), y, c)
                    if ol - r > near then DrawLabel(dragLayer, (r + ol) / 2, y, ol - r, c, T.bg)
                    elseif l - oright > near then DrawLabel(dragLayer, (oright + l) / 2, y, l - oright, c, T.bg) end
                end
            end
        end
    end
end

-- Where the drag started, a faint outline the element can be put back on.
local function DrawOutline(item)
    local l, r, t, b = item.startBox.l, item.startBox.r, item.startBox.t, item.startBox.b
    local c = T.fg
    DrawLine(dragLayer, l, t, r, t, c, OUTLINE_ALPHA)
    DrawLine(dragLayer, l, b, r, b, c, OUTLINE_ALPHA)
    DrawLine(dragLayer, l, b, l, t, c, OUTLINE_ALPHA)
    DrawLine(dragLayer, r, b, r, t, c, OUTLINE_ALPHA)
end

-- The middle of where two spans overlap, else of the first.
local function Middle(a1, a2, b1, b2)
    local lo, hi = math.max(a1, b1), math.min(a2, b2)
    if lo <= hi then return (lo + hi) / 2 end
    return (a1 + a2) / 2
end

-- The selected element's anchor: a line from its target's side to it, with the gap on it.
local function DrawAnchor(item)
    Clear(anchorLayer)
    local info = item and not item.ownAnchor and AnchorOf(item.label)
    local target = info and placement.byLabel[info.target]
    if not target then return end
    local tl, tr, tt, tb = Box(target)
    local cl, cr, ct, cb = Box(item)
    if not (tl and cl) then return end
    local side, x1, y1, x2, y2 = info.side
    if side == "TOP" or side == "BOTTOM" then
        x1 = Middle(tl, tr, cl, cr)
        x2 = x1
        if side == "TOP" then y1, y2 = tt, cb else y1, y2 = tb, ct end
    else
        y1 = Middle(tb, tt, cb, ct)
        y2 = y1
        if side == "RIGHT" then x1, x2 = tr, cl else x1, x2 = tl, cr end
    end
    DrawLine(anchorLayer, x1, y1, x2, y2, T.accent)
    DrawLabel(anchorLayer, (x1 + x2) / 2, (y1 + y2) / 2, Gap(info), T.accent, T.fg)
end

-------------------------------------------------------------------------------
--  Undo: before each change by hand the editor keeps where every element was and what each one
--  was anchored to. Undo puts that back, Redo the change again, Revert everything since the
--  HUD Editor opened. A run of arrow-key nudges to one element is one change.
-------------------------------------------------------------------------------
local UNDO_MAX = 50
local undo, redo = {}, {}
local lastNudged
local Refresh, ShowTag, RefreshPanel, PaintHistory, PaintMarks

local function Snapshot()
    local snap = { spots = {}, anchors = {} }
    for _, item in ipairs(placement.items) do
        local point, rel, relPoint, x, y = item.frame:GetPoint(1)
        if point == "CENTER" and rel == UIParent and relPoint == "CENTER" then snap.spots[item.label] = { x, y } end
    end
    for label, info in pairs(Anchors()) do
        if type(info) == "table" then
            snap.anchors[label] = { target = info.target, side = info.side, x = info.x, y = info.y }
        end
    end
    return snap
end

-- snap: the state before the change, taken earlier (a drag's start); else now. nudged: the
-- element an arrow key moves, so the run counts once.
local function Checkpoint(snap, nudged)
    if nudged and nudged == lastNudged then return end
    lastNudged = nudged
    undo[#undo + 1] = snap or Snapshot()
    if #undo > UNDO_MAX then table.remove(undo, 1) end
    wipe(redo)
    PaintHistory()
end

-- Whether item may be changed by hand: not while locked. Keeps the state before the change.
local function Change(item, nudged)
    if IsLocked(item) then return false end
    Checkpoint(nil, nudged)
    return true
end

local function Restore(snap)
    local anchors = Anchors()
    wipe(anchors)
    for label, info in pairs(snap.anchors) do
        anchors[label] = { target = info.target, side = info.side, x = info.x, y = info.y }
    end
    for _, item in ipairs(placement.items) do
        local spot = snap.spots[item.label]
        local point, rel, relPoint, x, y = item.frame:GetPoint(1)
        if spot and not (point == "CENTER" and rel == UIParent and relPoint == "CENTER" and x == spot[1] and y == spot[2]) then
            Place(item, spot[1], spot[2])
            item.save({ point = "CENTER", relPoint = "CENTER", x = spot[1], y = spot[2] })
        end
    end
    lastNudged = nil
    if placement.selected then Refresh(placement.selected) end
end

local function Step(from, to)
    if InCombatLockdown() or #from == 0 or placement.dragging then return end
    to[#to + 1] = Snapshot()
    Restore(table.remove(from))
    PaintHistory()
end

function UI.UndoMove() Step(undo, redo) end
function UI.RedoMove() Step(redo, undo) end

function UI.RevertMoves()
    if InCombatLockdown() or #undo == 0 or placement.dragging then return end
    redo[#redo + 1] = Snapshot()
    Restore(undo[1])
    wipe(undo)
    PaintHistory()
end

-------------------------------------------------------------------------------
--  Moving: arrow keys, typed numbers, drags and Center, all ending in a saved CENTER spot.
-------------------------------------------------------------------------------

-- dx, dy in UIParent units.
local function Nudge(item, dx, dy)
    if InCombatLockdown() or IsLocked(item) then return end
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
    Clear(dragLayer)
    local guided = GuidesOn() and not IsAltKeyDown()
    if guided then
        local hw, hh = item.boxW / 2, item.boxH / 2
        local dx, dy = SnapBy(item, cx - hw, cx + hw, cy + hh, cy - hh)
        cx, cy = cx + (dx or 0), cy + (dy or 0)
    end
    Place(item, (cx - item.boxX - w / 2) / ratio, (cy - item.boxY - h / 2) / ratio)
    Propagate(item.label)
    DrawOutline(item)
    if guided then DrawGuides(item) end
    ShowTag()
end

local function StopDrag(item)
    if not item or not item.dragging then return end
    if InCombatLockdown() and item.frame:IsProtected() then placement.pendingDrag = item; return end
    item.dragging = false
    item.dragged = true
    placement.dragging = nil
    placement.driver:SetScript("OnUpdate", nil)
    Clear(dragLayer)
    local l, r, t, b, ratio = Bounds(item.frame)
    if l and (math.abs(l - item.startL) > 0.5 or math.abs(t - item.startT) > 0.5) then
        Checkpoint(item.before)
        local x, y = Place(item, ((l + r) / 2 - UIParent:GetWidth() / 2) / ratio, ((t + b) / 2 - UIParent:GetHeight() / 2) / ratio)
        item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    Moved(item)
    for other in pairs(placement.unsaved) do
        local _, _, _, x, y = other.frame:GetPoint(1)
        other.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    wipe(placement.unsaved)
    item.before = nil
    Refresh(item)
end

-- Across to the middle of the screen; its height stays.
local function CenterAcross(item)
    local x = Position(item)
    if x and x ~= 0 and Change(item) then Nudge(item, -x * Pixel(), 0) end
end

-- Out of the HUD Editor and onto the element's settings: the options window draws over the
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
local SIDE_W, SIDE_LABEL_W, GAP_LABEL_W = 50, 28, 26
local ROW_GAP = 4                                -- between the tag's rows
local TAG_H = BOX_H + 2 * TAG_PAD
local TAG_H_ANCHORED = 2 * BOX_H + ROW_GAP + 2 * TAG_PAD
local TAG_LEVEL = 230                            -- over the movers
local SIDES = { "TOP", "LEFT", "RIGHT", "BOTTOM" }
local SIDE_NAMES = { TOP = "Top", LEFT = "Left", RIGHT = "Right", BOTTOM = "Bottom" }
local ACROSS = { TOP = "y", BOTTOM = "y", LEFT = "x", RIGHT = "x" }

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
    if d == 0 or not Change(item) then return end
    if box.axis == "X" then Nudge(item, d * Pixel(), 0) else Nudge(item, 0, d * Pixel()) end
end

local function Revert(box)
    box.border:SetColor(0, 0, 0, 1)
    box.value = nil
    ShowTag()
end

-- The anchored element back on its target after its side or gap changed, and saved there.
local function Reanchor(item)
    Apply(item)
    Propagate(item.label)
    Refresh(item)
end

-- A new side keeps the gap, and the offset along the side when it runs the same way.
local function SetSide(item, side)
    local info = AnchorOf(item.label)
    if not info or info.side == side or not Change(item) then return end
    local gap = Gap(info)
    if ACROSS[side] ~= ACROSS[info.side] then info.x, info.y = 0, 0 end
    info.side = side
    SetGap(info, gap)
    Reanchor(item)
end

local function TypedGap(box)
    local v = tonumber(box:GetText())
    box:ClearFocus()
    local item = placement.selected
    local info = item and AnchorOf(item.label)
    if not (info and v) or not Change(item) then return end
    SetGap(info, math.floor(v + 0.5) * Pixel())
    Reanchor(item)
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
        Checkpoint()
        Anchors()[item.label] = info
    end
    ShowTag()
end

local function AnchorClicked(tag)
    local item = tag.item
    if not item then return end
    if AnchorOf(item.label) then
        Checkpoint()
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
        letter:SetSize(LETTER_W, BOX_H)
        if left then
            letter:SetPoint("LEFT", left, "RIGHT", PAIR_GAP, 0)
        else
            letter:SetPoint("TOPLEFT", tag, "TOPLEFT", TAG_PAD, -TAG_PAD)
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
    ns.Tooltip(tag.settings, "Settings", "Opens its settings and leaves the HUD Editor.")

    -- The second row, while anchored: the target's side it sits off, and the gap.
    local sides = CreateFrame("Frame", nil, tag)
    sides:SetPoint("TOPLEFT", tag, "TOPLEFT", TAG_PAD, -(TAG_PAD + BOX_H + ROW_GAP))
    sides:SetPoint("TOPRIGHT", tag, "TOPRIGHT", -TAG_PAD, -(TAG_PAD + BOX_H + ROW_GAP))
    sides:SetHeight(BOX_H)
    local sideLabel = ns.Font(sides, 11, nil, T.muted)
    sideLabel:SetText("Side")
    sideLabel:SetSize(SIDE_LABEL_W, BOX_H)
    sideLabel:SetPoint("LEFT")
    local prev = sideLabel
    tag.side = {}
    for _, side in ipairs(SIDES) do
        local button = ns.Button(sides, SIDE_NAMES[side], SIDE_W, BOX_H, function()
            if tag.item then SetSide(tag.item, side) end
        end)
        button:SetPoint("LEFT", prev, "RIGHT", AXIS_GAP, 0)
        ns.Tooltip(button, SIDE_NAMES[side], "Sits off this side of what it is anchored to, keeping the gap.")
        tag.side[side] = button
        prev = button
    end
    local gapLabel = ns.Font(sides, 11, nil, T.muted)
    gapLabel:SetText("Gap")
    gapLabel:SetSize(GAP_LABEL_W, BOX_H)
    gapLabel:SetPoint("LEFT", prev, "RIGHT", PAIR_GAP, 0)
    local gap = ns.NewEditBox(sides)
    gap:SetSize(BOX_W, BOX_H)
    gap:SetPoint("LEFT", gapLabel, "RIGHT", AXIS_GAP, 0)
    gap:SetFont(ns.UIFontPath(), 12, "")
    gap:SetJustifyH("CENTER")
    gap:SetMaxLetters(5)
    gap:SetScript("OnEnterPressed", TypedGap)
    gap:SetScript("OnEscapePressed", gap.ClearFocus)
    gap:SetScript("OnEditFocusGained", function() gap.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
    gap:SetScript("OnEditFocusLost", Revert)
    tag.gap = gap
    tag.sides = sides
    return tag
end

-- The side the element sits off, lit in the accent.
local function PaintSides(tag, info)
    for side, button in pairs(tag.side) do
        local on = info.side == side
        local edge, text = on and T.accent or BLACK, on and T.accent or T.fg
        button._rest = edge
        button._border:SetColor(edge.r, edge.g, edge.b, 1)
        button.label:SetTextColor(text.r, text.g, text.b, 1)
    end
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
        DrawAnchor(nil)
        return
    end
    if not tag then
        tag = BuildTag()
        placement.tag = tag
    end
    local info = not item.ownAnchor and AnchorOf(item.label)
    local anchored = info and true or false
    local height = anchored and TAG_H_ANCHORED or TAG_H
    local _, _, _, bottom = Bounds(item.handle)
    local above = bottom ~= nil and bottom - TAG_GAP - height < 0
    if tag.item ~= item or tag.above ~= above or tag.anchored ~= anchored then
        tag.item, tag.above, tag.anchored = item, above, anchored
        tag.x.value, tag.y.value, tag.gap.value = nil, nil, nil
        tag:SetHeight(height)
        tag.sides:SetShown(anchored)
        tag.anchor:SetShown(not item.ownAnchor)
        tag.settings:SetShown(item.page ~= nil)
        tag.settings:ClearAllPoints()
        tag.settings:SetPoint("LEFT", item.ownAnchor and tag.center or tag.anchor, "RIGHT", AXIS_GAP, 0)
        local w = 2 * (LETTER_W + AXIS_GAP + BOX_W) + 2 * PAIR_GAP + CENTER_W + 2 * TAG_PAD
        if not item.ownAnchor then w = w + AXIS_GAP + ANCHOR_W end
        if item.page then w = w + AXIS_GAP + SETTINGS_W end
        if anchored then
            local sidesW = SIDE_LABEL_W + 4 * (AXIS_GAP + SIDE_W) + PAIR_GAP + GAP_LABEL_W + AXIS_GAP + BOX_W
            w = math.max(w, sidesW + 2 * TAG_PAD)
        end
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
    if info then
        SetBox(tag.gap, math.floor(Gap(info) / Pixel() + 0.5))
        PaintSides(tag, info)
    end
    DrawAnchor(item)
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
    local edge = picked and T.accent or item.hovered and T.muted or BLACK
    h._border:SetColor(edge.r, edge.g, edge.b, 1)
    h._fill:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, lit and MOVER_FILL_LIT or MOVER_FILL)
    h:SetFrameLevel(item.baseLevel + (lit and 100 or 0))
    if item == placement.selected then ShowTag() end
    RefreshPanel()
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
    if IsControlKeyDown() and (key == "Z" or key == "Y") then
        self:SetPropagateKeyboardInput(false)
        if key == "Y" or IsShiftKeyDown() then UI.RedoMove() else UI.UndoMove() end
        return
    end
    local item = placement.selected
    if not item or item.dragging then return end
    local dx = key == "LEFT" and -1 or key == "RIGHT" and 1 or 0
    local dy = key == "DOWN" and -1 or key == "UP" and 1 or 0
    if dx == 0 and dy == 0 then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    self:SetPropagateKeyboardInput(false)
    if not Change(item, item) then return end
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
    wipe(undo)
    wipe(redo)
    lastNudged = nil
    PaintHistory()
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

function UI.SelectMover(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item or IsHidden(item) then return end
    if placement.selected ~= item then UI.ClearMoverSelection() end
    placement.selected = item
    item.selected = true
    Refresh(item)
end

function UI.StartMoverDrag(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    if not item or IsHidden(item) then return end
    UI.SelectMover(handle)
    if IsLocked(item) then return end
    item.before = Snapshot()
    local l, r, t, b = Box(item)
    local fl, fr, ft, fb = Bounds(item.frame)
    if not (l and fl) then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    item.grabX, item.grabY = (l + r) / 2 - mx / scale, (t + b) / 2 - my / scale
    item.boxX, item.boxY = (l + r - fl - fr) / 2, (t + b - ft - fb) / 2
    item.boxW, item.boxH = r - l, t - b
    item.startL, item.startT = fl, ft
    item.startBox = item.startBox or {}
    item.startBox.l, item.startBox.r, item.startBox.t, item.startBox.b = l, r, t, b
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
local LOCK_BADGE, LOCK_INSET = 12, 4     -- the padlock in a locked mover's corner

-- A hidden element's plate goes clear and lets the mouse through; a locked one shows its
-- padlock.
function PaintMarks(item)
    local hidden, h = IsHidden(item), item.handle
    h:SetAlpha(hidden and 0 or 1)
    h:EnableMouse(not hidden)
    if h._lock then
        if not h._lockSet then
            h._lock:SetTexture(ns.Shared.Style.LOCK, nil, nil, "TRILINEAR")
            h._lock:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
            h._lockSet = true
        end
        h._lock:SetShown(IsLocked(item))
    end
    if hidden and placement.selected == item then UI.ClearMoverSelection() end
end
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
        RefreshPanel()
    end)
    handle:HookScript("OnShow", function() RefreshPanel() end)
    Refresh(item)
end

-- HUD Editor plate for an on-screen display. Hidden until the caller shows it. page,
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
    mover._border = ns.Border(mover, BLACK)
    local text = ns.Shared.Parts.HudText(ns.Font(mover, 12))
    text:SetPoint("CENTER", mover, "CENTER")
    text:SetText(label)
    mover.text = text
    mover._lock = mover:CreateTexture(nil, "OVERLAY")
    mover._lock:SetSize(LOCK_BADGE, LOCK_BADGE)
    mover._lock:SetPoint("TOPRIGHT", -LOCK_INSET, -LOCK_INSET)
    mover._lock:Hide()
    UI.BindMover(mover, frame, label, onMoved, page, feature, ownAnchor)
    mover:Hide()
    return mover
end

--- The position to save for a window that drags itself outside the HUD Editor: CENTER on the
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

-------------------------------------------------------------------------------
--  The Elements panel: every element on screen in the HUD Editor, by module, found by name. A
--  row's eye keeps the element out of the way while editing, its padlock holds it in place, and
--  a click on the row selects it.
-------------------------------------------------------------------------------
local PANEL_W, PANEL_PAD, PANEL_HEAD = 248, 12, 40
local PANEL_LIST_H = 420               -- the list's height; longer lists scroll
local ROW_H, GROUP_H = 24, 22
local ROW_ICON, ROW_ICON_GAP = 14, 8
local ROW_HIDDEN_ALPHA = 0.45          -- a hidden element's row
local ROW_FILL = 0.16                  -- the selected row, in the accent
local panel, panelQueued

local function GroupOf(item)
    return item.page and item.page:match("^[^/]+") or "Other"
end

local function PanelList()
    local filter = panel.search:GetText():lower()
    local groups, byName = {}, {}
    for _, item in ipairs(placement.items) do
        if item.handle:IsShown() and (filter == "" or item.label:lower():find(filter, 1, true)) then
            local name = GroupOf(item)
            local group = byName[name]
            if not group then
                group = { name = name }
                byName[name] = group
                groups[#groups + 1] = group
            end
            group[#group + 1] = item
        end
    end
    table.sort(groups, function(a, b) return a.name < b.name end)
    for _, group in ipairs(groups) do table.sort(group, function(a, b) return a.label < b.label end) end
    return groups
end

local function ToggleMark(key, item)
    local marks = Marks(key)
    marks[item.label] = not marks[item.label] or nil
    PaintMarks(item)
    Refresh(item)
    RefreshPanel()
end

local function RowEnter(row)
    local item = row.item
    if item and not IsHidden(item) then
        item.hovered = true
        Refresh(item)
    end
end

local function RowLeave(row)
    local item = row.item
    if item then
        item.hovered = false
        Refresh(item)
    end
end

local function NewRow(child)
    local Parts = ns.Shared.Parts
    local St = ns.Shared.Style
    local row = CreateFrame("Button", nil, child)
    row:SetHeight(ROW_H)
    row.fill = ns.Solid(row, "BACKGROUND", T.accent, ROW_FILL)
    row.fill:SetAllPoints()
    row.mark = ns.Solid(row, "ARTWORK", T.accent, 1)
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(MOVER_STRIP)
    row.lock = Parts.IconButton(row, function() ToggleMark("locked", row.item) end, St.LOCK, nil, "Lock in place")
    row.lock:SetSize(ROW_ICON, ROW_ICON)
    row.lock.icon:SetSize(ROW_ICON, ROW_ICON)
    row.lock:SetPoint("RIGHT", -PANEL_PAD, 0)
    row.eye = Parts.IconButton(row, function() ToggleMark("hidden", row.item) end, St.EYE, nil, "Hide while editing")
    row.eye:SetSize(ROW_ICON, ROW_ICON)
    row.eye.icon:SetSize(ROW_ICON, ROW_ICON)
    row.eye:SetPoint("RIGHT", row.lock, "LEFT", -ROW_ICON_GAP, 0)
    row.label = ns.Font(row, 12)
    row.label:SetPoint("LEFT", PANEL_PAD, 0)
    row.label:SetPoint("RIGHT", row.eye, "LEFT", -ROW_ICON_GAP, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.item then UI.SelectMover(self.item.handle) end
    end)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

local function PaintRow(row, item)
    local St = ns.Shared.Style
    local hidden, locked, picked = IsHidden(item), IsLocked(item), placement.selected == item
    row.item = item
    row.label:SetText(item.label)
    row.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, hidden and ROW_HIDDEN_ALPHA or 1)
    row.fill:SetShown(picked)
    row.mark:SetShown(picked)
    row.eye.icon:SetTexture(hidden and St.EYE_OFF or St.EYE, nil, nil, "TRILINEAR")
    row.eye.tip = hidden and "Show while editing" or "Hide while editing"
    local eye = hidden and T.fg or T.muted
    row.eye.icon:SetVertexColor(eye.r, eye.g, eye.b, 1)
    row.lock.tip = locked and "Unlock" or "Lock in place"
    local lock = locked and T.accent or T.muted
    row.lock.icon:SetVertexColor(lock.r, lock.g, lock.b, locked and 1 or ROW_HIDDEN_ALPHA)
end

local function DrawPanel()
    panelQueued = false
    if not (panel and panel:IsShown()) then return end
    local child, rows, titles = panel.child, panel.rows, panel.titles
    local y, r, g, shown, hidden = 0, 0, 0, 0, 0
    for _, group in ipairs(PanelList()) do
        g = g + 1
        local title = titles[g]
        if not title then
            title = ns.Font(child, 10, nil, T.muted)
            titles[g] = title
        end
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", PANEL_PAD, -(y + GROUP_H - 6))
        title:SetText(group.name:upper())
        title:Show()
        y = y + GROUP_H
        for _, item in ipairs(group) do
            r = r + 1
            local row = rows[r] or NewRow(child)
            rows[r] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            PaintRow(row, item)
            row:Show()
            y = y + ROW_H
            shown = shown + 1
            if IsHidden(item) then hidden = hidden + 1 end
        end
    end
    for i = r + 1, #rows do
        rows[i].item = nil
        rows[i]:Hide()
    end
    for i = g + 1, #titles do titles[i]:Hide() end
    child:SetHeight(math.max(1, y))
    panel.count:SetText(hidden > 0 and (shown .. ns.Shared.Style.PLACE_DOT .. hidden .. " hidden") or tostring(shown))
end

-- One redraw a frame, however many changes ask for it.
function RefreshPanel()
    if panelQueued or not (panel and panel:IsShown()) then return end
    panelQueued = true
    C_Timer.After(0, DrawPanel)
end

local function BuildPanel()
    if panel then return panel end
    local St = ns.Shared.Style
    local f = CreateFrame("Frame", "NaowhForeverHudElements", UIParent)
    f:SetSize(PANEL_W, PANEL_HEAD + St.SEARCH_H + PANEL_PAD + PANEL_LIST_H + PANEL_PAD)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(505)
    f:SetClampedToScreen(true)
    ns.AllowOffscreen(f)
    ns.Shared.Parts.Backdrop(f):Paint(St.BACKDROP_ALPHA)
    ns.Border(f, St.BORDER_RGB)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local title = ns.Font(f, 14)
    title:SetPoint("LEFT", f, "TOPLEFT", PANEL_PAD, -PANEL_HEAD / 2)
    title:SetText("Elements")
    f.count = ns.Font(f, 11, nil, T.muted)
    f.count:SetPoint("RIGHT", f, "TOPRIGHT", -PANEL_PAD, -PANEL_HEAD / 2)
    f.search = ns.Shared.Parts.SearchBox(f, "Find an element", function() RefreshPanel() end)
    f.search:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_HEAD)
    f.search:SetPoint("TOPRIGHT", -PANEL_PAD, -PANEL_HEAD)
    f.search:SetHeight(St.SEARCH_H)
    local scroll = UI.SlimScroll(f)
    scroll:SetPoint("TOPLEFT", 0, -(PANEL_HEAD + St.SEARCH_H + PANEL_PAD))
    scroll:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_PAD)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(PANEL_W - PANEL_PAD, 1)
    scroll:SetScrollChild(child)
    f.child, f.rows, f.titles = child, {}, {}
    f:SetScript("OnShow", function() RefreshPanel() end)
    f:Hide()
    panel = f
    return f
end

local function ShowPanel(shown)
    if shown then BuildPanel():Show() elseif panel then panel:Hide() end
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

-- The HUD Editor's toolbar: the windows' backdrop and black edge, a header with the logo, the
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
local OFF_ALPHA = 0.4                 -- a module's switches while it is off; Undo with nothing to undo
local HISTORY_W, ELEMENTS_W = 64, 84

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

-- Undo, Redo and Revert dim with nothing to do, Elements lights while its panel shows.
local function Usable(button, on)
    button:SetAlpha(on and 1 or OFF_ALPHA)
    button:EnableMouse(on)
end

function PaintHistory()
    local f = configToolbar
    if not f then return end
    Usable(f._undo, #undo > 0)
    Usable(f._redo, #redo > 0)
    Usable(f._revert, #undo > 0)
    local on = ns.UnlockModeSettings.Get("elementsPanel") ~= false
    local edge = on and T.accent or BLACK
    f._elements._rest = edge
    f._elements._border:SetColor(edge.r, edge.g, edge.b, 1)
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
    title:SetText("HUD Editor")
    local exit = ns.AccentBorder(ns.Button(f, "Exit Config", EXIT_W, EXIT_H, function() ns.HideRaidReminderAnchorConfig() end))
    exit:SetPoint("RIGHT", f, "TOPRIGHT", -BAR_PAD, -BAR_HEAD / 2)
    BarRule(f, BAR_HEAD)

    local y = BAR_HEAD + BAR_GAP
    f._undo = ns.Button(f, "Undo", HISTORY_W, EXIT_H, function() UI.UndoMove() end)
    f._undo:SetPoint("TOPLEFT", BAR_PAD, -y)
    ns.Tooltip(f._undo, "Undo", "Puts back the last change. Ctrl + Z.")
    f._redo = ns.Button(f, "Redo", HISTORY_W, EXIT_H, function() UI.RedoMove() end)
    f._redo:SetPoint("LEFT", f._undo, "RIGHT", BAR_GAP / 2, 0)
    ns.Tooltip(f._redo, "Redo", "Makes the change again. Ctrl + Y.")
    f._revert = ns.Button(f, "Revert", HISTORY_W, EXIT_H, function() UI.RevertMoves() end)
    f._revert:SetPoint("LEFT", f._redo, "RIGHT", BAR_GAP / 2, 0)
    ns.Tooltip(f._revert, "Revert", "Puts back everything changed since the HUD Editor opened.")
    f._elements = ns.Button(f, "Elements", ELEMENTS_W, EXIT_H, function()
        local on = ns.UnlockModeSettings.Get("elementsPanel") == false
        ns.UnlockModeSettings.Set("elementsPanel", on)
        ShowPanel(on)
        PaintHistory()
    end)
    f._elements:SetPoint("TOPRIGHT", -BAR_PAD, -y)
    ns.Tooltip(f._elements, "Elements", "Shows or hides the list of every element.")
    y = y + EXIT_H + BAR_GAP
    f._guides = BarSwitch(f, "Guides", 0, y, GuidesOn, function(v) ns.UnlockModeSettings.Set("guides", v) end)
    ns.Tooltip(f._guides, "Guides", "Lines a dragged element up with the others and the screen centre. Hold Alt to drag freely.")
    y = y + SWITCH_ROW
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
    f._guides._refreshValue()
    PaintHistory()
    ShowPanel(ns.UnlockModeSettings.Get("elementsPanel") ~= false)
    for _, item in ipairs(placement.items) do PaintMarks(item) end
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
    ShowPanel(false)
    if reopenWindowOnExit then
        reopenWindowOnExit = false
        if not windowClosing and ns.OpenOptionsWindow then ns.OpenOptionsWindow() end
    end
end

function ns.IsRaidReminderAnchorConfigActive()
    return configActive
end
