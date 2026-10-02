-------------------------------------------------------------------------------
--  Sharing.lua -- asking a group member to share a dungeon quest you do not have
--  (ns.Journal.Sharing). Click the group count on a quest row: the first member on the
--  quest is asked over an addon message, and if they run Naowh Forever with the Dungeon
--  Journal on, their game shares it as their Share button would. Both sides say in chat
--  what happened. No answer in a few seconds, and the next member on it is asked.
--
--  Messages, on the group's channel, prefix "NaowhJournal", version first:
--    "1 A <theirs> <yours> <quest IDs>"        asks them for the first of these in their log
--    "1 R <yours> <theirs> <quest ID> <code>"  their answer: S shared, N not in their log,
--                                               P the game does not let it be shared, W wait
--  Each names who it is for and who it is from, by GUID: everyone in the group receives it,
--  the sender too, and an answer from a member no longer asked is not taken for the next.
--  Listened for only while the Journal and Quest Share Requests (shareRequests) are on and you
--  are in a group; off, nothing is made or registered, and you neither ask nor answer.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local J = ns.Journal
local S = J.Settings

local PREFIX = "NaowhJournal"
local VERSION = "1"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local PARTY = { "party1", "party2", "party3", "party4" }
local WAIT = 5        -- seconds for an answer before the next member on it is asked
local MAX_IDS = 8     -- quest IDs in one ask: a quest and its other versions
local COOLDOWN = 3    -- seconds between two quests shared on request, against spam

local Sharing = {}
J.Sharing = Sharing

local frame, prefixed
local lastShared = 0  -- GetTime() of the last quest shared on request

-- The ask in flight, while active: the quest's name and IDs, the members on it, and which
-- of them is asked now (at, guid). generation rejects the timer of an ask since answered.
local asking = { units = {}, names = {} }
local generation = 0

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- "Name" from the sender's "Name-Realm".
local function Short(sender)
    return sender:match("^([^%-]+)") or sender
end

-- Sends; false when the game refused (chat locked in an encounter, or throttled).
local function Send(text)
    local channel = Channel()
    if not channel or C_ChatInfo.InChatMessagingLockdown() then return false end
    local result = C_ChatInfo.SendAddonMessage(PREFIX, text, channel)
    return result == nil or result == Enum.SendAddonMessageResult.Success
end

-------------------------------------------------------------------------------
--  Asking
-------------------------------------------------------------------------------
local function Stop()
    generation = generation + 1
    asking.active = false
end

local AskNext

local function Timeout(sent)
    if sent ~= generation or not asking.active then return end
    ns.Print(("%s did not answer: they need Naowh Forever with its Dungeon Journal on.")
        :format(asking.names[asking.at]))
    AskNext()
end

-- Asks the next member on the quest; says so when there is no one left.
function AskNext()
    asking.at = asking.at + 1
    local unit = asking.units[asking.at]
    if not unit then
        if asking.at > 1 then ns.Print(("No one else in your group can share %s."):format(asking.name)) end
        return Stop()
    end
    local guid = UnitGUID(unit)
    if not guid or issecretvalue(guid) then return AskNext() end
    asking.guid = guid
    local mine = UnitGUID("player")
    if not mine or not Send(("%s A %s %s %s"):format(VERSION, guid, mine, asking.ids)) then
        ns.Print("The game is not passing addon messages right now (in an encounter): ask again after it.")
        return Stop()
    end
    ns.Print(("Asking %s to share %s with you..."):format(asking.names[asking.at], asking.name))
    generation = generation + 1
    local sent = generation
    C_Timer.After(WAIT, function() Timeout(sent) end)
end

-- Whether you ask and answer: the Journal and Quest Share Requests both on.
---@return boolean on
function Sharing.On()
    return S.Get("enabled") == true and S.Get("shareRequests") == true
end

