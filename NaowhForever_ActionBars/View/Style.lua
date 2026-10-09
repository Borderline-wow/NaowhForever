-- Style.lua: what only the Action Bars window draws: its colors and sizes, on top of the house look (ns.ActionBars.Style).
local ns = _G.NaowhForever
local Shared = ns.Shared

ns.ActionBars.Style = setmetatable({
    NEW_RGB = { r = 0.11, g = 0.37, b = 0.56 },
    LATER_RGB = { r = 0.79, g = 0.64, b = 0.29 },
    ACCOUNT_RGB = { r = 0.17, g = 0.23, b = 0.29 },
    CHARACTER_RGB = { r = 0.23, g = 0.19, b = 0.31 },
    GOOD_RGB = Shared.Style.HAVE_RGB,

    STACK_GAP = 3,
    FILL_W = 10,

    WIDTH = 980,
    HEIGHT = 640,
    CARD = 6,
    SIDE_W = 320,
    INNER = 14,
    ROW_PAD = 10,
    ROW_GAP = 8,
    ROW_FILL = 0.35,
    OUT_ALPHA = 0.22,
    CHIP_H = 13,
    LINE_GAP = 4,
    SWITCH_W = 36,
    SWITCH_H = 18,
    BUTTON_H = 30,
    HEADING_H = 26,

    TINY_SIZE = 9,
    TAG_SIZE = 10,
    NOTE_SIZE = 12,
    NAME_SIZE = 13,
    TITLE_SIZE = 14,
}, { __index = Shared.Style })
