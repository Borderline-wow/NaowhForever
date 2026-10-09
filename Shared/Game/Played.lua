-- Played.lua: the character's /played time, asked for once with the chat print muted and kept running (ns.Shared.Played).
local ns = _G.NaowhForever

local MUTE_LIMIT = 5
local FALLBACK_CHAT_WINDOWS = 10
local CHAT_FRAME = "ChatFrame"
local TIME_PLAYED = "TIME_PLAYED_MSG"
local LEVEL_UP = "PLAYER_LEVEL_UP"

local events, listening, asking
local total, level, at, knownLevel
local wanted = {}
local mutedChat = {}

local Played = {}
ns.Shared.Played = Played

local function RestoreChat()
    for i = 1, #mutedChat do mutedChat[i]:RegisterEvent(TIME_PLAYED) end
    wipe(mutedChat)
    asking = false
end

local function Request()
    if asking then return end
    asking = true
    for i = 1, NUM_CHAT_WINDOWS or FALLBACK_CHAT_WINDOWS do
        local cf = _G[CHAT_FRAME .. i]
        if cf and cf:IsEventRegistered(TIME_PLAYED) then
            cf:UnregisterEvent(TIME_PLAYED)
            mutedChat[#mutedChat + 1] = cf
        end
    end
    RequestTimePlayed()
    C_Timer.After(MUTE_LIMIT, RestoreChat)
end

local function OnTimePlayed(now, totalTime, levelTime)
    total, level, at, knownLevel = totalTime, levelTime, now, UnitLevel("player")
    if asking then C_Timer.After(0, RestoreChat) end
    Played.Answered(total, level)
end

local function OnLevelUp(now, newLevel)
    if total then total, level, at = total + now - at, 0, now end
    knownLevel = newLevel
    Played.LeveledUp(newLevel, total)
end

local function OnEvent(_, event, arg1, arg2)
    local now = GetTime()
    if event == TIME_PLAYED then
        OnTimePlayed(now, arg1, arg2)
    elseif event == LEVEL_UP then
        OnLevelUp(now, arg1)
    end
end

function Played.Answered(totalTime, levelTime) end

function Played.LeveledUp(newLevel, totalTime) end

function Played.Want(key)
    wanted[key] = true
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if not listening then
        events:RegisterEvent(TIME_PLAYED)
        events:RegisterEvent(LEVEL_UP)
        listening = true
    end
    if not total or knownLevel ~= UnitLevel("player") then Request() end
end

function Played.Drop(key)
    wanted[key] = nil
    if listening and not next(wanted) then
        events:UnregisterAllEvents()
        listening = false
    end
end

function Played.Total()
    return total and total + GetTime() - at
end

function Played.Level()
    return total and level + GetTime() - at
end
