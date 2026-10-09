-- CursorClip.lua: Combat Cursor Clip, the cursor kept inside the game window in combat.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local CVAR = "ClipCursor"
local CLIPPED, NOT_CLIPPED = "1", "0"

local function IsOn()
    return S.Get("enabled") and S.Get("cursorClip")
end

local function Clip()
    local account = ns.AccountSettings()
    if account.clipCursorSaved or not IsOn() then return end
    account.clipCursorSaved = GetCVar(CVAR) or NOT_CLIPPED
    SetCVar(CVAR, CLIPPED)
end

local function Restore()
    local account = ns.AccountSettings()
    if not account.clipCursorSaved then return end
    SetCVar(CVAR, account.clipCursorSaved)
    account.clipCursorSaved = nil
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" or (event == "PLAYER_LOGIN" and InCombatLockdown()) then
        Clip()
    else
        Restore()
    end
end

local function OnSettingChanged(key)
    if key ~= "enabled" and key ~= "cursorClip" then return end
    if InCombatLockdown() then Clip() end
    if not IsOn() then Restore() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", OnSettingChanged)

ns.Shared.Settings.Page("QoL/Cursor", S):Card({
    id = "cursorClip", name = "Cursor in Window", order = 30,
    help = "Keeps the cursor inside the game window while you fight.",
    rows = {
        { key = "cursorClip", label = "Keep Cursor In Window During Combat", toggle = true,
          help = "Stops the cursor leaving the game window while you fight, for a second monitor. "
              .. "Your own setting comes back afterwards." },
    },
})
