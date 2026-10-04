-------------------------------------------------------------------------------
--  View/Parts.lua -- the Dungeon Journal's own pieces (ns.Journal.View.Parts), over the
--  components every module shares (ns.Shared.Parts, read through this table): a fight's
--  length, and its side panels at the Journal's opacity.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local Shared = ns.Shared
local View = J.View
local Parts = View.Parts

local function Opacity()
    return J.Settings.Get("windowAlpha") or 1
end

-- "1:32".
---@param seconds number
function Parts.FightLength(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- A side panel (Shared.Parts.SidePanel) drawn with the Journal's view.
---@param actions { [1]: string, [2]: fun() }[]
function Parts.SidePanel(actions)
    return Shared.Parts.SidePanel(actions, View.New, Opacity)
end

J.Settings.OnChange(function(key)
    if key == "windowAlpha" then Shared.Parts.RepaintSidePanels() end
end)
