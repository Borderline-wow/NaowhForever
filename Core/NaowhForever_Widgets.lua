-------------------------------------------------------------------------------
--  NaowhForever_Widgets.lua -- the widget kit behind every options row.
--  ns.UI keeps the member names the page builders were written against (`local EUI = ns.UI`).
--  The window lifecycle members are filled in by the Window file, which loads after this one.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local BLACK = { r = 0, g = 0, b = 0 }

local UI = {}
ns.UI = UI

local CHEVRON = "Interface\\AddOns\\NaowhForever\\Media\\chevron.tga"
UI.CHEVRON = CHEVRON

UI.CONTENT_PAD = 20
UI.COGS_ICON = "Interface\\AddOns\\NaowhForever\\Media\\cog.tga"

function UI.L(text) return ns.L(text) end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------
local tooltipFrame

local function GetTooltipFrame()
    if tooltipFrame then return tooltipFrame end
    tooltipFrame = CreateFrame("Frame", nil, UIParent)
    tooltipFrame:SetFrameStrata("TOOLTIP")
    tooltipFrame:SetClampedToScreen(true)
    tooltipFrame:SetSize(250, 40)
    local bg = ns.Solid(tooltipFrame, "BACKGROUND", T.panel, 0.98)
    bg:SetAllPoints()
    ns.Border(tooltipFrame)
    tooltipFrame.text = ns.Font(tooltipFrame, 10, nil)
    tooltipFrame.text:SetPoint("TOPLEFT", 8, -8)
    tooltipFrame.text:SetPoint("TOPRIGHT", -8, -8)
    tooltipFrame.text:SetWordWrap(true)
    tooltipFrame.text:SetSpacing(3)
    tooltipFrame:Hide()
    return tooltipFrame
end

-- opts (optional): { anchor = "cursor"|"below"|"left"|"right", justify, width, force }
function UI.ShowWidgetTooltip(label, text, opts)
    -- Suppress in M+/raid/PvP combat: frame APIs return secret values in tainted
    -- execution; opts.force bypasses.
    if not (opts and opts.force) then
        local _, iType = IsInInstance()
        if iType == "party" and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
           and C_ChallengeMode.IsChallengeModeActive() then return end
        if (iType == "raid" or iType == "pvp" or iType == "arena") and InCombatLockdown() then return end
    end
    -- text may be a function for dynamic content; resolved after the suppression checks
    -- so it is never called when nothing will show.
    if type(text) == "function" then text = text() end
    if not text or text == "" then return end
    local tt = GetTooltipFrame()
    local MAX_W = 250
    tt:SetWidth((opts and opts.width) or MAX_W)
    tt.text:SetJustifyH((opts and opts.justify) or "CENTER")
    tt.text:SetText(text)
    tt:ClearAllPoints()
    if opts and opts.anchor == "cursor" then
        local scale = tt:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        tt:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 4)
    elseif opts and opts.anchor == "below" then
        tt:SetPoint("TOP", label, "BOTTOM", 0, -4)
    elseif opts and opts.anchor == "left" then
        tt:SetPoint("RIGHT", label, "LEFT", -4, 0)
    elseif opts and opts.anchor == "right" then
        tt:SetPoint("LEFT", label, "RIGHT", 4, 0)
    else
        tt:SetPoint("BOTTOM", label, "TOP", 0, 4)
    end
    -- Shown BEFORE measuring: font geometry is wrong on hidden frames. Width shrinks to
    -- the natural single line when it fits; string metrics can be secret in restricted
    -- content, in which case the caps stand.
    tt:Show()
    if not (opts and opts.width) then
        local sw = tt.text:GetStringWidth()
        if not (issecretvalue and issecretvalue(sw)) then
            tt:SetWidth(math.min(sw + 16, MAX_W))
        end
    end
    tt:SetHeight(10)
    local textH = tt.text:GetStringHeight()
    if issecretvalue and issecretvalue(textH) then
        tt:SetHeight(26)
    else
        tt:SetHeight(textH + 16)
    end
end

function UI.HideWidgetTooltip()
    if tooltipFrame then tooltipFrame:Hide() end
end

-------------------------------------------------------------------------------
--  Bare controls
-------------------------------------------------------------------------------
-- A pill switch. WoW has no rounded-rectangle primitive, and a mask gets about one pixel of
-- gradient at 20px (stepped ends), so track and knob are antialiased art tinted with
-- SetVertexColor. toggle_track.tga is 128x64, the 2:1 ratio of W:H below; changing that
-- ratio means redrawing it.
local TRACK_TEX = "Interface\\AddOns\\NaowhForever\\Media\\toggle_track.tga"
local KNOB_TEX = "Interface\\AddOns\\NaowhForever\\Media\\toggle_knob.tga"
local SPEAKER_TEX = "Interface\\AddOns\\NaowhForever\\Media\\speaker.tga"   -- a sound dropdown's play button

-- w/h/knobSize are optional overrides for a smaller switch; knob and inset scale off the
-- height (70% and 15%).
function UI.BuildToggleControl(parent, frameLevel, get, set, w, h, knobSize)
    local W, H = w or 40, h or 20
    local KNOB = knobSize or math.floor(H * 0.7 + 0.5)
    local INSET = math.max(2, math.floor(H * 0.15 + 0.5))
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(W, H)
    if frameLevel then t:SetFrameLevel(frameLevel) end

    -- Pixel snapping throws away the art's antialiasing (the real cause of the jagged
    -- switch); Blizzard's NineSlice makes the same two calls.
    local function Smooth(tex)
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
    end

    local track = t:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(TRACK_TEX)
    track:SetAllPoints()
    Smooth(track)

    local knob = t:CreateTexture(nil, "ARTWORK")
    knob:SetTexture(KNOB_TEX)
    knob:SetSize(KNOB, KNOB)
    Smooth(knob)

    -- Read through fields so a kept control can be pointed at new callbacks (UI.KeepToggle).
    t._get, t._set = get, set
    local on = false
    local function PaintTrack(c, a)
        track:SetVertexColor(c.r, c.g, c.b, a)
    end

    local function Paint(state)
        on = state and true or false
        knob:ClearAllPoints()
        if on then
            PaintTrack(T.accent, 1)
            knob:SetVertexColor(1, 1, 1, 1)
            knob:SetPoint("RIGHT", t, "RIGHT", -INSET, 0)
        else
            PaintTrack(T.line, 1)
            knob:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
            knob:SetPoint("LEFT", t, "LEFT", INSET, 0)
        end
    end

    -- Off has no border to light up the way ns.Button's hover does, so the track itself
    -- carries it: the lighter accent when on, the neutral row fill when off.
    t:SetScript("OnEnter", function()
        PaintTrack(on and T.accentSoft or T.grey, 1)
    end)
    t:SetScript("OnLeave", function()
        PaintTrack(on and T.accent or T.line, 1)
    end)

    local function Snap() Paint(t._get() and true or false) end
    t:SetScript("OnClick", function()
        t._set(not (t._get() and true or false))
        Snap()
    end)
    Snap()
    t._refreshValue = Snap
    return t, Paint, Snap
end

