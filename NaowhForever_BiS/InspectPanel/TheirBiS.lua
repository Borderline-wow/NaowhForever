-- TheirBiS.lua: their BiS stars, asked of their Naowh Forever by whisper; yours answered.
local ns = _G.NaowhForever

local IP = ns.InspectPanel
local S = ns.QoLSettings
local Items = ns.Shared.Items
local SLOT_NAME, GEAR_SLOTS = Items.SLOT_NAME, Items.GEAR_SLOTS

local PREFIX = "NaowhInspect"
local ASK_GAP = 10
local ANSWER_WAIT = 10
local ANSWER_GAP = 3
local ANSWERS_MAX, ANSWERS_WINDOW = 10, 10
local ASKERS_MAX, KEPT_MAX = 40, 50
local MAX_BYTES = 255
local MAX_RANK = 99
local MAX_ID = 2 ^ 31
local COMMA, ASK, ANSWER = 44, 81, 65
local KIND_AT = 3
local NEXT_ENTRY = 2
local ASK_FORMAT = "1 Q %s %s"
local ANSWER_HEAD = "1 A %s "
local ENTRY = "%d:%d:%d"
local NOTHING = "-"
local ASK_PATTERN = "^1 Q (Player%-%d+%-%x+) Player%-%d+%-%x+$"
local ANSWER_PATTERN = "^1 A (Player%-%d+%-%x+) (%S+)$"
local ENTRY_PATTERN = "^(%d%d?):(%d+):(%d%d?)"

local own, frame, prefixed
local pending = {}
local asked, askedCount = {}, 0
local kept, keptCount = {}, 0
local askers, askerCount = {}, 0
local windowAt, sentCount = -ANSWERS_WINDOW, 0
local items, ranks = {}, {}
local entries = {}

local function Readable(value)
    return type(value) == "string" and value ~= "" and not issecretvalue(value)
end

local function ShareOn()
    return S.Get("enabled") == true and S.Get("inspectPanelShareBis") == true
end

local function Own()
    own = own or UnitGUID("player")
    return own
end

function IP.TheirRank(guid, slot, id)
    if not guid then return nil end
    if guid == Own() then return ns.IsBisItem(id) end
    local entry = kept[guid]
    if entry and entry.items[slot] == id then return entry.ranks[slot] end
end

function IP.RunsNaowh(guid)
    if not guid then return false end
    if kept[guid] then return true end
    local Score = ns.NaowhScore
    local known = Score and Score.Known and Score.Known(guid)
    return known ~= nil and known.shared == true
end

local OnMessage

local function Listen()
    local want = ShareOn() or pending.guid ~= nil
    if want and not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnMessage)
    end
    if not frame then return end
    if want then
        if not prefixed then
            prefixed = true
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        frame:RegisterEvent("CHAT_MSG_ADDON")
    else
        frame:UnregisterEvent("CHAT_MSG_ADDON")
    end
end

local function Expire()
    if pending.guid and GetTime() - pending.at >= ANSWER_WAIT then
        pending.guid = nil
        Listen()
    end
end

local function Ask(unit, guid)
    if guid == Own() or not UnitIsPlayer(unit) then return end
    if UnitFactionGroup(unit) ~= UnitFactionGroup("player") then return end
    local now = GetTime()
    local last = asked[guid]
    if last and now - last < ASK_GAP then return end
    if C_ChatInfo.InChatMessagingLockdown() then return end
    local target = IP.FullName(unit)
    if not (target and own) then return end
    if not last then
        if askedCount >= KEPT_MAX then
            wipe(asked)
            askedCount = 0
        end
        askedCount = askedCount + 1
    end
    asked[guid] = now
    pending.guid, pending.unit, pending.at = guid, unit, now
    Listen()
    C_ChatInfo.SendAddonMessage(PREFIX, ASK_FORMAT:format(guid, own), "WHISPER", target)
    C_Timer.After(ANSWER_WAIT, Expire)
end

