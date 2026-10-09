-- CombatLogger.lua: Auto Combat Logging, the combat log on in raids and dungeons and off when you leave.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local Group = ns.Shared.Settings.Group

local WHERE = { { ask = "Ask Once", always = "Always", never = "Never" }, { "ask", "always", "never" } }
local KIND_KEYS = { raid = "combatLogRaids", party = "combatLogDungeons" }
local RECHECK = { enabled = true, combatLogger = true, combatLogRaids = true, combatLogDungeons = true,
    combatLogStopOnLeave = true, combatLogAclPrompt = true }
local POPUP_INDEX = 3
local ACL_CVAR = "advancedCombatLogging"
local KEY_JOIN = ":"
local TEXT_STARTED, TEXT_STOPPED = "Combat logging started.", "Combat logging stopped."
local TEXT_RELOAD = "Advanced combat logging starts after a reload. Reload UI now?"
local TEXT_FORGET = "Forget every saved answer? Each raid and dungeon set to Ask Once asks again the next time "
    .. "you enter it."
local TEXT_NONE, TEXT_ONE, TEXT_MANY = "nothing answered yet", "1 answer saved", " answers saved"
local TEXT_LOGGING, TEXT_NOT_LOGGING = "Logging now", "Not logging"
local SUMMARY = "%s. Raids: %s, dungeons: %s, %s"

local logging = false

local function On()
    return S.Get("enabled") and S.Get("combatLogger")
end

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
    if S.Get("combatLogChat") then
        ns.Print(on and TEXT_STARTED or TEXT_STOPPED)
    end
end

local function Mode(kind)
    local key = KIND_KEYS[kind]
    if not key then return nil end
    local mode = S.Get(key)
    return WHERE[1][mode] and mode or "never"
end

local function AclText()
    return ns.Color("accent", "Naowh") .. " Forever\n\nAdvanced Combat Logging is off. Warcraft Logs needs it "
        .. "for a detailed report. Turn it on now? This reloads your UI."
end

local function LogText()
    return ns.Color("accent", "Naowh") .. " Forever\n\nEnable combat logging for:\n|cffffa300%s|r\n(%s)\n\n"
        .. "Your choice will be remembered."
end

local function OnAclAccept()
    SetCVar(ACL_CVAR, 1)
    ns.ConfirmReload(TEXT_RELOAD)
end

StaticPopupDialogs["NAOWHFOREVER_ACL_PROMPT"] = {
    button1 = "Enable",
    button2 = "Skip",
    OnAccept = OnAclAccept,
    timeout = 0,
    hideOnEscape = true,
    preferredIndex = POPUP_INDEX,
}

local function AdvancedLoggingOn()
    local acl = GetCVar(ACL_CVAR)
    if acl == nil or acl == "1" or not S.Get("combatLogAclPrompt") then return true end
    StaticPopupDialogs["NAOWHFOREVER_ACL_PROMPT"].text = AclText()
    StaticPopup_Show("NAOWHFOREVER_ACL_PROMPT")
    return false
end

local function StartIfAllowed()
    if AdvancedLoggingOn() then SetLogging(true) end
end

local function Remember(data, enabled)
    Instances()[data.key] = { enabled = enabled, name = data.name, diffName = data.diffName }
    if enabled then
        StartIfAllowed()
    else
        SetLogging(false)
    end
end

StaticPopupDialogs["NAOWHFOREVER_COMBATLOG_PROMPT"] = {
    button1 = "Enable Logging",
    button2 = "Skip",
    OnAccept = function(_, data) Remember(data, true) end,
    OnCancel = function(_, data) Remember(data, false) end,
    timeout = 0,
    hideOnEscape = true,
    preferredIndex = POPUP_INDEX,
}

local function Ask(key, name, diffName)
    if not AdvancedLoggingOn() then return end
    SetLogging(true)
    StaticPopupDialogs["NAOWHFOREVER_COMBATLOG_PROMPT"].text = LogText()
    StaticPopup_Show("NAOWHFOREVER_COMBATLOG_PROMPT", name, diffName, { key = key, name = name, diffName = diffName })
