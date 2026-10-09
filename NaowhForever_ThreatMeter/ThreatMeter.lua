-- ThreatMeter.lua: the Threat Meter's settings (ns.ThreatMeterSettings), their migrations and its table (ns.ThreatMeter).
local ns = _G.NaowhForever

local F = ns.FEATURES.threatMeter
local St = ns.Shared.Style

local OLD_TEXTURES = { smooth = "", flat = "Solid" }

local function Copy(c) return { r = c.r, g = c.g, b = c.b } end

local S = ns.UI.ModuleSettings("threatMeter", {
    enabled = F.enabled,
    width = 301, height = 206, barHeight = 22, maxBars = 40,
    source = "target", focusEnabled = F.focusEnabled, visibility = "threat",
    locked = false, barSpacing = 3, fontSize = 11, font = "", outline = "OUTLINE",
    showIcons = true, showRanks = true, highlightPlayer = true,
    backgroundAlpha = 0.94, backgroundColor = false, barAlpha = 0.72, texture = "", percentMode = "pull",
    growUp = false, showHeader = true, ignorePets = false, statusPos = "top",
    showValue = true, showPercent = true,
    playerColorOn = false, playerColor = Copy(St.RED_RGB),
    tankColorOn = false, tankColor = Copy(St.HAVE_RGB),
    pullBar = true, pullColor = Copy(St.WARN_RGB),
    themeColors = false,
    warnSound = F.warnSound, warnSoundKey = "none", warnAt = 80, warnSkipTank = true,
    threatPos = { point = "BOTTOM", relPoint = "BOTTOM", x = 393, y = 0 },
})
ns.ThreatMeterSettings = S

local function MigrateVisibility()
    local db = S.DB()
    if db.visibilityMerged then return end
    db.visibilityMerged = true
    local hideEmpty = db.onlyWithThreat
    if hideEmpty == nil then hideEmpty = true end
    db.onlyWithThreat = nil
    local v = db.visibility
    if hideEmpty and (v == nil or v == "always" or v == "combat") then
        db.visibility = "threat"
    elseif db.visibility == nil then
        db.visibility = "always"
    end
end

local function MigrateTexture()
    local db = S.DB()
    local name = OLD_TEXTURES[db.texture]
    if name then db.texture = name ~= "" and name or nil end
end

local TM = { Settings = S }
ns.ThreatMeter = TM

function TM.On()
    return S.Get("enabled")
end

function TM.Migrate()
    MigrateVisibility()
    MigrateTexture()
end
