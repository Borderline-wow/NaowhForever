-------------------------------------------------------------------------------
--  NaowhForever_Blessings.lua -- paladin blessings: a blessing per class, or per
--  player where one needs something else, shared with the group's other paladins running
--  Naowh Forever, and a bar that casts it. A class button blesses the next member of that
--  class who needs it; the player list blesses one person. Aura and Righteous Fury buttons
--  sit at the front. The group leader and assistants can set every paladin's plan.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

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

local BY_KEY, BY_CODE, FAMILY, IDS = {}, {}, {}, {}
local function Index(entry)
    BY_KEY[entry.key] = entry
    if entry.code then BY_CODE[entry.code] = entry end
    IDS[entry.key] = {}
    for _, id in ipairs(entry.ranks) do FAMILY[id] = entry.key; IDS[entry.key][id] = true end
    for _, id in ipairs(entry.greater or {}) do FAMILY[id] = entry.key; IDS[entry.key][id] = true end
end
for _, entry in ipairs(BLESSINGS) do entry.blessing = true; Index(entry) end
for _, entry in ipairs(AURAS) do Index(entry) end
Index(FURY)

local EXPIRING = 300          -- seconds left that count as due for a refresh
local SYMBOL_OF_KINGS = 21177 -- the reagent every Greater Blessing uses
local QUESTION = 134400
local RED = { r = 0.97, g = 0.27, b = 0.27 }
local PALADIN_COLOR = RAID_CLASS_COLORS.PALADIN

local others = {}             -- paladin name (realm when not ours) -> { classes, aura, known }
local bar, cells, flyout, rows, auraButton, furyButton, keyNext, keyGreater
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
        if IsPlayerSpell(ids[i]) then return ids[i] end
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
-- Names as addon message senders carry them: the realm only when it is not ours.
local function Roster()
    local units = { "player" }
    if IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    local realm = GetNormalizedRealmName()
    local list = {}
    for _, unit in ipairs(units) do
        local name, unitRealm = UnitFullName(unit)
        local _, class = UnitClass(unit)
        local guid = UnitGUID(unit)
        -- A member whose data has not arrived yet reads "Unknown" with no class; the next
        -- roster or aura update picks them up.
        if name and not (Secret(name) or Secret(unitRealm) or Secret(class) or Secret(guid)) and class then
            local who = name
            if unitRealm and unitRealm ~= "" and unitRealm ~= realm then who = name .. "-" .. unitRealm end
            list[#list + 1] = { unit = unit, guid = guid, class = class, who = who,
                -- Group headers know same-realm members by the bare name.
                names = who == name and (name .. "," .. name .. "-" .. realm) or who }
        end
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

-- Present, with the time left when it runs out; nil when unreadable. Aura access can be
-- withdrawn outside combat lockdown too (seen on boss pulls), and GetAuraDataByIndex then
-- raises instead of returning nil, so the restriction is checked before the call.
local function BuffState(unit, key)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return false end
        local id = aura.spellId
        if Secret(id) then return nil end
        if FAMILY[id] == key then
            local expires = aura.expirationTime
            if Secret(expires) or not expires or expires == 0 then return true end
            return true, expires - GetTime()
        end
    end
    return false
end

-- Range does not apply to every spell and unit pair; nil leaves it to the cast.
local function InRange(member, spell)
    if member.guid == UnitGUID("player") then return true end
    local inRange = C_Spell.IsSpellInRange(spell, member.unit)
    return Secret(inRange) or inRange ~= false
end

-- Who a class button blesses next: missing first, then running out, then whoever has the
-- least left, skipping anyone dead, offline or out of range. Also the class summary.
local function Survey(members)
    local target, targetSpell, rank, left
    local missing, shortest, reachable = 0, nil, false
    local spells = {}
    for _, member in ipairs(members) do
        local key = Assigned(member)
        if key and spells[key] == nil then spells[key] = CastSpell(key, members) or false end
        local spell = key and spells[key]
        if spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit) then
            local has, remaining = BuffState(member.unit, key)
            if has == false then
                missing = missing + 1
                shortest = 0
            elseif remaining and (not shortest or remaining < shortest) then
                shortest = remaining
            end
            if has ~= nil and UnitIsVisible(member.unit) and InRange(member, spell) then
                reachable = true
                local r = not has and 0 or (remaining and remaining < EXPIRING and 1 or 2)
                local l = remaining or math.huge
                if not target or r < rank or (r == rank and l < left) then
                    target, targetSpell, rank, left = member, spell, r, l
                end
            end
        end
    end
    return target, targetSpell, missing, shortest, reachable
end