-- Asks the group members on the entry's quest, one at a time, to share it with you.
---@param entry JournalQuestEntry a quest you do not have
function Sharing.Ask(entry)
    if entry.inLog or not IsInGroup() or not Sharing.On() then return end
    if asking.active then
        ns.Print(("Still waiting on %s for %s."):format(asking.names[asking.at], asking.name))
        return
    end
    local quest = entry.quest
    wipe(asking.units)
    wipe(asking.names)
    for i = 1, math.min(GetNumSubgroupMembers(), #PARTY) do
        local unit = PARTY[i]
        if J.Quests.UnitOnQuest(unit, quest, nil) then
            local name = UnitName(unit)
            asking.units[#asking.units + 1] = unit
            asking.names[#asking.names + 1] = name and not issecretvalue(name) and name or unit
        end
    end
    if #asking.units == 0 then return end
    -- The quest and its other versions: they may have any one of them.
    local ids = tostring(quest[1])
    for i = 1, math.min(quest.alt and #quest.alt or 0, MAX_IDS - 1) do ids = ids .. "," .. quest.alt[i] end
    asking.active, asking.name, asking.ids, asking.at = true, entry.name, ids, 0
    AskNext()
end

local ANSWERS = {
    S = "%s shared %s with you: accept it in the window the game opens.",
    N = "%s is not on %s any more.",
    P = "%s cannot share %s: the game does not let it be shared.",
    W = "%s shared a quest a moment ago: ask again in a few seconds.",
}

local function OnAnswer(from, code)
    if not asking.active or from ~= asking.guid or not ANSWERS[code] then return end
    ns.Print(ANSWERS[code]:format(asking.names[asking.at], asking.name))
    if code == "S" or code == "W" then return Stop() end
    generation = generation + 1   -- this member's timer is done with
    AskNext()
end

-------------------------------------------------------------------------------
--  Answering
-------------------------------------------------------------------------------
-- An ask for you: shares the first of its quests in your log, and says so to both sides.
-- The IDs are as many as one addon message holds, at most.
local function OnAsk(asker, ids, sender)
    if not asker:find("^Player%-") then return end
    local who = Short(sender)
    local found, index
    for id in ids:gmatch("%d+") do
        index = C_QuestLog.GetLogIndexForQuestID(tonumber(id))
        if index then found = tonumber(id) break end
    end
    local code
    if not found then
        code = "N"
        ns.Print(("%s asked you to share a quest you are not on."):format(who))
    else
        local title = C_QuestLog.GetTitleForQuestID(found) or "a quest"
        if not C_QuestLog.IsPushableQuest(found) then
            code = "P"
            ns.Print(("%s asked you to share %s, but the game does not let it be shared."):format(who, title))
        elseif GetTime() - lastShared < COOLDOWN then
            code = "W"
            ns.Print(("%s asked you to share %s: you shared one a moment ago."):format(who, title))
        else
            code, lastShared = "S", GetTime()
            -- The same call Blizzard's own Share button makes.
            QuestLogPushQuest(index)
            ns.Print(("%s asked you to share %s: shared it with your group."):format(who, title))
        end
    end
    Send(("%s R %s %s %d %s"):format(VERSION, asker, UnitGUID("player"), found or 0, code))
end

-- Only messages for you: an ask for your quest, or the answer to yours.
local function OnMessage(text, sender)
    local version, kind, to, from, rest = strsplit(" ", text, 5)
    if version ~= VERSION or not rest or to ~= UnitGUID("player") then return end
    if kind == "A" then
        OnAsk(from, rest, sender)
    elseif kind == "R" then
        local _, code = strsplit(" ", rest, 2)
        OnAnswer(from, code)
    end
end

-------------------------------------------------------------------------------
--  Listening
-------------------------------------------------------------------------------
-- Asks only come in a group: out of one, other addons' guild and whisper messages do not
-- wake the handler.
local function Listen()
    if IsInGroup() then
        frame:RegisterEvent("CHAT_MSG_ADDON")
    else
        frame:UnregisterEvent("CHAT_MSG_ADDON")
        Stop()
    end
end

-- CHAT_MSG_ADDON: prefix, text, channel, sender. Secret in chat lockdown: skipped.
local function OnEvent(_, event, prefix, text, channel, sender)
    if event == "GROUP_ROSTER_UPDATE" then return Listen() end
    if issecretvalue(prefix) or prefix ~= PREFIX then return end
    if issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender) then return end
    if GROUP_CHANNELS[channel] then OnMessage(text, sender) end
end

-- Listening runs while it is on: the frame is made the first time it is.
local function Sync()
    local on = Sharing.On()
    if not (on or frame) then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    if on then
        if not prefixed then
            prefixed = true
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        Listen()
    else
        frame:UnregisterAllEvents()
        Stop()
    end
end

S.OnChange(function(key)
    if key == "enabled" or key == "shareRequests" then Sync() end
end)
hooksecurefunc(ns, "Apply", Sync)
