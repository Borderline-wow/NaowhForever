-- GeneralSettings.lua: the Quest List's key on its settings page (Discovery/Quest List), declared as a card.
local ns = _G.NaowhForever

local Completo = ns.Completo
local S = Completo.Settings
local Settings = ns.Shared.Settings

local PAGE = "Discovery/Quest List"
local ORDER_KEYS = 30

local page = Settings.Page(PAGE, S)

page:Card({
    id = "keys", name = "Key Binding", order = ORDER_KEYS,
    help = "The key that opens the Quest List window.",
    rows = {
        { label = "Open Quest List", binding = "NAOWHFOREVER_COMPLETO",
          help = "Press it to open or close the Quest List. Shift-L unless something else had it." },
    },
})
