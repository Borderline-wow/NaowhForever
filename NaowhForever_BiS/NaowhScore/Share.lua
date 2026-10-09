-- Share.lua: your Naowh Score sent to your group and guild as it changes, and theirs kept.
local ns = _G.NaowhForever

local Score = ns.NaowhScore
local S = ns.QoLSettings

local PREFIX = "NaowhScore"
local SEND_DELAY = 1
local ANSWER_SPREAD = 30
local GUILD_ANSWER_GAP = 30
local TENTHS = 10
local MAX_TENTHS = 9999
local ROUND = 0.5
local MAX_LEVEL = 1000
local REQUEST = "R"
local SCORE_FORMAT = "S %s %d %d"
local SCORE_PATTERN = "^S (Player%-%d+%-%x+) (%d+) ?(%d*)$"
local GUILD = "GUILD"
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }
local EVENTS = { "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_REGEN_ENABLED" }

local own
local lastSent
local inGroup = false
local guildAsked = false
local lastGuildAnswer = -GUILD_ANSWER_GAP
local held = false
local sendQueued = false
local answerQueued = {}
local answers = {}
local events = CreateFrame("Frame")

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Sharing()
    return S.Get("enabled") == true and S.Get("naowhScore") == true and S.Get("naowhScoreShare") == true
end

local function Tenths()
    local score, complete = Score.Unit("player")
    if not complete then return nil end
    return math.floor(score * TENTHS + ROUND)
end

local function Message(tenths)
    return SCORE_FORMAT:format(own, tenths, UnitLevel("player"))
end

local function SendAll(message)
    local group = GroupChannel()
    if group then C_ChatInfo.SendAddonMessage(PREFIX, message, group) end
    if IsInGuild() then C_ChatInfo.SendAddonMessage(PREFIX, message, GUILD) end
end

local function Send(channel, force)
    if not Sharing() then return end
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
    SendAll(message)
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
    if answerQueued[channel] or not Sharing() then return end
    if channel == GUILD then
        if GetTime() - lastGuildAnswer < GUILD_ANSWER_GAP then return end
        lastGuildAnswer = GetTime()
    end
    answerQueued[channel] = true
    C_Timer.After(math.random(1, ANSWER_SPREAD) / TENTHS, Answer(channel))
end

local function Ask(channel)
    if InCombatLockdown() then
        held = true
        return
    end
    C_ChatInfo.SendAddonMessage(PREFIX, REQUEST, channel)
end

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
        Ask(GUILD)
        Send(GUILD, true)
    end
end

local function Received(message, channel, sender)
    if message == REQUEST then return AnswerSoon(channel) end
    local guid, tenths, level = message:match(SCORE_PATTERN)
    tenths, level = tonumber(tenths), tonumber(level)
    if not guid or guid == own or not tenths or tenths > MAX_TENTHS then return end
    if not ns.SenderIs(sender, channel, guid) then return end
    if level and level > MAX_LEVEL then level = nil end
    if Score.Remember then Score.Remember(guid, tenths / TENTHS, true, true, level) end
end

local function OnMessage(prefix, message, channel, sender)
    if issecretvalue(prefix) or issecretvalue(message) or issecretvalue(channel) or issecretvalue(sender) then return end
    if prefix ~= PREFIX or not CHANNELS[channel] then return end
    Received(message, channel, sender)
end

local function CombatEnded()
    if not held then return end
    held = false
    Joined()
    Send(nil, true)
end

local function OnEvent(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        OnMessage(prefix, message, channel, sender)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        SendSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        CombatEnded()
    else
        own = own or UnitGUID("player")
        Joined()
        if event == "PLAYER_ENTERING_WORLD" then SendSoon() end
    end
end

local function OnSetting(key)
    if key ~= "enabled" and key ~= "naowhScore" and key ~= "naowhScoreShare" then return end
    lastSent = nil
    if own then SendSoon() end
end

events:SetScript("OnEvent", OnEvent)
S.OnChange(OnSetting)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
