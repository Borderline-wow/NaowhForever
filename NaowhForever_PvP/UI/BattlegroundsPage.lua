-- BattlegroundsPage.lua: the Battleground Displays card on the PvP/Battlegrounds settings page.
local ns = _G.NaowhForever

local S = ns.PvPSettings
local Settings = ns.Shared.Settings

local function Reset()
    S.Set("scoresPos", false)
    S.Set("timerPos", false)
end

Settings.Page("PvP/Battlegrounds", S):Card({
    id = "displays", name = "Battleground Displays", order = 10,
    help = "Move the battleground scores and the start countdown in the HUD Editor, under PvP.",
    rows = {
        { key = "scoresPos", label = "Reset Positions", buttonText = "Reset", button = Reset,
          help = "Puts both back where the game shows them." },
    },
})