local function MayAnswer(sender, now)
    if now - windowAt >= ANSWERS_WINDOW then windowAt, sentCount = now, 0 end
    if sentCount >= ANSWERS_MAX then return false end
    local last = askers[sender]
    if last and now - last < ANSWER_GAP then return false end
    if not last then
        if askerCount >= ASKERS_MAX then
            wipe(askers)
            askerCount = 0
        end
        askerCount = askerCount + 1
    end
    askers[sender] = now
    sentCount = sentCount + 1
    return true
end

local function Answer(sender)
    if C_ChatInfo.InChatMessagingLockdown() or not MayAnswer(sender, GetTime()) then return end
    local head = ANSWER_HEAD:format(Own())
    local length = #head
    wipe(entries)
    for _, gear in ipairs(GEAR_SLOTS) do
        local slot = gear[1]
        local id = GetInventoryItemID("player", slot)
        local rank = id and ns.IsBisItem(id)
        if rank and rank <= MAX_RANK then
            local text = ENTRY:format(slot, id, rank)
            local add = #text + (#entries > 0 and 1 or 0)
            if length + add > MAX_BYTES then break end
            entries[#entries + 1] = text
            length = length + add
        end
    end
    C_ChatInfo.SendAddonMessage(PREFIX, head .. (#entries > 0 and table.concat(entries, ",") or NOTHING), "WHISPER",
        sender)
end

local function Read(body)
    wipe(items)
    wipe(ranks)
    if body == NOTHING then return true end
    local pos, count, length = 1, 0, #body
    while true do
        local _, last, slot, id, rank = body:find(ENTRY_PATTERN, pos)
        if not last then return false end
        slot, id, rank = tonumber(slot), tonumber(id), tonumber(rank)
        if not SLOT_NAME[slot] or items[slot] or id < 1 or id >= MAX_ID or rank < 1 then return false end
        count = count + 1
        if count > #GEAR_SLOTS then return false end
        items[slot], ranks[slot] = id, rank
        if last == length then return true end
        if body:byte(last + 1) ~= COMMA then return false end
        pos = last + NEXT_ENTRY
    end
end

local function Keep(guid)
    local entry = kept[guid]
    if not entry then
        if keptCount >= KEPT_MAX then
            wipe(kept)
            keptCount = 0
        end
        entry = { items = {}, ranks = {} }
        kept[guid] = entry
        keptCount = keptCount + 1
    end
    wipe(entry.items)
    wipe(entry.ranks)
    for slot, id in pairs(items) do entry.items[slot], entry.ranks[slot] = id, ranks[slot] end
end

local function OnAnswer(guid, body, sender)
    if pending.guid ~= guid then return end
    local unit = pending.unit
    local _, shown = IP.Current()
    if shown ~= guid or GetTime() - pending.at > ANSWER_WAIT then
        pending.guid = nil
        return Listen()
    end
    if not ns.SenderIsUnit(sender, unit, guid) then return end
    pending.guid = nil
    Listen()
    if not Read(body) then return end
    Keep(guid)
    IP.PaintSlots()
end

function OnMessage(_, _, prefix, message, channel, sender)
    if issecretvalue(prefix) or issecretvalue(message) or issecretvalue(channel) or issecretvalue(sender) then return end
    if prefix ~= PREFIX or channel ~= "WHISPER" or not Readable(sender) or type(message) ~= "string"
        or #message > MAX_BYTES then
        return
    end
    local kind = message:byte(KIND_AT)
    if kind == ASK then
        local to = ShareOn() and message:match(ASK_PATTERN)
        if to and to == Own() then Answer(sender) end
    elseif kind == ANSWER then
        local guid, body = message:match(ANSWER_PATTERN)
        if guid then OnAnswer(guid, body, sender) end
    end
end

IP.OnRefresh(function(unit, guid)
    if guid and IP.Ready(guid) then Ask(unit, guid) end
end)

S.OnChange(function(key)
    if key == "enabled" or key == "inspectPanelShareBis" then Listen() end
end)
hooksecurefunc(ns, "Apply", Listen)

IP._TheirBiSTest = { OnMessage = OnMessage, pending = pending, Read = Read, items = items }
