-------------------------------------------------------------------------------
--  Played.lua -- the character's /played time (ns.Shared.Played), asked for once with the chat
--  print muted and kept running from the answer. The XP Bar's Played text and XP per Hour's
--  Played row use it; Answered and LeveledUp are hooked to hear the answer and each level up.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local Played = {}
ns.Shared.Played = Played

local MUTE_LIMIT = 5

local events, listening, asking
local total, level, at, knownLevel
local wanted = {}
local mutedChat = {}

local function RestoreChat()
    for i = 1, #mutedChat do mutedChat[i]:RegisterEvent("TIME_PLAYED_MSG") end
    wipe(mutedChat)
    asking = false
end

local function Request()
    if asking then return end
    asking = true
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            mutedChat[#mutedChat + 1] = cf
        end
    end
    RequestTimePlayed()
    C_Timer.After(MUTE_LIMIT, RestoreChat)
end

function Played.Answered(totalTime, levelTime) end

function Played.LeveledUp(newLevel, totalTime) end

local function OnEvent(_, event, arg1, arg2)
    local now = GetTime()
    if event == "TIME_PLAYED_MSG" then
        total, level, at, knownLevel = arg1, arg2, now, UnitLevel("player")
        if asking then C_Timer.After(0, RestoreChat) end
        Played.Answered(total, level)
    elseif event == "PLAYER_LEVEL_UP" then
        if total then total, level, at = total + now - at, 0, now end
        knownLevel = arg1
        Played.LeveledUp(arg1, total)
    end
end

function Played.Want(key)
    wanted[key] = true
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if not listening then
        events:RegisterEvent("TIME_PLAYED_MSG")
        events:RegisterEvent("PLAYER_LEVEL_UP")
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
