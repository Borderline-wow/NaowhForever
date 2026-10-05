-------------------------------------------------------------------------------
--  NaowhForever_UnlockMode.lua -- Unlock Mode's movers and EllesmereUI's anchor system.
--  An element is placed CENTER on the screen centre unless it is anchored: to a side of
--  another element, or to a screen edge (Relative to Screen). Anchors are kept per profile in
--  ns.UnlockModeSettings by mover label, and re-applied whenever a target moves or resizes.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local BLACK = { r = 0, g = 0, b = 0 }
local WARNING = { r = 1, g = 0.35, b = 0.35 }
local CHAIN_TEX = "Interface\\AddOns\\NaowhForever\\Media\\chain.tga"
local MENU_W, SUB_W, DD_W, ITEM_H = 220, 150, 170, 24
local HOVER_DELAY, ANIM_DUR = 0.12, 0.15
local SNAP_THRESH = 6          -- UI units a dragged edge snaps from
local DIM_ALPHA, DIM_FADE = 0.30, 0.5
local MAX_DEPTH = 20           -- anchor chain length followed at most
local LINE_TEX = "Interface\\AddOns\\NaowhForever\\Media\\soft-line.tga"
local PULSE_TEX = "Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask"

local placement = { active = false, items = {}, byLabel = {}, unsaved = {} }

-------------------------------------------------------------------------------
--  Pixels: one physical pixel in UIParent units, and EllesmereUI's snaps.
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

-------------------------------------------------------------------------------
--  Anchor records: anchors[label] = { target, side, offsetX, offsetY, edge }
--  target is a mover label or a SCREEN_ key; side is the side of the target the element sits
--  on. Offsets are UIParent units, from the element's near edge to the target's edge on the
--  anchored axis and centre to centre on the other. edge = { key, side, offset } holds the
--  other axis to a screen edge.
-------------------------------------------------------------------------------
local SCREEN = { SCREEN_LEFT = "X", SCREEN_RIGHT = "X", SCREEN_TOP = "Y", SCREEN_BOTTOM = "Y" }
local SCREEN_NAMES = { SCREEN_LEFT = "Left Screen Edge", SCREEN_RIGHT = "Right Screen Edge",
    SCREEN_TOP = "Top Screen Edge", SCREEN_BOTTOM = "Bottom Screen Edge" }
local SIDES = { "Left", "Right", "Top", "Bottom" }
local EDGE_ITEMS = {
    { key = "SCREEN_LEFT", side = "RIGHT", text = "Left" },
    { key = "SCREEN_RIGHT", side = "LEFT", text = "Right" },
    { key = "SCREEN_TOP", side = "BOTTOM", text = "Top" },
    { key = "SCREEN_BOTTOM", side = "TOP", text = "Bottom" },
    { text = "Center" },
}

local function Anchors()
    local db = ns.UnlockModeSettings.DB()
    if type(db.anchors) ~= "table" then db.anchors = {} end
    return db.anchors
end

local function AnchorOf(label)
    local info = Anchors()[label]
    if type(info) == "table" and type(info.target) == "string" then return info end
end

local function LabelOf(key) return SCREEN_NAMES[key] or key end

-- Keeps a screen edge on the other axis; one on the new target's own axis no longer applies.
local function SetAnchorInfo(label, target, side, offsetX, offsetY)
    local prev = AnchorOf(label)
    local edge = prev and type(prev.edge) == "table" and prev.edge or nil
    if edge and SCREEN[target] and SCREEN[edge.key] == SCREEN[target] then edge = nil end
    Anchors()[label] = { target = target, side = side, offsetX = offsetX, offsetY = offsetY, edge = edge }
end

local function ClearAnchorInfo(label) Anchors()[label] = nil end

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

-- A screen edge is a strip one unit thick just outside the screen, so its inner edge is the
-- screen's edge and its centre on the other axis the screen's centre.
local function Rect(key)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if key == "SCREEN_LEFT" then return -1, 0, h, 0 end
    if key == "SCREEN_RIGHT" then return w, w + 1, h, 0 end
    if key == "SCREEN_TOP" then return 0, w, h + 1, h end
    if key == "SCREEN_BOTTOM" then return 0, w, 0, -1 end
    local item = placement.byLabel[key]
    if item then return Box(item) end
end

-- The element's centre for its record, given the target's rect and its own size.
local function Place(info, tL, tR, tT, tB, cW, cH)
    local tCX, tCY = (tL + tR) / 2, (tT + tB) / 2
    local side, ox, oy = info.side, info.offsetX, info.offsetY
    local cx, cy
    if side == "LEFT" then cx, cy = tL + ox - cW / 2, tCY + oy
    elseif side == "RIGHT" then cx, cy = tR + ox + cW / 2, tCY + oy
    elseif side == "TOP" then cx, cy = tCX + ox, tT + oy + cH / 2
    elseif side == "BOTTOM" then cx, cy = tCX + ox, tB + oy - cH / 2
    else cx, cy = tCX + ox, tCY + oy end
    local e = info.edge
    if type(e) == "table" and SCREEN[e.key] and e.offset then
        local el, er, et, eb = Rect(e.key)
        if SCREEN[e.key] == "X" then
            if e.side == "RIGHT" then cx = er + e.offset + cW / 2 else cx = el + e.offset - cW / 2 end
        else
            if e.side == "TOP" then cy = et + e.offset + cH / 2 else cy = eb + e.offset - cH / 2 end
        end
    end
    return cx, cy
