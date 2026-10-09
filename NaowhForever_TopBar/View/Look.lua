-- Look.lua: how the Top Bar draws, the same for the bar and its preview: pills, clock, rows of buttons, the FPS / MS readout (ns.TopBar.Look).
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local Parts = ns.Shared.Parts

local TB = ns.TopBar
local S = TB.Settings
local C = TB.C
local St = TB.Style

local GAP, SEG_PAD, BADGE_SIZE, PERCENT = C.GAP, C.SEG_PAD, C.BADGE_SIZE, C.PERCENT
local LDB_PREFIX, SIDES = C.LDB_PREFIX, C.SIDES
local PILL_BG, PILL_LINE_ALPHA = St.PILL_BG, St.PILL_LINE_ALPHA
local GLYPH, ICON, WHITE = St.GLYPH, St.ICON, St.WHITE
local BTN_PAD, EDGE, CLOCK_GAP, CLOCK_PAD, BAR_ROOM = 8, 14, 22, 6, 2
local PILLS, CLOCK_SEG_PAD = 3, 4
local CLOCK_MIN_W, CLOCK_TEXT_PAD = 24, 8
local FPS_GREAT, FPS_GOOD, FPS_OK = 100, 60, 30
local MS_GOOD, MS_OK = 75, 150
local HEX_SCALE, ROUND = 255, C.ROUND
local NO_OUTLINE = "NONE"
local CLOCK_24H, CLOCK_12H = "%H:%M", "%I:%M %p"
local SYSTEM_TEXT = "FPS: |c%s%d|r  MS: |c%s%d|r"
local NO_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local GLYPH_COORDS = { 0, 1, 0, 1 }

local shades = {}

local function Tone(key, v)
    local shade = shades[v]
    if not shade then
        shade = { r = v, g = v, b = v }
        shades[v] = shade
    end
    local c = ns.ThemeTint(key, shade)
    return c.r, c.g, c.b
end

local function Hex(r, g, b)
    return ("ff%02x%02x%02x"):format(math.floor(r * HEX_SCALE + ROUND), math.floor(g * HEX_SCALE + ROUND),
        math.floor(b * HEX_SCALE + ROUND))
end

local function Band(c) return { r = c.r, g = c.g, b = c.b, hex = Hex(c.r, c.g, c.b) } end

local FPS_GREAT_BAND, FPS_GOOD_BAND = Band(St.FPS_GREAT_RGB), Band(St.FPS_GOOD_RGB)
local FPS_OK_BAND, FPS_LOW_BAND = Band(St.FPS_OK_RGB), Band(St.FPS_LOW_RGB)
local MS_GOOD_BAND, MS_OK_BAND, MS_HIGH_BAND = Band(St.MS_GOOD_RGB), Band(St.MS_OK_RGB), Band(St.MS_HIGH_RGB)

local function FpsBand(fps)
    if fps >= FPS_GREAT then return FPS_GREAT_BAND end
    if fps >= FPS_GOOD then return FPS_GOOD_BAND end
    if fps >= FPS_OK then return FPS_OK_BAND end
    return FPS_LOW_BAND
end

local function MsBand(ms)
    if ms < MS_GOOD then return MS_GOOD_BAND end
    if ms < MS_OK then return MS_OK_BAND end
    return MS_HIGH_BAND
end

