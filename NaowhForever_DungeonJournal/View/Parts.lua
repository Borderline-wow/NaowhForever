-- Parts.lua: the Dungeon Journal's own small parts: a fight's length, a row's band to its card's edges, its side panels (J.View.Parts).
local ns = _G.NaowhForever

local J = ns.Journal
local Shared = ns.Shared
local View = J.View
local Parts = View.Parts

local CARD_PAD = J.Style.CARD_PAD

local SECONDS_PER_MINUTE = J.C.SECONDS_PER_MINUTE
local EDGE_INSET = 1
local FIGHT_LENGTH = "%d:%02d"

local function Opacity()
    return J.Settings.Get("windowAlpha") or 1
end

local function OnSettingChanged(key)
    if key == "windowAlpha" then Shared.Parts.RepaintSidePanels() end
end

function Parts.FightLength(seconds)
    return FIGHT_LENGTH:format(math.floor(seconds / SECONDS_PER_MINUTE), seconds % SECONDS_PER_MINUTE)
end

function Parts.CardBand(row, alpha)
    local band = ns.Solid(row, "BACKGROUND", ns.THEME.fg, alpha)
    band:SetPoint("TOPLEFT", -CARD_PAD + EDGE_INSET, 0)
    band:SetPoint("BOTTOMRIGHT", CARD_PAD - EDGE_INSET, 0)
    return band
end

function Parts.SidePanel(actions)
    return Shared.Parts.SidePanel(actions, View.New, Opacity)
end

J.Settings.OnChange(OnSettingChanged)