end

-- Offsets for a side from where the element is now.
local function CaptureOffsets(item, target, side)
    local tL, tR, tT, tB = Rect(target)
    local cL, cR, cT, cB = Box(item)
    if not (tL and cL) then return end
    local tCX, tCY, cCX, cCY = (tL + tR) / 2, (tT + tB) / 2, (cL + cR) / 2, (cT + cB) / 2
    if side == "LEFT" then return cR - tL, cCY - tCY end
    if side == "RIGHT" then return cL - tR, cCY - tCY end
    if side == "TOP" then return cCX - tCX, cB - tT end
    return cCX - tCX, cT - tB
end

local function CaptureEdgeOffset(item, key, side)
    local el, er, et, eb = Rect(key)
    local cL, cR, cT, cB = Box(item)
    if not cL then return end
    if SCREEN[key] == "X" then
        if side == "RIGHT" then return cL - er end
        return cR - el
    end
    if side == "TOP" then return cB - et end
    return cT - eb
end

-- Puts the element's centre (its Box) at (cx, cy) in UIParent units: its frame CENTER on the
-- screen centre, snapped to whole pixels, and saved there; during a drag the save waits for the
-- drop. False when it is already there.
local function MoveTo(item, cx, cy, raw)
    local frame = item.frame
    local bl, br, bt, bb = Box(item)
    local fl, fr, ft, fb = Bounds(frame)
    if not (bl and fl) then return false end
    cx = cx - ((bl + br) - (fl + fr)) / 2
    cy = cy - ((bt + bb) - (ft + fb)) / 2
    local es, ratio = frame:GetEffectiveScale(), frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = (cx - UIParent:GetWidth() / 2) / ratio
    local y = (cy - UIParent:GetHeight() / 2) / ratio
    if not raw then
        x, y = SnapCenter(x, frame:GetWidth(), es), SnapCenter(y, frame:GetHeight(), es)
    end
    local point, rel, relPoint, px, py = frame:GetPoint(1)
    local half = Perfect() / es * 0.5
    if point == "CENTER" and rel == UIParent and relPoint == "CENTER"
        and math.abs(px - x) < half and math.abs(py - y) < half then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if placement.dragging then
        placement.unsaved[item] = true
    else
        item.save({ point = "CENTER", relPoint = "CENTER", x = x, y = y })
    end
    return true
end

-- An anchored element to its place. A protected one waits for the end of combat.
local function Apply(item)
    local info = not item.ownAnchor and AnchorOf(item.label)
    if not info then return end
    local tL, tR, tT, tB = Rect(info.target)
    local cL, cR, cT, cB = Box(item)
    if not (tL and cL) then return end
    if info.offsetX == nil or info.offsetY == nil then info.offsetX, info.offsetY = 0, 0 end
    local cx, cy = Place(info, tL, tR, tT, tB, cR - cL, cT - cB)
    if InCombatLockdown() and item.frame:IsProtected() then
        placement.parked = true
        return
    end
    MoveTo(item, cx, cy)
end

-- Everything anchored to label (or holding to it as its screen edge), and on down the chain.
local function Propagate(label, visited)
    visited = visited or {}
    if visited[label] then return end
    visited[label] = true
    for child, info in pairs(Anchors()) do
        if type(info) == "table" and (info.target == label or (type(info.edge) == "table" and info.edge.key == label)) then
            local item = placement.byLabel[child]
            if item and item ~= placement.dragging then
                Apply(item)
                Propagate(child, visited)
            end
        end
    end
end

local function Depth(label)
    local depth, seen = 0, {}
    local info = AnchorOf(label)
    while info and not SCREEN[info.target] and depth < MAX_DEPTH do
        if seen[label] then return 0 end
        seen[label] = true
        depth = depth + 1
        label = info.target
        info = AnchorOf(label)
    end
    return depth
end

-- Every anchor, parents first so a child never reads its target's old spot.
local function ReapplyAll()
    local list = {}
    for label in pairs(Anchors()) do
        local item = placement.byLabel[label]
        if item and AnchorOf(label) then list[#list + 1] = { item = item, depth = Depth(label) } end
    end
    table.sort(list, function(a, b) return a.depth < b.depth end)
    for _, e in ipairs(list) do Apply(e.item) end
end
UI.ReapplyAnchors = ReapplyAll

-- Size and position changes outside a drag: one pass a frame, whatever asked. A size change
-- re-places the element itself (its near edge stays on its target); a move, whoever made it,
-- only takes what is anchored to it along.
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

local function Moved(item)
    local l, t = item.frame:GetLeft(), item.frame:GetTop()
    if not (l and t) then return end
    if item.lastL and math.abs(l - item.lastL) < 0.5 and math.abs(t - item.lastT) < 0.5 then return end
    item.lastL, item.lastT = l, t
    Queue(item.label)
end

-- Anchors catch up at login, after every profile switch (ns.Apply), after combat held a
-- protected one back, and when the screen changes size.
local function WatchAnchors()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        if not placement.followsApply then
            placement.followsApply = true
            hooksecurefunc(ns, "Apply", function() C_Timer.After(0, ReapplyAll) end)
        end
        placement.parked = nil
        C_Timer.After(0, ReapplyAll)
    end)
    local screen = CreateFrame("Frame", nil, UIParent)
    screen:SetAllPoints()
    screen:SetScript("OnSizeChanged", function()
        for key in pairs(SCREEN) do Queue(key) end
    end)
