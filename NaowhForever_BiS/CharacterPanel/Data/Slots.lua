-- Slots.lua: the game's equipment slots by inventory slot ID, named as its slot buttons are (CP.SLOTS).
local ns = _G.NaowhForever

local CP = ns.CharacterPanel

CP.SLOTS = {
    [0] = "Ammo", [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger0", [12] = "Finger1",
    [13] = "Trinket0", [14] = "Trinket1", [15] = "Back", [16] = "MainHand", [17] = "SecondaryHand",
    [18] = "Ranged", [19] = "Tabard",
}
