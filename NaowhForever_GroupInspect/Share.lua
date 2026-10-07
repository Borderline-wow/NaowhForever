-------------------------------------------------------------------------------
--  Share.lua -- Group Inspect's stats and the Naowh Forever exchange. GI.StatsFromGear(record)
--  sums a member's stats from the gear they wear (statsShared false). Members who run Naowh
--  Forever send their exact stats, talent points per tree and version over addon messages in
--  the group channel, and their record gets statsShared, talents, hasNF and nfVersion:
--    request "1 R", sent only while the window is open (on opening it, and when someone joins)
--    answer  "1 S <GUID> <version> <t1>/<t2>/<t3> <STR> <AGI> <STA> <INT> <SPI> <AP> <SP>
--            <CRIT> <HIT> <ARMOR>", CRIT and HIT in tenths of a percent, one message under 255
--            bytes, sent after a short random wait, at most once per ANSWER_GAP, and again when
--            your gear or talents change while someone asked in the last ASKED_WINDOW seconds.
--  Answering needs Share Your Stats (groupInspectShare) and a group. An answer is kept only from
--  the member its GUID names (ns.SenderIs), still in the group, every field checked, at most one
--  per member per ACCEPT_GAP; nothing received is sent back.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local GI = ns.GroupInspect
local S = ns.QoLSettings
local SW = ns.StatWeights
local GEAR_SLOTS = ns.Shared.Items.GEAR_SLOTS

local IsItemDataCachedByID, GetItemInfoInstant = C_Item.IsItemDataCachedByID, C_Item.GetItemInfoInstant

local PREFIX = "NaowhGroup"
local REQUEST = "1 R"
local ANSWER_FORMAT = "1 S %s %s %d/%d/%d %d %d %d %d %d %d %d %d %d %d"
local ANSWER_PATTERN = "^1 S (Player%-%d+%-%x+) (%d[%w%.%-]*) (%d+)/(%d+)/(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) "
    .. "(%d+) (%d+) (%d+) (%d+) (%d+)$"