end

-------------------------------------------------------------------------------
--  Unlock Mode visuals shared by every mover: the dimmer, red flash, connector lines.
-------------------------------------------------------------------------------
local Refresh, CancelPick, CloseMenus

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

local function FlashRed(item)
    local h = item.handle
    if not h._redBorder then
        h._redBorder = ns.Border(h, WARNING, 0)
        h._redBorder._frame:SetFrameLevel(h:GetFrameLevel() + 4)
        h._redFlash = CreateFrame("Frame", nil, h)
    end
    local elapsed = 0
    h._redFlash:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.8 then
            h._redBorder:SetColor(WARNING.r, WARNING.g, WARNING.b, 0.5 + 0.5 * math.sin(elapsed * 10))
        elseif elapsed < 1.5 then
            h._redBorder:SetColor(WARNING.r, WARNING.g, WARNING.b, math.max(0, 1 - (elapsed - 0.8) / 0.7))
        else
            h._redBorder:SetColor(WARNING.r, WARNING.g, WARNING.b, 0)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- A refusal at the cursor, following it for three seconds.
local function Reject(item, text)
    CancelPick()
    FlashRed(item)
    if not placement.rejectAnchor then
        placement.rejectAnchor = CreateFrame("Frame", nil, UIParent)
        placement.rejectAnchor:SetSize(1, 1)
    end
    UI.ShowWidgetTooltip(placement.rejectAnchor, text, { anchor = "cursor", force = true })
    local elapsed = 0
    placement.rejectAnchor:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 3 then
            UI.HideWidgetTooltip()
            self:SetScript("OnUpdate", nil)
            return
        end
        UI.ShowWidgetTooltip(self, text, { anchor = "cursor", force = true })
    end)
end

-- Lines from each anchored mover to its target while either is hovered or dragged: they grow
-- from the child in half a second, then a pulse runs along them every 2.5 seconds.
local LINE_DUR, PULSE_CYCLE, PULSE_SWEEP = 0.5, 2.5, 0.56

local function UIPoint(handle)
    local l, r, t, b = Bounds(handle)
    if l then return (l + r) / 2, (t + b) / 2 end
end

local function UpdateLines()
    local lines = placement.lines
    local idx, now = 0, GetTime()
    for child, info in pairs(Anchors()) do
        local cm = type(info) == "table" and placement.byLabel[child]
        local tm = cm and placement.byLabel[info.target]
        if cm and tm and cm.handle:IsVisible() and tm.handle:IsVisible() then
            local key = child .. ":" .. info.target
            if cm.hoverConfirmed or cm.dragging or tm.hoverConfirmed or tm.dragging then
                lines.anim[key] = lines.anim[key] or now
                local t = math.min((now - lines.anim[key]) / LINE_DUR, 1)
                local ease = 1 - (1 - t) * (1 - t)
                local x1, y1 = UIPoint(cm.handle)
                local x2, y2 = UIPoint(tm.handle)
                if x1 and x2 then
                    idx = idx + 1
                    local line, pulse = lines.Get(idx)
                    line:SetStartPoint("BOTTOMLEFT", UIParent, x1, y1)
                    line:SetEndPoint("BOTTOMLEFT", UIParent, x1 + (x2 - x1) * ease, y1 + (y2 - y1) * ease)
                    line:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 0.75 * ease)
                    line:Show()
                    pulse:Hide()
                    if ease >= 1 then
                        local cycle = ((now - lines.anim[key] - 0.3) % PULSE_CYCLE) / PULSE_CYCLE
                        if cycle <= PULSE_SWEEP then
                            local st = cycle / PULSE_SWEEP
                            local s = st * st * (3 - 2 * st)
                            local head, tail = math.min(1, s * 2), math.min(1, math.max(0, s * 2 - 1))
                            local fade = 1
                            if s < 0.1 then fade = s / 0.1 elseif s > 0.7 then fade = (1 - s) / 0.3 end
                            if head > tail then
                                pulse:SetStartPoint("BOTTOMLEFT", UIParent, x1 + (x2 - x1) * tail, y1 + (y2 - y1) * tail)
                                pulse:SetEndPoint("BOTTOMLEFT", UIParent, x1 + (x2 - x1) * head, y1 + (y2 - y1) * head)
                                pulse:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 0.5 * math.max(0, fade))
                                pulse:Show()
                            end
                        end
                    end
                end
            else
                lines.anim[key] = nil
            end
        end
    end
    for i = idx + 1, #lines.pool do
        lines.pool[i]:Hide()
        lines.pulses[i]:Hide()
    end
