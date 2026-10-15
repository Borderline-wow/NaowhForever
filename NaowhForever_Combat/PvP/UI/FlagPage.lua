-- FlagPage.lua: the PvP Flag card on the PvP/Flag settings page.
local ns = _G.NaowhForever

local S = ns.PvPSettings
local Settings = ns.Shared.Settings

local SIZE_RANGE = { 32, 96, 1 }

if ns.PvP.OLD_COPY then return end

Settings.Page("PvP/Flag", S):Card({
    id = "flagButton", name = "PvP Flag", order = 10, switch = "flagButton",
    help = "A button that flags or unflags you for PvP, showing which you are.",
    rows = {
        { key = "flagButtonSize", label = "Button Size", slider = SIZE_RANGE },
    },
})
