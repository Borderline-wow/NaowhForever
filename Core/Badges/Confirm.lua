-- Confirm.lua: a patron's badge shows once their own client holds its claim on the BattleTag naowh.gg has.
local ns = _G.NaowhForever

local Confirm = {}
ns.BadgeConfirm = Confirm

local PREFIX = "NaowhBadge"
local ASK, YES, NO = "1 Q", "1 Y", "1 N"
local ASK_GAP = 60
local ANSWER_WAIT = 10
local ASKS_MAX, ASKS_WINDOW = 10, 10
local ANSWERS_MAX, ANSWERS_WINDOW = 10, 10
local ANSWER_GAP = 3
local KEPT_MAX = 200
local FNV_OFFSET, FNV_LOW = 2166136261, 403
local TWO_8, TWO_24, TWO_32 = 256, 16777216, 4294967296
local HASH = "%08x"
local SEPARATOR = "|"
local CLAIM_CHAR = "[ABCDEFGHJKMNPQRSTVWXYZ2-9]"
local CLAIM_PATTERN = "^" .. CLAIM_CHAR:rep(4) .. "%-" .. CLAIM_CHAR:rep(4) .. "$"
local DASH, SPACE = "-", " "
local CONFIRMED, UNCLAIMED, MISMATCH = "confirmed", "unclaimed", "mismatch"
local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde",
}
local TEXT_UNCLAIMED = ns.L("Your Naowh Forever badge needs claiming on this character: the Naowh Forever app "
    .. "does it for you, or type /nf badges claim with the code from your naowh.gg account.")
local TEXT_MISMATCH = ns.L("Your Naowh Forever badge is off on this character: its claim, or the BattleTag saved "
    .. "on naowh.gg, is not this character's.")

Confirm.CONFIRMED, Confirm.UNCLAIMED, Confirm.MISMATCH = CONFIRMED, UNCLAIMED, MISMATCH

local me, myEntry, state, warned
local frame, prefixed, listening
local confirmed, confirmedCount = {}, 0
local asked, waiting, askedCount = {}, {}, 0
local askWindowAt, askCount = -ASKS_WINDOW, 0
local answered, answeredCount = {}, 0
local answerWindowAt, answerCount = -ANSWERS_WINDOW, 0
local onConfirmed

local function Secret(value) return issecretvalue and issecretvalue(value) end

local function Readable(value)
    return type(value) == "string" and value ~= "" and not Secret(value)
end

function Confirm.Hash(claim, battletag, guid)
    local text = claim .. SEPARATOR .. battletag .. SEPARATOR .. guid
    local hash = FNV_OFFSET
    for i = 1, #text do
        hash = bit.bxor(hash, text:byte(i)) % TWO_32
        hash = (hash * FNV_LOW + (hash % TWO_8) * TWO_24) % TWO_32
    end
    return HASH:format(hash)
end

local function Me()
    me = me or UnitGUID("player")
    return me
end

function Confirm.SetEntry(entry)
    myEntry, state = entry, nil
end

local function Typed()
    local saved = ns.AccountSettings().badgeClaims
    return saved and saved[Me()]
end

local function Matches(claim, battletag, listed)
    return type(claim) == "string" and Confirm.Hash(claim, battletag, Me()) == listed
end

local function Check()
    local listed = myEntry and myEntry.claim
    if type(listed) ~= "string" then return nil end
    local _, battletag = BNGetInfo()
    if not Readable(battletag) then return nil end
    local written = ns.BADGE_CLAIMS and ns.BADGE_CLAIMS[Me()]
    local typed = Typed()
    if Matches(typed, battletag, listed) then return CONFIRMED end
    if type(written) == "table" then
        for i = 1, #written do
            if Matches(written[i], battletag, listed) then return CONFIRMED end
        end
    end
    if typed == nil and type(written) ~= "table" then return UNCLAIMED end
    return MISMATCH
end

function Confirm.State()
    if state == nil and myEntry then
        state = Check()
        if state and state ~= CONFIRMED and not warned then
            warned = true
            ns.Print(state == UNCLAIMED and TEXT_UNCLAIMED or TEXT_MISMATCH)
        end
    end
    return state
end

function Confirm.Mine()
    return Confirm.State() == CONFIRMED
end

function Confirm.Listed()
    return myEntry ~= nil
end

function Confirm.Claim(code)
    code = type(code) == "string" and code:upper() or ""
    if not code:find(CLAIM_PATTERN) then return false end
    local account = ns.AccountSettings()
    account.badgeClaims = account.badgeClaims or {}
    account.badgeClaims[Me()] = code
    state, warned = nil, true
    return true, Confirm.State()
