-- Style.lua: what only Naowh's Forge draws: its colors, fonts and sizes, on top of the house look (ns.Macros.Style).
local ns = _G.NaowhForever
local Shared = ns.Shared

ns.Macros.Style = setmetatable({
    WARNING_RGB = Shared.Style.WARN_RGB,
    ERROR_RGB = Shared.Style.RED_RGB,
    OK_RGB = Shared.Style.HAVE_RGB,
    CHIP_RGB = { r = 0.95, g = 0.83, b = 0.42 },
    CODE_FONT = ns.MEDIA .. "Fonts\\JetBrainsMonoNL-Regular.ttf",

    PAD = 14,
    LIST_W = 270,
    INSPECTOR_W = 320,
    ROW_ICON = 30,
    ICON_EDGES = 2,
    BUTTON_H = 26,
    BUTTON_GAP = 6,
    ICON_TEXT_GAP = 10,
    MACRO_CARD_PAD = 12,
    SCROLLBAR_ROOM = 12,
    QUESTION_LABEL_W = 170,
    QUESTION_H = 24,
    QUESTION_GAP = 6,

    TAG_SIZE = 10,
    NOTE_SIZE = 12,
    TEXT_SIZE = 13,
    CARD_TITLE_SIZE = 16,
}, { __index = Shared.Style })
