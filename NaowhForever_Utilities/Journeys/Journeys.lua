-- Journeys.lua: the Journeys settings (ns.JourneysSettings), its table (ns.Journeys) and its per-character stores.
local ns = _G.NaowhForever

local F = ns.FEATURES.journeys

local S = ns.UI.ModuleSettings("journeys", {
    enabled = F.enabled,
    card = F.card,
    cardScale = 1,
    cardAlpha = 1,
    hearth = true,
    hearthSaving = 120,
    teleports = true,
    mapRoute = true,
    minimapRoute = true,
    learnLifts = F.learnLifts,
    quests = true,
    mapPins = true,
    stepEnds = true,
})
ns.JourneysSettings = S

local OLD_ADDON = "NaowhForever_Journeys"
local OLD_COPY = C_AddOns.DoesAddOnExist(OLD_ADDON) and C_AddOns.GetAddOnEnableState(OLD_ADDON) > 0

local Jy = { Settings = S, OLD_COPY = OLD_COPY }
ns.Journeys = Jy

function Jy.On()
    return S.Get("enabled") == true and not OLD_COPY
end

function Jy.CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function Jy.CharStore(key)
    local account = ns.AccountSettings()
    if type(account[key]) ~= "table" then account[key] = {} end
    local mine = Jy.CharKey()
    if type(account[key][mine]) ~= "table" then account[key][mine] = {} end
    return account[key][mine]
end