end

local function ShowLines(on)
    if not placement.lines then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("BACKGROUND")
        f:SetFrameLevel(1)
        f:SetAllPoints()
        f:EnableMouse(false)
        local lines = { frame = f, pool = {}, pulses = {}, anim = {} }
        function lines.Get(i)
            if not lines.pool[i] then
                local line = f:CreateLine(nil, "ARTWORK", nil, 1)
                line:SetThickness(3)
                line:SetTexture(LINE_TEX)
                local pulse = f:CreateLine(nil, "ARTWORK", nil, 2)
                pulse:SetThickness(3)
                pulse:SetTexture(PULSE_TEX)
                lines.pool[i], lines.pulses[i] = line, pulse
            end
            return lines.pool[i], lines.pulses[i]
        end
        placement.lines = lines
    end
    local f = placement.lines.frame
    f:SetShown(on)
    f:SetScript("OnUpdate", on and UpdateLines or nil)
    if not on then
        for i = 1, #placement.lines.pool do
            placement.lines.pool[i]:Hide()
            placement.lines.pulses[i]:Hide()
        end
        wipe(placement.lines.anim)
    end
end

-- A screen edge drawn while its Relative to Screen row is hovered, or flashed once it is picked.
local function EdgeMarker(key, flash)
    if not placement.marker then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(400)
        f:SetAllPoints()
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.9)
        placement.marker = f
    end
    local f, tex = placement.marker, placement.marker.tex
    if not key then
        if not f.flashing then f:Hide() end
        return
    end
    local px = 5 * Mult()
    tex:ClearAllPoints()
    if key == "SCREEN_LEFT" then tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT"); tex:SetWidth(px)
    elseif key == "SCREEN_RIGHT" then tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetWidth(px)
    elseif key == "SCREEN_TOP" then tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(px)
    else tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(px) end
    f:Show()
    if flash then
        f.flashing = true
        C_Timer.After(0.8, function()
            f.flashing = nil
            f:Hide()
        end)
    end
end

-------------------------------------------------------------------------------
--  Menus: the cog menu, its Relative to Screen flyout, and the anchor side dropdown. One of
--  each, rebuilt on every open, over a full-screen click catcher that closes them.
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
    if row.box then row.box:Hide() end
    if row.arrow then row.arrow:Hide() end
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

local function Paint(row, c) row.label:SetTextColor(c.r, c.g, c.b, 1) end

-- A clickable row, filled grey on hover. color: its text colour, when not the theme's.
local function Action(menu, text, onClick, color)
    local row = Row(menu)
    local rest = color or T.fg
    row.label:SetText(ns.L(text))
    Paint(row, rest)
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
    for _, menu in ipairs({ placement.cogMenu, placement.edgeMenu, placement.sideMenu }) do
        if menu then menu:Hide() end
    end
    if placement.catcher then placement.catcher:Hide() end
    local item = placement.menuItem
    placement.menuItem = nil
    if not item then return end
    item.menuOpen = false
    if not item.handle:IsMouseOver() then
        item.hovered = false
        item.Collapse()
        Refresh(item)
    end
end

local function AtCursor(menu)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

-------------------------------------------------------------------------------
--  Moving: nudges, drags and Center on Screen, all ending in a saved CENTER spot or, for an
--  anchored element, new offsets on the same anchor.
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

-- dx, dy in UIParent units. An anchored element moves by its offsets, so nothing is read back
-- from the screen and nudges never drift.
local function Nudge(item, dx, dy)
    if InCombatLockdown() then return end
    if not item.menuOpen then item.Collapse(true) end
    local info = not item.ownAnchor and AnchorOf(item.label)
    if info and not Rect(info.target) then return end
    if info then
        info.offsetX, info.offsetY = (info.offsetX or 0) + dx, (info.offsetY or 0) + dy
        local e = info.edge
        if type(e) == "table" and SCREEN[e.key] and e.offset then
            e.offset = e.offset + (SCREEN[e.key] == "X" and dx or dy)
        end
        Apply(item)
    else
        local l, r, t, b = Box(item)
        if not l then return end
        MoveTo(item, (l + r) / 2 + dx, (t + b) / 2 + dy, true)
    end
    Propagate(item.label)
    Refresh(item)
    if item.syncOffsets then item.syncOffsets() end
end

-- After a drop: the same anchor, offsets from where it landed.
local function Recapture(item)
    local info = not item.ownAnchor and AnchorOf(item.label)
    if not info then return end
    local ox, oy = CaptureOffsets(item, info.target, info.side)
    if ox then info.offsetX, info.offsetY = ox, oy end
    local e = info.edge
    if type(e) == "table" and SCREEN[e.key] then e.offset = CaptureEdgeOffset(item, e.key, e.side) end
end

