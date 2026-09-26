-------------------------------------------------------------------------------
--  NaowhForever_CombatLogger.lua -- the QoL combat logger: turns the combat log on in raids
--  and off outside them. The first visit to each raid and difficulty asks, and the answer
--  is remembered.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local logging = false

local function On()
    return S.Get("enabled") and S.Get("combatLogger")
end

-- Created on first write, so the defaults table is never written into.
local function Instances()
    local db = S.DB()
    db.combatLogInstances = db.combatLogInstances or {}
    return db.combatLogInstances
end
ns.CombatLogInstances = Instances

local function SetLogging(on)
    if on == logging then return end
    LoggingCombat(on)
    logging = on
end

StaticPopupDialogs["NAOWHFOREVER_ACL_PROMPT"] = {
    text = "|cff0091edNaowh|r Forever\n\nAdvanced Combat Logging is off. Warcraft Logs needs it "
        .. "for a detailed report. Turn it on now? This reloads your UI.",
    button1 = "Enable & Reload",
    button2 = "Skip",
    OnAccept = function()
        SetCVar("advancedCombatLogging", 1)
        ReloadUI()
    end,
    timeout = 0,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- A client without the setting has nothing to turn on, so it never asks.
local function AdvancedLoggingOn()
    local acl = GetCVar("advancedCombatLogging")
    if acl == nil or acl == "1" then return true end
    StaticPopup_Show("NAOWHFOREVER_ACL_PROMPT")
    return false
end

local function Remember(data, enabled)
    Instances()[data.key] = { enabled = enabled, name = data.name, diffName = data.diffName }
    if enabled then
        if AdvancedLoggingOn() then SetLogging(true) end
    else
        SetLogging(false)
    end
end

StaticPopupDialogs["NAOWHFOREVER_COMBATLOG_PROMPT"] = {
    text = "|cff0091edNaowh|r Forever\n\nEnable combat logging for:\n|cffffa300%s|r\n(%s)\n\n"
        .. "Your choice will be remembered.",
    button1 = "Enable Logging",
    button2 = "Skip",
    OnAccept = function(_, data) Remember(data, true) end,
    OnCancel = function(_, data) Remember(data, false) end,
    timeout = 0,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Check()
    local name, kind, difficulty, diffName, _, _, _, instanceID = GetInstanceInfo()
    if not On() or kind ~= "raid" then
        SetLogging(false)
        return
    end
    local key = instanceID .. ":" .. difficulty
    local saved = Instances()[key]
    if saved and saved.enabled == false then
        SetLogging(false)
    elseif saved then
        if AdvancedLoggingOn() then SetLogging(true) end
    else
        -- Logging starts while the question is up, so the pull it is asked on is not lost.
        if not AdvancedLoggingOn() then return end
        SetLogging(true)
        StaticPopup_Show("NAOWHFOREVER_COMBATLOG_PROMPT", name, diffName,
            { key = key, name = name, diffName = diffName })
    end
end
ns.CombatLogCheck = Check

function ns.CombatLogging()
    return logging
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
events:SetScript("OnEvent", function(_, event, isLogin, isReload)
    if event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) and On() then
        if not AdvancedLoggingOn() then return end
    end
    Check()
end)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "combatLogger" then Check() end
end)
hooksecurefunc(ns, "Apply", Check)
