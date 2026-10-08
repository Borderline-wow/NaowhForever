-------------------------------------------------------------------------------
--  NaowhForever_ChatZones.lua -- the QoL chat zones: the zone (and level) of whoever speaks in a
--  chat channel, guild chat or a whisper, in front of their message.
--
--  The game never sends a stranger's zone, so a name is only tagged once it shows up in one of:
--  Group Finder results, the guild roster, the friends list, your group, a /who you ran, or an
--  answer from another player running this addon (asked with an addon whisper the first time
--  they speak). A message from someone not yet known goes through untagged.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local PREFIX = "NFZone"
local ASK_EVERY = 600     -- seconds before the same player is asked again
local ANSWER_WAIT = 30    -- seconds an answer to our question is kept after asking
local ANSWER_EVERY = 60   -- seconds before the same player gets another answer
local ANSWERS_MAX, ANSWERS_WINDOW = 10, 10 -- answers we send in all, per window
local ASKERS_MAX = 40
local SEND_EVERY = 1      -- seconds between two addon whispers we send
local MAX_QUEUE = 20
local MAX_ZONE = 48
local SEP = "\t"
local ASK_PATTERN = "^Q\t(Player%-%d+%-%x+)$"
local ANSWER_PATTERN = "^A\t(Player%-%d+%-%x+)\t(%d%d?%d?)\t(.+)$"