end

local function FactionOf(guid, unit)
    if unit then
        local faction = UnitFactionGroup(unit)
        if Readable(faction) then return faction end
    end
    local _, _, _, race = GetPlayerInfoByGUID(guid)
    return Readable(race) and RACE_FACTION[race] or nil
end

local function Enemy(guid, unit)
    local theirs, ours = FactionOf(guid, unit), UnitFactionGroup("player")
    return theirs ~= nil and Readable(ours) and theirs ~= ours
end

local function NameOf(guid)
    local _, _, _, _, _, name, second = GetPlayerInfoByGUID(guid)
    if not Readable(name) then return nil end
    if Readable(second) then return name .. SPACE .. second end
    return name
end

local function Key(name)
    return (name:gsub(DASH, SPACE))
end

local function Ask(guid, who)
    if not listening or C_ChatInfo.InChatMessagingLockdown() then return end
    who = Readable(who) and who or NameOf(guid)
    if not who then return end
    local now = GetTime()
    local last = asked[guid]
    if last and now - last < ASK_GAP then return end
    if now - askWindowAt >= ASKS_WINDOW then askWindowAt, askCount = now, 0 end
    if askCount >= ASKS_MAX then return end
    askCount = askCount + 1
    if not last then
        if askedCount >= KEPT_MAX then
            wipe(asked)
            wipe(waiting)
            askedCount = 0
        end
        askedCount = askedCount + 1
    end
    asked[guid] = now
    waiting[Key(who)] = guid
    C_ChatInfo.SendAddonMessage(PREFIX, ASK, "WHISPER", who)
end

function Confirm.Shows(guid, who, unit)
    if guid == Me() then return Confirm.Mine() end
    if confirmed[guid] then return true end
    if Enemy(guid, unit) then return true end
    Ask(guid, who)
    return false
end

local function MayAnswer(sender, now)
    if now - answerWindowAt >= ANSWERS_WINDOW then answerWindowAt, answerCount = now, 0 end
    if answerCount >= ANSWERS_MAX then return false end
    local last = answered[sender]
    if last and now - last < ANSWER_GAP then return false end
    if not last then
        if answeredCount >= KEPT_MAX then
            wipe(answered)
            answeredCount = 0
        end
        answeredCount = answeredCount + 1
    end
    answered[sender] = now
    answerCount = answerCount + 1
    return true
end

local function OnAnswer(sender, yes)
    local key = Key(sender)
    local guid = waiting[key]
    if not guid then return end
    waiting[key] = nil
    local at = asked[guid]
    if not yes or not at or GetTime() - at > ANSWER_WAIT then return end
    if not confirmed[guid] then
        if confirmedCount >= KEPT_MAX then
            wipe(confirmed)
            confirmedCount = 0
        end
        confirmedCount = confirmedCount + 1
    end
    confirmed[guid] = true
    if onConfirmed then onConfirmed(guid) end
end

local function OnMessage(_, _, prefix, message, channel, sender)
    if Secret(prefix) or Secret(message) or Secret(channel) or Secret(sender) then return end
    if prefix ~= PREFIX or channel ~= "WHISPER" or not Readable(sender) then return end
    if message == ASK then
        if C_ChatInfo.InChatMessagingLockdown() or not MayAnswer(sender, GetTime()) then return end
        C_ChatInfo.SendAddonMessage(PREFIX, Confirm.Mine() and YES or NO, "WHISPER", sender)
    elseif message == YES or message == NO then
        OnAnswer(sender, message == YES)
    end
end

function Confirm.Listen(on)
    if on == (listening or false) then return end
    listening = on
    if on and not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnMessage)
    end
    if not frame then return end
    if on then
        if not prefixed then
            prefixed = true
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        frame:RegisterEvent("CHAT_MSG_ADDON")
    else
        frame:UnregisterEvent("CHAT_MSG_ADDON")
    end
end

function Confirm.OnConfirmed(fn) onConfirmed = fn end

Confirm._Test = { OnMessage = OnMessage, confirmed = confirmed, asked = asked, waiting = waiting,
    Listening = function() return listening end,
    Reset = function()
        me, state, warned = nil, nil, nil
        wipe(confirmed); wipe(asked); wipe(waiting); wipe(answered)
        confirmedCount, askedCount, answeredCount = 0, 0, 0
        askWindowAt, askCount, answerWindowAt, answerCount = -ASKS_WINDOW, 0, -ANSWERS_WINDOW, 0
    end }