-------------------------------------------------------------------------------
--  Keybinds
-------------------------------------------------------------------------------
-- Next Blessing and Next Greater Blessing, bound in Key Bindings > AddOns (Bindings.xml).
-- Out of combat each key is re-aimed on every refresh; in combat, where buffs cannot be read,
-- it steps through the list it had when the fight began, one press per entry.
BINDING_HEADER_NAOWHFOREVER = "Naowh Forever"
_G["BINDING_NAME_CLICK NaowhForeverBlessNext:LeftButton"] = "Next Blessing"
_G["BINDING_NAME_CLICK NaowhForeverBlessNextGreater:LeftButton"] = "Next Greater Blessing"

local STEP = [[
    local i, n = self:GetAttribute("step") or 1, self:GetAttribute("count") or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. i))
    self:SetAttribute("step", i + 1)
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
        and UnitIsVisible(member.unit) and InRange(member, spell)) then return end
    local has, remaining = BuffState(member.unit, key)
    if has == false then return 0, 0 end
    if has and remaining and remaining < EXPIRING then return 1, remaining end
end

local function ByUrgency(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.left < b.left
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

-- The single blessing for everyone due. A Greater one per class whose members all share its
-- blessing, cast on the most urgent of them, and only while Symbols of Kings are carried, so
-- it never replaces a player's own choice.
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

local function Send(msg)
    local channel = Channel()
    if channel and not InCombatLockdown() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
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
    if who == UnitName("player") then return end
    if msg == "R" then
        BroadcastSoon()
        return
    end
    local target, plan = msg:match("^S|([^|]+)|(%S+)$")
    if target then
        local from = InGroup(who)
        local classes, aura = DecodePlan(plan)
        if not (IsPaladin() and classes and from and CanAssign(from.unit)
                and target == UnitName("player") .. "-" .. GetNormalizedRealmName()) then
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
    local body, known = msg:match("^F|(%S+)|(%a*)$")
    local member = body and InGroup(who)
    if not (member and member.class == "PALADIN") then return end
    local classes, aura = DecodePlan(body)
    if not classes then return end
    local set = {}
    for code in known:gmatch(".") do
        if BY_CODE[code] then set[BY_CODE[code].key] = true end
    end
    others[who] = { classes = classes, aura = aura, known = set }
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
                button:SetAllPoints(c)
                button:EnableMouse(false)
                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                button:SetIcon(icon)
                local text = button:CreateFontString(nil, "OVERLAY")
                text:SetFont(ns.UIFontPath(), 10, "OUTLINE")
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

-- The red base and "!" for a missing buff: always, under the managed display when there
-- is one, otherwise from the out-of-combat read.
local function ShowState(frame, key, has, remaining)
    local missing = key ~= nil and (frame.watch ~= nil or has == false)
    frame.icon:SetVertexColor(missing and RED.r or 1, missing and RED.g or 1, missing and RED.b or 1)
    frame.mark:SetText(missing and "!" or "")
    frame.timer:SetText(not frame.watch and remaining and S.Get("blessTimers")
        and math.ceil(remaining / 60) .. "m" or "")
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
local function Icon(frame, color)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(frame, color or { r = 0, g = 0, b = 0 })
    frame.mark = ns.Font(frame, 14, "OUTLINE", RED)
    frame.mark:SetPoint("CENTER")
    frame.timer = ns.Font(frame, 10, "OUTLINE")
    frame.timer:SetPoint("BOTTOM", 0, 1)
end

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
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return header, button
end

local function SetNames(header, names)
    if header.names == names then return end
    header.names = names
    header:SetAttribute("nameList", names)
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

local ToggleFlyout

local function ClassMenu(owner, class)
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
        root:CreateCheckbox("Players", function() return flyoutClass == class end,
            function() ToggleFlyout(class) end)
        root:CreateButton("Assignments", function() ns.OpenOptionsWindow("Assignments") end)
    end)
end

local function PrepareCell(cell)
    local members = cell.members
    local target, spell, missing, shortest, reachable = Survey(members)
    local key = Store().classes[cell.class]
    local shown = spell or (key and CastSpell(key, members))
    cell.icon:SetTexture(shown and C_Spell.GetSpellTexture(shown) or QUESTION)
    -- With nobody to bless the last target stays, but without a spell to cast on them.
    if target then SetNames(cell.header, target.names) end
    cell.cast:SetAttribute("spell1", spell)
    cell.target = target
    local due = missing > 0 or (shortest and shortest < EXPIRING)
    cell.icon:SetDesaturated(not reachable)
    cell.icon:SetVertexColor(due and RED.r or 1, due and RED.g or 1, due and RED.b or 1)
    cell.mark:SetText(missing > 0 and missing or "")
    cell.timer:SetText(S.Get("blessTimers") and shortest and shortest > 0
        and math.ceil(shortest / 60) .. "m" or "")
    local glow = missing > 0 and reachable
    if glow ~= cell.glowing then
        cell.glowing = glow
        local LCG = LibStub("LibCustomGlow-1.0")
        if glow then
            LCG.PixelGlow_Start(cell, { RED.r, RED.g, RED.b, 1 }, 8, nil, nil, 1, 0, 0, nil, "NaowhBless")
        else
            LCG.PixelGlow_Stop(cell, "NaowhBless")
        end
    end
