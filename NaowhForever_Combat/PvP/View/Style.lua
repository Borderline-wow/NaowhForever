-- Style.lua: the PvP module's own look, on top of Shared/Style.lua.
local ns = _G.NaowhForever

local P = ns.PvP

P.Style = setmetatable({
    BORDER = 1,
    ICON_GAP = 3,
    ROW_GAP = 4,
    HEADER_PAD = 4,
    TIME_SIZE = 0.34,
    COUNT_SIZE = 0.3,
    TEXT_INSET = 2,
    MIN_TEXT = 8,
    STAGE_MARGIN = 14,
    OUTLINE = "OUTLINE",
    BLACK = { r = 0, g = 0, b = 0 },
    ABSORB_TEXT = "|TInterface\\Icons\\Spell_Holy_PowerWordShield:0:0:0:0:64:64:5:59:5:59|t %d",
    ABSORB_SIZE = 0.42,
    ABSORB_PAD = 4,
    ABSORB_RGB = { r = 0.55, g = 0.82, b = 1 },
    NAME_SIZE = 0.42,
    NAME_RGB = { r = 1, g = 1, b = 1 },
    BLINK = 0.5,
    WHITE_RGBA = { 1, 1, 1, 1 },
    YELLOW_RGBA = { 1, 0.82, 0, 1 },
    RED_RGBA = { 1, 0.2, 0.2, 1 },
    FAINT_RGBA = { 1, 0.2, 0.2, 0.3 },
}, { __index = ns.Shared.Style })
P.Style.NAME_GAP = P.Style.ICON_GAP * 2
