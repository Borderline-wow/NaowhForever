-------------------------------------------------------------------------------
--  Panel.lua -- the Naowh character panel (ns.CharacterPanel): the game's character panel in
--  the BiS List's look. Blizzard keeps the panel and all it does (its slots' clicks, drags and
--  tooltips, its tabs, its stats); Naowh fades its art (SetAlpha, never Hide) and lays its own
--  frames over it, from post-hooks only. Off by default, and nothing is hooked until it is
--  first turned on.
--
--  EllesmereUI styles the same panel, and the two are never on at once. Turning Naowh's on turns
--  EllesmereUI's Character Sheet off (its own switch, EllesmereUIDB.themedCharacterSheet, as its
--  options set it), and turning Naowh's off turns it back on, if it was Naowh's that turned it
--  off; either way after a reload, which EllesmereUI needs to swap its look. Should EllesmereUI's
--  come back on by other means, Naowh's stands down. With both on, a player new to Naowh Forever
--  (the welcome not seen yet) gets Naowh's from the next reload, told in chat; anyone else is
--  asked once.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local CP = {}
ns.CharacterPanel = CP

-- The stats' pane: the game's right pane (its CharacterFrame.xml, RightPaneHost), and the one
-- edge in from its sides that your score, the stats and the switch under them all keep.
CP.PANE_W = 233
CP.EDGE = 16

--- EllesmereUI styles the character panel: its Character Sheet style is anything but Blizz
--- Default (its own public getter; nil when its window skins are not loaded).
function CP.EllesmereSheet()
    local E = _G.EllesmereUI
    return E ~= nil and E.GetBlizzWindowStyle ~= nil and E.GetBlizzWindowStyle("charsheet") ~= "off"
end

function CP.On()
    return S.Get("enabled") == true and S.Get("characterPanel") == true and not CP.EllesmereSheet()
end

-- EllesmereUI's character sheet switched to suit ours: off when ours goes on, back on when ours
-- goes off if it was ours that turned it off. A reload swaps EllesmereUI's look.
local ASK_DELAY = 2
local RELOAD_OFF = "EllesmereUI's character panel is off, so Naowh's can take over. Reload now to switch?"
local RELOAD_ON = "EllesmereUI's character panel is back on. Reload now to switch?"

local function SwapEllesmere(on)
    local db = _G.EllesmereUIDB
    if type(db) ~= "table" or not (_G.EllesmereUI and _G.EllesmereUI.GetBlizzWindowStyle) then return end
    if on and db.themedCharacterSheet ~= false then
        db.themedCharacterSheet = false
        S.Set("characterPanelTookOver", true)
        ns.ConfirmReload(RELOAD_OFF)
    elseif not on and S.Get("characterPanelTookOver") then
        db.themedCharacterSheet = true
        S.Set("characterPanelTookOver", false)
        ns.ConfirmReload(RELOAD_ON)
    end
end

S.OnChange(function(key, value)
    if key == "characterPanel" then SwapEllesmere(value == true) end
end)

local ASK = "EllesmereUI's character panel is on. Naowh's is recommended, as it comes with more features. "
    .. "Use Naowh's instead?"

local function UseOurs()
    S.Set("characterPanelAsked", true)
    S.Set("characterPanel", true)
end

local function KeepTheirs()
    S.Set("characterPanelAsked", true)
    S.Set("characterPanel", false)
end

local TAKEN = "Naowh's character panel takes over from EllesmereUI's after your next reload."
local newcomer

local function TakeOver()
    S.Set("characterPanelAsked", true)
    _G.EllesmereUIDB.themedCharacterSheet = false
    S.Set("characterPanelTookOver", true)
    ns.Print(TAKEN)
end

local function AskOnce()
    if InCombatLockdown() or S.Get("characterPanelAsked") then return end
    if not (S.Get("enabled") and S.Get("characterPanel") and CP.EllesmereSheet()) then return end
    if type(_G.EllesmereUIDB) ~= "table" then return end
    if newcomer then return TakeOver() end
    ns.Confirm(ASK, UseOurs, KeepTheirs, "Use Naowh's", "Keep EllesmereUI's")
end

local asker = CreateFrame("Frame")
asker:RegisterEvent("PLAYER_ENTERING_WORLD")
asker:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    newcomer = not ns.AccountSettings().welcomeSeen
    C_Timer.After(ASK_DELAY, AskOnce)
end)

function CP._AskForTest(isNew)
    newcomer = isNew
    AskOnce()
end