function UI.BuildDropdownControl(parent, ddW, fLevel, values, order, get, set)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ddW or 160, 24)
    if fLevel then btn:SetFrameLevel(fLevel) end
    local bg = ns.Solid(btn, "BACKGROUND", T.panel, 1)
    bg:SetAllPoints()
    local border = ns.Border(btn, BLACK)
    local lbl = ns.Font(btn, 12, nil)
    lbl:SetPoint("LEFT", 8, 0)
    lbl:SetPoint("RIGHT", -18, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(CHEVRON)
    arrow:SetSize(10, 10)
    if arrow.SetRotation then arrow:SetRotation(-math.pi / 2) end
    arrow:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    arrow:SetPoint("RIGHT", -7, 0)
    -- Read through fields so a kept control can be pointed at new data (UI.KeepDropdown).
    btn._values, btn._order, btn._get, btn._set = values, order, get, set
    local function Keys()
        if btn._order then return btn._order end
        local out = {}
        for k in pairs(btn._values) do out[#out + 1] = k end
        table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
        return out
    end
    btn._refreshLabel = function()
        local v = btn._get()
        lbl:SetText(btn._values[v] or tostring(v or ""))
    end
    -- An anchored dropdown, not a context menu, and it closes itself. Three things line up:
    --   * OpenContextMenu anchors to the cursor; OpenMenu with an anchor is the dropdown case.
    --   * The manager closes menus on GLOBAL_MOUSE_DOWN, after this script, so toggling on
    --     OnClick always found the menu gone and reopened it.
    --   * It skips that close only when the hovered frame answers HandlesGlobalMouseEvent
    --     (Menu.lua), as Blizzard's DropdownButton does.
    btn.HandlesGlobalMouseEvent = function(_, buttonName, event)
        return event == "GLOBAL_MOUSE_DOWN" and buttonName == "LeftButton"
    end

    local function MenuOpen()
        return btn._menu and btn._menu.IsShown and btn._menu:IsShown()
    end

    btn:SetScript("OnMouseDown", function()
        if MenuOpen() then
            btn._menu:Close()
            btn._menu = nil
            return
        end
        if not (MenuUtil and MenuUtil.CreateRootMenuDescription and MenuVariants
            and Menu and Menu.GetManager and AnchorUtil) then return end
        local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
        if not desc then return end
        -- Scrolling is opt-in on Blizzard's menu (IsScrollable is false until this is
        -- called); unset, a long list ran off the screen. It only engages past this height:
        -- 420, or the caller's btn._menuHeight (a number, or a function giving one) for a list
        -- meant to show whole.
        local menuHeight = btn._menuHeight
        if type(menuHeight) == "function" then menuHeight = menuHeight() end
        if desc.SetScrollMode then desc:SetScrollMode(menuHeight or 420) end
        for _, k in ipairs(Keys()) do
            local key = k
            desc:CreateRadio(btn._values[key] or tostring(key),
                function() return btn._get() == key end,
                function()
                    btn._set(key)
                    btn._refreshLabel()
                end)
        end
        btn._menu = Menu.GetManager():OpenMenu(btn, desc,
            AnchorUtil.CreateAnchor("TOPLEFT", btn, "BOTTOMLEFT", 0, -2))
    end)
    btn:SetScript("OnEnter", function()
        border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    end)
    btn:SetScript("OnLeave", function()
        border:SetColor(0, 0, 0, 1)
    end)
    btn._refreshLabel()
    btn._refreshValue = btn._refreshLabel
    btn:SetScript("OnHide", function()
        if btn._menu then btn._menu:Close(); btn._menu = nil end
    end)
    return btn, lbl
end

function UI.BuildSliderCore(parent, trackW, trackH, thumbSz, inputW, inputH, inputFontSz,
                            inputAlpha, minV, maxV, step, get, set)
    local track = CreateFrame("Frame", nil, parent)
    track._minV, track._maxV, track._step = minV, maxV, step or 1
    local function Clamp(v)
        v = tonumber(v)
        if not v then return nil end
        local lo, hi, st = track._minV, track._maxV, track._step
        v = math.floor((v - lo) / st + 0.5) * st + lo
        v = tonumber(("%.4f"):format(v))
        if v < lo then v = lo elseif v > hi then v = hi end
        return v
    end

    track:SetSize(trackW, math.max(trackH, thumbSz))
    track:EnableMouse(true)
    -- Read through fields so a kept control can be pointed at new callbacks (UI.KeepSlider).
    track._get, track._set = get, set
    local rail = ns.Solid(track, "BACKGROUND", T.line, 1)
    rail:SetPoint("LEFT", 0, 0)
    rail:SetPoint("RIGHT", 0, 0)
    rail:SetHeight(trackH)
    local fill = ns.Solid(track, "BORDER", T.accent, 1)
    fill:SetPoint("LEFT", 0, 0)
    fill:SetHeight(trackH)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(KNOB_TEX)
    thumb:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
    thumb:SetSize(thumbSz, thumbSz)

    local valBox = CreateFrame("EditBox", nil, parent)
    valBox:SetSize(inputW, inputH)
    valBox:SetAutoFocus(false)
    valBox:SetFont(ns.UIFontPath(), inputFontSz or 12, "")
    valBox:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1)
    valBox:SetTextInsets(4, 4, 0, 0)
    valBox:SetJustifyH("CENTER")
    valBox:SetAlpha(inputAlpha or 1)
    local boxBg = ns.Solid(valBox, "BACKGROUND", T.bg, 1)
    boxBg:SetAllPoints()
    local boxBorder = ns.Border(valBox, BLACK)
    valBox:SetScript("OnEnter", function() boxBorder:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end)
    valBox:SetScript("OnLeave", function() boxBorder:SetColor(0, 0, 0, 1) end)

    local function Paint()
        local lo, hi = track._minV, track._maxV
        local v = Clamp(track._get()) or lo
        local frac = (hi > lo) and (v - lo) / (hi - lo) or 0
        fill:SetWidth(math.max(0.001, frac * trackW))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", frac * trackW, 0)
        valBox:SetText(track._format and track._format(v) or tostring(v))
        valBox:SetCursorPosition(0)
    end

    local function FromCursor()
        local scale = track:GetEffectiveScale()
        local cx = GetCursorPosition() / scale
        local left = track:GetLeft()
        if not left then return end
        local frac = (cx - left) / trackW
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local v = Clamp(track._minV + frac * (track._maxV - track._minV))
        if v ~= nil and v ~= track._get() then
            track._set(v)
        end
        Paint()
    end

    -- The drag ends when the button comes up, wherever the cursor is: OnMouseUp alone
    -- strands the drag when the release lands outside the track. While it runs, UI.sliderDrag
    -- is the track, so a page that redraws on every change (Shared/Settings/Page.lua) waits
    -- for the release: its redraw hides the rows, which ended the drag after one step.
    local function EndDrag()
        track:SetScript("OnUpdate", nil)
        if UI.sliderDrag == track then UI.sliderDrag = nil end
    end
    local function OnDragUpdate()
        if not IsMouseButtonDown("LeftButton") then
            EndDrag()
            Paint()
            return
        end
        FromCursor()
    end
    track:SetScript("OnMouseDown", function()
        UI.sliderDrag = track
        FromCursor()
        track:SetScript("OnUpdate", OnDragUpdate)
    end)
    track:SetScript("OnMouseUp", function()
        EndDrag()
        Paint()
    end)
    track:SetScript("OnHide", EndDrag)

    local function Commit()
        if UI.rebindingRows then return end
        -- What a formatted box shows ("120%", "6s") reads back as its number.
        local v = Clamp((valBox:GetText():gsub("[^%d%.%-]", "")))
        if v ~= nil then track._set(v) end
        Paint()
        valBox:ClearFocus()
    end
    valBox:SetScript("OnEnterPressed", Commit)
    valBox:SetScript("OnEditFocusLost", function() Commit() end)
    valBox:SetScript("OnEscapePressed", function()
        Paint()
        valBox:ClearFocus()
    end)

    Paint()
    track._refreshValue = Paint
    track._valBox = valBox
    -- Its parts, public for a caller that styles its own slider (the Dungeon Journal's
    -- opacity): the rail, the filled part, the thumb, and the value box with its fill and
    -- border ({ _frame, SetColor }). Paint only sizes and moves them, so a restyle lasts.
    track.rail, track.fill, track.thumb = rail, fill, thumb
    track.valueBox, track.valueFill, track.valueBorder = valBox, boxBg, boxBorder
    return track, valBox, Paint
end

function UI.SetSliderRange(track, minV, maxV, step)
    track._minV, track._maxV, track._step = minV, maxV, step or 1
end

-- What a slider's value box shows, set as track._format (or a row's cfg.format): a percent
-- or seconds. The box reads either back as a plain number.
function UI.FormatPercent(v) return v .. "%" end
function UI.FormatSeconds(v) return v .. "s" end

-------------------------------------------------------------------------------
--  Row factory (the W: dialect every options page is written in)
-------------------------------------------------------------------------------
local W = {}
UI.Widgets = W

local ROW_H, HEADER_H = 50, 40
local BUTTONS_W, BUTTONS_H, BUTTONS_GAP = 84, 24, 6   -- a button row's buttons

-- Features a player has opened this session, by page and name. A feature's options sit
-- under its row (W:Feature); on a page marked `collapse` they start closed, still built so
-- callers keep the frames they expect, but hidden and taking no height.
local openFeatures = {}
local featureParents = {}

-- The settings search opens the feature holding the setting it jumps to.
function UI.OpenFeature(id)
    while id do
        openFeatures[id] = true
        id = featureParents[id]
    end
end

