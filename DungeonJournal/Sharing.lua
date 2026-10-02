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
--  Sharing a dungeon's quests
-------------------------------------------------------------------------------
-- A shared quest opens in each member's quest window, and while it is open there the next
-- share is turned away as busy. So quests go one at a time: each waits until everyone it
-- was sent to (the game names them in "Sharing quest with X...") has answered, and one
-- that came back busy goes to the back of the queue to try again. Nobody named within
-- SENT_WAIT means there is no one to wait for; ANSWER_WAIT is the most any quest waits.
local SENT_WAIT, ANSWER_WAIT, RETRIES = 2, 30, 2

local shareQueue, sharing = {}, nil
local shareFrame
local sentPattern, busyPattern, answerPatterns

-- The quests of the dungeon in your log that the game lets you share, as log IDs.
---@param dungeon JournalDungeon
---@return number[] ids
function Sharing.Shareable(dungeon)
    local ids = {}
    for _, quest in ipairs(dungeon.quests and dungeon.quests.quests or {}) do
        local id = J.Quests.LoggedID(quest)
        if id and C_QuestLog.IsPushableQuest(id) then ids[#ids + 1] = id end
    end
    return ids
end

local function QuestName(id)
    return C_QuestLog.GetTitleForQuestID(id) or tostring(id)
end

-- The game's push results as patterns: "Sharing quest with X..." is the send, every other
-- ERR_QUEST_PUSH_*_S (accepted, declined, busy, already on it...) an answer.
local function Pattern(fmt)
    fmt = fmt:gsub("%%%d?%$?s", "\001"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. fmt:gsub("\001", "(.+)") .. "$"
end

local function PushPatterns()
    if answerPatterns then return end
    answerPatterns = {}
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and key:find("^ERR_QUEST_PUSH_.+_S$")
            and key ~= "ERR_QUEST_PUSH_SUCCESS_S" then
            answerPatterns[#answerPatterns + 1] = Pattern(value)
        end
    end
    sentPattern = ERR_QUEST_PUSH_SUCCESS_S and Pattern(ERR_QUEST_PUSH_SUCCESS_S)
    busyPattern = ERR_QUEST_PUSH_BUSY_S and Pattern(ERR_QUEST_PUSH_BUSY_S)
end

local NextShare

local function FinishShare()
    local cur = sharing
    sharing = nil
    if cur.timer then cur.timer:Cancel() end
    if cur.busy and cur.tries < RETRIES then
        cur.tries, cur.busy = cur.tries + 1, nil
        shareQueue[#shareQueue + 1] = cur
        ns.Print(("Someone was busy for %s; sharing it again after the rest."):format(QuestName(cur.id)))
    end
    NextShare()
end

function NextShare()
    local cur = table.remove(shareQueue, 1)
    if not (cur and IsInGroup()) then
        if cur then ns.Print("Stopped sharing: you are not in a group.") else ns.Print("Done sharing.") end
        wipe(shareQueue)
        shareFrame:UnregisterAllEvents()
        return
    end
    -- Sharing is blocked in combat; the queue waits for PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        table.insert(shareQueue, 1, cur)
        shareFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.Print("Sharing carries on after combat.")
        return
    end
    local index = C_QuestLog.GetLogIndexForQuestID(cur.id)
    if not index then return NextShare() end
    QuestLogPushQuest(index)
    sharing, cur.sent, cur.answered = cur, {}, {}
    cur.timer = C_Timer.NewTimer(SENT_WAIT, function()
        if sharing ~= cur then return end
        if next(cur.sent) == nil then return FinishShare() end
        cur.timer = C_Timer.NewTimer(ANSWER_WAIT - SENT_WAIT, function()
            if sharing == cur then FinishShare() end
        end)
    end)
end

-- Push results come as system messages; UI_INFO_MESSAGE and UI_ERROR_MESSAGE carry the
-- text second.
local function OnShareEvent(_, event, a, b)
    if event == "PLAYER_REGEN_ENABLED" then
        shareFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not sharing then NextShare() end
        return
    end
    local cur, msg = sharing, event == "CHAT_MSG_SYSTEM" and a or b
    if not cur or type(msg) ~= "string" or issecretvalue(msg) then return end
    local name = sentPattern and msg:match(sentPattern)
    if name then
        cur.sent[name] = true
        return
    end
    for _, pattern in ipairs(answerPatterns) do
        name = msg:match(pattern)
        if name then
            cur.answered[name] = true
            if busyPattern and msg:match(busyPattern) then cur.busy = true end
            for sent in pairs(cur.sent) do
                if not cur.answered[sent] then return end
            end
            if next(cur.sent) then FinishShare() end
            return
        end
    end
end

-- Shares the dungeon's quests in your log with your group, one at a time. A second click
-- while sharing adds only the quests not queued already.
---@param dungeon JournalDungeon
function Sharing.ShareAll(dungeon)
    if not IsInGroup() then
        ns.Print("Join a group to share quests.")
        return
    end
    local ids = Sharing.Shareable(dungeon)
    if #ids == 0 then
        ns.Print("None of your quests for this dungeon can be shared.")
        return
    end
    local queued = { [sharing and sharing.id or 0] = true }
    for _, item in ipairs(shareQueue) do queued[item.id] = true end
    local names = {}
    for _, id in ipairs(ids) do
        if not queued[id] then
            shareQueue[#shareQueue + 1] = { id = id, tries = 0 }
            names[#names + 1] = QuestName(id)
        end
    end
    if #names == 0 then
        ns.Print("Those quests are being shared already.")
        return
    end
    ns.Print("Sharing " .. table.concat(names, ", ")
        .. ". Each one waits until your group has answered the one before.")
    PushPatterns()
    if not shareFrame then
        shareFrame = CreateFrame("Frame")
        shareFrame:SetScript("OnEvent", OnShareEvent)
    end
    for _, event in ipairs({ "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do
        shareFrame:RegisterEvent(event)
    end
    if not sharing then NextShare() end
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

-------------------------------------------------------------------------------
--  Accept Shared Dungeon Quests
-------------------------------------------------------------------------------
-- A dungeon quest a group member shares is accepted as it opens. Every ID the data knows
-- counts: a quest, its alt versions, the steps of its chain and its lead-in. QoL's skip key
-- leaves one open to look at first.
local SKIP_HELD = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }
local acceptFrame, dungeonQuestIDs

local function AddIDs(list)
    for _, step in ipairs(list or {}) do
        if type(step) == "table" then
            for _, id in ipairs(step) do dungeonQuestIDs[id] = true end
        else
            dungeonQuestIDs[step] = true
        end
    end
end

local function OnQuestDetail()
    local qol = ns.QoLSettings
    local held = SKIP_HELD[qol.Get("questSkipModifier")]
    if (held and held()) or not UnitIsPlayer("questnpc") or not dungeonQuestIDs[GetQuestID()] then return end
    -- QoL's Auto Accept Quests takes every quest already.
    if qol.Get("enabled") and qol.Get("questAccept") then return end
    if QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
end

local function SyncAccept()
    local on = S.Get("enabled") == true and S.Get("acceptShared") == true
    if not (on or acceptFrame) then return end
    if not acceptFrame then
        dungeonQuestIDs = {}
        for _, dungeon in ipairs(J.QuestData) do
            for _, quest in ipairs(dungeon.quests) do
                dungeonQuestIDs[quest[1]] = true
                AddIDs(quest.alt)
                AddIDs(quest.steps)
                AddIDs(quest.lead)
            end
        end
        for _, list in pairs(J.QuestChains) do AddIDs(list) end
        acceptFrame = CreateFrame("Frame")
        acceptFrame:SetScript("OnEvent", OnQuestDetail)
    end
    if on then
        acceptFrame:RegisterEvent("QUEST_DETAIL")
    else
        acceptFrame:UnregisterAllEvents()
    end
end

S.OnChange(function(key)
    if key == "enabled" or key == "shareRequests" then Sync() end
    if key == "enabled" or key == "acceptShared" then SyncAccept() end
end)
hooksecurefunc(ns, "Apply", Sync)
hooksecurefunc(ns, "Apply", SyncAccept)
