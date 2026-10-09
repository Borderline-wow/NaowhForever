-- Share.lua: Group Inspect's exchange with other players' Naowh Forever: when to ask, answer and listen.
local ns = _G.NaowhForever
local GI = ns.GroupInspect
local S = ns.QoLSettings
local Message = GI.Message
local OwnStats = GI.OwnStats

local PREFIX, REQUEST, MAX_BYTES, CHANNELS = Message.PREFIX, Message.REQUEST, Message.MAX_BYTES, Message.CHANNELS
local TENTH_SCALE = GI.C.TENTHS
local ANSWER_GAP = 10
local ACCEPT_GAP = 8
local ASKED_WINDOW = 300
local REQUEST_GAP = 10
local SEND_DELAY = 2
local PARTY_SPREAD, RAID_SPREAD = 15, 50
local FROM_MAX = 80
local CHANGE_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP" }
local HELD_EVENTS = { "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }

local Parse, Apply, parsed = Message.Parse, Message.Apply, Message.parsed
local mine, ReadMine = OwnStats.values, OwnStats.Read

local own, frame, prefixed, channel
local registered = {}
local askedAt, lastAnswer, lastRequest = -ASKED_WINDOW, -ANSWER_GAP, -REQUEST_GAP
local answerQueued, requestQueued, changeQueued, held = false, false, false, false
local lastFrom, fromCount = {}, 0
local askedFor = {}

local function Own()
    own = own or UnitGUID("player")
    return own
end

local function Secret(value)
    return value ~= nil and issecretvalue(value)
end

local function ShareOn()
    return S.Get("groupInspectShare") == true
end

local function IsOpen()
    return GI.IsOpen() == true
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function FillSelf()
    if IsOpen() and ReadMine() and Own() then Apply(own, mine) end
end

local function Toggle(event, on)
    if on == (registered[event] == true) then return end
    registered[event] = on or nil
    if on then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
end

local OnEvent

local function Listen()
    local open = IsOpen()
    local want = open or ShareOn()
    channel = want and GroupChannel() or nil
    if channel and not prefixed then
        prefixed = true
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    Toggle("GROUP_ROSTER_UPDATE", want)
    Toggle("PLAYER_ENTERING_WORLD", want)
    Toggle("CHAT_MSG_ADDON", channel ~= nil)
    local push = channel ~= nil and (open or (ShareOn() and GetTime() - askedAt < ASKED_WINDOW))
    for i = 1, #CHANGE_EVENTS do Toggle(CHANGE_EVENTS[i], push) end
    for i = 1, #HELD_EVENTS do Toggle(HELD_EVENTS[i], held and want) end
end

local function Blocked()
    return InCombatLockdown() or C_ChatInfo.InChatMessagingLockdown()
end

local function SendMine()
    if not (ShareOn() and channel and Own()) then return end
    if Blocked() or not ReadMine() then
        held = true
        return Listen()
    end
    C_ChatInfo.SendAddonMessage(PREFIX, Message.Answer(own), channel)
    lastAnswer = GetTime()
end

local function AnswerNow()
    answerQueued = false
    SendMine()
end

local function Spread()
    local tenths = channel == "PARTY" and PARTY_SPREAD or RAID_SPREAD
    return math.random(1, tenths) / TENTH_SCALE
end

local function AnswerSoon()
    if answerQueued then return end
    answerQueued = true
    local wait = Spread()
    local since = GetTime() - lastAnswer
    if since < ANSWER_GAP then wait = wait + ANSWER_GAP - since end
    C_Timer.After(wait, AnswerNow)
end

local function Asked()
    if not (ShareOn() and channel) then return end
    askedAt = GetTime()
    Listen()
    AnswerSoon()
end

local function NoteAsked()
    wipe(askedFor)
    local members = GI.Members()
    for i = 1, #members do
        local guid = members[i].guid
        if guid then askedFor[guid] = true end
    end
end

local function RequestNow()
    requestQueued = false
    if not (IsOpen() and channel) then return end
    if Blocked() then
        held = true
        return Listen()
    end
    C_ChatInfo.SendAddonMessage(PREFIX, REQUEST, channel)
    lastRequest = GetTime()
    NoteAsked()
end

local function RequestSoon()
    if requestQueued or not (IsOpen() and channel) then return end
    local since = GetTime() - lastRequest
    if since >= REQUEST_GAP then return RequestNow() end
    requestQueued = true
    C_Timer.After(REQUEST_GAP - since, RequestNow)
end

local function Joined()
    local members = GI.Members()
    for i = 1, #members do
        local guid = members[i].guid
        if guid and guid ~= own and not askedFor[guid] then return true end
    end
    return false
end

local function ChangedNow()
    changeQueued = false
    FillSelf()
    if ShareOn() and channel and GetTime() - askedAt < ASKED_WINDOW then
        AnswerSoon()
    else
        Listen()
    end
end

local function ChangeSoon()
    if changeQueued then return end
    changeQueued = true
    C_Timer.After(SEND_DELAY, ChangedNow)
end

local function Accept(guid, now)
    local last = lastFrom[guid]
    if last and now - last < ACCEPT_GAP then return false end
    if not last then
        if fromCount >= FROM_MAX then
            wipe(lastFrom)
            fromCount = 0
        end
        fromCount = fromCount + 1
    end
    lastFrom[guid] = now
    return true
end

local function Received(message, sender)
    if message == REQUEST then
        if not ns.SenderIsUnit(sender, "player", Own()) then Asked() end
        return
    end
    local guid = Parse(message)
    if not guid or guid == Own() or not GI.Member(guid) then return end
    if not ns.SenderIs(sender, channel, guid) or not Accept(guid, GetTime()) then return end
    Apply(guid, parsed)
end

function OnEvent(_, event, prefix, message, kind, sender)
    if event == "CHAT_MSG_ADDON" then
        if Secret(prefix) or Secret(message) or Secret(kind) or Secret(sender) then return end
        if prefix ~= PREFIX or kind ~= channel or not CHANNELS[kind] or type(message) ~= "string"
            or #message > MAX_BYTES or type(sender) ~= "string" then
            return
        end
        Received(message, sender)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        Listen()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if Blocked() then return end
        held = false
        Listen()
        FillSelf()
        if GetTime() - askedAt < ASKED_WINDOW then AnswerSoon() end
        RequestSoon()
    else
        ChangeSoon()
    end
end

local function Opened()
    Listen()
    FillSelf()
    RequestSoon()
end

local function Roster(guid)
    if guid ~= nil or not IsOpen() then return end
    local record = Own() and GI.Member(own)
    if record and record.statsShared ~= true then FillSelf() end
    if channel and Joined() then RequestSoon() end
end

GI.OnChange(Roster)
hooksecurefunc(GI, "Open", Opened)
hooksecurefunc(GI, "Close", Listen)
S.OnChange(function(key)
    if key == "groupInspectShare" then Listen() end
end)
hooksecurefunc(ns, "Apply", Listen)
frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnEvent)
Toggle("PLAYER_ENTERING_WORLD", true)

GI._ShareTest = { OnEvent = OnEvent, Parse = Parse, parsed = parsed, mine = mine, ReadMine = ReadMine,
    Listen = Listen, registered = registered, PREFIX = PREFIX }
