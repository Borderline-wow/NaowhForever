-- Senders.lua: whether an addon message's sender is who it says (ns.SenderIs, ns.SenderIsUnit, ns.InGuild).
local ns = _G.NaowhForever

local DASH, SPACE = 45, 32
local PARTY_OTHERS, RAID_SIZE = 4, 40
local GROUP = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local PARTY_UNITS, RAID_UNITS = { "player" }, {}
for i = 1, PARTY_OTHERS do PARTY_UNITS[i + 1] = "party" .. i end
for i = 1, RAID_SIZE do RAID_UNITS[i] = "raid" .. i end

local guildGUID, guildMember = {}, {}
local guildStale = true
local guildEvents

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Readable(v)
    return type(v) == "string" and v ~= "" and not Secret(v)
end

local function OwnRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return Readable(realm) and realm or nil
end

local function Strip(name, realm)
    local n, r = #name, realm and #realm or 0
    if realm and n > r + 1 and name:byte(n - r) == DASH and name:find(realm, n - r + 1, true) == n - r + 1 then
        return name:sub(1, n - r - 1)
    end
    return name
end

local function NameIs(name, first, second, realm)
    if not Readable(first) then return false end
    if name == first then return not Readable(second) or second == realm end
    if not Readable(second) then return false end
    local n = #first
    if #name ~= n + 1 + #second then return false end
    local sep = name:byte(n + 1)
    return (sep == DASH or sep == SPACE) and name:find(first, 1, true) == 1
        and name:find(second, n + 2, true) == n + 2
end

local function GroupUnit(guid)
    local raid = IsInRaid and IsInRaid()
    local units = raid and RAID_UNITS or PARTY_UNITS
    local count = raid and GetNumGroupMembers() or ((GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) + 1)
    for i = 1, math.min(count, #units) do
        local unit = units[i]
        local g = UnitGUID(unit)
        if g and not Secret(g) and g == guid then return unit end
    end
end

local function InGroup(sender, guid)
    local unit = GroupUnit(guid)
    if not unit then return false end
    if not UnitFullName then return false end
    local first, second = UnitFullName(unit)
    if Secret(first) or Secret(second) then return false end
    local realm = OwnRealm()
    return NameIs(sender, first, second, realm) or NameIs(Strip(sender, realm), first, second, realm)
end

local function GuildChanged()
    guildStale = true
end

local function GuildRoster()
    if not guildEvents then
        guildEvents = CreateFrame("Frame")
        guildEvents:SetScript("OnEvent", GuildChanged)
        guildEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
        guildEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
    end
    if not guildStale then return guildGUID end
    guildStale = false
    wipe(guildGUID)
    wipe(guildMember)
    local realm = OwnRealm()
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if Readable(name) and Readable(guid) then
            local short = Strip(name, realm)
            guildGUID[name], guildGUID[short], guildMember[guid] = guid, guid, true
            guildGUID[(short:gsub(" ", "-", 1))], guildGUID[(short:gsub("%-", " ", 1))] = guid, guid
        end
    end
    return guildGUID
end

local function InGuild(sender, guid)
    local roster = GuildRoster()
    local g = roster[sender] or roster[Strip(sender, OwnRealm())]
    return g ~= nil and g == guid
end

local function Friend(sender, guid)
    local info = C_FriendList and C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(sender)
    local g = type(info) == "table" and info.guid
    return Readable(g) and g == guid
end

function ns.InGuild(guid)
    if not Readable(guid) then return false end
    GuildRoster()
    return guildMember[guid] == true
end

function ns.SenderIs(sender, channel, guid)
    if not (Readable(sender) and Readable(channel) and Readable(guid)) then return false end
    if GROUP[channel] then return InGroup(sender, guid) end
    if channel == "GUILD" then return InGuild(sender, guid) end
    if channel == "WHISPER" then return Friend(sender, guid) or InGroup(sender, guid) or InGuild(sender, guid) end
    return false
end

function ns.SenderIsUnit(sender, unit, guid)
    if not (Readable(sender) and Readable(unit) and Readable(guid) and UnitFullName) then return false end
    local g = UnitGUID(unit)
    if not Readable(g) or g ~= guid then return false end
    local first, second = UnitFullName(unit)
    if Secret(first) or Secret(second) then return false end
    local realm = OwnRealm()
    return NameIs(sender, first, second, realm) or NameIs(Strip(sender, realm), first, second, realm)
end

ns._SendersTest = { NameIs = NameIs, Strip = Strip, GuildChanged = GuildChanged }
