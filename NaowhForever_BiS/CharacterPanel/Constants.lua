-- Constants.lua: the sizes and look the character panel's files, and the inspect panel's, share (CP.C).
local ns = _G.NaowhForever

local CP = ns.CharacterPanel
local St = ns.Shared.Style

CP.PANE_W = 233
CP.EDGE = 16

CP.C = {
    TITLE_RGB = St.TIP_TITLE_RGB,
    GOLD_RGB = { r = 1, g = 0.82, b = 0 },
    BLACK_RGB = St.BORDER_RGB,
    TAB_RGB = { r = 0.16, g = 0.16, b = 0.17 },
    SHADOW_ALPHA = St.HUD_SHADOW_ALPHA,
    SHADOW_X = St.HUD_SHADOW_X,
    HOVER_ALPHA = 0.5,
    TRACK_GREY = 0.16,
    CROP_IN = St.ICON_CROP,
    CROP_OUT = St.ICON_CROP_HIGH,
    RING_OUT = -1,
    HALF = 0.5,
    FILTER = "TRILINEAR",
    TEXTURE = "Texture",
    SECTION_SIZE = 11,
    TEXT_SIZE = 12,
    SMALL_SIZE = 10,
    EMBLEM = 44,
    BADGE_INSET = 10,
    STAT_ROWS = 16,
}

CP.TAB_RGB = CP.C.TAB_RGB
