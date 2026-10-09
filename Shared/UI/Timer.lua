-- Timer.lua: a timer line the client runs down by itself, its short time text, and stopping any timer bar (ns.Shared.Parts).
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts = Shared.Parts
local St = Shared.Style

local LINE_TRACK_ALPHA = 1
local LINE_FROM_SHARE = 0.45
local LINE_GLOW_W, LINE_GLOW_ALPHA = 28, 0.55
local MINUTES_FROM, HOURS_FROM = 90, 5400
local MINUTE, HOUR = 60, 3600
local SECONDS_FORMAT, MINUTES_FORMAT, HOURS_FORMAT = "%ds", "%dm", "%dh"
local STOP_AGO = 1

local shortTimes = {}

local function LineTimed()
    return C_DurationUtil and C_DurationUtil.CreateDuration and Enum and Enum.StatusBarTimerDirection
        and Enum.StatusBarInterpolation and true or false
end

local function LineBindable(text)
    return text and C_DurationUtil.CreateDurationTextBinding and C_StringUtil
        and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding
end

local function LineBinding(line, text)
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(text)
    binding:SetDuration(line.dur)
    line.formatter = Parts.ShortTime()
    binding:SetFormatter(line.formatter)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetEnabled(false)
    return binding
end

local function LineFormatter(line, prefix)
    local formatter = Parts.ShortTime(prefix)
    if formatter == line.formatter then return end
    line.formatter = formatter
    line.binding:SetFormatter(formatter)
end

local function LineRun(line, start, duration, prefix)
    if line.dur then
        line.dur:SetTimeFromStart(start, duration)
        if line.binding then LineFormatter(line, prefix) end
        line:SetTimerDuration(line.dur, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
        if line.binding then line.binding:SetEnabled(true) end
    else
        line:SetValue(math.max(0, math.min(1, (start + duration - GetTime()) / duration)))
    end
    line.glow:Show()
end

local function LineStop(line)
    if line.dur then
        Parts.StopTimer(line, line.dur)
        if line.binding then line.binding:SetEnabled(false) end
    end
    line:SetValue(0)
    line.glow:Hide()
    if line.text then line.text:SetText("") end
end

local function LinePaint(line, color, textColor)
    local share = LINE_FROM_SHARE
    line.from:SetRGBA(color.r * share, color.g * share, color.b * share, 1)
    line.to:SetRGBA(color.r, color.g, color.b, 1)
    line:GetStatusBarTexture():SetGradient("HORIZONTAL", line.from, line.to)
    line.glowFrom:SetRGBA(color.r, color.g, color.b, 0)
    line.glowTo:SetRGBA(color.r, color.g, color.b, LINE_GLOW_ALPHA)
    line.glow:SetGradient("HORIZONTAL", line.glowFrom, line.glowTo)
    local c = textColor or color
    if line.text then line.text:SetTextColor(c.r, c.g, c.b) end
end

local function LineGlow(line, height)
    local over = CreateFrame("Frame", nil, line)
    over:SetAllPoints()
    local glow = over:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(St.WHITE)
    glow:SetBlendMode("ADD")
    glow:SetSize(LINE_GLOW_W, height)
    glow:SetPoint("RIGHT", line:GetStatusBarTexture(), "RIGHT")
    glow:Hide()
    return glow
end

function Parts.ShortTime(prefix)
    prefix = prefix or ""
    local formatter = shortTimes[prefix]
    if formatter then return formatter end
    local Up = Enum.NumericRuleFormatRounding.Up
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({
        { threshold = 0, format = prefix .. SECONDS_FORMAT, step = 1, rounding = Up },
        { threshold = MINUTES_FROM, format = prefix .. MINUTES_FORMAT, step = 1, rounding = Up,
            components = { { div = MINUTE } } },
        { threshold = HOURS_FROM, format = prefix .. HOURS_FORMAT, step = 1, rounding = Up,
            components = { { div = HOUR } } },
    })
    shortTimes[prefix] = formatter
    return formatter
end

function Parts.StopTimer(bar, dur, full)
    dur:SetTimeFromStart(GetTime() - STOP_AGO, STOP_AGO)
    bar:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, full
        and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
end

function Parts.TimerLine(parent, height, text)
    local line = CreateFrame("StatusBar", nil, parent)
    line:SetHeight(height)
    line:SetStatusBarTexture(St.WHITE)
    line:SetMinMaxValues(0, 1)
    line:SetValue(0)
    line:SetClipsChildren(true)
    ns.Solid(line, "BACKGROUND", T.line, LINE_TRACK_ALPHA):SetAllPoints()
    line.from, line.to = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    line.glowFrom, line.glowTo = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
    line.glow = LineGlow(line, height)
    line.text = text
    if LineTimed() then
        line.dur = C_DurationUtil.CreateDuration()
        if LineBindable(text) then line.binding = LineBinding(line, text) end
    end
    line.Run, line.Stop, line.Paint = LineRun, LineStop, LinePaint
    LinePaint(line, T.accent)
    return line
end
