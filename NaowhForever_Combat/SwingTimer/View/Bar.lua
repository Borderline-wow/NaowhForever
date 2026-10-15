-- Bar.lua: a Swing Timer bar's look, the same on screen and on the cards' previews.
local ns = _G.NaowhForever

local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style
local ST = ns.SwingTimer
local S = ST.Settings
local C = ST.C

local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FLAT_TEX = C.FLAT_TEX
local TEXT_PAD = 4
local BG_ALPHA = 0.6
local TEXT_SIZE = 11
local TICK_W = 2
local SPARK_W, SPARK_GROW = 8, 2
local EDGE = 2
local OVER_LEVEL = 2
local QUEUED = " - "

local Look = {}
ST.Look = Look

function Look.Row(parent, label)
    local row = CreateFrame("Frame", nil, parent)
    row.label, row.slot, row.switch = label, ST.BAR_SWING[label], C.BAR_SWITCH[label]
    row.hand = label == "MH" or label == "OH"
    row.colorKey = label:lower() .. "Color"
    row.bg = ns.Solid(row, "BACKGROUND", T.bg, BG_ALPHA)
    row.bg:SetAllPoints()
    row.border = ns.Border(row)

    local bar = CreateFrame("StatusBar", nil, row)
    ns.PixelInset(bar, 1)
    bar:SetStatusBarTexture(FLAT_TEX)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints()
    over:SetFrameLevel(bar:GetFrameLevel() + OVER_LEVEL)
    row.window = over:CreateTexture(nil, "ARTWORK")
    row.window:Hide()
    row.spark = over:CreateTexture(nil, "OVERLAY", nil, 1)
    row.spark:SetTexture(SPARK_TEX)
    row.spark:SetBlendMode("ADD")
    row.spark:Hide()
    if row.slot == ST.SWING.MainHand then
        row.tick = over:CreateTexture(nil, "OVERLAY", nil, 2)
        row.tick:SetWidth(TICK_W)
        row.tick:Hide()
    end
    row.tag = ns.Font(over, TEXT_SIZE, "OUTLINE")
    row.tag:SetPoint("LEFT", row, "LEFT", TEXT_PAD, 0)
    row.tag:SetText(label)
    row.time = ns.Font(over, TEXT_SIZE, "OUTLINE")
    row.time:SetPoint("RIGHT", row, "RIGHT", -TEXT_PAD, 0)
    row.time:SetText("")
    return row
end

function Look.Style(row, tex)
    local size, h = S.Get("textSize"), S.Get("rowHeight")
    row.bar:SetStatusBarTexture(tex)
    row.spark:ClearAllPoints()
    row.spark:SetPoint("CENTER", row.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    row.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, S.Get("bgAlpha"))
    row.spark:SetSize(SPARK_W, h * SPARK_GROW)
    local font, outline = S.Get("font"), S.Get("outline")
    Parts.HudFont(row.tag, font, size, outline)
    Parts.HudFont(row.time, font, size, outline)
    row.tag:SetShown(S.Get("showLabel"))
    row.time:SetShown(S.Get("showTime"))
end

function Look.BarColor(row)
    if S.Get("classColored") and row.slot ~= ST.TARGET then
        local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b, 1 end
    end
    return ST.Color(row.colorKey)
end

function Look.Tag(row, queuedName)
    if queuedName then
        row.tag:SetText(row.label .. QUEUED .. queuedName)
    else
        row.tag:SetText(row.label)
    end
end

function Look.Range(row, far)
    local c = far and St.RED_RGB or T.fg
    row:SetAlpha(far and S.Get("outOfRangeAlpha") or 1)
    row.tag:SetTextColor(c.r, c.g, c.b)
    row.time:SetTextColor(c.r, c.g, c.b)
end

function Look.Window(row, share, r, g, b, a)
    local win = row.window
    local w = (S.Get("width") - EDGE) * math.min(share, 1)
    local side = S.Get("depleteFill") and "LEFT" or "RIGHT"
    win:ClearAllPoints()
    win:SetPoint("TOP" .. side, row.bar, "TOP" .. side, 0, 0)
    win:SetPoint("BOTTOM" .. side, row.bar, "BOTTOM" .. side, 0, 0)
    win:SetWidth(math.max(w, 1))
    win:SetColorTexture(r, g, b, a)
    win:Show()
end

function Look.Tick(row, frac, r, g, b, a)
    local tick = row.tick
    if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
    if S.Get("depleteFill") then frac = 1 - frac end
    local x = (S.Get("width") - EDGE) * frac
    tick:ClearAllPoints()
    tick:SetPoint("TOP", row.bar, "TOPLEFT", x, 0)
    tick:SetPoint("BOTTOM", row.bar, "BOTTOMLEFT", x, 0)
    tick:SetColorTexture(r, g, b, a)
    tick:Show()
end
