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
--  asked once. A "took over" that EllesmereUI's own switch does not bear out (copied in with a
--  profile, or EllesmereUI's turned back on since) is forgotten at login with its question, so
--  the player is asked as on a first run. CP.Rival is that rule for any of the game's windows
--  both style: the Naowh Inspect Panel (InspectPanel/) uses it for the inspect window.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local CP = {}
ns.CharacterPanel = CP

-- The stats' pane: the game's right pane (its CharacterFrame.xml, RightPaneHost), and the one
-- edge in from its sides that your score, the stats and the switch under them all keep.
CP.PANE_W = 233
CP.EDGE = 16

-- EllesmereUI's window switched to suit ours: off when ours goes on, back on when ours goes off
-- if it was ours that turned it off. A reload swaps EllesmereUI's look.
local ASK_DELAY = 2
local RELOAD_OFF = "EllesmereUI's %s is off, so Naowh's can take over. Reload now to switch?"
local RELOAD_ON = "EllesmereUI's %s is back on. Reload now to switch?"
local ASK = "EllesmereUI's %s is on. Naowh's is recommended, as it comes with more features. "
    .. "Use Naowh's instead?"
local TAKEN = "Naowh's %s takes over from EllesmereUI's after your next reload."

local rivals = {}

--- One of the game's windows EllesmereUI styles too: r.key our switch (r.key .. "TookOver" and
--- r.key .. "Asked" beside it), r.winKey EllesmereUI's name for the window (its public getter's),
--- r.dbKey its own switch in EllesmereUIDB, r.name the window in a player's words.
---@return table rival .Styled() EllesmereUI styles it, .On() ours is on and not standing down
function CP.Rival(r)
    local rival = {}
    local tookOver, asked = r.key .. "TookOver", r.key .. "Asked"

    function rival.Styled()
        local E = _G.EllesmereUI
        return E ~= nil and E.GetBlizzWindowStyle ~= nil and E.GetBlizzWindowStyle(r.winKey) ~= "off"
    end

    function rival.On()
        return S.Get("enabled") == true and S.Get(r.key) == true and not rival.Styled()
    end

    local function Swap(on)
        local db = _G.EllesmereUIDB
        if type(db) ~= "table" or not (_G.EllesmereUI and _G.EllesmereUI.GetBlizzWindowStyle) then return end
        if on and db[r.dbKey] ~= false then
            db[r.dbKey] = false
            S.Set(tookOver, true)
            ns.ConfirmReload(RELOAD_OFF:format(r.name))
        elseif not on and S.Get(tookOver) then
            S.Set(tookOver, false)
            if db[r.dbKey] == false then
                db[r.dbKey] = true
                ns.ConfirmReload(RELOAD_ON:format(r.name))
            end
        end
    end

    S.OnChange(function(key, value)
        if key == r.key then Swap(value == true) end
    end)

    local function UseOurs()
        S.Set(asked, true)
        S.Set(r.key, true)
    end

    local function KeepTheirs()
        S.Set(asked, true)
        S.Set(r.key, false)
    end

    function rival.Repair()
        local db = _G.EllesmereUIDB
        if type(db) ~= "table" or not S.Get(tookOver) or db[r.dbKey] == false then return end
        S.Set(tookOver, false)
        S.Set(asked, false)
    end

    function rival.Due()
        if S.Get(asked) or not (S.Get("enabled") and S.Get(r.key) and rival.Styled()) then return false end
        return type(_G.EllesmereUIDB) == "table"
    end

    function rival.Ask()
        ns.Confirm(ASK:format(r.name), UseOurs, KeepTheirs, "Use Naowh's", "Keep EllesmereUI's")
    end

    function rival.TakeOver()
        S.Set(asked, true)
        _G.EllesmereUIDB[r.dbKey] = false
        S.Set(tookOver, true)
        ns.Print(TAKEN:format(r.name))
    end

    rivals[#rivals + 1] = rival
    return rival
end

local sheet = CP.Rival({ key = "characterPanel", winKey = "charsheet", dbKey = "themedCharacterSheet",
    name = "character panel" })

--- EllesmereUI styles the character panel: its Character Sheet style is anything but Blizz
--- Default (its own public getter; nil when its window skins are not loaded).
CP.EllesmereSheet = sheet.Styled
CP.On = sheet.On

-- A newcomer gets every window of ours, told in chat; anyone else one question a login at most,
-- the character panel's first: a second confirm would close the first.
local newcomer

local function AskOnce()
    for _, rival in ipairs(rivals) do rival.Repair() end
    if InCombatLockdown() then return end
    for _, rival in ipairs(rivals) do
        if rival.Due() then
            if not newcomer then return rival.Ask() end
            rival.TakeOver()
        end
    end
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