local VERSION_PATTERN = "^%d[%w%.%-]*$"
local MAX_BYTES = 255
local MAX_VERSION = 20
local MAX_POINTS = 100
local STAT_KEYS = { "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "CRIT", "HIT", "ARMOR" }
local STAT_MAX = { 99999, 99999, 99999, 99999, 99999, 99999, 99999, 1000, 1000, 999999 }
local TENTHS = { CRIT = true, HIT = true }
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local ANSWER_GAP = 10
local ACCEPT_GAP = 8
local ASKED_WINDOW = 300
local REQUEST_GAP = 10
local SEND_DELAY = 2
local PARTY_SPREAD, RAID_SPREAD = 15, 50
local FROM_MAX = 80
local CHANGE_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP" }
local HELD_EVENTS = { "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }
local ROLE = {
    ["protection-warrior"] = "Tank", ["protection-paladin"] = "Tank",
    ["holy-paladin"] = "Healer", ["discipline-priest"] = "Healer", ["holy-priest"] = "Healer",
    ["restoration-druid"] = "Healer", ["restoration-shaman"] = "Healer",
}
local DAMAGE = "Damage"
local SCHOOLS_FIRST, SCHOOLS_LAST = 2, 7

local PRIMARY, AP, RAP, POWER, SPELL_DAMAGE, HEALING, CRIT, SPELL_CRIT, HIT, SPELL_HIT = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
local KIND = {
    ITEM_MOD_STRENGTH_SHORT = PRIMARY, ITEM_MOD_AGILITY_SHORT = PRIMARY, ITEM_MOD_STAMINA_SHORT = PRIMARY,
    ITEM_MOD_INTELLECT_SHORT = PRIMARY, ITEM_MOD_SPIRIT_SHORT = PRIMARY, RESISTANCE0_NAME = PRIMARY,
    ITEM_MOD_ATTACK_POWER_SHORT = AP, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = RAP,
    ITEM_MOD_SPELL_POWER_SHORT = POWER, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = SPELL_DAMAGE,
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = HEALING,
    ITEM_MOD_CRIT_RATING_SHORT = CRIT, ITEM_MOD_CRIT_SPELL_RATING_SHORT = SPELL_CRIT,
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = SPELL_CRIT,
    ITEM_MOD_HIT_RATING_SHORT = HIT, ITEM_MOD_HIT_SPELL_RATING_SHORT = SPELL_HIT,
}
local PRIMARY_KEY = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
}

local own, frame, prefixed, channel
local version = type(ns.CODE_BUILD) == "string" and #ns.CODE_BUILD <= MAX_VERSION
    and ns.CODE_BUILD:find(VERSION_PATTERN) and ns.CODE_BUILD or "0"
local registered = {}
local askedAt, lastAnswer, lastRequest = -ASKED_WINDOW, -ANSWER_GAP, -REQUEST_GAP
local answerQueued, requestQueued, changeQueued, held = false, false, false, false
local lastFrom, fromCount = {}, 0
local askedFor = {}
local sums = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local primary = { STR = 0, AGI = 0, STA = 0, INT = 0, SPI = 0, ARMOR = 0 }
local mine = { ok = false, stats = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, spent = { 0, 0, 0 } }
local parsed = { stats = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, spent = { 0, 0, 0 } }
local groupIDs = {}

local function Own()
    own = own or UnitGUID("player")
    return own
end

local function Secret(value)
    return value ~= nil and issecretvalue(value)
end

local function ShareOn()
    return S.Get("enabled") == true and S.Get("groupInspectShare") == true
end

local function IsOpen()
    return GI.IsOpen() == true
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Round(value)
    return math.floor(value + 0.5)
end

local function Tenth(value)
    return math.floor(value * 10 + 0.5) / 10
end

local function Clamp(value, most)
    value = Round(value)
    if value < 0 then return 0 end
    if value > most then return most end
    return value
end

local function AddItem(stats, hunter)
    for key, amount in pairs(stats) do
        local kind = KIND[key]
        if kind and type(amount) == "number" and not Secret(amount) then
            if kind == PRIMARY then
                local name = PRIMARY_KEY[key]
                primary[name] = primary[name] + amount
            elseif kind == RAP then
                if hunter then sums[AP] = sums[AP] + amount end
            elseif kind == CRIT or kind == SPELL_CRIT or kind == HIT or kind == SPELL_HIT then
                sums[kind] = sums[kind] + SW.KeyAmount(key, amount)
            else
                sums[kind] = sums[kind] + amount
            end
        end
    end
end

function GI.StatsFromGear(record)
    if type(record) ~= "table" or record.statsShared == true or type(record.gear) ~= "table" then return false end
    for i = 1, #sums do sums[i] = 0 end
    for key in pairs(primary) do primary[key] = 0 end
    local hunter = record.classFile == "HUNTER"
    local gear, complete = record.gear, true
    for i = 1, #GEAR_SLOTS do
        local entry = gear[GEAR_SLOTS[i][1]]
        local link = entry and entry.link
        if type(link) == "string" and not Secret(link) then
            local id = entry.id or GetItemInfoInstant(link)
            local stats = id and IsItemDataCachedByID(id) and SW.Stats(link)
            if stats then AddItem(stats, hunter) else complete = false end
        end
    end
    local into = record.stats
    if type(into) ~= "table" then
        into = {}
        record.stats = into
    end
    into.STR, into.AGI, into.STA = primary.STR, primary.AGI, primary.STA
    into.INT, into.SPI, into.ARMOR = primary.INT, primary.SPI, primary.ARMOR
    into.AP = sums[AP]
    into.SP = sums[POWER] + math.max(sums[SPELL_DAMAGE], sums[HEALING])
    into.CRIT = Tenth(sums[CRIT] + sums[SPELL_CRIT])
    into.HIT = Tenth(sums[HIT] + sums[SPELL_HIT])
    record.statsShared = false
    return complete
end

local function ReadSpent()
    local spent = mine.spent
    spent[1], spent[2], spent[3] = 0, 0, 0
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if type(groups) ~= "table" then return end
    wipe(groupIDs)
    for i = 1, math.min(#groups, #spent) do groupIDs[i] = groups[i].groupID end
    local infos = C_Traits.GetGroupCurrencyInfo(configID, groupIDs)
    if type(infos) ~= "table" then return end
    for _, info in ipairs(infos) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        for i = 1, #groupIDs do
            if currency and info.traitNodeGroupID == groupIDs[i] then spent[i] = currency.spent or 0 end
        end
    end
end

local function Best(a, b, c, d)
    local most = a
    if b > most then most = b end
    if c and c > most then most = c end
    if d and d > most then most = d end
    return most
end

local function SpellBest(read)
    local most = 0
    for school = SCHOOLS_FIRST, SCHOOLS_LAST do
        local value = read(school)
        if Secret(value) then return nil end
        if value > most then most = value end
    end
    return most
end

local function ReadMine()
    if C_Secrets.ShouldUnitStatsBeSecret() then return mine.ok end
    local stats = mine.stats
    for i = 1, 5 do
        local _, value = UnitStat("player", i)
        if Secret(value) then return mine.ok end
        stats[i] = Clamp(value, STAT_MAX[i])
    end
    local _, class = UnitClass("player")
    local base, up, down
    if class == "HUNTER" then
        base, up, down = UnitRangedAttackPower("player")
    else
        base, up, down = UnitAttackPower("player")
    end
    local healing, meleeCrit = GetSpellBonusHealing(), GetCritChance()
    local spellDamage, spellCrit = SpellBest(GetSpellBonusDamage), SpellBest(GetSpellCritChance)
    local meleeHit = GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier()
    local spellHit = GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier()
    local _, armor = UnitArmor("player")
    if Secret(base) or Secret(up) or Secret(down) or Secret(healing) or Secret(meleeCrit) or not spellDamage
        or not spellCrit or Secret(meleeHit) or Secret(spellHit) or Secret(armor) then
        return mine.ok
    end
    stats[6] = Clamp(base + up + down, STAT_MAX[6])
    stats[7] = Clamp(Best(spellDamage, healing), STAT_MAX[7])
    stats[8] = Clamp(Best(meleeCrit, spellCrit) * 10, STAT_MAX[8])
    stats[9] = Clamp(Best(meleeHit, spellHit) * 10, STAT_MAX[9])
    stats[10] = Clamp(armor, STAT_MAX[10])
    ReadSpent()
    mine.ok = true
    return true
end

local function Apply(guid, from)
    local record = GI.Member(guid)
    if type(record) ~= "table" then return end
    local into = record.stats
    if type(into) ~= "table" then
        into = {}
        record.stats = into
    end
    local stats = from.stats
    for i = 1, #STAT_KEYS do
        local key = STAT_KEYS[i]
        into[key] = TENTHS[key] and stats[i] / 10 or stats[i]
    end
    local talents = record.talents
    if type(talents) ~= "table" then
        talents = {}
        record.talents = talents
    end
    if type(talents.spent) ~= "table" then talents.spent = {} end
    local spent, best, most = from.spent, nil, 0
    for i = 1, #spent do
        talents.spent[i] = spent[i]
        if spent[i] > most then best, most = i, spent[i] end
    end
    local key = best and record.classFile and SW.TreeSpec(record.classFile, best)
    local spec = key and SW.Spec(key)
    talents.tree = spec and spec.name or nil
    talents.role = best and (ROLE[key or ""] or DAMAGE) or nil
    record.statsShared, record.hasNF = true, true
    record.nfVersion = from == mine and version or from.version
    record.updated = GetTime()
    if GI.Changed then GI.Changed(guid) end
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
    local stats, spent = mine.stats, mine.spent
    C_ChatInfo.SendAddonMessage(PREFIX, ANSWER_FORMAT:format(own, version, spent[1], spent[2], spent[3],
        stats[1], stats[2], stats[3], stats[4], stats[5], stats[6], stats[7], stats[8], stats[9], stats[10]), channel)
    lastAnswer = GetTime()
end

local function AnswerNow()
    answerQueued = false
    SendMine()
end

local function Spread()
    local tenths = channel == "PARTY" and PARTY_SPREAD or RAID_SPREAD
    return math.random(1, tenths) / 10
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

local function Number(text, index, into, most)
    local value = tonumber(text)
    if not value or value ~= value or value > most then return false end
    into[index] = value
    return true
end

local function Parse(message)
    local guid, ver, t1, t2, t3, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10 = message:match(ANSWER_PATTERN)
    if not guid or #ver > MAX_VERSION then return nil end
    local spent, stats = parsed.spent, parsed.stats
    if not (Number(t1, 1, spent, MAX_POINTS) and Number(t2, 2, spent, MAX_POINTS) and Number(t3, 3, spent, MAX_POINTS))
        or spent[1] + spent[2] + spent[3] > MAX_POINTS then
        return nil
    end
    if not (Number(s1, 1, stats, STAT_MAX[1]) and Number(s2, 2, stats, STAT_MAX[2]) and Number(s3, 3, stats, STAT_MAX[3])
        and Number(s4, 4, stats, STAT_MAX[4]) and Number(s5, 5, stats, STAT_MAX[5]) and Number(s6, 6, stats, STAT_MAX[6])
        and Number(s7, 7, stats, STAT_MAX[7]) and Number(s8, 8, stats, STAT_MAX[8]) and Number(s9, 9, stats, STAT_MAX[9])
        and Number(s10, 10, stats, STAT_MAX[10])) then
        return nil
    end
    parsed.version = ver
    return guid
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
    if key == "enabled" or key == "groupInspectShare" then Listen() end
end)
hooksecurefunc(ns, "Apply", Listen)
frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnEvent)
Toggle("PLAYER_ENTERING_WORLD", true)

GI._ShareTest = { OnEvent = OnEvent, Parse = Parse, parsed = parsed, mine = mine, ReadMine = ReadMine,
    Listen = Listen, registered = registered, PREFIX = PREFIX }