function UI.MarkFeatureParents(open)
    local parents = {}
    for id in pairs(open) do
        local parent = featureParents[id]
        while parent do parents[parent] = true; parent = featureParents[parent] end
    end
    for id in pairs(parents) do open[id] = true end
end

local function Collapsed(parent, frame, h)
    if parent._nsuiCollapsed then
        frame:Hide()
        return frame, 0
    end
    return frame, h
end

-- Only enabled for pages whose rows have stable identities. Config objects stay
-- attached to their controls; rebuilding updates their callbacks and dropdown data.
function UI.BeginReusableRows(parent)
    parent._rowCache = parent._rowCache or {}
    parent._rowUses = {}
    parent._nsuiRowCount = 0
    UI.rebindingRows = true
    for _, rows in pairs(parent._rowCache) do
        for _, row in ipairs(rows) do row:Hide() end
    end
    UI.rebindingRows = nil
end

local function CachedRow(parent, key)
    if not parent._rowCache then return nil end
    local index = (parent._rowUses[key] or 0) + 1
    parent._rowUses[key] = index
    local rows = parent._rowCache[key]
    if not rows then rows = {}; parent._rowCache[key] = rows end
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        rows[index] = row
    end
    row:ClearAllPoints()
    row:Show()
    return row
end

-- Any frame or region a builder makes, reused like the rows: on a parent that reuses its
-- rows, each key hands back what this call site made last build, in build order; elsewhere
-- it is made fresh. One-time setup belongs in create(parent); the caller sets everything
-- else every build. The second return is true for an element made just now.
function UI.Keep(parent, key, create)
    if not parent._rowCache then return create(parent), true end
    local index = (parent._rowUses[key] or 0) + 1
    parent._rowUses[key] = index
    local list = parent._rowCache[key]
    if not list then list = {}; parent._rowCache[key] = list end
    local el, new = list[index], false
    if not el then
        el, new = create(parent), true
        list[index] = el
    end
    el:ClearAllPoints()
    el:Show()
    if el.CreateTexture then UI.BeginReusableRows(el) end
    return el, new
end

function UI.KeepFont(parent, key, size, flags, color)
    local fs = UI.Keep(parent, key, function(p) return ns.Font(p, size, flags, color) end)
    local c = color or T.fg
    fs:SetTextColor(c.r, c.g, c.b, 1)
    return fs
end

function UI.KeepToggle(parent, key, get, set, w, h, knobSize)
    local t = UI.Keep(parent, key, function(p)
        return UI.BuildToggleControl(p, nil, get, set, w, h, knobSize)
    end)
    t._get, t._set = get, set
    t:SetFrameLevel(parent:GetFrameLevel() + 2)
    t._refreshValue()
    return t
end

function UI.KeepDropdown(parent, key, width, values, order, get, set)
    local dd = UI.Keep(parent, key, function(p)
        return UI.BuildDropdownControl(p, width, nil, values, order, get, set)
    end)
    dd._values, dd._order, dd._get, dd._set = values, order, get, set
    dd:SetFrameLevel(parent:GetFrameLevel() + 2)
    dd._refreshLabel()
    return dd
end

-- The range is fixed when it is made, so one key is one slider shape.
function UI.KeepSlider(parent, key, trackW, trackH, thumbSz, inputW, inputH, inputFontSz,
                       inputAlpha, minV, maxV, step, get, set)
    local track = UI.Keep(parent, key, function(p)
        local t = UI.BuildSliderCore(p, trackW, trackH, thumbSz, inputW, inputH, inputFontSz,
            inputAlpha, minV, maxV, step, get, set)
        -- The value box is the track's sibling, so it follows the track in and out of use.
        t:HookScript("OnShow", function() t._valBox:Show() end)
        t:HookScript("OnHide", function() t._valBox:Hide() end)
        return t
    end)
    track._get, track._set = get, set
    track._valBox:Show()
    track._refreshValue()
    return track, track._valBox
end

function UI.KeepButton(parent, key, text, w, h, onClick)
    local btn = UI.Keep(parent, key, function(p) return ns.Button(p, text, w, h) end)
    btn:SetSize(w, h)
    ns.SetButtonText(btn, text)
    btn._onClick = onClick
    return btn
end

local function UpdateConfig(dst, src)
    if dst == src then return end
    -- Dropdowns retain these table identities in their menu callbacks.
    local values, order = dst.values, dst.order
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
    for _, key in ipairs({ "values", "order" }) do
        local prior = key == "values" and values or order
        if type(prior) == "table" and type(src[key]) == "table" then
            if prior ~= src[key] then
                for k in pairs(prior) do prior[k] = nil end
                for k, v in pairs(src[key]) do prior[k] = v end
            end
            dst[key] = prior
        end
    end
end

local function BuildRegionControl(rgn, cfg)
    local function Get() return cfg.getValue() end
    local function Set(...) return cfg.setValue(...) end
    if cfg.type == "iconbutton" then
        local button = CreateFrame("Button", nil, rgn)
        button:SetSize(32, 32)
        button:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        ns.Border(button, { r = 0, g = 0, b = 0 })
        button:RegisterForDrag("LeftButton")
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                if cfg.onRightClick then cfg.onRightClick() end
            else
                cfg.onClick()
            end
        end)
        button:SetScript("OnDragStart", function() cfg.onClick() end)
        button:SetScript("OnEnter", function(self)
            if cfg.tooltip then UI.ShowWidgetTooltip(self, cfg.tooltip, { anchor = "cursor", justify = "LEFT" }) end
        end)
        button:SetScript("OnLeave", function() UI.HideWidgetTooltip() end)
        button._refreshValue = function()
            icon:SetTexture(cfg.icon or 134400)
            icon:SetDesaturated(cfg.active ~= nil and not cfg.active())
        end
        button._refreshValue()
        return button
    elseif cfg.type == "button" then
        local button = ns.Button(rgn, cfg.buttonText or "Edit", 90, 24, function() cfg.onClick() end)
        button:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        return button
    elseif cfg.type == "buttons" then
        -- A row of buttons, right to left from the region's edge: cfg.buttons = { { text,
        -- onClick, tooltip, width }, ... }. Clicks and tooltips are read from cfg when they
        -- happen, so a reused row follows its new config.
        local holder = CreateFrame("Frame", nil, rgn)
        holder:SetHeight(BUTTONS_H)
        holder:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        holder._buttons = {}
        local x = 0
        for i = #cfg.buttons, 1, -1 do
            local w = cfg.buttons[i].width or BUTTONS_W
            local button = ns.Button(holder, "", w, BUTTONS_H, function() cfg.buttons[i].onClick() end)
            button:SetPoint("RIGHT", holder, "RIGHT", -x, 0)
            holder._buttons[i] = button
            x = x + w + BUTTONS_GAP
        end
        holder:SetWidth(math.max(1, x - BUTTONS_GAP))
        holder._refreshValue = function()
            for i, button in ipairs(holder._buttons) do
                local b = cfg.buttons[i]
                ns.SetButtonText(button, b.text)
                if b.tooltip then ns.Tooltip(button, b.text, b.tooltip) end
            end
        end
        holder._refreshValue()
        return holder
    elseif cfg.type == "toggle" then
        local toggle = UI.BuildToggleControl(rgn, rgn:GetFrameLevel() + 2,
            Get, Set)
        toggle:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        return toggle
    elseif cfg.type == "dropdown" then
        local dd = UI.BuildDropdownControl(rgn, cfg.width or 160, rgn:GetFrameLevel() + 2,
            cfg.values, cfg.order, Get, Set)
        dd:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        -- A sound's: a play button before it (cfg.preview plays the picked one). The dropdown's
        -- child, so it dims with it, and in _buttons, so it takes no clicks while off.
        if cfg.preview then
            local play = CreateFrame("Button", nil, dd)
            play:SetSize(24, 24)
            play:SetPoint("RIGHT", dd, "LEFT", -4, 0)
            ns.Solid(play, "BACKGROUND", T.panel, 1):SetAllPoints()
            ns.Border(play, BLACK)
            play.icon = play:CreateTexture(nil, "ARTWORK")
            play.icon:SetTexture(SPEAKER_TEX)
            play.icon:SetSize(14, 14)
            play.icon:SetPoint("CENTER")
            play.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
            play:SetScript("OnClick", function() cfg.preview(Get()) end)
            ns.Tooltip(play, "Play it", "Plays the sound picked here.")
            play:HookScript("OnEnter", function(self) self.icon:SetVertexColor(T.fg.r, T.fg.g, T.fg.b) end)
            play:HookScript("OnLeave", function(self) self.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b) end)
            dd._buttons = { play }
        end
        return dd
    elseif cfg.type == "slider" then
        local track, valBox = UI.BuildSliderCore(rgn, cfg.trackWidth or 120, 4, 12, cfg.boxWidth or 40, 22, 12,
            1, cfg.min or 0, cfg.max or 100, cfg.step or 1, Get, Set)
        -- Read on every paint, so a reused row follows its config's format.
        track._format = function(v) return cfg.format and cfg.format(v) or tostring(v) end
        track._refreshValue()
        valBox:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        track:SetPoint("RIGHT", valBox, "LEFT", -8, 0)
        return track
    elseif cfg.type == "palette" then
        -- A row of small chips showing colors; nothing to click. One chip per color that
        -- cfg.colors() returns, built as they are first needed and hidden when a later call
        -- returns fewer.
        local SIZE, GAP = 22, 4
        local chips = CreateFrame("Frame", nil, rgn)
        chips:SetHeight(SIZE)
        chips:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        local made = {}
        local function Paint()
            local colors = cfg.colors()
            local n = #colors
            chips:SetWidth(math.max(1, n * (SIZE + GAP) - GAP))
            for i = 1, n do
                local chip = made[i]
                if not chip then
                    chip = CreateFrame("Frame", nil, chips)
                    chip:SetSize(SIZE, SIZE)
                    chip:SetPoint("LEFT", chips, "LEFT", (i - 1) * (SIZE + GAP), 0)
                    chip.fill = ns.Solid(chip, "BACKGROUND", T.bg, 1)
                    chip.fill:SetAllPoints()
                    ns.Border(chip, T.muted, 0.6)
                    made[i] = chip
                end
                local c = colors[i]
                chip.fill:SetColorTexture(c.r, c.g, c.b, 1)
                chip:Show()
            end
            for i = n + 1, #made do made[i]:Hide() end
        end
        chips._refreshValue = Paint
        Paint()
        return chips
    elseif cfg.type == "colorpicker" then
        -- Text Color in the custom and Ability Reminder editors.
        local swatch = UI.BuildColorSwatchControl(rgn, Get, Set, cfg.hasAlpha)
        swatch:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
        return swatch
    end
