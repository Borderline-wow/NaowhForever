-- Style.lua: the Gear & Trinkets look, on top of Shared/Style.lua.
local ns = _G.NaowhForever

ns.GearSets.Style = setmetatable({
    ICON_INSET = 1,
    EMPTY_ICON = 134400,
    BLACK = { r = 0, g = 0, b = 0 },
    NAME_RGB = { r = 1, g = 1, b = 1 },
    EQUIPPED_RGB = { r = 0.29, g = 0.87, b = 0.5 },
    MISSING_RGB = { r = 0.97, g = 0.44, b = 0.44 },
    HINT_RGB = { r = 0.6, g = 0.62, b = 0.65 },
}, { __index = ns.Shared and ns.Shared.Style })
