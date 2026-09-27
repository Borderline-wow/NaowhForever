-------------------------------------------------------------------------------
--  NaowhForever_CursorClip.lua -- the QoL combat cursor clip: keeps the cursor inside the
--  game window during combat, then puts the ClipCursor setting back as it was.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- The player's own ClipCursor value while we hold it at 1; nil when we are not holding it.
local saved

local function Clip()
    if saved or not (S.Get("enabled") and S.Get("cursorClip")) then return end
    saved = GetCVar("ClipCursor") or "0"
    SetCVar("ClipCursor", "1")
end

local function Restore()
    if not saved then return end
    SetCVar("ClipCursor", saved)
    saved = nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or (event == "PLAYER_LOGIN" and InCombatLockdown()) then
        Clip()
    else
        Restore()
    end
end)

hooksecurefunc(S, "Set", function(key)
    if key ~= "enabled" and key ~= "cursorClip" then return end
    if InCombatLockdown() then Clip() end
    if not (S.Get("enabled") and S.Get("cursorClip")) then Restore() end
end)