end

-- A row that is switched off (cfg.disabled) greys out whatever its control is, and the
-- control takes no clicks: a slider's value box and every button of a button row included.
local DIM_ALPHA = 0.3

local function Dim(cfg, lbl, control, off)
    local alpha = off and DIM_ALPHA or 1
    lbl:SetAlpha(alpha)
    if not control then return end
    control:SetAlpha(alpha)
    -- A palette and a button row's holder take no clicks themselves.
    if cfg.type ~= "palette" and cfg.type ~= "buttons" then control:EnableMouse(not off) end
    local box = control._valBox
    if box then
        box:SetAlpha(alpha)
        box:EnableMouse(not off)
        if off then box:ClearFocus() end
    end
    if control._buttons then
        for _, button in ipairs(control._buttons) do button:EnableMouse(not off) end
    end
    if off and control._menu then
        control._menu:Close()
        control._menu = nil
    end
end

local function BuildRegion(row, cfg, left, width)
    local rgn = CreateFrame("Frame", nil, row)
    rgn:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
    rgn:SetSize(width, ROW_H)

    local control = BuildRegionControl(rgn, cfg)
    rgn._control = control
    local disabled = type(cfg.disabled) == "function" and cfg.disabled()

    local lbl = ns.Font(rgn, 14, nil)
    lbl:SetPoint("LEFT", rgn, "LEFT", 20, 0)
    if control then
        lbl:SetPoint("RIGHT", control, "LEFT", -8, 0)
    else
        lbl:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    end
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(cfg.text or "")
    rgn._label = lbl
    Dim(cfg, lbl, control, disabled)

    rgn._cfg = cfg
    rgn._refresh = function(newCfg)
        UpdateConfig(cfg, newCfg)
        local off = type(cfg.disabled) == "function" and cfg.disabled()
        lbl:SetText(cfg.text or "")
        Dim(cfg, lbl, control, off)
        if control and control._refreshValue then control._refreshValue() end
    end

    local tip = disabled and cfg.disabledTooltip or cfg.tooltip
    if tip then
        local hit = CreateFrame("Button", nil, rgn)
        hit:SetPoint("TOPLEFT", lbl, "TOPLEFT", -4, 4)
        hit:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 4, -4)
        hit:SetScript("OnEnter", function(self)
            local off = type(cfg.disabled) == "function" and cfg.disabled()
            UI.ShowWidgetTooltip(self, off and cfg.disabledTooltip or cfg.tooltip,
                { anchor = "cursor", justify = "LEFT" })
        end)
        hit:SetScript("OnLeave", function() UI.HideWidgetTooltip() end)
    end
    return rgn
end

-- A slider's range is fixed when it is built, so it is part of what makes a cached row
-- reusable for a config.
local function RegionKey(cfg)
    local key = cfg.type .. ":" .. (cfg.text or "")
    if cfg.type == "slider" then
        key = key .. ":" .. tostring(cfg.min) .. ":" .. tostring(cfg.max) .. ":" .. tostring(cfg.trackWidth)
        if cfg.boxWidth then key = key .. ":" .. cfg.boxWidth end
    elseif cfg.type == "buttons" then
        key = key .. ":" .. #cfg.buttons
    elseif cfg.preview then
        key = key .. ":preview"
    end
    return key
end

-- While the settings search builds its index (Core/NaowhForever_Search.lua sets
-- UI.searchScan), the row widgets only record what they would show and build nothing.
local function ScanLabel(text, tooltip)
    if type(text) ~= "string" or text == "" then return end
    local scan = UI.searchScan
    scan.items[#scan.items + 1] = { section = scan.section, label = text,
        tooltip = type(tooltip) == "string" and tooltip or nil,
        feature = scan.feature, featureName = scan.featureName }
end

-- A builder that draws its own controls (the XP Bar preview) names them for the search here;
-- outside the scan it does nothing. The frame it builds lists them in _searchLabels, so the
-- search can jump to it.
function UI.ScanLabels(labels, tooltip)
    if not UI.searchScan then return end
    for _, text in ipairs(labels) do ScanLabel(text, tooltip) end
end

-- While a search is typed (UI.searchWords), rows holding every word in their name or
-- tooltip get a soft band.
local function Mark(frame, text, tooltip)
    local on = false
    local words = UI.searchWords
    if words and type(text) == "string" and text ~= "" then
        local name = text:lower()
        on = true
        for _, word in ipairs(words) do
            if not name:find(word, 1, true) then on = false break end
        end
    end
    if on and not frame._searchMark then
        frame._searchMark = ns.Solid(frame, "BACKGROUND", T.accent, 0.18)
        frame._searchMark:SetAllPoints()
    end
    if frame._searchMark then frame._searchMark:SetShown(on) end
end

local function MarkRow(parent, row, leftCfg, rightCfg)
    Mark(row._leftRegion, leftCfg.text, leftCfg.tooltip)
    if rightCfg then Mark(row._rightRegion, rightCfg.text, rightCfg.tooltip) end
    return Collapsed(parent, row, ROW_H)
end