local function PlaceBroker(place, side, key, ldb)
    local name = key:sub(#LDB_PREFIX + 1)
    local obj = ldb:GetDataObjectByName(name)
    if not (obj and obj.icon) then return end
    local glyph = GLYPH[name]
    place(side, key, glyph or obj.icon, glyph ~= nil, glyph and GLYPH_COORDS or obj.iconCoords or NO_COORDS, name)
end

local function IsBroker(key)
    return type(key) == "string" and key:sub(1, #LDB_PREFIX) == LDB_PREFIX
end

local Look = { GLYPH_COORDS = GLYPH_COORDS, Tone = Tone }
TB.Look = Look

function Look.Accent()
    return T.accent.r, T.accent.g, T.accent.b
end

-- Classic+ icons are in full colour, so nothing tints them; the game's highlight shows the hover.
function Look.IconColor()
    if ns.classicSkin then return 1, 1, 1 end
    local c = S.Get("iconColor")
    return c.r, c.g, c.b
end

function Look.HoverColor()
    if ns.classicSkin then return 1, 1, 1 end
    return Look.Accent()
end

function Look.BtnSize()
    return S.Get("iconSize") + BTN_PAD
end

function Look.BarHeight()
    return math.max(S.Get("showClock") and S.Get("clockSize") + CLOCK_PAD or 0, Look.BtnSize() + BAR_ROOM)
end

function Look.FpsRGB(fps)
    local c = FpsBand(fps)
    return c.r, c.g, c.b
end

function Look.MsRGB(ms)
    local c = MsBand(ms)
    return c.r, c.g, c.b
end

function Look.NewPills(frame)
    local segs = {}
    for i = 1, PILLS do
        local seg = frame:CreateTexture(nil, "BACKGROUND")
        local line = frame:CreateTexture(nil, "BORDER")
        ns.Hairline(line, "h")
        line:SetPoint("BOTTOMLEFT", seg, "BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT")
        line:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, PILL_LINE_ALPHA)
        seg.line = line
        segs[i] = seg
    end
    return segs
end

function Look.PaintPills(frame, segs, left, right, clock, nLeft, nRight)
    local pill = ns.ThemeTint("bg", PILL_BG)
    for _, seg in ipairs(segs) do seg:SetColorTexture(pill.r, pill.g, pill.b, S.Get("bgAlpha") / PERCENT) end
    local segL, segC, segR = segs[1], segs[2], segs[3]
    local joined = not S.Get("showClock") and nLeft > 0 and nRight > 0
    segL:ClearAllPoints()
    segL:SetPoint("TOPLEFT", left, "TOPLEFT", -SEG_PAD, 0)
    segL:SetPoint("BOTTOMRIGHT", joined and right or left, "BOTTOMRIGHT", SEG_PAD, 0)
    segL:SetShown(nLeft > 0)
    segL.line:SetShown(nLeft > 0)
    segR:ClearAllPoints()
    segR:SetPoint("TOPLEFT", right, "TOPLEFT", -SEG_PAD, 0)
    segR:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", SEG_PAD, 0)
    segR:SetShown(nRight > 0 and not joined)
    segR.line:SetShown(nRight > 0 and not joined)
    segC:ClearAllPoints()
    segC:SetShown(S.Get("showClock"))
    segC.line:SetShown(S.Get("showClock"))
    segC:SetPoint("LEFT", clock, "LEFT", -(SEG_PAD + CLOCK_SEG_PAD), 0)
    segC:SetPoint("RIGHT", clock, "RIGHT", SEG_PAD + CLOCK_SEG_PAD, 0)
    segC:SetPoint("TOP", frame, "TOP")
    segC:SetPoint("BOTTOM", frame, "BOTTOM")
end

function Look.ClockFont(clock)
    local size, outline = S.Get("clockSize"), S.Get("clockOutline")
    local flags = outline == NO_OUTLINE and "" or outline
    if not clock:SetFont(UI.FontPath(S.Get("clockFont")), size, flags) then
        clock:SetFont(ns.UIFontPath(), size, flags)
    end
    Parts.HudText(clock, outline == "" and "card" or false)
    clock:SetTextColor(Tone("fg", WHITE))
end

function Look.ClockText()
    local use24h = S.Get("use24h")
    local text = date(use24h and CLOCK_24H or CLOCK_12H)
    if not use24h then text = text:gsub("^0", "") end
    return text
end

function Look.Row(group, list, n)
    local size, icon, x = Look.BtnSize(), S.Get("iconSize"), 0
    local font, outline = S.Get("font"), S.Get("outline")
    for i = 1, n do
        local b = list[i]
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", group, "LEFT", x, 0)
        b.icon:SetSize(icon, icon)
        b.icon:SetVertexColor(Look.IconColor())
        if b.badge then Parts.HudFont(b.badge, font, BADGE_SIZE, outline) end
        b:Show()
        x = x + size + GAP
    end
    group:SetSize(math.max(1, x - GAP), size)
end

function Look.Fit(frame, left, right, clock, nLeft, nRight)
    left:ClearAllPoints()
    right:ClearAllPoints()
    if not S.Get("showClock") then
        local leftW = nLeft > 0 and left:GetWidth() or 0
        local rightW = nRight > 0 and right:GetWidth() or 0
        local gap = (nLeft > 0 and nRight > 0) and GAP or 0
        frame:SetWidth(2 * EDGE + leftW + gap + rightW)
        left:SetPoint("LEFT", frame, "LEFT", EDGE, 0)
        right:SetPoint("RIGHT", frame, "RIGHT", -EDGE, 0)
        return
    end
    local side = math.max(left:GetWidth(), right:GetWidth())
    local clockW = math.max(CLOCK_MIN_W, clock:GetStringWidth() + CLOCK_TEXT_PAD)
    frame:SetWidth(2 * (EDGE + side + CLOCK_GAP) + clockW)
    left:SetPoint("LEFT", frame, "LEFT", EDGE + side - left:GetWidth(), 0)
    right:SetPoint("RIGHT", frame, "RIGHT", -(EDGE + side - right:GetWidth()), 0)
end

function Look.SystemFont(text)
    Parts.HudFont(text, S.Get("font"), S.Get("sysSize"), S.Get("outline"))
    text:SetTextColor(Tone("fg", WHITE))
end

function Look.SystemText(text, fps, ms)
    text:SetText(SYSTEM_TEXT:format(FpsBand(fps).hex, fps, MsBand(ms).hex, ms))
end

function Look.Buttons(place)
    local layout, ldb = TB.Layout.Saved(), TB.LDB()
    for s = 1, #SIDES do
        local side = SIDES[s]
        local keys = layout[side]
        for i = 1, #keys do
            local key = keys[i]
            if ICON[key] then
                place(side, key, ICON[key], true, GLYPH_COORDS)
            elseif ldb and IsBroker(key) then
                PlaceBroker(place, side, key, ldb)
            end
        end
    end
end