-- Snapping while dragging: the closest other mover shown, or the one picked as its snap target,
-- lines up an edge or centre within SNAP_THRESH on each axis. Elements anchored below the
-- dragged one and its siblings are left out; its own target is not.
local function SnapPosition(item, cx, cy, halfW, halfH)
    local snap = placement.snapInfo
    wipe(snap)
    if ns.UnlockModeSettings.Get("snap") == false then return cx, cy end
    local dL, dR, dT, dB = cx - halfW, cx + halfW, cy + halfH, cy - halfH
    local target = item.snapTarget and placement.byLabel[item.snapTarget]
    if not (target and target.handle:IsVisible()) then
        target = nil
        local excluded = {}
        local function Exclude(label)
            for child, info in pairs(Anchors()) do
                if type(info) == "table" and info.target == label and not excluded[child] then
                    excluded[child] = true
                    Exclude(child)
                end
            end
        end
        Exclude(item.label)
        local mine = AnchorOf(item.label)
        if mine then
            for sib, info in pairs(Anchors()) do
                if type(info) == "table" and sib ~= item.label and info.target == mine.target then excluded[sib] = true end
            end
        end
        local best = math.huge
        for _, other in ipairs(placement.items) do
            if other ~= item and not excluded[other.label] and other.handle:IsVisible() then
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

-- Full-screen guides on a snapped axis, and a pulse on the mover snapped to.
local function ShowGuides()
    local g, snap = placement.guides, placement.snapInfo
    if not g then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("BACKGROUND")
        f:SetFrameLevel(2)
        f:SetAllPoints()
        g = { frame = f, x = ns.Solid(f, "OVERLAY", T.accent, 0.5), y = ns.Solid(f, "OVERLAY", T.accent, 0.5),
            pulse = CreateFrame("Frame", nil, f) }
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
                h._snapBorder = ns.Border(h, T.fg, 0)
                h._snapBorder._frame:SetFrameLevel(h:GetFrameLevel() + 3)
            end
            local elapsed = 0
            g.pulse:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                h._snapBorder:SetColor(T.fg.r, T.fg.g, T.fg.b, (0.45 + 0.45 * math.sin(elapsed * 9.42)) * 0.9)
            end)
        else
            g.pulse:SetScript("OnUpdate", nil)
        end
    end
end

local function HideGuides()
    local g = placement.guides
    if not g then return end
    g.frame:Hide()
    if g.target and g.target.handle._snapBorder then g.target.handle._snapBorder:SetColor(1, 1, 1, 0) end
    g.target = nil
    g.pulse:SetScript("OnUpdate", nil)
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
    local visited = { [item.label] = true }
    for child, info in pairs(Anchors()) do
        if type(info) == "table" and info.target == item.label and placement.byLabel[child] then
            Apply(placement.byLabel[child])
            Propagate(child, visited)
        end
    end
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
        Recapture(item)
        Propagate(item.label)
    end
    for other in pairs(placement.unsaved) do SaveWhereItIs(other) end
    wipe(placement.unsaved)
    Refresh(item)
end

local function CenterOnScreen(item)
    if InCombatLockdown() then return end
    local l, r = Box(item)
    if not l then return end
    local px = ToPixels((l + r) / 2 - UIParent:GetWidth() / 2)
    if px ~= 0 then Nudge(item, FromPixels(-px), 0) end
end

-------------------------------------------------------------------------------
--  Anchoring from a mover: pick mode, the side dropdown and Relative to Screen.
-------------------------------------------------------------------------------
local function StartPick(item)
    CancelPick()
    CloseMenus()
    placement.picking = item
    item.ShowPickText("Click any element\nto anchor to it")
    Dim(true)
end

function CancelPick()
    local item = placement.picking
    if item then
        placement.picking = nil
        item.HidePickText()
        if item.handle:IsMouseOver() then item.Expand() else item.Collapse() end
        Dim(false)
    end
    local picker = placement.snapPicker
    if picker then
        placement.snapPicker = nil
        picker.snapTarget = picker.preSnapTarget
        picker.preSnapTarget = nil
        Dim(false)
    end
    if placement.sideMenu then placement.sideMenu:Hide() end
end

local function Unanchor(item)
    ClearAnchorInfo(item.label)
    SaveWhereItIs(item)
    Refresh(item)
end

local function ShowSideMenu(child, target)
    local menu = placement.sideMenu or MenuFrame(260)
    placement.sideMenu = menu
    ClearMenu(menu, DD_W)
    for _, name in ipairs(SIDES) do
        local side = name:upper()
        Action(menu, ("Anchor to %s"):format(name), function()
            CloseMenus()
            SetAnchorInfo(child.label, target.label, side)
            Apply(child)
            C_Timer.After(0, function() Propagate(child.label) end)
            Refresh(child)
        end)
    end
    if AnchorOf(child.label) then
        Divider(menu)
        Action(menu, "Remove Anchor", function()
            CloseMenus()
            ClearAnchorInfo(child.label)
            Refresh(child)
        end, WARNING)
    end
    AtCursor(menu)
    Catcher()
    Finish(menu)
end