function W:DualRow(parent, yOffset, leftCfg, rightCfg)
    if UI.searchScan then
        for _, cfg in ipairs({ leftCfg, rightCfg }) do
            if cfg.type ~= "label" then ScanLabel(cfg.text, cfg.tooltip) end
            if cfg.type == "buttons" then
                for _, b in ipairs(cfg.buttons) do ScanLabel(b.text, b.tooltip) end
            end
        end
        return nil, ROW_H
    end
    local key = "row:" .. RegionKey(leftCfg) .. ":" .. (rightCfg and RegionKey(rightCfg) or "")
    local row = CachedRow(parent, key) or CreateFrame("Frame", nil, parent)
    -- What the search jumps to: the row that shows this label.
    row._searchL, row._searchR = leftCfg.text, rightCfg and rightCfg.text
    row._searchF = parent._nsuiFeatureId
    -- A button row's buttons are found by their own names too.
    for _, cfg in ipairs({ leftCfg, rightCfg }) do
        if cfg.type == "buttons" then
            row._searchLabels = row._searchLabels or {}
            for _, b in ipairs(cfg.buttons) do row._searchLabels[b.text] = true end
        end
    end
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, yOffset)

    if not row._rule then
        row._rule = ns.Solid(row, "ARTWORK", T.line, 0.6)
        row._rule:SetPoint("BOTTOMLEFT"); row._rule:SetPoint("BOTTOMRIGHT"); ns.Hairline(row._rule, "h")
    end
    local function FitRegions()
        local width = math.max(1, parent:GetWidth() - UI.CONTENT_PAD * 2)
        local half = rightCfg and width / 2 or width
        row._leftRegion:SetWidth(half)
        if row._rightRegion then
            row._rightRegion:SetWidth(half)
            row._rightRegion:SetPoint("TOPLEFT", row, "TOPLEFT", half, 0)
        end
    end
    if row._leftRegion then
        row._leftRegion._refresh(leftCfg)
        if rightCfg then row._rightRegion._refresh(rightCfg) end
        FitRegions()
        return MarkRow(parent, row, leftCfg, rightCfg)
    end

    local w = row:GetWidth()
    if w <= 0 then
        -- Anchored-both-sides width is not resolved until layout runs; derive it. The
        -- final fallback is the options window's content width.
        w = (parent:GetWidth() or 0) - UI.CONTENT_PAD * 2
        if w <= 0 then w = 910 end
    end
    if rightCfg then
        local half = w / 2
        row._leftRegion = BuildRegion(row, leftCfg, 0, half)
        row._rightRegion = BuildRegion(row, rightCfg, half, half)
        local divider = ns.Solid(row, "ARTWORK", T.line, 0.6)
        divider:SetPoint("TOP", row, "TOP", 0, -8)
        divider:SetPoint("BOTTOM", row, "BOTTOM", 0, 8)
        ns.Hairline(divider, "v")
    else
        row._leftRegion = BuildRegion(row, leftCfg, 0, w)
    end
    return MarkRow(parent, row, leftCfg, rightCfg)
end

function W:SectionHeader(parent, text, yOffset)
    if UI.searchScan then
        UI.searchScan.section, UI.searchScan.feature, UI.searchScan.featureName = text, nil, nil
        return nil, HEADER_H
    end
    parent._nsuiRowCount = 0
    parent._nsuiCollapsed, parent._nsuiFeatureId = nil, nil
    local f = CachedRow(parent, "header:" .. text) or CreateFrame("Frame", nil, parent)
    f:SetHeight(HEADER_H)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, yOffset)
    f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, yOffset)
    if f._headerBuilt then return f, HEADER_H end
    f._headerBuilt = true
    local lbl = ns.Font(f, 14, nil, T.fg)
    lbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 8)
    lbl:SetText(text)
    local sep = ns.Solid(f, "ARTWORK", T.line, 1)
    sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ns.Hairline(sep, "h")
    return f, HEADER_H
end

-- A feature with several options: one full-width row with an arrow, its name and, when cfg
-- is a toggle, its on/off switch, so it can be switched without opening it. Its options are
-- the rows after it, up to the next section header, feature or W:EndFeature. key names the
-- feature for its open state when cfg.text is not stable.
function W:Feature(parent, yOffset, cfg, key)
    local scan = UI.searchScan
    if scan then
        scan.feature, scan.featureName = nil, nil
        ScanLabel(cfg.text, cfg.tooltip)
        scan.feature, scan.featureName = scan.page .. ":" .. (key or cfg.text), cfg.text
        return nil, ROW_H
    end
    parent._nsuiCollapsed, parent._nsuiFeatureId = nil, nil
    local collapsible = parent._collapsible == true
    local id = collapsible and (parent._pageKey .. ":" .. (key or cfg.text)) or nil
    -- The feature switch opens its options on enable and closes them on disable.
    if collapsible and cfg.type == "toggle" then
        local set = cfg.setValue
        cfg.setValue = function(v)
            openFeatures[id] = v and true or nil
            if not v and UI.searchOpen then UI.searchOpen[id] = nil end
            set(v)
        end
    end
    local row = W:DualRow(parent, yOffset, cfg)
    if not row._feature then
        row._feature = true
        row._leftRegion._label:SetFont(ns.UIFontPath(), cfg.type == "label" and 14 or 16, "")
        row._leftRegion._label:SetPoint("LEFT", row._leftRegion, "LEFT", 30, 0)
        row.arrow = row:CreateTexture(nil, "ARTWORK")
        row.arrow:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\chevron.tga")
        row.arrow:SetSize(14, 14)
        row.arrow:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.arrow:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
        row.hit = CreateFrame("Button", nil, row)
        row.hit:SetPoint("TOPLEFT")
        row.hit:SetPoint("BOTTOMLEFT")
        row.hit:SetPoint("RIGHT", row._leftRegion, "RIGHT", -120, 0)
        row.hit:SetFrameLevel(row._leftRegion:GetFrameLevel() + 3)
        row.hit:SetScript("OnClick", function(hit)
            openFeatures[hit._id] = not openFeatures[hit._id] or nil
            UI:RefreshPage(true)
        end)
        row.hit:SetScript("OnEnter", function(hit)
            row.arrow:SetVertexColor(T.fg.r, T.fg.g, T.fg.b, 1)
            local tip = hit._cfg.tooltip
            if tip then UI.ShowWidgetTooltip(hit, tip, { anchor = "cursor", justify = "LEFT" }) end
        end)
        row.hit:SetScript("OnLeave", function()
            row.arrow:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
            UI.HideWidgetTooltip()
        end)
    end
    row.hit._id, row.hit._cfg = id, cfg
    local closed = collapsible and not openFeatures[id] and not (UI.searchOpen and UI.searchOpen[id])
    row.hit:SetShown(collapsible)
    row.arrow:SetShown(collapsible)
    -- One chevron: pointing right while closed, turned to point down while open.
    row.arrow:SetRotation(closed and 0 or -math.pi / 2)
    parent._nsuiCollapsed = closed or nil
    parent._nsuiFeatureId = (parent._pageKey or "") .. ":" .. (key or cfg.text)
    return row, ROW_H
end

-- A presentation-only disclosure nested inside an existing feature. Settings keep
-- their original keys; search opens both levels before measuring the destination row.
function W:Disclosure(parent, yOffset, text, key)
    local cfg = type(text) == "table" and text or { type = "label", text = text }
    local scan = UI.searchScan
    local parentId = scan and scan.feature or parent._nsuiFeatureId
    local nestedKey = (parentId or "") .. ":" .. key
    local pageKey = scan and scan.page or (parent._pageKey or "")
    local id = pageKey .. ":" .. nestedKey
    featureParents[id] = parentId
    if scan then
        scan.disclosure = { feature = scan.feature, featureName = scan.featureName }
        ScanLabel(cfg.text, cfg.tooltip)
        scan.feature, scan.featureName = id, cfg.text
        return nil, ROW_H
    end
    local saved = { closed = parent._nsuiCollapsed, feature = parentId }
    local row, h = self:Feature(parent, yOffset, cfg, nestedKey)
    row._searchF = parentId
    parent._nsuiDisclosure = saved
    if saved.closed then row:Hide(); parent._nsuiCollapsed = true; h = 0 end
    return row, h
end

function W:EndDisclosure(parent)
    local scan = UI.searchScan
    if scan then
        local saved = scan.disclosure
        scan.feature, scan.featureName = saved.feature, saved.featureName
        scan.disclosure = nil
        return
    end
    local saved = parent._nsuiDisclosure
    parent._nsuiCollapsed, parent._nsuiFeatureId = saved.closed, saved.feature
    parent._nsuiDisclosure = nil
end

function W:EndFeature(parent)
    if UI.searchScan then
        UI.searchScan.feature, UI.searchScan.featureName = nil, nil
        return
    end
    parent._nsuiCollapsed, parent._nsuiFeatureId = nil, nil
end

function W:Button(parent, text, yOffset, onClick)
    if UI.searchScan then
        ScanLabel(text)
        return nil, ROW_H
    end
    local row = CachedRow(parent, "button:" .. text) or CreateFrame("Frame", nil, parent)
    row._searchL, row._searchF = text, parent._nsuiFeatureId
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, yOffset)
    row._onClick = onClick
    if not row._btn then
        row._btn = ns.Button(row, text, 200, 26, function() row._onClick() end)
        row._btn:SetPoint("LEFT", row, "LEFT", 20, 0)
    end
    Mark(row, text)
    return Collapsed(parent, row, ROW_H)
