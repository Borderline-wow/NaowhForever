-------------------------------------------------------------------------------
--  View/Style.lua -- what only the BiS List draws (ns.BiS.Style), over the house look
--  (ns.Shared.Style, read through this table).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

ns.BiS.Style = setmetatable({
    -- The window: as large as the Dungeon Journal's, the paperdoll's card where its list is.
    WINDOW_W = 1160,
    WINDOW_H = 800,
    SIDE_W = 380,

    -- The paperdoll: slots down both sides of your model, the weapons underneath.
    SLOT = 44,
    SLOT_GAP = 7,
    MODEL_GAP = 12,
    DOLL_W = 372,
    LOOK_W = 150,           -- the switch over the model: your BiS, or what you wear now
    CAMERA = 0.85,          -- the model's camera, a little closer than the game's
    GAINS_H = 132,          -- what your BiS gets you, under the weapons
    TURN_SPEED = 0.012,     -- radians the model turns per pixel dragged
    ZOOM_STEP = 0.1,
    ZOOM_MAX = 0.7,
    LIST_BUTTON_H = 26,     -- the list you use, as a button over the paperdoll

    -- The list: the summary (how many are yours, the filter, a bar of your slots), then a row
    -- per slot.
    FILTER_W = 380,
    ROW_H = 32,
    ROW_ICON = 22,
    STATUS_W = 8,           -- the list's inset: every text starts this far in, and ends this far
                            -- short of the right edge; bands, rules and the slot bar go edge to edge
    COLUMN_GAP = 10,        -- between a row's columns: name, gain, wand, source
    SLOT_W = 82,            -- the slot's name: "Shoulder" and "Main Hand", the longest, and a gap
    META_W = 230,           -- where it drops, on the right
    TAIL_W = 70,            -- Worn, In Bag, its picks
    PLACE_H = 40,           -- a place to run next: two lines
    PICKER_BOX_W = 286,     -- the item box along the picker's bottom
}, { __index = ns.Shared.Style })