-- The target picked: refused when it already follows the element, or sits two or more links
-- above it; otherwise the side dropdown opens at the cursor.
local function PickTarget(target)
    local child = placement.picking
    if target == child then
        CancelPick()
        return
    end
    local visited, walk = { [child.label] = true }, target.label
    while walk do
        if visited[walk] then return Reject(target, "This would create a circular anchor") end
        visited[walk] = true
        local info = AnchorOf(walk)
        walk = info and info.target
    end
    local depth, up = 0, AnchorOf(child.label)
    while up and depth < MAX_DEPTH do
        depth = depth + 1
        if up.target == target.label and depth >= 2 then
            return Reject(target, "This would create a circular anchor")
        end
        up = AnchorOf(up.target)
    end
    CancelPick()
    ShowSideMenu(child, target)
end

-- With nothing anchored the edge becomes the anchor, as does one replacing an edge on its own
-- axis; under an element anchor it holds the other axis. The element stays where it is.
local function SetScreenAnchor(item, key, side)
    if InCombatLockdown() then return end
    local info = AnchorOf(item.label)
    local axis = SCREEN[key]
    local crossEdge = info and type(info.edge) == "table" and SCREEN[info.edge.key] and SCREEN[info.edge.key] ~= axis
    if not info or SCREEN[info.target] == axis or crossEdge then
        local ox, oy = CaptureOffsets(item, key, side)
        if not ox then return end
        SetAnchorInfo(item.label, key, side, ox, oy)
    else
        local off = CaptureEdgeOffset(item, key, side)
        if not off then return end
        if info.offsetX == nil or info.offsetY == nil then
            info.offsetX, info.offsetY = CaptureOffsets(item, info.target, info.side)
        end
        info.edge = { key = key, side = side, offset = off }
    end
    Refresh(item)
end

-- Center: the screen edges let go. An anchor to another element stays; the Anchor link owns it.
local function ClearScreenAnchor(item)
    if InCombatLockdown() then return end
    local info = AnchorOf(item.label)
    if not info then return end
    if SCREEN[info.target] then
        Unanchor(item)
    elseif type(info.edge) == "table" then
        info.edge = nil
        local ox, oy = CaptureOffsets(item, info.target, info.side)
        if ox then info.offsetX, info.offsetY = ox, oy end
        Refresh(item)
    end
end

local function ShowEdgeMenu(item, row)
    local menu = placement.edgeMenu or MenuFrame(256)
    placement.edgeMenu = menu
    ClearMenu(menu, SUB_W)
    local info = AnchorOf(item.label)
    local primary = info and SCREEN[info.target] and info.target
    local edge = info and type(info.edge) == "table" and info.edge.key
    for _, e in ipairs(EDGE_ITEMS) do
        local current = (e.key and (e.key == primary or e.key == edge)) or (not e.key and not info)
        local r = Row(menu)
        local rest = current and 0.5 or 0
        r.label:SetText(ns.L(e.text))
        Paint(r, current and T.accent or T.fg)
        r.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, rest)
        r:SetScript("OnEnter", function()
            r.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, 1)
            if e.key then EdgeMarker(e.key) end
        end)
        r:SetScript("OnLeave", function()
            r.hl:SetColorTexture(T.grey.r, T.grey.g, T.grey.b, rest)
            EdgeMarker(nil)
        end)
        r:SetScript("OnClick", function()
            CloseMenus()
            if e.key then
                SetScreenAnchor(item, e.key, e.side)
                EdgeMarker(e.key, true)
            else
                ClearScreenAnchor(item)
            end
        end)
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
    menu:SetScript("OnLeave", function(self)
        C_Timer.After(0.05, function()
            if self:IsShown() and not self:IsMouseOver() and not row:IsMouseOver() then self:Hide() end
        end)
    end)
    Finish(menu)
end

-- Out of Unlock Mode and onto the element's options: the options window draws over the
-- movers, so the two cannot share the screen.
local function OpenElementOptions(item)
    ns.HideRaidReminderAnchorConfig()
    ns.OpenOptionsWindow(item.page)
    if item.feature then UI.GoToSetting(item.page, nil, item.feature) end
end