end

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- A key field for one binding action (Bindings.xml), saved where the game's Key Bindings
-- screen saves it.
-- Click it and press a key to bind, Escape to cancel; right-click clears it.
-- The page reuses its rows, so a region that already has its key button keeps it.
function UI.KeyField(rgn, action, label)
    if rgn._keyField then return end
    rgn._keyField = true
    local btn = ns.Button(rgn, "", 150, 26)
    btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    -- The row's label, and the hover area that shows its tooltip, end where the field starts,
    -- or that tooltip covers the field.
    if rgn._label then rgn._label:SetPoint("RIGHT", btn, "LEFT", -8, 0) end
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local capturing
    local function Show()
        local key = GetBindingKey(action)
        btn.label:SetText(capturing and "Press a key..." or key and GetBindingText(key) or "|cff808080Not bound|r")
        btn:SetAlpha(InCombatLockdown() and 0.4 or 1)
    end
    local function Stop()
        capturing = false
        btn:EnableKeyboard(false)
        Show()
    end
    local function Save()
        SaveBindings(GetCurrentBindingSet())
    end
    btn:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then return end
        if button == "RightButton" then
            for _, key in ipairs({ GetBindingKey(action) }) do SetBinding(key) end
            Save()
            Stop()
            return
        end
        capturing = true
        btn:EnableKeyboard(true)
        btn:SetPropagateKeyboardInput(false)
        Show()
    end)
    btn:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" or InCombatLockdown() then
            Stop()
            return
        end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local previous = GetBindingAction(combo)
        for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
        SetBinding(combo, action)
        Save()
        if previous ~= "" and previous ~= action then
            ns.Print(("%s is now bound to %s instead of %s."):format(GetBindingText(combo), label,
                GetBindingName(previous)))
        end
        Stop()
    end)
    -- Setting an OnKeyDown script turns keyboard input on; it stays off until the field is clicked.
    btn:EnableKeyboard(false)
    btn:SetScript("OnShow", Show)
    btn:SetScript("OnHide", function() if capturing then Stop() end end)
    ns.Tooltip(btn, label, "Click, then press a key to bind it. Escape cancels; right-click clears. "
        .. "The same binding as in Key Bindings > Naowh Forever.")
    Show()
end

-- A full-row Reload UI button (see Reload UI in the Core file).
function W:ReloadButton(parent, yOffset)
    local row, h = self:Button(parent, "Reload UI", yOffset)
    if row and row._btn then ns.MakeReloadButton(row._btn) end
    return row, h
end

-- The swatch alone, sized to drop into either a full row (W:ColorPicker below) or a
-- DualRow region (BuildRegionControl's "colorpicker" slot) -- one Blizzard color picker
-- wiring, not two copies of it drifting apart.
function UI.BuildColorSwatchControl(parent, get, set, hasAlpha)
    local swatchBtn = CreateFrame("Button", nil, parent)
    swatchBtn:SetSize(40, 20)
    ns.Border(swatchBtn, BLACK)
    local swatch = ns.Solid(swatchBtn, "BACKGROUND", T.fg, 1)
    swatch:SetAllPoints()
    swatchBtn._get, swatchBtn._set, swatchBtn._hasAlpha = get, set, hasAlpha
    local function PaintSwatch()
        local r, g, b = swatchBtn._get()
        swatch:SetColorTexture(r or 1, g or 1, b or 1, 1)
    end
    PaintSwatch()
    swatchBtn._refreshValue = PaintSwatch

    -- The picker calls swatchFunc as it opens and cancelFunc on Escape or a click away, so
    -- nothing is saved until the color actually moves off the one it opened with.
    swatchBtn:SetScript("OnClick", function()
        local read, write, withAlpha = swatchBtn._get, swatchBtn._set, swatchBtn._hasAlpha
        local r, g, b, a = read()
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        local changed = false
        local function Apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = withAlpha and ColorPickerFrame:GetColorAlpha() or 1
            local near = 1 / 255
            if not changed and math.abs(nr - r) <= near and math.abs(ng - g) <= near
                and math.abs(nb - b) <= near and math.abs(na - a) <= near then
                return
            end
            changed = true
            write(nr, ng, nb, na)
            PaintSwatch()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            opacity = a,
            hasOpacity = withAlpha and true or false,
            swatchFunc = Apply,
            opacityFunc = Apply,
            cancelFunc = function()
                if not changed then return end
                write(r, g, b, a)
                PaintSwatch()
            end,
        })
    end)
    return swatchBtn
end

function W:ColorPicker(parent, text, yOffset, get, set, hasAlpha)
    if UI.searchScan then
        ScanLabel(text)
        return nil, ROW_H
    end
    local row = CachedRow(parent, "color:" .. text) or CreateFrame("Frame", nil, parent)
    row._searchL = text
    row._colorGet, row._colorSet = get, set
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD, yOffset)

    local count = (parent._nsuiRowCount or 0) + 1
    parent._nsuiRowCount = count
    if row._swatch then
        row._swatch._refreshValue()
        if row._band then row._band:SetShown(count % 2 == 1) end
        return Collapsed(parent, row, ROW_H)
    end
    if count % 2 == 1 or parent._rowCache then
        local band = ns.Solid(row, "BACKGROUND", T.panel, 0.35)
        band:SetAllPoints()
        band:SetShown(count % 2 == 1)
        row._band = band
    end

    local lbl = ns.Font(row, 14, nil)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(text)

    local swatchBtn = UI.BuildColorSwatchControl(row,
        function() return row._colorGet() end,
        function(...) return row._colorSet(...) end, hasAlpha)
    row._swatch = swatchBtn
    swatchBtn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    return Collapsed(parent, row, ROW_H)
end

-- A wrapped line of muted text across the content width, for context a row label cannot
-- carry. On a page that reuses its rows the font string is reused too, in build order.
function W:Note(parent, text, yOffset)
    if UI.searchScan then return nil, ROW_H end
    local row = CachedRow(parent, "note")
    if row then
        row:SetPoint("TOPLEFT")
        row:SetSize(1, 1)
    end
    local fs = row and row._fs
    if not fs then
        fs = ns.Font(row or parent, 12, nil, T.muted)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if row then row._fs = fs end
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD + 20, yOffset - 12)
    local w = parent:GetWidth() or 0
    if w <= 0 then w = 960 end
    fs:SetWidth(w - (UI.CONTENT_PAD + 20) * 2)
    fs:SetText(text)
    fs:Show()
    local h = math.ceil(fs:GetStringHeight()) + 24
    return Collapsed(parent, fs, h)
end

-- Shared placement controls for ordinary display plates and reminder anchor handles.
-- All geometry belongs to this addon; the guide is positioned numerically on UIParent,
-- never anchored to a protected display such as the Top Bar.
local placement = { active = false }

local function PlacementPoint(item)
    local point, relative, relPoint, x, y = item.frame:GetPoint(1)
    if not point then return end
    if relative and relative ~= UIParent then
        local cx, cy = item.frame:GetCenter()
        local px, py = UIParent:GetCenter()
        if not cx or not px then return end
        local scale = item.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        point, relPoint, x, y = "CENTER", "CENTER", cx - px / scale, cy - py / scale
    end
    return point, relPoint, x, y
end

local function SavePlacement(item, point, relPoint, x, y)
    if not point then point, relPoint, x, y = PlacementPoint(item) end
    if not point then return end
    item.frame:ClearAllPoints()
    item.frame:SetPoint(point, UIParent, relPoint, x, y)
    item.save({ point = point, relPoint = relPoint, x = x, y = y })
end

local function StopPlacementDrag(item)
    if not item or not item.dragging then return end
    if InCombatLockdown() and item.frame:IsProtected() then placement.pendingDrag = item; return end
    item.dragging = false
    item.handle:SetScript("OnUpdate", nil)
    item.frame:StopMovingOrSizing()
    SavePlacement(item)
end

function UI.ClearMoverSelection()
    StopPlacementDrag(placement.selected)
    placement.selected = nil
    if not placement.keys then return end
    placement.outline:Hide()
    placement.vertical:Hide()
    placement.horizontal:Hide()
    if not InCombatLockdown() then placement.keys:SetPropagateKeyboardInput(true) end
end