end

local function AskOnce(instanceID, difficulty, name, diffName)
    local key = instanceID .. KEY_JOIN .. difficulty
    local saved = Instances()[key]
    if saved and saved.enabled == false then
        SetLogging(false)
    elseif saved then
        StartIfAllowed()
    else
        Ask(key, name, diffName)
    end
end

local function Check()
    if not On() then
        SetLogging(false)
        return
    end
    local name, kind, difficulty, diffName, _, _, _, instanceID = GetInstanceInfo()
    local mode = Mode(kind)
    if not mode then
        if S.Get("combatLogStopOnLeave") then SetLogging(false) end
        return
    end
    if mode == "never" then
        SetLogging(false)
        return
    end
    if mode == "always" then
        StartIfAllowed()
        return
    end
    AskOnce(instanceID, difficulty, name, diffName)
end
ns.CombatLogCheck = Check

function ns.CombatLogging()
    return logging
end

local function OnEvent(_, event, isLogin, isReload)
    if event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) and On() then
        if not AdvancedLoggingOn() then return end
    end
    Check()
end

local function OnSettingChanged(key)
    if RECHECK[key] then Check() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", Check)

local function Answered()
    local saved, n = S.Get("combatLogInstances"), 0
    if type(saved) == "table" then
        for _ in pairs(saved) do n = n + 1 end
    end
    return n
end

local function AnyAnswered()
    return Answered() > 0
end

local function Forget()
    S.Set("combatLogInstances", nil)
end

local function ForgetAll()
    ns.Confirm(TEXT_FORGET, Forget)
end

local function Summary()
    local n = Answered()
    local answered = n == 0 and TEXT_NONE or n == 1 and TEXT_ONE or (n .. TEXT_MANY)
    return SUMMARY:format(logging and TEXT_LOGGING or TEXT_NOT_LOGGING, WHERE[1][Mode("raid")]:lower(),
        WHERE[1][Mode("party")]:lower(), answered)
end

ns.Shared.Settings.Page("QoL/System", S):Card({
    id = "combatLogger", name = "Auto Combat Logging", order = 30, switch = "combatLogger",
    help = "Turns the combat log on in raids and dungeons and off when you leave. Set to Ask Once, it asks "
        .. "the first time you enter each one and difficulty, and remembers your answer.",
    summary = Summary,
    rows = {
        Group("Where"),
        { key = "combatLogRaids", label = "Log in Raids", choice = WHERE,
          help = "Always logs every raid, Never logs none, and Ask Once asks the first time you enter each "
              .. "raid and difficulty." },
        { key = "combatLogDungeons", label = "Log in Dungeons", choice = WHERE,
          help = "Always logs every dungeon, Never logs none, and Ask Once asks the first time you enter "
              .. "each dungeon and difficulty." },
        { key = "combatLogStopOnLeave", label = "Stop When You Leave", toggle = true,
          help = "Turns the log off when you leave the raid or dungeon. Off keeps it running outside, for "
              .. "world bosses, until you enter a place set to Never or skipped." },
        Group("Notices"),
        { key = "combatLogChat", label = "Chat Message", toggle = true,
          help = "Says in chat when the combat log starts and when it stops." },
        { key = "combatLogAclPrompt", label = "Ask for Advanced Logging", toggle = true,
          help = "Offers to turn on Advanced Combat Logging, which Warcraft Logs needs, while it is off. "
              .. "Off logs without asking, and the report has less detail." },
        Group("Answers"),
        { label = "Forget All Answers", buttonText = "Forget All", button = ForgetAll, needs = AnyAnswered,
          why = "Nothing answered yet",
          help = "Forgets your answer for every raid, dungeon and difficulty, so each one asks again the "
              .. "next time you enter it." },
    },
})