local TAGGED = { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER" }

local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local known = {}    -- name -> { zone, level, at }
local asked = {}    -- GUID -> { key, at, open }: the name we whispered, when, and no answer yet
local answered, answeredCount = {}, 0 -- sender -> time we last answered them
local windowAt, sentCount = -ANSWERS_WINDOW, 0
local queue = {}    -- GUIDs waiting to be asked
local looking = {}  -- name -> true while a [Where?] /who for them is out
local sending, filtering = false, false

local function On()
    return S.Get("enabled") and S.Get("chatZones")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- Same-realm players without the realm, others as Name-Realm, so every source keys alike.
local function Key(name)
    if not name or name == "" or Secret(name) then return nil end
    return Ambiguate(name, "none")
end

local function Remember(name, zone, level)
    local key = Key(name)
    if not key or not zone or zone == "" or Secret(zone) then return end
    level = tonumber(level)
    known[key] = { zone = zone, level = level and level > 0 and level or nil, at = GetTime() }
end

local function Fresh(key)
    local entry = key and known[key]
    if entry and GetTime() - entry.at <= S.Get("chatZonesMaxAge") * 60 then return entry end
end

-- The chat event carries the speaker's GUID, which gives their class even for a stranger.
local function ClassColour(guid)
    if not guid or guid == "" or Secret(guid) or not S.Get("chatZonesClassColour") then return nil end
    local _, class = GetPlayerInfoByGUID(guid)
    return class and C_ClassColor.GetClassColor(class)
end

local function Tag(entry, guid)
    local text = "[" .. entry.zone
    if S.Get("chatZonesLevel") and entry.level then text = text .. " " .. entry.level end
    text = text .. "]"
    local colour = ClassColour(guid)
    return (colour and colour:WrapTextInColorCode(text) or ns.Color("muted", text)) .. " "
end

-------------------------------------------------------------------------------
-- Sources the client already has
-------------------------------------------------------------------------------
local function ReadGroupFinder(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info or info.isDelisted then return end
    for i = 1, info.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p then Remember(p.name, p.areaName, p.level) end
    end
end

local function ReadGroupFinderAll()
    local _, results = C_LFGList.GetSearchResults()
    for _, id in ipairs(results or {}) do ReadGroupFinder(id) end
end

local function ReadGuild()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
        if online then Remember(name, zone, level) end
    end
end

local function ReadFriends()
    for i = 1, C_FriendList.GetNumFriends() do
        local f = C_FriendList.GetFriendInfoByIndex(i)
        if f and f.connected then Remember(f.name, f.area, f.level) end
    end
    -- Forever has no character friends list, only Battle.net friends.
    for i = 1, (BNGetNumFriends() or 0) do
        local account = C_BattleNet.GetFriendAccountInfo(i)
        local game = account and account.gameAccountInfo
        if game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID then
            Remember(game.characterName, game.areaName, game.characterLevel)
        end
    end
end

local function ReadGroup()
    for i = 1, GetNumGroupMembers() do
        local name, _, _, level, _, _, zone, online = GetRaidRosterInfo(i)
        if online then Remember(name, zone, level) end
    end
end

local function ReadWho()
    for i = 1, C_FriendList.GetNumWhoResults() do
        local w = C_FriendList.GetWhoInfo(i)
        if w then
            Remember(w.fullName, w.area, w.level)
            local key = Key(w.fullName)
            if key and looking[key] and w.area then
                looking[key] = nil
                ns.Print(("%s is in %s, level %s."):format(key, w.area, tostring(w.level)))
            end
        end
    end
end

-- A /who with one result comes back as a chat line, not a WHO_LIST_UPDATE, so read that too.
-- The game's own format strings become patterns: %d the level, the last %s the zone.
local whoPatterns

local function WhoPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local out = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    out = out:gsub("%%d", "(%%d+)"):gsub("%%s", "(.-)")
    return "^" .. out .. "$"
end

local function ReadWhoLine(msg)
    if not msg or Secret(msg) or not msg:find("|Hplayer:", 1, true) then return end
    whoPatterns = whoPatterns or { WhoPattern(WHO_LIST_GUILD_FORMAT), WhoPattern(WHO_LIST_FORMAT) }
    for _, pattern in ipairs(whoPatterns) do
        local caps = { msg:match(pattern) }
        if #caps >= 6 then
            Remember(caps[1], caps[#caps], caps[3])
            local key = Key(caps[1])
            if key then looking[key] = nil end
            return
        end
    end
end

-------------------------------------------------------------------------------
-- [Where?]: the game only runs a /who from a click or keypress, so a stranger's whisper gets a
-- link to click. "addon:" links reach EventRegistry's SetItemRef inside the click itself.
-------------------------------------------------------------------------------
local LINK = "addon:NaowhForever:where:"

local function WhereLink(key)
    return "|H" .. LINK .. key .. "|h" .. ns.Color("muted", "[Where?]") .. "|h"
end

local function OnLinkClick(_, link)
    if type(link) ~= "string" or link:sub(1, #LINK) ~= LINK then return end
    local key = link:sub(#LINK + 1)
    if key == "" then return end
    looking[key] = true
    C_FriendList.SendWho(('n-"%s"'):format(key:match("^[^-]+")))
end

-------------------------------------------------------------------------------
-- Asking other players who run the addon
-------------------------------------------------------------------------------
local function SendNext()
    local guid = table.remove(queue, 1)
    local entry = guid and asked[guid]
    if entry and On() then
        entry.at, entry.open = GetTime(), true
        C_ChatInfo.SendAddonMessage(PREFIX, "Q" .. SEP .. guid, "WHISPER", entry.key)
    end
    if #queue > 0 then
        C_Timer.After(SEND_EVERY, SendNext)
    else
        sending = false
    end
end

local function Ask(key, guid)
    if Fresh(key) or #queue >= MAX_QUEUE then return end
    if asked[guid] and GetTime() - asked[guid].at < ASK_EVERY then return end
    asked[guid] = { key = key, at = GetTime() }
    queue[#queue + 1] = guid
    if not sending then
        sending = true
        C_Timer.After(0, SendNext)
    end
end

local function MayAnswer(sender, now)
    if now - windowAt >= ANSWERS_WINDOW then windowAt, sentCount = now, 0 end
    if sentCount >= ANSWERS_MAX then return false end
    local last = answered[sender]
    if last and now - last < ANSWER_EVERY then return false end
    if not last then
        if answeredCount >= ASKERS_MAX then
            wipe(answered)
            answeredCount = 0
        end
        answeredCount = answeredCount + 1
    end
    answered[sender] = now
    sentCount = sentCount + 1
    return true
end

-- Ask "Q <their GUID>", answer "A <own GUID> <level> <zone>". An answer is kept only for a
-- question still open, from the player whose chat line carried that GUID.
local function OnAddonMessage(msg, sender)
    if Secret(msg) or Secret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    local to = msg:match(ASK_PATTERN)
    if to then
        if to ~= UnitGUID("player") or not S.Get("chatZonesShare") then return end
        if C_ChatInfo.InChatMessagingLockdown() or not MayAnswer(sender, GetTime()) then return end
        local answer = table.concat({ "A", to, UnitLevel("player"), GetRealZoneText() or "" }, SEP)
        C_ChatInfo.SendAddonMessage(PREFIX, answer, "WHISPER", sender)
        return
    end
    local guid, level, zone = msg:match(ANSWER_PATTERN)
    local entry = guid and asked[guid]
    if not (entry and entry.open) or GetTime() - entry.at > ANSWER_WAIT then return end
    -- Forever's addon message sender is "Name Surname" where the chat author is only "Name".
    if sender ~= entry.key and sender:sub(1, #entry.key + 1) ~= entry.key .. " " then return end
    entry.open = nil
    Remember(entry.key, ns.PlainText(zone, MAX_ZONE), level)
end

-------------------------------------------------------------------------------
-- The chat filter: runs once per chat frame per message, so it only reads and queues.
-------------------------------------------------------------------------------
local function Filter(_, event, msg, author, ...)
    if Secret(msg) or Secret(author) then return false end
    local key = Key(author)
    if not key or key == UnitName("player") then return false end
    local guid = select(10, ...)
    local entry = Fresh(key)
    if not entry then
        if S.Get("chatZonesAsk") and guid and guid ~= "" and not Secret(guid) then Ask(key, guid) end
        if event == "CHAT_MSG_WHISPER" and S.Get("chatZonesWhere") then
            return false, msg .. " " .. WhereLink(key), author, ...
        end
        return false
    end
    return false, Tag(entry, guid) .. msg, author, ...
end

-------------------------------------------------------------------------------
-- The Group Finder window: the leader's zone on each row, every member's zone in the tooltip.
-- Blizzard_GroupFinder_VanillaStyle loads on demand, so its functions are hooked once it has.
-------------------------------------------------------------------------------
local DATA_DISPLAY_SPACE = 160 -- the group data on the right of a row (155 wide, 2 in)
local ROLE_SCALE = 0.75 -- the row's role icons, shrunk to make room for the zone
local rowText = setmetatable({}, { __mode = "k" }) -- search entry -> our zone FontString
local scaled = setmetatable({}, { __mode = "k" })  -- search entries whose role icons we shrank
local tipText = setmetatable({}, { __mode = "k" }) -- tooltip member frame -> our zone FontString
local hooked = false

local function FinderOn()
    return On() and S.Get("chatZonesFinder")
end

local function ZoneString(store, parent, font)
    local fs = store[parent]
    if not fs then
        fs = parent:CreateFontString(nil, "ARTWORK", font)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        store[parent] = fs
    end
    return fs
end

local function LeaderZone(resultID)
    local leader = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(resultID)
    if leader and leader.areaName then return leader.areaName end
    local first = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    return first and first.areaName
end

local function ScaleRoles(entry, on)
    local display = entry.DataDisplay
    if not display or (not on and not scaled[entry]) then return end
    display:SetScale(on and ROLE_SCALE or 1)
    scaled[entry] = on or nil
end

-- The screen x of the leftmost thing shown in a frame: its block is wider than the icons in it.
local LeftmostShown

local function LeftmostOf(best, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region:IsVisible() then
            if region.GetChildren then
                best = LeftmostShown(region, best)
            else
                local left = region:GetLeft()
                if left then
                    left = left * region:GetEffectiveScale()
                    if not best or left < best then best = left end
                end
            end
        end
    end
    return best
end

function LeftmostShown(frame, best)
    return LeftmostOf(LeftmostOf(best, frame:GetRegions()), frame:GetChildren())
end

local function UpdateRow(entry)
    ScaleRoles(entry, FinderOn())
    local zone = FinderOn() and entry.resultID and entry:IsShown() and LeaderZone(entry.resultID)
    if not zone or zone == "" or Secret(zone) then
        if rowText[entry] then rowText[entry]:Hide() end
        return
    end
    local fs = ZoneString(rowText, entry, "GameFontDisableSmallLeft")
    -- Forever's rows differ from Classic Era's; match the activity line's font and centre on it.
    local path, size, flags = entry.ActivityName:GetFont()
    if path then fs:SetFont(path, size, flags) end
    local muted = ns.THEME.muted
    fs:SetTextColor(muted.r, muted.g, muted.b)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", entry.ActivityName, "RIGHT", 8, 0)
    -- Stop short of the role icons: their frame's left edge when laid out, else the template's width.
    -- Measured on screen (the icons are scaled), then back in the row's units.
    local stop = entry.DataDisplay and LeftmostShown(entry.DataDisplay)
    local start = entry.ActivityName:GetRight()
    local width = (stop and start) and ((stop / entry:GetEffectiveScale()) - start - 16)
        or (entry:GetWidth() - DATA_DISPLAY_SPACE - 26 - entry.ActivityName:GetStringWidth())
    fs:SetWidth(math.max(1, width))
    fs:SetText(zone)
    fs:Show()
end

-- The rightmost edge of a member line (level or role icons), so the zones line up in a column.
local function LineRight(row)
    local right = row.Level and row.Level:IsShown() and row.Level:GetRight() or 0
    for _, icon in ipairs(row.Roles or {}) do
        if icon:IsShown() and icon:GetRight() then right = math.max(right, icon:GetRight()) end
    end
    return right
end

local function UpdateTooltip(tip, resultID)
    for _, fs in pairs(tipText) do fs:Hide() end
    local info = FinderOn() and resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not info then return end
    local zones = {}
    for i = 1, info.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        if p and p.name and p.areaName and not Secret(p.areaName) then zones[p.name] = p.areaName end
    end
    local rows = {}
    if tip.Leader and tip.Leader:IsShown() then rows[1] = tip.Leader end
    if tip.memberPool then
        for frame in tip.memberPool:EnumerateActive() do rows[#rows + 1] = frame end
    end
    local right = 0
    for _, row in ipairs(rows) do right = math.max(right, LineRight(row)) end
    if right == 0 then return end
    local widest = 0
    for _, row in ipairs(rows) do
        -- The game sends only the leader's zone; other members show one if we know it elsewhere.
        local name = row.Name and row.Name:GetText()
        local key = Key(name)
        local cached = key and Fresh(key)
        local zone = name and zones[name] or cached and cached.zone
        local left = row:GetLeft()
        if zone and left then
            local fs = ZoneString(tipText, row, "GameFontHighlightSmallLeft")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", right - left + 8, 0)
            fs:SetText(zone)
            fs:Show()
            widest = math.max(widest, fs:GetStringWidth())
        end
    end
    local tipLeft = tip:GetLeft()
    if widest > 0 and tipLeft then
        local need = right - tipLeft + 8 + widest + 11
        if tip:GetWidth() < need then tip:SetWidth(need) end
    end
end

local function HookFinder()
    if hooked or not _G.LFGBrowseSearchEntry_Update then return end
    hooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
    if _G.LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", UpdateTooltip)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == PREFIX and channel == "WHISPER" then OnAddonMessage(msg, sender) end
    elseif event == "ADDON_LOADED" then
        HookFinder()
        if hooked then events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        ReadGroupFinderAll()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        ReadGroupFinder(...)
    elseif event == "GUILD_ROSTER_UPDATE" then
        ReadGuild()
    elseif event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
        ReadFriends()
    elseif event == "GROUP_ROSTER_UPDATE" then
        ReadGroup()
    elseif event == "WHO_LIST_UPDATE" then
        ReadWho()
    elseif event == "CHAT_MSG_SYSTEM" then
        ReadWhoLine(...)
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        -- A guildmate's zone may have changed since the last roster; the game throttles this.
        local key = Key(select(2, ...))
        if key and not Fresh(key) and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    wipe(queue)
    if filtering then
        for _, event in ipairs(TAGGED) do RemoveFilter(event, Filter) end
        filtering = false
    end
    if not FinderOn() then
        for _, fs in pairs(rowText) do fs:Hide() end
        for entry in pairs(scaled) do ScaleRoles(entry, false) end
    end
    EventRegistry:UnregisterCallback("SetItemRef", events)
    if not On() then
        wipe(known)
        wipe(looking)
        return
    end
    EventRegistry:RegisterCallback("SetItemRef", OnLinkClick, events)
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    for _, event in ipairs({ "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
        "GROUP_ROSTER_UPDATE", "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }) do
        events:RegisterEvent(event)
    end
    if C_LFGList and C_LFGList.GetSearchResultPlayerInfo then
        events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    end
    for _, event in ipairs(TAGGED) do AddFilter(event, Filter) end
    filtering = true
    if FinderOn() then
        HookFinder()
        if not hooked then events:RegisterEvent("ADDON_LOADED") end
    end
    if IsInGuild() then ReadGuild() end
    ReadFriends()
    ReadGroup()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "chatZones" or key == "chatZonesFinder" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Group = ns.Shared.Settings.Group

ns.Shared.Settings.Page("QoL/Interface", S):Card({
    id = "chatZones", name = "Chat Zones", order = 60, switch = "chatZones",
    help = "The zone of whoever speaks in a chat channel, guild chat or a whisper, in front of their "
        .. "message. The game never says where a stranger is, so a player is tagged once they are "
        .. "in the Group Finder, your guild, your friends or your group, came up in a /who, or "
        .. "answered from their own copy of Naowh Forever. Their first message may come through "
        .. "untagged.",
    rows = {
        Group("Tags"),
        { key = "chatZonesLevel", label = "Show Level", toggle = true },
        { key = "chatZonesClassColour", label = "Class Colour", toggle = true,
          help = "The tag in the speaker's class colour. Off, it is grey." },
        { key = "chatZonesMaxAge", label = "Forget After", slider = { 1, 60, 1 }, unit = " min",
          help = "A zone older than this is no longer shown, since the player has likely moved on." },
        { key = "chatZonesWhere", label = "Where? on Whispers", toggle = true,
          help = "A [Where?] link after a whisper from someone whose zone is not known. Clicking it "
              .. "runs a /who for them and prints their zone; their next messages are tagged." },
        Group("Group Finder"),
        { key = "chatZonesFinder", label = "Zones in Group Finder", toggle = true,
          help = "The leader's zone on each Group Finder listing, and every member's zone when you "
              .. "hover it." },
        Group("Other Players"),
        { key = "chatZonesAsk", label = "Ask Other Players", toggle = true,
          help = "The first time someone speaks, ask their Naowh Forever for their zone with a hidden "
              .. "addon whisper. Players without it never see the question." },
        { key = "chatZonesShare", label = "Share My Zone", toggle = true,
          help = "Tell other Naowh Forever players your zone and level when they ask. Off, you can "
              .. "still ask them; they just learn nothing back." },
    },
})