function UI.RefreshMoverSelection()
    local item = placement.selected
    if not item or InCombatLockdown() then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    local frame = item.frame
    if not frame:GetPoint(1) then return end
    local scale = item.handle:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, bottom = item.handle:GetLeft(), item.handle:GetBottom()
    if left and bottom then
        local width, height = item.handle:GetWidth() * scale + 4, item.handle:GetHeight() * scale + 4
        left, bottom = left * scale - 2, bottom * scale - 2
        placement.outline:ClearAllPoints()
        placement.outline:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        placement.outline:SetSize(width, height)
        placement.outline:Show()
    end
    local cx, cy = frame:GetCenter()
    if cx and cy then
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        placement.vertical:ClearAllPoints()
        placement.vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx * ratio, 0)
        placement.vertical:SetSize(1, UIParent:GetHeight())
        placement.horizontal:ClearAllPoints()
        placement.horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, cy * ratio)
        placement.horizontal:SetSize(UIParent:GetWidth(), 1)
        placement.vertical:Show()
        placement.horizontal:Show()
    end
end

local function PlacementKey(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(true)
    local item = placement.selected
    if not placement.active or not item or item.dragging or GetCurrentKeyBoardFocus() then return end
    if key == "ESCAPE" then UI.ClearMoverSelection(); self:SetPropagateKeyboardInput(false); return end
    local dx = key == "LEFT" and -1 or key == "RIGHT" and 1 or 0
    local dy = key == "DOWN" and -1 or key == "UP" and 1 or 0
    if dx == 0 and dy == 0 then return end
    if not item.handle:IsVisible() then UI.ClearMoverSelection(); return end
    local step = IsShiftKeyDown() and 10 or 1
    -- Normalize the uncommon non-screen anchor through the same path used by dragging.
    local point, relPoint, x, y = PlacementPoint(item)
    if not point then return end
    -- Save the requested offsets directly; layout readback can round fractional points.
    SavePlacement(item, point, relPoint, x + dx * step, y + dy * step)
    UI.RefreshMoverSelection()
    self:SetPropagateKeyboardInput(false)
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
        placement.outline = CreateFrame("Frame", nil, UIParent)
        placement.outline:SetFrameStrata("FULLSCREEN_DIALOG")
        placement.outline:SetFrameLevel(499)
        ns.Solid(placement.outline, "BACKGROUND", { r = 1, g = 1, b = 1 }, 0.10):SetAllPoints()
        ns.Border(placement.outline, { r = 1, g = 1, b = 1 })
        local guides = CreateFrame("Frame", nil, UIParent)
        guides:SetFrameStrata("BACKGROUND")
        guides:SetFrameLevel(2)
        placement.vertical = ns.Solid(guides, "OVERLAY", T.accentSoft, 0.9)
        placement.horizontal = ns.Solid(guides, "OVERLAY", T.accentSoft, 0.9)
        -- Keep selection geometry aligned when owners resize or reposition their previews.
        local refreshElapsed = 0
        keys:SetScript("OnUpdate", function(_, elapsed)
            refreshElapsed = refreshElapsed + elapsed
            if refreshElapsed < 0.05 then return end
            refreshElapsed = 0
            if placement.active and placement.selected then UI.RefreshMoverSelection() end
        end)
        keys:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                UI.ClearMoverSelection()
                keys:Hide()
            else
                StopPlacementDrag(placement.pendingDrag)
                placement.pendingDrag = nil
                if placement.active then UI.BeginMoverMode() else keys:UnregisterAllEvents() end
            end
        end)
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
    UI.RefreshMoverSelection()
end

function UI.StartMoverDrag(handle)
    if not placement.active or InCombatLockdown() or not handle:IsVisible() then return end
    local item = handle._placement
    UI.SelectMover(handle)
    item.dragging = true
    item.frame:StartMoving()
    handle:SetScript("OnUpdate", function()
        if not InCombatLockdown() then UI.RefreshMoverSelection() end
    end)
end

function UI.StopMoverDrag(handle)
    StopPlacementDrag(handle._placement)
    UI.RefreshMoverSelection()
end

-- Out of Unlock Mode and onto the element's options: the options window draws over the
-- movers, so the two cannot share the screen.
local function OpenElementOptions(item)
    ns.HideRaidReminderAnchorConfig()
    ns.OpenOptionsWindow(item.page)
    if item.feature then UI.GoToSetting(item.page, nil, item.feature) end
end

-- page: the options page that sets the element up ("QoL/General"); feature: the section on
-- it to open, if it has one.
function UI.BindMover(handle, frame, label, onMoved, page, feature)
    local item = { handle = handle, frame = frame, label = label, save = onMoved, page = page, feature = feature }
    handle._placement = item
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            UI.SelectMover(handle)
        elseif button == "RightButton" and page and not InCombatLockdown() then
            MenuUtil.CreateContextMenu(handle, function(_, root)
                root:CreateTitle(label)
                root:CreateButton("Element Options", function() OpenElementOptions(item) end)
            end)
        end
    end)
    handle:SetScript("OnDragStart", function() UI.StartMoverDrag(handle) end)
    handle:SetScript("OnDragStop", function() UI.StopMoverDrag(handle) end)
    handle:HookScript("OnHide", function()
        StopPlacementDrag(item)
        if placement.selected == item then UI.ClearMoverSelection() end
    end)
end

-- Unlock Mode plate for an on-screen display. Hidden until the caller shows it. page and
-- feature: where its options are (UI.BindMover).
function UI.AttachMover(frame, label, onMoved, page, feature)
    local mover = CreateFrame("Frame", nil, frame)
    mover:SetAllPoints()
    mover:SetFrameLevel(frame:GetFrameLevel() + 20)
    ns.Solid(mover, "BACKGROUND", T.accent, 0.35):SetAllPoints()
    ns.Border(mover, T.accent)
    local text = ns.Font(mover, 12, "OUTLINE")
    text:SetPoint("CENTER")
    text:SetText(label)
    mover.text = text
    UI.BindMover(mover, frame, label, onMoved, page, feature)
    mover:Hide()
    return mover
end

-- Font dropdown data: "" follows the Addon Font, then every SharedMedia font. A saved font
-- that has since gone missing stays listed so the dropdown does not show a blank.
-------------------------------------------------------------------------------
--  Slim scroll
-------------------------------------------------------------------------------
-- A scroll frame with a thin scrollbar in the theme's colours, in place of Blizzard's grey
-- one with its arrow buttons: a track and a thumb sized to how much of the content shows,
-- dragged, clicked or moved with the mouse wheel. It hides while everything fits. The bar
-- sits to the right of the frame, width + gap inside whatever the frame is anchored in.
local SCROLL_STEP = 40

function UI.SlimScroll(parent, width, gap)
    width, gap = width or 6, gap or 6
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(width)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", gap, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", gap, 0)
    bar:SetObeyStepOnDrag(false)
    local track = ns.Solid(bar, "BACKGROUND", T.line, 0.6)
    track:SetAllPoints()
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(T.muted.r, T.muted.g, T.muted.b, 0.8)
    thumb:SetWidth(width)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    bar:SetScript("OnEnter", function() thumb:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1) end)
    bar:SetScript("OnLeave", function() thumb:SetColorTexture(T.muted.r, T.muted.g, T.muted.b, 0.8) end)

    scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
        range = range or self:GetVerticalScrollRange()
        local shown = self:GetHeight()
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        thumb:SetHeight(math.max(24, bar:GetHeight() * shown / (shown + range)))
        if bar:GetValue() > range then bar:SetValue(range) end
    end)
    scroll:SetScript("OnVerticalScroll", function(_, offset)
        if math.abs(bar:GetValue() - offset) > 0.5 then bar:SetValue(offset) end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(bar:GetValue() - delta * SCROLL_STEP)
    end)
    scroll.bar = bar
    return scroll
end

