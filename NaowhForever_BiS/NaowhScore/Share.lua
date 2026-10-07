-------------------------------------------------------------------------------
--  Share.lua -- your Naowh Score, sent to your group and your guild as it changes, so every
--  player running Naowh Forever has it at once, at any distance, without inspecting you; and
--  theirs, kept for your tooltips (Inspect.lua). Always on: running Naowh Forever means sharing
--  your score. Its cost is a handful of events and a short message when your gear changes.
--
--  Sent: "S <your GUID> <score in tenths> <your level>" when the score shown would change (a gear swap's
--  burst sends once, SEND_DELAY after it), on joining a group, and in answer to a request; a
--  request ("R") goes to your group when you join it and to your guild once a session, and
--  each answer waits a moment at random so a raid's or a guild's do not all come at once.
--  Nothing goes out in combat: it waits for combat's end. A score is kept only from the player its
--  GUID names, found in your group or guild (ns.SenderIs).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Score = ns.NaowhScore

local PREFIX = "NaowhScore"
local SEND_DELAY = 1          -- seconds after a gear change: a set swap's burst sends once
local ANSWER_SPREAD = 30      -- an answer to a request waits up to this many tenths of a second
local GUILD_ANSWER_GAP = 30   -- seconds: the guild is answered at most this often
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }
local MAX_LEVEL = 1000

local own                     -- your GUID
local lastSent                -- the score last sent, in tenths
local inGroup = false
local guildAsked = false
local lastGuildAnswer = -GUILD_ANSWER_GAP
local held = false            -- something to send once combat ends
local sendQueued = false
local answerQueued = {}       -- channel -> an answer is waiting to go

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Your score in tenths, once every item you wear has loaded.
local function Tenths()
    local score, complete = Score.Unit("player")
    if not complete then return nil end
    return math.floor(score * 10 + 0.5)
end

local function Message(tenths)
    return ("S %s %d %d"):format(own, tenths, UnitLevel("player"))
end

-- Sends your score to channel (or your group and guild): forced, or only if it changed.
local function Send(channel, force)
    if InCombatLockdown() then
        held = true
        return
    end
    local tenths = Tenths()
    if not tenths or not own then return end
    if not force and tenths == lastSent then return end
    lastSent = tenths
    local message = Message(tenths)
    if channel then
        C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
        return
    end
    local group = GroupChannel()
    if group then C_ChatInfo.SendAddonMessage(PREFIX, message, group) end
    if IsInGuild() then C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD") end
end

local function SendChanged()
    sendQueued = false
    Send()
end

local function SendSoon()
    if sendQueued then return end
    sendQueued = true
    C_Timer.After(SEND_DELAY, SendChanged)
end

local answers = {}   -- channel -> the function that answers it, made once each

local function Answer(channel)
    local fn = answers[channel]
    if not fn then
        fn = function()
            answerQueued[channel] = nil
            Send(channel, true)
        end
        answers[channel] = fn
    end
    return fn
end

local function AnswerSoon(channel)
    if answerQueued[channel] then return end
    if channel == "GUILD" then
        if GetTime() - lastGuildAnswer < GUILD_ANSWER_GAP then return end
        lastGuildAnswer = GetTime()
    end
    answerQueued[channel] = true
    C_Timer.After(math.random(1, ANSWER_SPREAD) / 10, Answer(channel))
end

local function Ask(channel)
    if InCombatLockdown() then
        held = true
        return
    end
    C_ChatInfo.SendAddonMessage(PREFIX, "R", channel)
end

-- Joining a group: ask for theirs and give yours. Once a session, the guild too.
local function Joined()
    local group = GroupChannel()
    local now = group ~= nil
    if now and not inGroup then
        Ask(group)
        Send(group, true)
    end
    inGroup = now
    if not guildAsked and IsInGuild() then
        guildAsked = true
        Ask("GUILD")
        Send("GUILD", true)
    end
end

local function Received(message, channel, sender)
    if message == "R" then return AnswerSoon(channel) end
    local guid, tenths, level = message:match("^S (Player%-%d+%-%x+) (%d+) ?(%d*)$")
    tenths, level = tonumber(tenths), tonumber(level)
    if not guid or guid == own or not tenths or tenths > 9999 then return end
    if not ns.SenderIs(sender, channel, guid) then return end
    if level and level > MAX_LEVEL then level = nil end
    if Score.Remember then Score.Remember(guid, tenths / 10, true, true, level) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if issecretvalue(prefix) or issecretvalue(message) or issecretvalue(channel) or issecretvalue(sender) then
            return
        end
        if prefix ~= PREFIX or not CHANNELS[channel] then return end
        Received(message, channel, sender)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        SendSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not held then return end
        held = false
        Joined()
        Send(nil, true)
    else   -- PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE
        own = own or UnitGUID("player")
        Joined()
        if event == "PLAYER_ENTERING_WORLD" then SendSoon() end
    end
end)

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
for _, event in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(event)
end