-- An Offset X / Offset Y box: whole pixels; Enter nudges by the difference, Escape reverts.
local function OffsetBox(row, item, key)
    if not row.box then
        local box = CreateFrame("EditBox", nil, row)
        box:SetSize(54, 20)
        box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        box:SetFont(ns.UIFontPath(), 12, "")
        box:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
        box:SetTextInsets(4, 4, 0, 0)
        box:SetJustifyH("CENTER")
        box:SetAutoFocus(false)
        box:SetMaxLetters(6)
        ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
        local border = ns.Border(box, BLACK)
        box:SetScript("OnEnter", function() border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
        box:SetScript("OnLeave", function() border:SetColor(0, 0, 0, 1) end)
        row.box = box
    end
    local box = row.box
    box:SetFrameLevel(row:GetFrameLevel() + 1)
    local function Px()
        local info = AnchorOf(item.label)
        return math.floor(ToPixels(info and info[key] or 0) + 0.5)
    end
    box:SetText(tostring(Px()))
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local val = tonumber(self:GetText())
        if val then
            local delta = math.floor(val + 0.5) - Px()
            if delta ~= 0 then
                if key == "offsetX" then Nudge(item, FromPixels(delta), 0) else Nudge(item, 0, FromPixels(delta)) end
            end
        end
        self:SetText(tostring(Px()))
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Px()))
        self:ClearFocus()
    end)
    box:Show()
    return box, Px
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

    local info = not item.ownAnchor and AnchorOf(item.label)
    item.syncOffsets = nil
    if info and not InCombatLockdown() then
        local to = Row(menu)
        to:EnableMouse(false)
        to:SetHeight(22)
        menu.y = menu.y + 2
        to.label:SetText(ns.L("Anchored to: %s"):format(LabelOf(info.target)))
        to.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
        local boxes = {}
        for _, key in ipairs({ "offsetX", "offsetY" }) do
            local row = Row(menu)
            row:EnableMouse(false)
            row:SetHeight(22)
            menu.y = menu.y + 2
            row.label:SetText(ns.L(key == "offsetX" and "Offset X" or "Offset Y"))
            Paint(row, T.fg)
            local box, Px = OffsetBox(row, item, key)
            boxes[#boxes + 1] = { box = box, px = Px }
        end
        item.syncOffsets = function()
            for _, b in ipairs(boxes) do
                if not b.box:HasFocus() then b.box:SetText(tostring(b.px())) end
            end
        end
        Divider(menu)
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

    if not item.ownAnchor then
        Divider(menu)
        local linked = info and (SCREEN[info.target] or (type(info.edge) == "table" and SCREEN[info.edge.key]))
        local row = Action(menu, "Relative to Screen", function() end, linked and T.accent or nil)
        if not row.arrow then
            row.arrow = row:CreateTexture(nil, "ARTWORK")
            row.arrow:SetSize(10, 10)
            row.arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.arrow:SetTexture(UI.CHEVRON)
        end
        row.arrow:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
        row.arrow:Show()
        row:SetScript("OnClick", function() ShowEdgeMenu(item, row) end)
        row:HookScript("OnEnter", function()
            row.arrow:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
            ShowEdgeMenu(item, row)
        end)
        row:HookScript("OnLeave", function()
            row.arrow:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
            C_Timer.After(0.05, function()
                local sub = placement.edgeMenu
                if sub and sub:IsShown() and not sub:IsMouseOver() and not row:IsMouseOver() then sub:Hide() end
            end)
        end)
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", item.cog, "BOTTOMLEFT", 0, -2)
    Catcher()
    Finish(menu)
end

-------------------------------------------------------------------------------
--  Selection and the arrow keys
-------------------------------------------------------------------------------
-- The mover's border and name for its state: white when hovered or selected, accent at rest;
-- the name orange while anchored.
function Refresh(item)
    if not item then return end
    local h = item.handle
    local lit = item.selected or item.hovered or item.dragging
    if lit then h._border:SetColor(T.fg.r, T.fg.g, T.fg.b, 1) else h._border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end
    h:SetFrameLevel(item.baseLevel + (lit and 100 or 0))
    if item.cog then item.cog:SetFrameLevel(h:GetFrameLevel() + 10) end
    local anchored = not item.ownAnchor and AnchorOf(item.label) ~= nil
    item.chain:SetShown(anchored)
    if item.link then
        item.link.label:SetText(ns.L(anchored and "Anchored" or "Anchor"))
        local c = item.link:IsMouseOver() and T.accentSoft or T.fg
        item.link.label:SetTextColor(c.r, c.g, c.b, 1)
    end
end

function UI.ClearMoverSelection()
    local item = placement.selected
    StopPlacementDrag(item)
    placement.selected = nil
    if item then
        item.selected = false
        Refresh(item)
    end
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
        local open = placement.sideMenu and placement.sideMenu:IsShown()
            or placement.cogMenu and placement.cogMenu:IsShown()
        if open then
            CloseMenus()
        elseif placement.picking or placement.snapPicker then
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
    ShowLines(true)
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
    if placement.lines then ShowLines(false) end
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
    if not item or placement.picking or placement.snapPicker then return end
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
-- The hover row under the name: "Anchor" ("Anchored" while it is), and the cog at the top
-- right. They grow in over ANIM_DUR once the cursor has rested HOVER_DELAY on the mover.
local function BuildChrome(item)
    local h, text = item.handle, item.handle.text
    local frame = item.frame

    local link = CreateFrame("Button", nil, h)
    link:RegisterForClicks("LeftButtonUp")
    link.label = ns.Font(link, 10, "OUTLINE")
    link.label:SetPoint("CENTER")
    link:SetPoint("TOP", text, "BOTTOM", 0, -4)
    link:Hide()
    item.link = not item.ownAnchor and link or nil

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

    local chain = h:CreateTexture(nil, "OVERLAY")
    chain:SetSize(12, 12)
    chain:SetPoint("RIGHT", text, "LEFT", -3, 0)
    chain:SetTexture(CHAIN_TEX)
    chain:SetVertexColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    chain:Hide()
    item.chain = chain

    local pick = ns.Font(h, 11, "OUTLINE")
    pick:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    pick:SetPoint("CENTER", h, "CENTER")
    pick:SetJustifyH("CENTER")
    pick:Hide()

    local state, goal, anim = 0, 0, CreateFrame("Frame", nil, h)
    local hoverW, hoverH = 0, 0
    local rest   -- the mover's own points while it is grown, to put back after

    local function Over()
        return h:IsMouseOver() or cog:IsMouseOver() or link:IsShown() and link:IsMouseOver()
    end

    -- s from 0 (at rest, the mover covering the element) to 1 (grown to fit name and links).
    local function SetState(s)
        local point, rel = text:GetPoint(1)
        if point == "CENTER" and rel == h then text:SetPoint("CENTER", h, "CENTER", 0, s * 8) end
        local shown = s > 0.01
        cog:SetAlpha(s)
        cog:SetShown(shown)
        if item.link then
            link:SetAlpha(s)
            link:SetShown(shown and not placement.picking)
        end
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
        item.hoverConfirmed = true
        Refresh(item)
        local rowW = item.link and (link.label:GetStringWidth() or 45) or 0
        link:SetSize(rowW + 4, 14)
        hoverW = math.max(text:GetStringWidth() or 0, rowW) + 16
        hoverH = (text:GetStringHeight() or 10) + 4 + (item.link and 14 or 0) + 12
        pick:Hide()
        AnimateTo(1)
    end

    function item.Collapse(now)
        item.hoverConfirmed = false
        if now then
            anim:SetScript("OnUpdate", nil)
            state, goal = 0, 0
            SetState(0)
        else
            AnimateTo(0)
        end
    end

    function item.ShowPickText(msg)
        anim:SetScript("OnUpdate", nil)
        state, goal = 0, 0
        SetState(0)
        text:SetAlpha(0)
        pick:SetText(ns.L(msg))
        pick:Show()
    end

    function item.HidePickText()
        pick:Hide()
        text:SetAlpha(1)
    end

    link:SetScript("OnEnter", function()
        link.label:SetTextColor(T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1)
        item.hovered = true
        Refresh(item)
        local info = AnchorOf(item.label)
        if info then UI.ShowWidgetTooltip(link, LabelOf(info.target)) end
    end)
    link:SetScript("OnLeave", function()
        UI.HideWidgetTooltip()
        Refresh(item)
    end)
    link:SetScript("OnClick", function()
        UI.HideWidgetTooltip()
        if InCombatLockdown() then return end
        if AnchorOf(item.label) then
            Unanchor(item)
        else
            StartPick(item)
        end
    end)

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
        if placement.picking or placement.snapPicker then return end
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
            if placement.picking ~= item then item.Collapse() end
            Refresh(item)
        end)
    end)
