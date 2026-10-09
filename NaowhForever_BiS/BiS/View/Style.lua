-- Style.lua: what only the BiS List draws (B.Style), over the house look.
local ns = _G.NaowhForever

ns.BiS.Style = setmetatable({
    STAR_GAP = 4,
    WINDOW_W = 1160,
    WINDOW_H = 800,
    SIDE_W = 380,

    SLOT = 44,
    SLOT_GAP = 7,
    MODEL_GAP = 12,
    DOLL_W = 372,
    LOOK_W = 150,
    CAMERA = 0.85,
    GAINS_H = 132,
    TURN_SPEED = 0.012,
    ZOOM_STEP = 0.1,
    ZOOM_MAX = 0.7,
    LIST_BUTTON_H = 26,
    CROP_IN = 0.08,
    CROP_OUT = 0.92,

    FILTER_W = 380,
    ROW_H = 32,
    ROW_ICON = 22,
    STATUS_W = 8,
    COLUMN_GAP = 10,
    SLOT_W = 82,
    META_W = 230,
    TAIL_W = 70,
    PLACE_H = 40,
    PICKER_BOX_W = 286,
    NAME_GAP = 8,
    ACTION_GAP = 6,
    CURSOR_TIP_X = 16,
    LIT = 0.12,
    CARD_ALPHA = 0.95,
    TOAST_W = 300,

    TINY_SIZE = 10,
    NAME_SIZE = 13,
    COUNT_SIZE = 20,

    GOLD_RGB = { r = 1, g = 0.82, b = 0 },
    GAIN_BIG_RGB = { r = 0x1e / 255, g = 1, b = 0 },
    GAIN_RGB = { r = 0.47, g = 0.86, b = 0.45 },
    GAIN_SMALL_RGB = { r = 0.42, g = 0.62, b = 0.45 },
}, { __index = ns.Shared.Style })
