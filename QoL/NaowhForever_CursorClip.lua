-------------------------------------------------------------------------------
--  NaowhForever_CursorClip.lua -- the QoL combat cursor clip: keeps the cursor inside the
--  game window during combat, then puts the ClipCursor setting back as it was.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

-- The player's own ClipCursor value while we hold it at 1; nil when we are not holding it.
-- Saved, so a crash or a killed client mid-fight is put right at the next login instead of
-- the held 1 being taken for the player's own setting.
local function Clip()
    local account = ns.AccountSettings()
    if account.clipCursorSaved or not (S.Get("enabled") and S.Get("cursorClip")) then return end
    account.clipCursorSaved = GetCVar("ClipCursor") or "0"
    SetCVar("ClipCursor", "1")
end

local function Restore()
    local account = ns.AccountSettings()
    if not account.clipCursorSaved then return end
    SetCVar("ClipCursor", account.clipCursorSaved)
    account.clipCursorSaved = nil
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
