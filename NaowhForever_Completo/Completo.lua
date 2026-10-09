-- Completo.lua: Completo's settings, its module table (ns.Completo) and its map pins' scale.
local ns = _G.NaowhForever

local F = ns.FEATURES.completo

local MIN_PIN_SCALE = 1.5

local S = ns.UI.ModuleSettings("completo", {
    enabled = F.enabled, hideDone = false, windowAlpha = 1, windowScale = 1,
    mapPins = F.mapPins, mapGrey = false, mapChainsOnly = false, mapPinSize = 18,
    rareHideKilled = false, rareAlert = F.rareAlert, rareMarker = "skull", rareAlertKilled = false,
    rareSound = true, rareSoundKey = "file:gruntlinghorn", rareAlertPosition = nil, rareAlertScale = 1,
    rareAlertTime = 20, rareAlertFont = "", rareAlertFontSize = 13, rareAlertOutline = "",
    rareAlertBackground = "card", rareAlertGlow = false,
    rarePins = F.rarePins, rarePinsKilled = false, rarePinSize = 18,
})
ns.CompletoSettings = S

local Completo = { Settings = S }
ns.Completo = Completo

function Completo.ScalePin(pin)
    local map = pin:GetMap()
    local canvas = map and map.GetCanvasScale and map:GetCanvasScale()
    if not canvas or canvas <= 0 then return end
    local scale = math.max(1, MIN_PIN_SCALE / canvas)
    if map.GetGlobalPinScale and not (pin.IsIgnoringGlobalPinScale and pin:IsIgnoringGlobalPinScale()) then
        scale = scale * map:GetGlobalPinScale()
    end
    pin:SetScale(scale)
    pin:ApplyCurrentPosition()
end

function Completo.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