function UI.FontChoices(selected)
    local values, order = { [""] = "Addon Font" }, { "" }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            values[name] = name
            order[#order + 1] = name
        end
    end
    if type(selected) == "string" and selected ~= "" and not values[selected] then
        values[selected] = selected .. " (unavailable)"
        order[#order + 1] = selected
    end
    return values, order
end

-- A SharedMedia font by name, or the Addon Font for "" and anything missing.
function UI.FontPath(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = LSM and name and name ~= "" and LSM:Fetch("font", name, true)
    return path or ns.UIFontPath()
end

-- Settings for the Naowh Forever modules: one table per module inside the active profile,
-- read through defaults so a key an older profile never wrote picks up the current default.
-- The row makers return W:DualRow configs; `on` names the master toggle a row depends on, or
-- lists several (off while any of them is), and every toggle redraws the page so dependants
-- dim and undim with it.
-- S.OnChange(fn) calls fn(key, value) after every S.Set, in the order they were added: a
-- module listens to its own settings there instead of wrapping S.Set with hooksecurefunc.
local moduleDefaults = {}
local SHARE_DEPTH = 4

local function Plain(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return true end
    if t ~= "table" or depth > SHARE_DEPTH then return false end
    for k, val in pairs(v) do
        local kt = type(k)
        if (kt ~= "string" and kt ~= "number") or not Plain(val, depth + 1) then return false end
    end
    return true
end

local function CopyPlain(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = CopyPlain(val) end
    return out
end

-- What a profile string carries of a module: each setting it has a default for, as that type
-- (not the lists it keeps, which default to empty), and its Unlock Mode positions.
local function Shareable(defaults, k, v)
    if type(k) ~= "string" then return false end
    local d = defaults[k]
    if d == nil then return k:find("Pos$") ~= nil and type(v) == "table" and Plain(v, 0) end
    if type(v) ~= type(d) then return false end
    if type(d) == "table" then return next(d) ~= nil and Plain(v, 0) end
    return true
end

function ns.ExportModuleSettings(root)
    local out
    for key, defaults in pairs(moduleDefaults) do
        local t = root[key]
        if type(t) == "table" then
            for k, v in pairs(t) do
                if Shareable(defaults, k, v) then
                    out = out or {}
                    out[key] = out[key] or {}
                    out[key][k] = CopyPlain(v)
                end
            end
        end
    end
    return out
end

function ns.ImportModuleSettings(root, modules)
    if type(root) ~= "table" or type(modules) ~= "table" then return end
    for key, values in pairs(modules) do
        local defaults = moduleDefaults[key]
        if defaults and type(values) == "table" then
            if type(root[key]) ~= "table" then root[key] = {} end
            for k, v in pairs(values) do
                if Shareable(defaults, k, v) then root[key][k] = CopyPlain(v) end
            end
        end
    end
end

function UI.ModuleSettings(key, defaults)
    local S = {}
    local listeners = {}
    local known = moduleDefaults[key]
    if known then
        for k, v in pairs(defaults) do
            if known[k] == nil then known[k] = v end
        end
    else
        moduleDefaults[key] = defaults
    end
    function S.DB()
        local root = ns.SettingsRoot()
        if type(root[key]) ~= "table" then root[key] = {} end
        return root[key]
    end
    function S.Get(k)
        local v = S.DB()[k]
        if v == nil then return defaults[k] end
        return v
    end
    function S.Raw(k) return S.DB()[k] end
    function S.Default(k) return defaults[k] end
    function S.Set(k, v)
        S.DB()[k] = v
        for i = 1, #listeners do listeners[i](k, v) end
    end
    function S.OnChange(fn) listeners[#listeners + 1] = fn end

    local function Row(cfg, k, on)
        cfg.getValue = function() return S.Get(k) end
        cfg.setValue = cfg.setValue or function(v) S.Set(k, v) end
        if type(on) == "table" then
            cfg.disabled = function()
                for i = 1, #on do
                    if not S.Get(on[i]) then return true end
                end
                return false
            end
        elseif on then
            cfg.disabled = function() return not S.Get(on) end
        end
        return cfg
    end
    function S.Toggle(k, text, tooltip, on)
        return Row({ type = "toggle", text = text, tooltip = tooltip,
            setValue = function(v) S.Set(k, v); UI:RefreshPage(true) end }, k, on)
    end
    function S.Slider(k, text, min, max, step, tooltip, on)
        return Row({ type = "slider", text = text, tooltip = tooltip,
            min = min, max = max, step = step }, k, on)
    end
    function S.Dropdown(k, text, values, order, tooltip, on)
        return Row({ type = "dropdown", text = text, tooltip = tooltip,
            values = values, order = order }, k, on)
    end
    -- A sound to pick: it plays as you pick it, and its play button plays it again. play
    -- takes the key; UI.PlaySoundKey (the addon's sound list) unless given.
    function S.SoundDropdown(k, text, values, order, tooltip, on, play)
        play = play or UI.PlaySoundKey
        return Row({ type = "dropdown", text = text, tooltip = tooltip, values = values, order = order,
            width = 200, preview = play, setValue = function(v) S.Set(k, v); play(v) end }, k, on)
    end
    return S
end

-------------------------------------------------------------------------------
--  Sounds
-------------------------------------------------------------------------------
-- Bundled English voice clips work without an optional SharedMedia provider.
-- Stable keys are shared by preview, native aura registrations and exported rules.
local bundledVoices = {
    { key = "voice:dispel-me", text = "Dispel me", file = "dispel-me.ogg" },
    { key = "voice:move-out", text = "Move out", file = "move-out.ogg" },
    { key = "voice:use-a-defensive", text = "Use a defensive", file = "use-a-defensive.ogg" },
    { key = "voice:combat", text = "Combat", file = "combat.ogg" },
    { key = "voice:safe", text = "Safe", file = "safe.ogg" },
}
local voicePath = "Interface\\AddOns\\NaowhForever\\Media\\Voice\\"
function UI.BuildAlertSoundTables()
    local paths, names, order = {}, { none = "None" }, { "none" }
    for _, voice in ipairs(bundledVoices) do
        paths[voice.key] = voicePath .. voice.file
        names[voice.key] = "Voice: " .. voice.text .. " (English)"
        order[#order + 1] = voice.key
    end
    return paths, names, order
end

function UI.AppendSharedMediaSounds(paths, names, order)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local list = LSM:HashTable("sound")
    if not list then return end
    local sorted = {}
    for name in pairs(list) do sorted[#sorted + 1] = name end
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(sorted) do
        local key = "sm:" .. name
        if name == "None" then
            -- LibSharedMedia's own silent placeholder. It stays out of the list, but a
            -- choice saved before keeps a readable name instead of the raw "sm:None".
            names[key] = names[key] or "None"
        elseif not names[key] then
            paths[key] = list[name]
            names[key] = name
            order[#order + 1] = key
        end
    end
end

-- Plays a sound by its key in the addon's sound list (ns.SoundChoices); "none" plays nothing.
function UI.PlaySoundKey(key)
    UI._PlayLSMSound(UI.SoundPathFor(key))
end

function UI._PlayLSMSound(v)
    if v == nil or v == 1 then return end
    if type(v) == "string" then
        PlaySoundFile(v, "Master")
    elseif type(v) == "number" then
        PlaySound(v, "Master")
    end
end

-- Resolves a stored soundKey to a playable path. Built once and dropped whenever SharedMedia
-- registers another sound (boss mods register theirs when they load, often after login).
-- Rebuilding on a miss instead re-sorted every sound on every callout once a pack was removed.
local soundPaths
local soundProvider
local function SoundRegistered(_, mediatype)
    if mediatype == "sound" then
        soundPaths = nil
        if ns and ns.Integrations then ns.Integrations.Refresh() end
    end
end

function UI.SoundPathFor(key)
    if not key or key == "none" then return nil end
    -- Dedicated files keep racial gating separate from previews and other sounds.
    if key == "voice:stoneform-ready" then return voicePath .. "stoneform-ready.ogg" end
    if key == "voice:stoneform-preview" then return voicePath .. "stoneform-preview.ogg" end
    if key == "voice:shadowmeld-ready" then return voicePath .. "shadowmeld-ready.ogg" end
    if key == "voice:shadowmeld-preview" then return voicePath .. "shadowmeld-preview.ogg" end
    for _, voice in ipairs(bundledVoices) do
        if key == voice.key then return voicePath .. voice.file end
    end
    local provider = LibStub and LibStub("LibSharedMedia-3.0", true)
    -- A missing optional provider is not a cached miss. It may load later.
    if not provider then return nil end
    if provider ~= soundProvider then
        if soundProvider then
            soundProvider.UnregisterCallback(UI, "LibSharedMedia_Registered")
        end
        provider.RegisterCallback(UI, "LibSharedMedia_Registered", SoundRegistered)
        soundProvider = provider
        soundPaths = nil
    end
    if not soundPaths then
        local paths, names, order = UI.BuildAlertSoundTables()
        UI.AppendSharedMediaSounds(paths, names, order)
        soundPaths = paths
    end
    return soundPaths[key]
end
