-- SwingTimer.lua: the Swing Timer's settings (ns.SwingTimerSettings), its table (ns.SwingTimer) and its colors.
local ns = _G.NaowhForever

local F = ns.FEATURES.swingTimer
local T = ns.THEME
local St = ns.Shared.Style

local RANGED_SHADE = 0.6
local TARGET = "target"

local function Copy(c) return { r = c.r, g = c.g, b = c.b } end

local S = ns.UI.ModuleSettings("swingTimer", {
    enabled = F.enabled,
    width = 220, rowHeight = 14, spacing = 2, textSize = 11, font = "", outline = "OUTLINE",
    texture = "Naowh Gradient", bgAlpha = 0.6,
    visibility = "combat", hideWhenIdle = false,
    showMH = true, showOH = false, showR = false,
    depleteFill = false, showTime = true, showLabel = true, showSpark = true,
    rangeCheck = true, outOfRangeAlpha = 0.4,
    classColored = false, themeColors = false,
    mhColor = Copy(St.LOOK_RGB),
    ohColor = Copy(St.SECOND_RGB),
    rColor = Copy(St.HAVE_RGB),
    queueHighlight = F.queueHighlight,
    queueColor = { r = 1, g = 0.70, b = 0.20 },
    cleaveColor = Copy(St.RED_RGB),
    sealColors = F.sealColors,
    sealRighteousColor = { r = 0.95, g = 0.85, b = 0.40 },
    sealCrusaderColor = { r = 0.95, g = 0.55, b = 0.20 },
    sealCommandColor = { r = 0.75, g = 0.35, b = 0.95 },
    sealJusticeColor = { r = 0.60, g = 0.65, b = 0.75 },
    sealLightColor = { r = 1, g = 0.95, b = 0.70 },
    sealWisdomColor = { r = 0.35, g = 0.65, b = 1 },
    sealFuryColor = { r = 0.95, g = 0.25, b = 0.20 },
    sealMartyrdomColor = { r = 0.90, g = 0.40, b = 0.70 },
    swingWindow = F.swingWindow, swingWindowTime = 0.4,
    swingWindowColor = { r = 1, g = 1, b = 1, a = 0.35 },
    windowLatency = false,
    autoShotWindow = F.autoShotWindow,
    autoShotStandColor = { r = 0.30, g = 0.85, b = 0.35, a = 0.6 },
    autoShotMovingColor = { r = 0.95, g = 0.20, b = 0.20, a = 0.6 },
    castClip = F.castClip,
    castOkColor = { r = 1, g = 1, b = 1, a = 1 },
    castBadColor = { r = 1, g = 0.15, b = 0.15, a = 1 },
    targetSwing = F.targetSwing,
    tgtColor = { r = 0.85, g = 0.20, b = 0.20 },
})
ns.SwingTimerSettings = S

local SUPPORTED = C_SwingTimer and Enum.PlayerSwingType and C_DurationUtil
    and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDurationTextBinding
    and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and Enum.NumericRuleFormatRounding and Enum.StatusBarTimerDirection
    and Enum.StatusBarInterpolation and true or false

local function ThemedBar(key)
    if key == "mhColor" then return T.accent.r, T.accent.g, T.accent.b, 1 end
    if key == "ohColor" then return T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, 1 end
    if key == "rColor" then return T.accent.r * RANGED_SHADE, T.accent.g * RANGED_SHADE, T.accent.b * RANGED_SHADE, 1 end
end

local function Color(key)
    if S.Get("themeColors") then
        local r, g, b, a = ThemedBar(key)
        if r then return r, g, b, a end
    end
    local c = S.Get(key)
    return c.r, c.g, c.b, c.a or 1
end

local ST = { Settings = S, SUPPORTED = SUPPORTED, TARGET = TARGET, Color = Color }
ns.SwingTimer = ST

if SUPPORTED then
    ST.SWING = Enum.PlayerSwingType
    ST.BAR_SWING = { MH = ST.SWING.MainHand, OH = ST.SWING.OffHand, R = ST.SWING.Ranged, TGT = TARGET }
end

function ST.On()
    return SUPPORTED and S.Get("enabled")
end

function ST.Plain(v)
    return not (issecretvalue and issecretvalue(v))
end