end

-- page: the options page that sets the element up ("QoL/General"); feature: the section on
-- it to open, if it has one. ownAnchor: it holds itself to the screen its own way, so it
-- takes no anchor of its own (it can still be anchored to).
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
    frame:HookScript("OnSizeChanged", function() Queue(label, "size") end)
    -- The mover can cover more than the frame (a reminder's sample), and grows with it.
    handle:HookScript("OnSizeChanged", function() Queue(label, "size") end)
    hooksecurefunc(frame, "SetPoint", function()
        if not item.dragging then C_Timer.After(0, function() Moved(item) end) end
    end)
    -- A module's own resize grip sizes the frame from a corner of its choosing: the anchor
    -- leaves it be until the grip lets go.
    hooksecurefunc(frame, "StartSizing", function() item.sizing = true end)
    -- A module's own drag (a window dragged by its title) or resize: an anchored element keeps
    -- its anchor with the gap it was dropped at, as an Unlock Mode drag does.
    hooksecurefunc(frame, "StopMovingOrSizing", function()
        item.sizing = nil
        C_Timer.After(0, function()
            Recapture(item)
            Propagate(label)
        end)
    end)

    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    BuildChrome(item)
    handle:SetScript("OnMouseDown", function() item.dragged = nil end)
    handle:SetScript("OnMouseUp", function(_, button)
        if not placement.active or InCombatLockdown() or item.dragging or item.dragged then return end
        if button == "LeftButton" then
            if placement.picking then
                PickTarget(item)
            elseif placement.snapPicker then
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
        if placement.picking == item then CancelPick() end
        item.Collapse(true)
    end)
    Refresh(item)
end

-- Unlock Mode plate for an on-screen display. Hidden until the caller shows it. page,
-- feature and ownAnchor: as UI.BindMover's.
function UI.AttachMover(frame, label, onMoved, page, feature, ownAnchor)
    local mover = CreateFrame("Frame", nil, frame)
    mover:SetAllPoints()
    mover:SetFrameLevel(frame:GetFrameLevel() + 20)
    ns.Solid(mover, "BACKGROUND", T.accent, 0.35):SetAllPoints()
    mover._border = ns.Border(mover, T.accent)
    local text = ns.Font(mover, 12, "OUTLINE")
    text:SetPoint("CENTER", mover, "CENTER")
    text:SetText(label)
    mover.text = text
    UI.BindMover(mover, frame, label, onMoved, page, feature, ownAnchor)
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

WatchAnchors()
