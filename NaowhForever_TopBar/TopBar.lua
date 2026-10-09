-- TopBar.lua: the Top Bar's settings and the module table (ns.TopBar).
local ns = _G.NaowhForever

local F = ns.FEATURES.topBar

local S = ns.UI.ModuleSettings("topBar", {
    enabled = F.enabled,
    showClock = F.showClock,
    iconSize = 22, clockSize = 27, clockFont = "Gotham Narrow Ultra", clockOutline = "NONE", use24h = false,
    font = "", outline = "OUTLINE",
    bgAlpha = 85, iconColor = { r = 1, g = 1, b = 1 },
    hideInCombat = false, mouseover = false, mouseoverAlpha = 0,
    showSystem = F.showSystem, systemTooltip = true, sysSize = 13, tooltipScale = 120,
    layout = { left = { "ldb:NaowhForeverJournal", "ldb:NaowhForeverDiscovery" },
        right = { "ldb:NaowhForeverBiS", "ldb:NaowhForeverTraining" } },
})
ns.TopBarSettings = S

local TB = { Settings = S }
ns.TopBar = TB

function TB.On()
    return S.Get("enabled")
end

function TB.LDB()
    return LibStub("LibDataBroker-1.1", true)
end
