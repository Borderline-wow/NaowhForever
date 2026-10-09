-- Style.lua: what only Discovery draws (Discovery.Style), on top of the house look in Shared/Style.lua.
local ns = _G.NaowhForever

local Discovery = ns.Discovery

Discovery.Style = setmetatable({
    GOLD_RGB = { r = 1, g = 0.82, b = 0 },
    STORED_RGB = { r = 1, g = 0.82, b = 0 },
    MISSING_RGB = { r = 0.97, g = 0.44, b = 0.44 },
    READY_RGB = { r = 0x19 / 255, g = 1, b = 0x19 / 255 },
    QUIET_RGB = { r = 0.61, g = 0.64, b = 0.69 },
    HINT_RGB = { r = 0.3, g = 0.71, b = 0.96 },
    HAND_IN_RGB = { r = 0.3, g = 0.7, b = 0.95 },
    TITLE_SIZE = 13,
    KICKER_SIZE = 10,
    COUNT_SIZE = 22,
    LINE_GAP = 3,
    LEVEL_W = 24,
    TICK_SIZE = 14,
    PIN_RIGHT = 10,
    STATUS_W = 110,
    STATUS_GAP = 10,
    HERO_PAD = 16,
    HERO_TOP = 14,
    COUNT_GAP = 4,
    SECTION_GAP = 8,
    BAR_ALPHA = 0.85,
}, { __index = ns.Shared.Style })
