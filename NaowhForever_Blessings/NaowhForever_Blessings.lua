-------------------------------------------------------------------------------
--  NaowhForever_Blessings.lua -- paladin blessings: a blessing per class, or per
--  player where one needs something else, shared with the group's other paladins running
--  Naowh Forever, and a bar that casts it. A class button blesses the next member of that
--  class who needs it; the player list blesses one person. Aura and Righteous Fury buttons
--  sit at the front. The group leader and assistants can set every paladin's plan. The
--  settings card's preview (BlessingsPage) shares the bar's look, tooltips and menus.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts = ns.Shared.Parts

local PREFIX = "NaowhBless"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local VALID_CLASS = {}
for _, class in ipairs(CLASSES) do VALID_CLASS[class] = true end

-- Ranks lowest first, from Forever's spell data (build 1.60.1.69913). Codes are what a plan
-- is sent as.
local BLESSINGS = {
    { key = "might", code = "m", ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, greater = { 25782, 25916 } },
    { key = "wisdom", code = "w", ranks = { 19742, 19850, 19852, 19853, 19854, 25290 }, greater = { 25894, 25918 } },
    { key = "kings", code = "k", ranks = { 20217 }, greater = { 25898 } },
    { key = "salvation", code = "s", ranks = { 1038 }, greater = { 25895 } },
    { key = "light", code = "l", ranks = { 19977, 19978, 19979 }, greater = { 25890 } },
}
local AURAS = {
    { key = "devotion", code = "D", ranks = { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
    { key = "retribution", code = "R", ranks = { 7294, 10298, 10299, 10300, 10301 } },
    { key = "concentration", code = "C", ranks = { 19746 } },
    { key = "shadow", code = "S", ranks = { 19876, 19895, 19896 } },
    { key = "frost", code = "F", ranks = { 19888, 19897, 19898 } },
    { key = "fire", code = "I", ranks = { 19891, 19899, 19900 } },
    { key = "sanctity", code = "T", ranks = { 20218 } },
}
local FURY = { key = "fury", ranks = { 25780 } }

local BY_KEY, BY_CODE, FAMILY, IDS, GREATER = {}, {}, {}, {}, {}
local function Index(entry)
    BY_KEY[entry.key] = entry
    if entry.code then BY_CODE[entry.code] = entry end
    IDS[entry.key] = {}
    for _, id in ipairs(entry.ranks) do FAMILY[id] = entry.key; IDS[entry.key][id] = true end
    for _, id in ipairs(entry.greater or {}) do
        FAMILY[id] = entry.key
        IDS[entry.key][id] = true
        GREATER[id] = true
    end
end
for _, entry in ipairs(BLESSINGS) do entry.blessing = true; Index(entry) end
for _, entry in ipairs(AURAS) do Index(entry) end
Index(FURY)

local EXPIRING = 300          -- seconds left that count as due for a refresh
local SYMBOL_OF_KINGS = 21177 -- the reagent every Greater Blessing uses
local QUESTION = 134400
local RED = { r = 0.97, g = 0.27, b = 0.27 }
local YELLOW = { r = 1, g = 0.85, b = 0.3 }
local BLUE = { r = 0.35, g = 0.6, b = 1 }
local ICON_BORDER = { r = 0, g = 0, b = 0 }
local MARK_SIZE, LABEL_SIZE, LABEL_MIN = 14, 10, 7
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local AURA_TIP = "Left-click: cast your aura.\nRight-click: choose it."
local FURY_TIP = "Left-click: cast it on yourself."

local others = {}             -- paladin name (realm when not ours) -> { classes, aura, known }
local bar, cells, flyout, rows, auraButton, furyButton, keyNext, keyGreater, secureHandler
local flyoutClass, dirty, ticker, unlocked
local buildAfterCombat, broadcastAfterCombat

local function On()
    return S.Get("blessings")
end

local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

-- Unit identity and auras can come back secret in restricted content; those are skipped.
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function HighestKnown(ids)
    for i = #ids, 1, -1 do
        if C_SpellBook.IsSpellKnown(ids[i]) then return ids[i] end
    end
end

local function Learned(entry)
    return HighestKnown(entry.ranks) or (entry.greater and HighestKnown(entry.greater))
end

local function SpellName(key)
    local entry = BY_KEY[key]
    return entry and C_Spell.GetSpellName(entry.ranks[1]) or key
end

local function SpellIcon(key)
    local entry = BY_KEY[key]
    return entry and C_Spell.GetSpellTexture(entry.ranks[1]) or QUESTION
end

local function ClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE[class] or class
end

-- Forever names carry a surname: UnitName gives only the first name ("Glyadin"), while
-- UnitFullName and addon message senders give the whole one ("Glyadin Skywolf").
local function MyName()
    return (UnitFullName("player"))
end

local function Store()
    local account = ns.AccountSettings()
    account.blessings = account.blessings or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    local store = account.blessings[key]
    -- Before per-player choices and auras this held only { CLASS = blessing }.
    if not (store and store.classes) then
        local classes = {}
        for class, blessing in pairs(store or {}) do
            if VALID_CLASS[class] and BY_KEY[blessing] then classes[class] = blessing end
        end
        store = { classes = classes, players = {} }
        account.blessings[key] = store
    end
    return store
end

-------------------------------------------------------------------------------
--  The group
-------------------------------------------------------------------------------
local function Readable(v)
    return not Secret(v) and v ~= nil and v ~= ""
end

-- The names a group header can know a member by: it matches nameList against UnitName in a
-- party and GetRaidRosterInfo in a raid, which on Forever can be the first name alone.
-- A name two members share (two of them "Bob" to the header) is left out for both, so the
-- header cannot pick the wrong one; the class buttons skip them (targetable false).
local function HeaderNames(member, realm, firstNames, raid)
    local seen, out = {}, {}
    local function Add(name)
        if Readable(name) and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    for _, name in ipairs(member.candidates) do
        if firstNames[name] == 1 then Add(name) end
    end
    if not member.who:find("-", 1, true) then Add(member.who .. "-" .. realm) end
    -- The name the header itself compares (UnitName, with the server, in a party).
    local seenBy
    if raid then
        seenBy = member.rosterName
    elseif Readable(member.short) then
        seenBy = Readable(member.server) and member.short .. "-" .. member.server or member.short
    end
    return table.concat(out, ","), Readable(seenBy) and seen[seenBy] == true
end

-- Names as addon message senders carry them: the realm only when it is not ours.
local function Roster()
    local units = { "player" }
    local raid = IsInRaid()
    if raid then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    local realm = GetNormalizedRealmName()
    local list, firstNames = {}, {}
    for i, unit in ipairs(units) do
        local name, unitRealm = UnitFullName(unit)
        local _, class = UnitClass(unit)
        local guid = UnitGUID(unit)
        -- A member whose data has not arrived yet reads "Unknown" with no class; the next
        -- roster or aura update picks them up.
        if name and not (Secret(name) or Secret(unitRealm) or Secret(class) or Secret(guid)) and class then
            local who = name
            if unitRealm and unitRealm ~= "" and unitRealm ~= realm then who = name .. "-" .. unitRealm end
            local short, server = UnitName(unit)
            local member = { unit = unit, guid = guid, class = class, who = who, short = short,
                server = server, rosterName = raid and (GetRaidRosterInfo(i)) or nil }
            -- Every name the header could compare for them, each counted once per member.
            local names = { who, short, member.rosterName }
            if Readable(short) and Readable(server) then names[4] = short .. "-" .. server end
            member.candidates = {}
            local counted = {}
            for k = 1, 4 do
                local n = names[k]
                if Readable(n) and not counted[n] then
                    counted[n] = true
                    firstNames[n] = (firstNames[n] or 0) + 1
                    member.candidates[#member.candidates + 1] = n
                end
            end
            list[#list + 1] = member
        end
    end
    for _, member in ipairs(list) do
        member.names, member.targetable = HeaderNames(member, realm, firstNames, raid)
    end
    return list
end

local function InGroup(who)
    for _, member in ipairs(Roster()) do
        if member.who == who then return member end
    end
end

local function CanAssign(unit)
    local lead, assist = UnitIsGroupLeader(unit), UnitIsGroupAssistant(unit)
    return not (Secret(lead) or Secret(assist)) and (lead or assist)
end

local function Assigned(member)
    local store = Store()
    return store.players[member.guid] or store.classes[member.class]
end

-- A Greater Blessing reaches the whole class, so it is only cast when everyone in the class
-- is down for the same blessing; otherwise the single one, so nobody's own choice is replaced.
local function CastSpell(key, members)
    local entry = BY_KEY[key]
    local greater = C_Item.GetItemCount(SYMBOL_OF_KINGS) > 0 and HighestKnown(entry.greater)
    if greater then
        for _, member in ipairs(members) do
            if Assigned(member) ~= key then greater = nil break end
        end
    end
    return greater or HighestKnown(entry.ranks)
end

local memoAt
local memo, scratch = {}, {}

local function BeginAuraMemo()
    memoAt = GetTime()
    for _, seen in pairs(memo) do seen.stale = true end
end

local function EndAuraMemo()
    memoAt = nil
end

local function Found(v)
    if v == true then return true end
    return true, v - GetTime()
end

-- Present, with the time left when it runs out; nil when unreadable. Aura access can be
-- withdrawn outside combat lockdown too (seen on boss pulls), and GetAuraDataByIndex then
-- raises instead of returning nil, so the restriction is checked before the call.
local function BuffState(unit, key)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local seen
    if memoAt and memoAt == GetTime() then
        seen = memo[unit]
        if not seen then seen = {}; memo[unit] = seen end
        if seen.stale then wipe(seen) end
    else
        wipe(scratch)
        seen = scratch
    end
    local v = seen[key]
    if v then return Found(v) end
    if seen.ended == "none" then return false end
    if seen.ended then return nil end
    for i = seen.next or 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then seen.ended = "none" return false end
        local id = aura.spellId
        if Secret(id) then seen.ended = "secret" return nil end
        local family = FAMILY[id]
        if family and seen[family] == nil then
            local expires = aura.expirationTime
            seen[family] = (Secret(expires) or not expires or expires == 0) and true or expires
        end
        if family and family == key then
            seen.next = i + 1
            return Found(seen[family])
        end
    end
    seen.ended = "none"
    return false
end

-- true in range, false out of it, nil when the game gives no answer (left to the cast). A
-- secret answer counts as no answer.
local function InRange(member, spell)
    if member.guid == UnitGUID("player") then return true end
    local inRange = C_Spell.IsSpellInRange(spell, member.unit)
    if Secret(inRange) then return nil end
    return inRange
end

local function ByUrgency(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.left < b.left
end

-- Who a class button blesses, in order: missing first, then running out, then whoever has
-- the least left, skipping anyone dead, offline or out of range. Also the class summary, with
-- how many of those in range are missing it or running out (only they light the button),
-- and how many of those are on the class blessing rather than their own.
local function Survey(members)
    local s = { missing = 0, reachable = false, missingNear = 0, expiringNear = 0, classDue = 0,
        classMissing = 0, queue = {} }
    local rank, left
    local queue = s.queue
    local players = Store().players
    local spells = {}
    for _, member in ipairs(members) do
        local key = Assigned(member)
        if key and spells[key] == nil then spells[key] = CastSpell(key, members) or false end
        local spell = key and spells[key]
        if spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit) then
            local has, remaining = BuffState(member.unit, key)
            if has == false then
                s.missing = s.missing + 1
                s.shortest = 0
            elseif remaining and (not s.shortest or remaining < s.shortest) then
                s.shortest = remaining
            end
            local range = UnitIsVisible(member.unit) and InRange(member, spell)
            if has ~= nil and range ~= false then
                s.reachable = true
                local r = not has and 0 or (remaining and remaining < EXPIRING and 1 or 2)
                -- Only a member in range the button can reach lights it.
                if range == true and r < 2 and member.targetable then
                    if r == 0 then s.missingNear = s.missingNear + 1 else s.expiringNear = s.expiringNear + 1 end
                    if not players[member.guid] then
                        s.classDue = s.classDue + 1
                        if r == 0 then s.classMissing = s.classMissing + 1 end
                    end
                end
                local l = remaining or math.huge
                if member.targetable then
                    queue[#queue + 1] = { names = member.names, spell = spell, rank = r, left = l }
                    if not s.target or r < rank or (r == rank and l < left) then
                        s.target, s.spell, rank, left = member, spell, r, l
                    end
                end
            end
        end
    end
    table.sort(queue, ByUrgency)
    -- Only those who need it; with nobody due, the one with least left. A Greater Blessing
    -- covers the whole class, so it is cast once.
    local due = 0
    for _, entry in ipairs(queue) do if entry.rank < 2 then due = due + 1 end end
    if GREATER[queue[1] and queue[1].spell] then due = math.min(due, 1) end
    for i = #queue, math.max(due, 1) + 1, -1 do queue[i] = nil end
    return s
end

-------------------------------------------------------------------------------
--  Keybinds
-------------------------------------------------------------------------------
-- Next Blessing and Next Greater Blessing, bound in Key Bindings > AddOns (Bindings.xml).
-- Out of combat each key is re-aimed on every refresh; in combat, where buffs cannot be read,
-- it steps through the list it had when the fight began, one press per entry.
local STEP = [[
    local i, n = self:GetAttribute("step") or 1, self:GetAttribute("count") or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. i))
    self:SetAttribute("step", i + 1)
]]

-- A class button's left-click: the next member of its queue, so in combat (where the queue
-- is the one from before the pull) repeated clicks go through those who needed it, round
-- again after the last, as a missed click cannot be told from a cast. The button is its group
-- header's child, and the header finds that member by name, wherever the raid has moved them.
-- One the header no longer finds (they left) leaves the button without a unit, and a spell
-- with none would go to the current target, so they are skipped.
local CLASS_STEP = [[
    if button ~= "LeftButton" then return end
    local n = self:GetAttribute("count") or 0
    local i = self:GetAttribute("step") or 1
    local header = self:GetParent()
    if not header:IsVisible() then return false end
    for _ = 1, n do
        if i > n then i = 1 end
        header:SetAttribute("nameList", self:GetAttribute("queueNames" .. i))
        if self:GetAttribute("unit") then
            self:SetAttribute("spell1", self:GetAttribute("queueSpell" .. i))
            self:SetAttribute("step", i + 1)
            return
        end
        i = i + 1
    end
    return false
]]

local function NewKeyButton(name, handler)
    local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    -- Key down only, so a press casts and steps once whatever ActionButtonUseKeyDown is set to.
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("useOnKeyDown", true)
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("count", 0)
    SecureHandlerWrapScript(btn, "OnClick", handler, STEP)
    return btn
end

-- Due for a blessing: missing first, then under the refresh time, by time left.
local function Due(member, key, spell)
    if not (spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit)
        and UnitIsVisible(member.unit) and InRange(member, spell) ~= false) then return end
    local has, remaining = BuffState(member.unit, key)
    if has == false then return 0, 0 end
    if has and remaining and remaining < EXPIRING then return 1, remaining end
end

local function SetQueue(btn, list)
    table.sort(list, ByUrgency)
    for i, entry in ipairs(list) do
        btn:SetAttribute("unit" .. i, entry.unit)
        btn:SetAttribute("spell" .. i, entry.spell)
    end
    btn:SetAttribute("count", #list)
    btn:SetAttribute("step", 1)
end

local function ClearKeys()
    if keyNext then keyNext:SetAttribute("count", 0) end
    if keyGreater then keyGreater:SetAttribute("count", 0) end
end

-- The single blessing for everyone due, and a Greater one per class whose members all share
-- its blessing, cast on the most urgent of them.
local function FillKeys(byClass)
    local single, greater = {}, {}
    local symbols = C_Item.GetItemCount(SYMBOL_OF_KINGS) > 0
    for _, class in ipairs(CLASSES) do
        local members = byClass[class]
        if members then
            local shared = Store().classes[class]
            for _, member in ipairs(members) do
                local key = Assigned(member)
                if key ~= shared then shared = nil end
                local spell = key and HighestKnown(BY_KEY[key].ranks)
                local rank, left = Due(member, key, spell)
                if rank then single[#single + 1] = { unit = member.unit, spell = spell, rank = rank, left = left } end
            end
            local spell = shared and symbols and HighestKnown(BY_KEY[shared].greater)
            local best
            for _, member in ipairs(spell and members or {}) do
                local rank, left = Due(member, shared, spell)
                if rank and (not best or ByUrgency({ rank = rank, left = left }, best)) then
                    best = { unit = member.unit, spell = spell, rank = rank, left = left }
                end
            end
            greater[#greater + 1] = best
        end
    end
    SetQueue(keyNext, single)
    SetQueue(keyGreater, greater)
end

-------------------------------------------------------------------------------
--  Sharing plans
-------------------------------------------------------------------------------
-- A plan travels as ten characters: a blessing code per class in CLASSES order, then the
-- aura's, "-" for none.
local function EncodePlan(classes, aura)
    local out = {}
    for i, class in ipairs(CLASSES) do
        out[i] = classes[class] and BY_KEY[classes[class]].code or "-"
    end
    out[#out + 1] = aura and BY_KEY[aura].code or "-"
    return table.concat(out)
end

local function DecodePlan(text)
    if #text ~= #CLASSES + 1 then return end
    local classes = {}
    for i, class in ipairs(CLASSES) do
        local c = text:sub(i, i)
        if c ~= "-" then
            local entry = BY_CODE[c]
            if not (entry and entry.blessing) then return end
            classes[class] = entry.key
        end
    end
    local c = text:sub(-1)
    if c == "-" then return classes end
    local entry = BY_CODE[c]
    if entry and not entry.blessing then return classes, entry.key end
end

local function KnownCodes()
    local codes = {}
    for _, entry in ipairs(BLESSINGS) do if Learned(entry) then codes[#codes + 1] = entry.code end end
    for _, entry in ipairs(AURAS) do if Learned(entry) then codes[#codes + 1] = entry.code end end
    return table.concat(codes)
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Nothing is sent in combat. What would have been is kept, the latest per kind and target,
-- and sent once combat ends.
local pending = {}

local function Send(msg, key)
    if InCombatLockdown() then
        pending[key or msg] = msg
        return
    end
    local channel = Channel()
    if channel then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
end

local function SendPending()
    for key, msg in pairs(pending) do
        pending[key] = nil
        Send(msg)
    end
end

-- Per-player choices for members of the group, as GUID=code pairs. "P|1|" starts the list
-- over, so an empty one clears what the others had.
local PLAYER_BATCH = 200
local MAX_PLAYER_CHOICES = 40
local sentPlayers

local function SendPlayers()
    local players = Store().players
    local parts, n, chunk = {}, 1, ""
    for _, member in ipairs(Roster()) do
        local key = players[member.guid]
        if key then
            local part = member.guid .. "=" .. BY_KEY[key].code
            if #chunk + #part > PLAYER_BATCH then
                parts[#parts + 1] = chunk
                chunk = ""
            end
            chunk = chunk == "" and part or chunk .. "," .. part
        end
    end
    parts[#parts + 1] = chunk
    if chunk == "" and #parts == 1 and not sentPlayers then return end
    sentPlayers = chunk ~= "" or #parts > 1
    for _, body in ipairs(parts) do
        Send("P|" .. n .. "|" .. body, "P|" .. n)
        n = n + 1
    end
end

local function Broadcast()
    if not IsPaladin() then return end
    if InCombatLockdown() then
        broadcastAfterCombat = true
        return
    end
    local store = Store()
    Send("F|" .. EncodePlan(store.classes, store.aura) .. "|" .. KnownCodes())
    SendPlayers()
end

-- Every client asks on a roster change, so answers are batched into one send.
local broadcastQueued
local function BroadcastSoon()
    if broadcastQueued then return end
    broadcastQueued = true
    C_Timer.After(1, function()
        broadcastQueued = false
        Broadcast()
    end)
end

local Refresh

local function Changed()
    Refresh()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

-- Parsed as data: only valid codes from a paladin in the group are kept, and only the
-- leader or an assistant can set someone else's plan.
local function OnMessage(msg, sender)
    local who = Ambiguate(sender, "none")
    if who == MyName() then return end
    if msg == "R" then
        BroadcastSoon()
        return
    end
    local target, plan = msg:match("^S|([^|]+)|(%S+)$")
    if target then
        local from = InGroup(who)
        local classes, aura = DecodePlan(plan)
        if not (IsPaladin() and classes and from and CanAssign(from.unit)
                and target == MyName() .. "-" .. GetNormalizedRealmName()) then
            return
        end
        local store = Store()
        store.classes = {}
        for class, key in pairs(classes) do
            if Learned(BY_KEY[key]) then store.classes[class] = key end
        end
        store.aura = aura and Learned(BY_KEY[aura]) and aura or nil
        ns.Print(who .. " updated your blessings.")
        BroadcastSoon()
        Changed()
        return
    end
    local part, list = msg:match("^P|(%d+)|(.*)$")
    if part then
        local from = others[who]
        if not from then return end
        if part == "1" then from.players, from.choices = {}, 0 end
        for guid, code in list:gmatch("(Player%-[%w%-]+)=(%a)") do
            local entry = BY_CODE[code]
            local choices = from.choices or 0
            if entry and entry.blessing and (from.players[guid] or choices < MAX_PLAYER_CHOICES) then
                if not from.players[guid] then from.choices = choices + 1 end
                from.players[guid] = entry.key
            end
        end
        if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
        return
    end
    local body, known = msg:match("^F|(%S+)|(%a*)$")
    local member = body and InGroup(who)
    if not (member and member.class == "PALADIN") then return end
    local classes, aura = DecodePlan(body)
    if not classes then return end
    local set = {}
    for code in known:gmatch(".") do
        if BY_CODE[code] then set[BY_CODE[code].key] = true end
    end
    local was = others[who]
    others[who] = { classes = classes, aura = aura, known = set, players = was and was.players or {},
        choices = was and was.choices or 0 }
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

-------------------------------------------------------------------------------
--  Buff display in combat
-------------------------------------------------------------------------------
-- Blizzard's managed aura display draws a buff's presence and time left, in combat too,
-- without addon code reading secret aura data. The frame under it stays red, so only a
-- missing buff shows red. Forever may not ship the display, so it is optional.
local watchUnavailable

local function Watch(frame)
    if watchUnavailable then return end
    local ok, container = pcall(function()
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        local c = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
        c:SetAllPoints(frame)
        c:SetFrameLevel(frame:GetFrameLevel() + 2)
        c:EnableMouse(false)
        c:AddAuraSlot("buff", "HELPFUL", {
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = function(button)
                -- Over the button's own icon, so its black border still shows. Not PixelInset:
                -- a Blizzard aura button's IsVisible is secret, and refitting it raises.
                button:SetAllPoints(frame.icon)
                button:EnableMouse(false)
                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                button:SetIcon(icon)
                local text = button:CreateFontString(nil, "OVERLAY")
                Parts.HudFont(text, S.Get("blessFont"), S.Get("blessTimerSize"), S.Get("blessOutline"))
                frame.watchText = text
                text:SetPoint("BOTTOM", 0, 1)
                button:SetDurationText(text, {})
            end,
        })
        c:SetEnabled(false)
        return c
    end)
    if not ok then
        watchUnavailable = true
        return
    end
    frame.watch = container
end

local function SetWatch(frame, unit, key)
    local c = frame.watch
    if not c or (frame.watchUnit == unit and frame.watchKey == key) then return end
    frame.watchUnit, frame.watchKey = unit, key
    c:SetUnit(unit or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = key and IDS[key] or {} })
    c:SetEnabled(unit ~= nil and key ~= nil)
end

local Look = {}
Look.RED, Look.YELLOW, Look.BLUE, Look.HIGHLIGHT = RED, YELLOW, BLUE, HIGHLIGHT

-- What each status colour paints with: itself, or with Apply Theme to Status Colours the
-- theme's Accent for missing, its lighter Accent for running out and a deeper shade of it for
-- players on their own blessing.
local tints = { [RED] = RED, [YELLOW] = YELLOW, [BLUE] = BLUE }
local deepAccent

-- Every icon on the bar: the art inset 1px inside the house black border.
function Look.Icon(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(frame.icon, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(frame, ICON_BORDER)
    frame.mark = ns.Font(frame, MARK_SIZE, "OUTLINE", RED)
    frame.mark:SetPoint("CENTER")
    frame.timer = ns.Font(frame, 10, "OUTLINE")
    frame.timer:SetPoint("BOTTOM", 0, 1)
end

function Look.Label(cell, class)
    cell.label = ns.Font(cell, LABEL_SIZE, "OUTLINE")
    cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    cell.label:SetWordWrap(false)
    cell.labelText = ClassName(class)
    cell.label:SetText(cell.labelText)
end

-- The first n letters of a name, in whole UTF-8 characters so a localized name never splits.
local function Shorten(text, n)
    local count = 0
    for at in text:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > n then return text:sub(1, at - 1) end
    end
    return text
end

-- Each name gets its own slot under the bar, the button plus the gap after it. A name too
-- long for it first shrinks, down to LABEL_MIN, then drops to its first three letters at
-- that size, and is cut off if even that is too long, so neighbours never run into each other.
local function FitLabel(label, text, width, font, outline)
    Parts.HudFont(label, font, LABEL_SIZE, outline)
    label:SetWidth(0)
    label:SetText(text)
    local full = label:GetUnboundedStringWidth()
    if full <= width then return end
    -- Text width grows with the font size, so this is the size the name just fits at.
    Parts.HudFont(label, font, math.max(LABEL_MIN, math.floor(LABEL_SIZE * width / full)), outline)
    if label:GetUnboundedStringWidth() <= width then return end
    label:SetText(Shorten(text, 3))
    if label:GetUnboundedStringWidth() > width then label:SetWidth(width) end
end

function Look.Read()
    Look.size, Look.gap, Look.groupGap = S.Get("blessBarSize"), S.Get("blessSpacing"), S.Get("blessGroupSpacing")
    Look.timerSize, Look.labels = S.Get("blessTimerSize"), S.Get("blessShowLabels")
    Look.font, Look.outline = S.Get("blessFont"), S.Get("blessOutline")
    if S.Get("blessThemeColors") then
        deepAccent = deepAccent or { r = T.accent.r * 0.6, g = T.accent.g * 0.6, b = T.accent.b * 0.6 }
        tints[RED], tints[YELLOW], tints[BLUE] = T.accent, T.accentSoft, deepAccent
    else
        tints[RED], tints[YELLOW], tints[BLUE] = RED, YELLOW, BLUE
    end
end

function Look.Place(frame, row, x)
    local size = Look.size
    frame:SetSize(size, size)
    local font, outline, missing = Look.font, Look.outline, tints[RED]
    Parts.HudFont(frame.timer, font, Look.timerSize, outline)
    if frame.watchText then Parts.HudFont(frame.watchText, font, Look.timerSize, outline) end
    Parts.HudFont(frame.mark, font, MARK_SIZE, outline)
    frame.mark:SetTextColor(missing.r, missing.g, missing.b)
    if frame.label then
        frame.label:SetShown(Look.labels)
        FitLabel(frame.label, frame.labelText, size + Look.gap, font, outline)
    end
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", row, "LEFT", x, 0)
    frame:Show()
    return x + size + Look.gap
end

function Look.Gap(x)
    if x > 0 then return x + Look.groupGap end
    return x
end

function Look.Width(x)
    return math.max(x - Look.gap, Look.size)
end

function Look.Minutes(seconds)
    if not (seconds and seconds > 0 and S.Get("blessTimers")) then return "" end
    return math.ceil(seconds / 60) .. "m"
end

function Look.Class(cell, colour, reachable, missing, shortest)
    colour = colour and tints[colour]
    cell.icon:SetDesaturated(not reachable)
    cell.icon:SetVertexColor(colour and colour.r or 1, colour and colour.g or 1, colour and colour.b or 1)
    cell.mark:SetText(missing > 0 and missing or "")
    cell.timer:SetText(Look.Minutes(shortest))
end

function Look.Self(frame, missing, remaining)
    local c = tints[RED]
    frame.icon:SetVertexColor(missing and c.r or 1, missing and c.g or 1, missing and c.b or 1)
    frame.mark:SetText(missing and "!" or "")
    frame.timer:SetText(Look.Minutes(remaining))
end

-- The red base and "!" for a missing buff: always, under the managed display when there
-- is one, otherwise from the out-of-combat read.
local function ShowState(frame, key, has, remaining)
    local missing = key ~= nil and (frame.watch ~= nil or has == false)
    Look.Self(frame, missing, not frame.watch and remaining)
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
-- A secure button that follows one named player through raid reordering, even in combat:
-- the group header owns its unit. Headers only build their button while visible, so the
-- parent must be shown when this runs.
local function Recipient(parent, name)
    local header = CreateFrame("Frame", name, parent, "SecureGroupHeaderTemplate")
    header:SetAttribute("template", "NaowhForeverBlessButtonTemplate")
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showSolo", true)
    header:SetAttribute("nameList", "-")
    header:SetAttribute("sortMethod", "NAMELIST")
    header:SetAttribute("point", "TOPLEFT")
    header:SetAttribute("unitsPerColumn", 1)
    header:SetAttribute("maxColumns", 1)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT")
    header:Show()
    local button = header:GetAttribute("child1")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type1", "spell")
    button:SetHighlightTexture(HIGHLIGHT, "ADD")
    return header, button
end

local function SetNames(header, names)
    if header:GetAttribute("nameList") ~= names then header:SetAttribute("nameList", names) end
end

local function SizeRecipient(header, button, size)
    header:SetAttribute("minWidth", size)
    header:SetAttribute("minHeight", size)
    button:SetSize(size, size)
end

local function SetOwn(column, key)
    local store = Store()
    if column == "AURA" then store.aura = key else store.classes[column] = key end
    BroadcastSoon()
    Changed()
end

local function Menu(owner, title, list, current, choose, noneText, can)
    can = can or Learned
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        for _, entry in ipairs(list) do
            if can(entry) then
                root:CreateRadio(SpellName(entry.key), function() return current() == entry.key end,
                    function() choose(entry.key) end)
            end
        end
        root:CreateRadio(noneText, function() return current() == nil end, function() choose(nil) end)
    end)
end

local function OwnAura() return Store().aura end
local function SetAura(key) SetOwn("AURA", key) end

local function AuraMenu(owner)
    Menu(owner, "Aura", AURAS, OwnAura, SetAura, "Default")
end

local ToggleFlyout

local function ClassMenu(owner, class, inSettings)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ClassName(class))
        for _, entry in ipairs(BLESSINGS) do
            if Learned(entry) then
                root:CreateRadio(SpellName(entry.key), function() return Store().classes[class] == entry.key end,
                    function() SetOwn(class, entry.key) end)
            end
        end
        root:CreateRadio("None", function() return Store().classes[class] == nil end,
            function() SetOwn(class, nil) end)
        root:CreateDivider()
        if not inSettings then
            root:CreateCheckbox("Players", function() return flyoutClass == class end,
                function() ToggleFlyout(class) end)
        end
        root:CreateButton("Assignments", function() ns.OpenBlessingsWindow() end)
    end)
end

local function PrepareCell(cell)
    local members = cell.members
    local s = Survey(members)
    local queue = s.queue
    local key = Store().classes[cell.class]
    local shown = s.spell or (key and CastSpell(key, members))
    cell.icon:SetTexture(shown and C_Spell.GetSpellTexture(shown) or QUESTION)
    local parts = {}
    for i, entry in ipairs(queue) do parts[i] = entry.names .. "=" .. entry.spell end
    local signature = table.concat(parts, ";")
    if signature ~= cell.signature then
        cell.signature = signature
        for i, entry in ipairs(queue) do
            cell.cast:SetAttribute("queueNames" .. i, entry.names)
            cell.cast:SetAttribute("queueSpell" .. i, entry.spell)
        end
        cell.cast:SetAttribute("count", #queue)
    end
    cell.cast:SetAttribute("step", 1)
    SetNames(cell.header, queue[1] and queue[1].names or "-")
    cell.target, cell.queued = s.target, #queue
    -- Red: someone in range is missing the class blessing; yellow: only running out; blue: only
    -- players on their own blessing need theirs.
    local color = s.classMissing > 0 and RED or s.classDue > 0 and YELLOW
        or s.missingNear + s.expiringNear > 0 and BLUE or nil
    Look.Class(cell, color, s.reachable, s.missing, s.shortest)
    local glow = s.classMissing > 0 and tints[RED]
    if glow ~= cell.glowing then
        cell.glowing = glow
        local LCG = LibStub("LibCustomGlow-1.0")
        if glow then
            LCG.PixelGlow_Start(cell, { glow.r, glow.g, glow.b, 1 }, 8, nil, nil, 1, 0, 0, nil, "NaowhBless")
        else
            LCG.PixelGlow_Stop(cell, "NaowhBless")
        end
    end
end

local function NewCell(class)
    local cell = CreateFrame("Frame", nil, bar)
    cell.class = class
    Look.Icon(cell)
    Look.Label(cell, class)
    cell.header, cell.cast = Recipient(cell, "NaowhForeverBless" .. class)
    -- A mouse click acts on release, so up only: one step per click. Addon buttons otherwise
    -- follow ActionButtonUseKeyDown and act only on the press, which up only never sends.
    cell.cast:RegisterForClicks("AnyUp")
    cell.cast:SetAttribute("useOnKeyDown", false)
    cell.cast:SetAttribute("count", 0)
    -- Out of combat a click re-reads the class first, so it starts from whoever needs it most.
    cell.cast:SetScript("PreClick", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret() then
            PrepareCell(cell)
        end
    end)
    SecureHandlerWrapScript(cell.cast, "OnClick", secureHandler, CLASS_STEP)
    cell.cast:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then ClassMenu(self, class) end
    end)
    local function Tip()
        local target = cell.target and Ambiguate(cell.target.who, "short")
        return (target and "Left-click: bless " .. target .. ".\n" or "")
            .. ((cell.queued or 0) > 1 and "In combat each click blesses the next who needed it.\n" or "")
            .. "Right-click: choose the blessing, the player list or assignments."
    end
    ns.Tooltip(cell.cast, ClassName(class), Tip)
    -- The secure button hides while nobody can be blessed; the menu still opens from the icon.
    ns.Tooltip(cell, ClassName(class), Tip)
    cell:EnableMouse(true)
    cell:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ClassMenu(self, class) end
    end)
    return cell
end

-------------------------------------------------------------------------------
--  The player list
-------------------------------------------------------------------------------
local function PlayerMenu(owner, member)
    local store = Store()
    Menu(owner, Ambiguate(member.who, "short"), BLESSINGS,
        function() return store.players[member.guid] end,
        function(key)
            store.players[member.guid] = key
            BroadcastSoon()
            Changed()
        end, "Class default")
end

local function NewRow(index)
    local row = CreateFrame("Frame", nil, flyout)
    row:SetSize(230, 30)
    row.name = ns.Font(row, 12, "OUTLINE")
    row.name:SetPoint("TOPLEFT", 4, -2)
    row.note = ns.Font(row, 10, nil, T.muted)
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.slot = CreateFrame("Frame", nil, row)
    row.slot:SetSize(26, 26)
    row.slot:SetPoint("RIGHT", -2, 0)
    Look.Icon(row.slot)
    row.header, row.cast = Recipient(row.slot, "NaowhForeverBlessRow" .. index)
    SizeRecipient(row.header, row.cast, 26)
    row.cast:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down and row.member then PlayerMenu(self, row.member) end
    end)
    ns.Tooltip(row.cast, "Bless", "Left-click: cast this player's blessing.\nRight-click: give "
        .. "them their own blessing, or back to the class default.")
    Watch(row.slot)
    -- The header re-points the button when the raid reorders mid-fight; the display follows.
    row.cast:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "unit" then SetWatch(row.slot, value, row.slot.watchKey) end
    end)
    return row
end

local function ArrangeFlyout(roster)
    local members = {}
    for _, member in ipairs(roster) do
        if member.class == flyoutClass then members[#members + 1] = member end
    end
    if #members == 0 then flyoutClass = nil end
    if not flyoutClass then
        flyout:Hide()
        return
    end
    local store = Store()
    flyout:Show()
    for i, member in ipairs(members) do
        local row = rows[i] or NewRow(i)
        rows[i] = row
        row.member = member
        local color = RAID_CLASS_COLORS[member.class]
        row.name:SetText(Ambiguate(member.who, "short"))
        row.name:SetTextColor(color.r, color.g, color.b)
        local own = store.players[member.guid]
        local key = Assigned(member)
        row.note:SetText(own and SpellName(own) or "Class default")
        row.slot.icon:SetTexture(key and SpellIcon(key) or QUESTION)
        SetNames(row.header, member.names)
        row.cast:SetAttribute("spell1", key and HighestKnown(BY_KEY[key].ranks))
        SetWatch(row.slot, member.unit, key)
        local has, remaining
        if key then has, remaining = BuffState(member.unit, key) end
        ShowState(row.slot, key, has, remaining)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 32)
        row:Show()
    end
    for i = #members + 1, #rows do
        SetNames(rows[i].header, "-")
        SetWatch(rows[i].slot, nil, nil)
        rows[i]:Hide()
    end
    flyout.title:SetText(ClassName(flyoutClass))
    flyout:SetSize(242, 30 + #members * 32)
end

function ToggleFlyout(class)
    if InCombatLockdown() then
        ns.Print("The player list opens after combat.")
        return
    end
    flyoutClass = flyoutClass ~= class and class or nil
    Refresh()
end

local function BuildFlyout()
    flyout = CreateFrame("Frame", nil, bar)
    flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 18)
    ns.Solid(flyout, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    ns.Border(flyout)
    flyout.title = ns.Font(flyout, 12, "OUTLINE", T.accent)
    flyout.title:SetPoint("TOPLEFT", 8, -6)
    local close = ns.Button(flyout, "X", 18, 18, function() ToggleFlyout(flyoutClass) end)
    close:SetPoint("TOPRIGHT", -4, -4)
    rows = {}
    flyout:Hide()
end

-------------------------------------------------------------------------------
--  Aura and Righteous Fury
-------------------------------------------------------------------------------
local function CurrentAura()
    local key = Store().aura
    if key and Learned(BY_KEY[key]) then return key end
    for _, entry in ipairs(AURAS) do
        if Learned(entry) then return entry.key end
    end
end

local function FuryName()
    return C_Spell.GetSpellName(FURY.ranks[1]) or "Righteous Fury"
end

local function NewSelfButton(name)
    local btn = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("unit1", "player")
    btn:SetHighlightTexture(HIGHLIGHT, "ADD")
    Look.Icon(btn)
    Watch(btn)
    return btn
end

local function PrepareSelf(btn, key)
    local spell = HighestKnown(BY_KEY[key].ranks)
    btn:SetAttribute("spell1", spell)
    btn.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    SetWatch(btn, "player", key)
    ShowState(btn, key, BuffState("player", key))
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
-- Secure buttons only change out of combat; a change asked for in one waits. So does one
-- asked for while auras are unreadable: every buff would read unknown and the class buttons
-- would lose their spell, then stay empty once combat locks them.
function Refresh()
    if not bar then return end
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then
        dirty = true
        return
    end
    dirty = false
    if not (On() and IsPaladin()) then
        bar:Hide()
        ClearKeys()
        return
    end
    bar:Show()
    if not bar:IsVisible() then return end
    BeginAuraMemo()
    Look.Read()
    local size = Look.size
    local x = 0

    local aura = S.Get("blessShowAura") and CurrentAura()
    if aura then
        PrepareSelf(auraButton, aura)
        x = Look.Place(auraButton, bar, x)
    else
        auraButton:Hide()
    end
    if S.Get("blessShowFury") and Learned(FURY) then
        PrepareSelf(furyButton, "fury")
        x = Look.Place(furyButton, bar, x)
    else
        furyButton:Hide()
    end
    x = Look.Gap(x)

    local roster = Roster()
    local byClass = {}
    for _, member in ipairs(roster) do
        byClass[member.class] = byClass[member.class] or {}
        table.insert(byClass[member.class], member)
    end
    for _, class in ipairs(CLASSES) do
        local members = byClass[class]
        local cell = cells[class]
        if members then
            cell = cell or NewCell(class)
            cells[class] = cell
            cell.members = members
            SizeRecipient(cell.header, cell.cast, size)
            x = Look.Place(cell, bar, x)
            PrepareCell(cell)
        elseif cell then
            SetNames(cell.header, "-")
            LibStub("LibCustomGlow-1.0").PixelGlow_Stop(cell, "NaowhBless")
            cell.glowing = nil
            cell:Hide()
        end
    end
    ArrangeFlyout(roster)
    FillKeys(byClass)
    EndAuraMemo()
    bar:SetSize(Look.Width(x), size)
    bar:SetShown(x > 0 or bar.mover:IsShown())
end

local function BuildBar()
    bar = CreateFrame("Frame", "NaowhForeverBlessingBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    cells = {}
    bar.mover = ns.UI.AttachMover(bar, "Blessings", function(pos) S.Set("blessPos", pos) end,
        "Blessings/Settings", "Blessings/Settings:bar")
    local pos = S.Get("blessPos")
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
    auraButton = NewSelfButton("NaowhForeverBlessAura")
    auraButton:SetScript("PostClick", function(self, button, down)
        if button ~= "RightButton" or down then return end
        AuraMenu(self)
    end)
    ns.Tooltip(auraButton, "Aura", AURA_TIP)
    furyButton = NewSelfButton("NaowhForeverBlessFury")
    ns.Tooltip(furyButton, FuryName(), FURY_TIP)
    secureHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    keyNext = NewKeyButton("NaowhForeverBlessNext", secureHandler)
    keyGreater = NewKeyButton("NaowhForeverBlessNextGreater", secureHandler)
    BuildFlyout()
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
-- Auras and the roster change constantly in a raid: one rescan a second at most, and one
-- exchange of plans per second.
local refreshQueued, syncQueued
-- Except right after our own cast: the bar shows the blessing landing on the next frame, so
-- a click is not answered by a second of the old red. The window stays open for the second,
-- at most one rescan a frame: in a group other auras change first, and a Greater Blessing's
-- class can land over more than one frame.
local landing, landingQueued

local function RunLanded()
    landingQueued = false
    Refresh()
end

local function RefreshLanded()
    if landingQueued then return end
    landingQueued = true
    C_Timer.After(0, RunLanded)
end

local function RunQueued()
    refreshQueued = false
    Refresh()
end

local function RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(1, RunQueued)
end

local function SyncSoon()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(1, function()
        syncQueued = false
        for who in pairs(others) do
            if not InGroup(who) then others[who] = nil end
        end
        if IsPaladin() or CanAssign("player") then Send("R") end
        BroadcastSoon()
        if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
    end)
end

local Apply

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then return end
        if prefix == PREFIX and GROUP_CHANNELS[channel] then OnMessage(msg, sender) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        SyncSoon()
        RefreshSoon()
    elseif event == "PARTY_LEADER_CHANGED" then
        if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if buildAfterCombat then
            buildAfterCombat = false
            Apply()
        elseif dirty then
            Refresh()
        end
        if broadcastAfterCombat then
            broadcastAfterCombat = false
            BroadcastSoon()
        end
        SendPending()
        if unlocked and bar then bar.mover:Show() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The bar holds secure buttons, so it cannot be dragged in combat.
        if bar then bar.mover:Hide() end
    elseif event == "SPELLS_CHANGED" then
        BroadcastSoon()
        RefreshSoon()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if not InCombatLockdown() and not Secret(spellID) and FAMILY[spellID] then landing = GetTime() end
    elseif event == "UNIT_AURA" then
        -- Fires for every unit the client tracks. A queued rescan already covers this one,
        -- and in combat Refresh would only mark the bar dirty, so both skip the unit test.
        local fresh = landing and GetTime() - landing < 1
        if refreshQueued and not fresh then return end
        if InCombatLockdown() then
            dirty = true
            return
        end
        local unit = ...
        if unit == "player" or unit:find("party", 1, true) == 1 or unit:find("raid", 1, true) == 1 then
            if fresh then RefreshLanded() else RefreshSoon() end
        end
    end
end)

function Apply()
    events:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if not On() then
        if bar and InCombatLockdown() then
            dirty = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif bar then
            bar:Hide()
            ClearKeys()
        end
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PARTY_LEADER_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if IsPaladin() then
        events:RegisterEvent("UNIT_AURA")
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        -- The bar's buttons are secure, so it is only built out of combat (a reload in one).
        if not bar and InCombatLockdown() then
            buildAfterCombat = true
            return
        end
        if not bar then BuildBar() end
        -- Range and time left change with nothing to announce them.
        ticker = C_Timer.NewTicker(3, function()
            if bar:IsShown() and not InCombatLockdown() then RefreshSoon() end
        end)
        Refresh()
    end
end

hooksecurefunc(S, "Set", function(key)
    if key:find("^bless") and key ~= "blessPos" and key ~= "blessWindowAlpha" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    if bar and not InCombatLockdown() then
        bar.mover:Show()
        bar:Show()
    end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if bar then
        bar.mover:Hide()
        Refresh()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  Auto-assign and presets
-------------------------------------------------------------------------------
-- Each class's blessings, most wanted first. In a raid Salvation moves up for classes that
-- do not tank; warriors, druids and paladins never get it, so a tank is never handed it.
local WANTED = {
    WARRIOR = { "might", "kings", "light" },
    ROGUE = { "might", "kings", "salvation", "light" },
    HUNTER = { "might", "kings", "wisdom", "salvation", "light" },
    PALADIN = { "wisdom", "kings", "might", "light" },
    PRIEST = { "wisdom", "kings", "salvation", "light" },
    MAGE = { "wisdom", "kings", "salvation", "light" },
    WARLOCK = { "wisdom", "kings", "salvation", "light" },
    SHAMAN = { "wisdom", "kings", "might", "salvation", "light" },
    DRUID = { "wisdom", "kings", "might", "light" },
}
local WANTED_RAID = {
    ROGUE = { "salvation", "might", "kings", "light" },
    HUNTER = { "salvation", "might", "kings", "wisdom", "light" },
    PRIEST = { "salvation", "wisdom", "kings", "light" },
    MAGE = { "salvation", "wisdom", "kings", "light" },
    WARLOCK = { "salvation", "wisdom", "kings", "light" },
    SHAMAN = { "salvation", "wisdom", "kings", "might", "light" },
}
local AURA_ORDER = { "devotion", "retribution", "concentration", "fire", "frost", "shadow", "sanctity" }

-- The paladins a plan can be made for: you, and every paladin whose plan has arrived.
local function Paladins()
    local list = {}
    if IsPaladin() then
        local known = {}
        for _, entry in ipairs(BLESSINGS) do if Learned(entry) then known[entry.key] = true end end
        for _, entry in ipairs(AURAS) do if Learned(entry) then known[entry.key] = true end end
        list[1] = { who = MyName(), known = known, you = true }
    end
    for who, plan in pairs(others) do list[#list + 1] = { who = who, known = plan.known } end
    for _, p in ipairs(list) do
        p.count = 0
        for _ in pairs(p.known) do p.count = p.count + 1 end
    end
    -- Whoever knows least picks first, so a paladin with few blessings is not left with none.
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count < b.count end
        return a.who < b.who
    end)
    return list
end

-- Each wanted key in turn goes to the first paladin still free who knows it.
local function Pick(paladins, wanted, give)
    local free = {}
    for _, p in ipairs(paladins) do free[#free + 1] = p end
    for _, key in ipairs(wanted) do
        for i, p in ipairs(free) do
            if p.known[key] then
                give(p, key)
                table.remove(free, i)
                break
            end
        end
    end
end

-- One blessing per paladin per class, the most wanted first; one aura each.
local function AutoPlans(raid)
    local paladins = Paladins()
    local plans = {}
    for _, p in ipairs(paladins) do plans[p.who] = { classes = {} } end
    for _, class in ipairs(CLASSES) do
        Pick(paladins, raid and WANTED_RAID[class] or WANTED[class],
            function(p, key) plans[p.who].classes[class] = key end)
    end
    Pick(paladins, AURA_ORDER, function(p, key) plans[p.who].aura = key end)
    return plans
end

-- Another paladin's plan, kept here until their broadcast confirms it, and sent to them.
local function SendPlan(who, classes, aura)
    others[who].classes, others[who].aura = classes, aura
    local full = who:find("-") and who or who .. "-" .. GetNormalizedRealmName()
    Send("S|" .. full .. "|" .. EncodePlan(classes, aura), "S|" .. full)
end

-- Your own plan, and everyone else's through the leader's S message.
local function ApplyPlans(plans)
    local store = Store()
    for who, plan in pairs(plans) do
        if who == MyName() then
            store.classes = {}
            for class, key in pairs(plan.classes) do store.classes[class] = key end
            store.aura = plan.aura
            BroadcastSoon()
        elseif others[who] then
            SendPlan(who, plan.classes, plan.aura)
        end
    end
    Changed()
end

-- Everyone's plan when another paladin is involved needs the leader or an assistant.
local function CanPlanAll()
    return next(others) == nil or CanAssign("player")
end

-- One saved set of plans for the account, by paladin name.
local function Presets()
    local account = ns.AccountSettings()
    account.blessingPreset = account.blessingPreset or {}
    return account.blessingPreset
end

local function SavePreset()
    local paladins = Paladins()
    if #paladins == 0 then return false end
    local preset = {}
    for _, p in ipairs(paladins) do
        local plan = p.you and Store() or others[p.who]
        local classes = {}
        for class, key in pairs(plan.classes) do classes[class] = key end
        preset[p.who] = { classes = classes, aura = plan.aura }
    end
    ns.AccountSettings().blessingPreset = preset
    return true
end

-- Only the paladins in the preset who are here now; each keeps to what they have learned.
local function LoadPreset()
    local plans = {}
    for _, p in ipairs(Paladins()) do
        local saved = Presets()[p.who]
        if saved then
            local plan = { classes = {} }
            for class, key in pairs(saved.classes or {}) do
                if p.known[key] then plan.classes[class] = key end
            end
            plan.aura = saved.aura and p.known[saved.aura] and saved.aura or nil
            plans[p.who] = plan
        end
    end
    ApplyPlans(plans)
    return next(plans) ~= nil
end

-- For the settings page and the Blessings window.
ns.Blessings = {
    Look = Look,
    AutoAssign = function() ApplyPlans(AutoPlans(IsInRaid())) end,
    CanPlanAll = CanPlanAll,
    SavePreset = SavePreset,
    LoadPreset = LoadPreset,
    HasPreset = function() return next(Presets()) ~= nil end,
    HasPaladins = function() return #Paladins() > 0 end,
    CLASSES = CLASSES, BLESSINGS = BLESSINGS, AURAS = AURAS,
    Store = Store, Roster = Roster, Learned = Learned, IsPaladin = IsPaladin, CanAssign = CanAssign, MyName = MyName,
    SpellName = SpellName, SpellIcon = SpellIcon, ClassName = ClassName, SetOwn = SetOwn,
    Others = function() return others end,
    -- The leader's edit to another paladin's plan.
    SetFor = function(who, column, key)
        local plan = others[who]
        if not plan then return end
        if column == "AURA" then plan.aura = key else plan.classes[column] = key end
        SendPlan(who, plan.classes, plan.aura)
    end,
    OpenMenu = Menu,
    AuraMenu = AuraMenu, ClassMenu = ClassMenu, CurrentAura = CurrentAura, FuryName = FuryName,
    AURA_TIP = AURA_TIP, FURY_TIP = FURY_TIP,
}
