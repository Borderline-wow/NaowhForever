-- Style.lua: the Training Planner's own look, on top of the house look in Shared/Style.lua.
local ns = _G.NaowhForever

ns.Training.Style = setmetatable({
    WARN_RGB = { r = 0.94, g = 0.70, b = 0.29 },
    UP_RGB = { r = 0.30, g = 0.82, b = 0.48 },
    UP_CODE = "|cff4dd17a",
    LOGO_FILE = ns.MEDIA .. "LogoAddon.tga",
    SHADOW_ALPHA = 0.85,
    LEARNED_ALPHA = 0.45,
    DISABLED_ALPHA = 0.45,
    UNPICKED_ALPHA = 0.55,
    ROW_H = 30,
    ROW_ICON = 22,
    SKIP_W = 46,
    SKIP_H = 18,
    SECTION_GAP = 18,
    FONT_SMALL = 11,
    FONT = 12,
    FONT_ROW = 13,
    BAR_W = 440,
    DOT_MAX = 20,
    YOU_GAP = 6,
}, { __index = ns.Shared.Style })