end

local function NewCell(class)
    local cell = CreateFrame("Frame", nil, bar)
    cell.class = class
    Icon(cell, RAID_CLASS_COLORS[class])
    cell.label = ns.Font(cell, 10, "OUTLINE")
    cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    cell.label:SetText(ClassName(class))
    cell.header, cell.cast = Recipient(cell, "NaowhForeverBless" .. class)
    cell.cast:SetScript("PreClick", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then PrepareCell(cell) end
    end)
    cell.cast:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then ClassMenu(self, class) end
    end)
    ns.Tooltip(cell.cast, ClassName(class), function()
        local target = cell.target and Ambiguate(cell.target.who, "short")
        return (target and "Left-click: bless " .. target .. ".\n" or "")
            .. "Right-click: choose the blessing, the player list or assignments."
    end)
    -- The secure button hides while nobody can be blessed; the menu still opens from the icon.
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
    Icon(row.slot)
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

local function NewSelfButton(name)
    local btn = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("unit1", "player")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    Icon(btn, PALADIN_COLOR)
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
    local size, gap = S.Get("blessBarSize"), 6
    local x = 0
    local function Place(frame)
        frame:SetSize(size, size)
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", bar, "LEFT", x, 0)
        frame:Show()
        x = x + size + gap
    end

    local aura = S.Get("blessShowAura") and CurrentAura()
    if aura then
        PrepareSelf(auraButton, aura)
        Place(auraButton)
    else
        auraButton:Hide()
    end
    if S.Get("blessShowFury") and Learned(FURY) then
        PrepareSelf(furyButton, "fury")
        Place(furyButton)
    else
        furyButton:Hide()
    end
    if x > 0 then x = x + gap end

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
            Place(cell)
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
    bar:SetSize(math.max(x - gap, size), size)
    bar:SetShown(x > 0 or bar.mover:IsShown())
end

local function BuildBar()
    bar = CreateFrame("Frame", "NaowhForeverBlessingBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    cells = {}
    bar.mover = ns.UI.AttachMover(bar, "Blessings", function(pos) S.Set("blessPos", pos) end)
    local pos = S.Get("blessPos")
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
    auraButton = NewSelfButton("NaowhForeverBlessAura")
    auraButton:SetScript("PostClick", function(self, button, down)
        if button ~= "RightButton" or down then return end
        Menu(self, "Aura", AURAS, function() return Store().aura end,
            function(key) SetOwn("AURA", key) end, "Default")
    end)
    ns.Tooltip(auraButton, "Aura", "Left-click: cast your aura.\nRight-click: choose it.")
    furyButton = NewSelfButton("NaowhForeverBlessFury")
    ns.Tooltip(furyButton, C_Spell.GetSpellName(FURY.ranks[1]) or "Righteous Fury",
        "Left-click: cast it on yourself.")
    local handler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    keyNext = NewKeyButton("NaowhForeverBlessNext", handler)
    keyGreater = NewKeyButton("NaowhForeverBlessNextGreater", handler)
    BuildFlyout()
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
-- Auras and the roster change constantly in a raid: one rescan a second at most, and one
-- exchange of plans per second.
local refreshQueued, syncQueued

local function RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(1, function()
        refreshQueued = false
        Refresh()
    end)
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
            return
        end
        if dirty then Refresh() end
        if broadcastAfterCombat then
            broadcastAfterCombat = false
            BroadcastSoon()
        end
        if unlocked and bar then bar.mover:Show() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The bar holds secure buttons, so it cannot be dragged in combat.
        if bar then bar.mover:Hide() end
    elseif event == "SPELLS_CHANGED" then
        BroadcastSoon()
        RefreshSoon()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" or unit:find("^party%d") or unit:find("^raid%d") then RefreshSoon() end
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
    if key:find("^bless") and key ~= "blessPos" then Apply() end
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

-- For the options pages.
ns.Blessings = {
    CLASSES = CLASSES, BLESSINGS = BLESSINGS, AURAS = AURAS,
    Store = Store, Roster = Roster, Learned = Learned, IsPaladin = IsPaladin, CanAssign = CanAssign,
    SpellName = SpellName, SpellIcon = SpellIcon, ClassName = ClassName, SetOwn = SetOwn,
    Others = function() return others end,
    -- The leader's edit to another paladin's plan: kept here until their broadcast confirms it.
    SetFor = function(who, column, key)
        local plan = others[who]
        if not plan then return end
        if column == "AURA" then plan.aura = key else plan.classes[column] = key end
        local full = who:find("-") and who or who .. "-" .. GetNormalizedRealmName()
        Send("S|" .. full .. "|" .. EncodePlan(plan.classes, plan.aura))
    end,
    OpenMenu = Menu,
}
