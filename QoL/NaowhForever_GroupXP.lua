-------------------------------------------------------------------------------
--  NaowhForever_GroupXP.lua -- the QoL group XP bars, fed by addon messages from members running
--  Naowh Forever. Messages: "1 level xp max" is someone's numbers, "R" asks everyone for theirs,
--  "O" says the sender switched it off.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PREFIX = "NaowhGroupXP"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
local ROW_H, NAME_W, GAP = 18, 90, 2

local frame, unlocked, prefixed, active, sendQueued, sendAfterCombat, requestPending, offAfterCombat
-- "Name" for your realm, "Name-Realm" otherwise -> { level, xp, max }, from their messages.
local others = {}
local rows = {}

local function On()
    return S.Get("enabled") and S.Get("groupXP")
end

-- Unit identity can come back secret in restricted content; those members are skipped.
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Own()
    return { level = UnitLevel("player"), xp = UnitXP("player"), max = UnitXPMax("player") }
end

-- Addon messages are not sent in combat; the latest numbers go out once it ends.
local function Send()
    local channel = Channel()
    if not channel then
        requestPending = false
        return
    end
    if InCombatLockdown() then
        sendAfterCombat = true
        return
    end
    if requestPending then
        requestPending = false
        C_ChatInfo.SendAddonMessage(PREFIX, "R", channel)
    end
    local own = Own()
    C_ChatInfo.SendAddonMessage(PREFIX, ("1 %d %d %d"):format(own.level, own.xp, own.max), channel)
end

-- Tells the group to drop your bar rather than leave it at your last numbers.
local function SendOff()
    local channel = Channel()
    if channel then C_ChatInfo.SendAddonMessage(PREFIX, "O", channel) end
end

-- XP arrives with every kill, so sends are held to one every two seconds. request also asks
-- the group for their numbers.
local function SendSoon(request)
    if request then requestPending = true end
    if sendQueued then return end
    sendQueued = true
    C_Timer.After(2, function()
        sendQueued = false
        if On() then Send() end
    end)
end

-- You first, then the group in its own order.
local function Roster()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local me = UnitIsUnit(unit, "player")
            if not Secret(me) and not me then units[#units + 1] = unit end
        end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    local realm = GetNormalizedRealmName()
    local list = {}
    for _, unit in ipairs(units) do
        local name, unitRealm = UnitFullName(unit)
        local _, class = UnitClass(unit)
        if name and not (Secret(name) or Secret(unitRealm) or Secret(class)) then
            local who = name
            if unitRealm and unitRealm ~= "" and unitRealm ~= realm then who = name .. "-" .. unitRealm end
            list[#list + 1] = { unit = unit, name = name, class = class, who = who }
        end
    end
    return list
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_H)
    row.name = ns.Font(row, 12, "OUTLINE")
    row.name:SetPoint("LEFT")
    row.name:SetWidth(NAME_W - 4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", NAME_W, 0)
    row.bar:SetPoint("BOTTOMRIGHT")
    row.bar:SetStatusBarTexture(GRADIENT)
    row.bar:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    row.bar:SetMinMaxValues(0, 1)
    ns.Solid(row.bar, "BACKGROUND", T.bg, 0.85):SetAllPoints()
    ns.Border(row.bar, { r = 0, g = 0, b = 0 })
    row.text = ns.Font(row.bar, 11, "OUTLINE")
    row.text:SetPoint("CENTER")
    rows[i] = row
    return row
end

-- data is nil for a member without the addon, who shows their level only.
local function Paint(row, name, class, level, data)
    local color = class and RAID_CLASS_COLORS[class]
    row.name:SetText(name)
    if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
    local lv = level and level > 0 and ("Lv " .. level) or "Lv ?"
    if not data then
        row.bar:SetValue(0)
        row.text:SetText(lv .. "  |cff9ca3afno addon|r")
    elseif data.level >= GetMaxLevelForPlayerExpansion() or data.max <= 0 then
        row.bar:SetValue(1)
        row.text:SetText("Lv " .. data.level .. "  Max")
    else
        local pct = data.xp / data.max
        row.bar:SetValue(pct)
        row.text:SetText(("Lv %d  %.1f%%"):format(data.level, pct * 100))
    end
    row:Show()
end

local SAMPLE = {
    { name = "Tank", class = "WARRIOR", data = { level = 24, xp = 11000, max = 12200 } },
    { name = "Healer", class = "PRIEST", data = { level = 25, xp = 3100, max = 13100 } },
    { name = "Rogue", class = "ROGUE", level = 23 },
}

local function Refresh()
    if not frame then return end
    local list = {}
    if unlocked then
        local _, class = UnitClass("player")
        list[1] = { name = UnitName("player"), class = class, data = Own() }
        for _, m in ipairs(SAMPLE) do list[#list + 1] = m end
    elseif On() and IsInGroup() then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or S.Get("groupXPShowSelf") then
                local level = UnitLevel(m.unit)
                if Secret(level) then level = nil end
                list[#list + 1] = { name = m.name, class = m.class, level = level,
                    data = m.unit == "player" and Own() or others[m.who] }
            end
        end
    end
    if #list == 0 then
        frame:Hide()
        return
    end
    frame:SetSize(S.Get("groupXPWidth"), #list * (ROW_H + GAP) - GAP)
    for i, m in ipairs(list) do
        local row = Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + GAP))
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + GAP))
        Paint(row, m.name, m.class, m.level, m.data)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    frame:Show()
end

-- Someone who left the group keeps nothing behind.
local function Prune()
    local inGroup = {}
    for _, m in ipairs(Roster()) do inGroup[m.who] = true end
    for who in pairs(others) do
        if not inGroup[who] then others[who] = nil end
    end
end

local function OnMessage(msg, sender)
    if Secret(sender) then return end
    local who = Ambiguate(sender, "none")
    if who == UnitName("player") then return end
    if msg == "R" then
        SendSoon()
        return
    elseif msg == "O" then
        others[who] = nil
        Refresh()
        return
    end
    local version, level, xp, max = msg:match("^(%d+) (%d+) (%d+) (%d+)$")
    if version ~= "1" then return end
    others[who] = { level = tonumber(level), xp = tonumber(xp), max = tonumber(max) }
    Refresh()
end

local function Place()
    local pos = S.Get("groupXPPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == PREFIX and GROUP_CHANNELS[channel] then OnMessage(msg, sender) end
        return
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        Prune()
        SendSoon(event == "PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        SendSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if offAfterCombat then
            offAfterCombat = false
            if not On() then
                SendOff()
                events:UnregisterAllEvents()
                return
            end
        end
        if not sendAfterCombat then return end
        sendAfterCombat = false
        Send()
        return
    end
    Refresh()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        -- Switched off in combat, the message waits for it to end.
        if active or offAfterCombat then
            if InCombatLockdown() then
                offAfterCombat = true
                events:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                offAfterCombat = false
                SendOff()
            end
        end
        active = false
        wipe(others)
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverGroupXP", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.mover = ns.UI.AttachMover(frame, "Group XP", function(pos) S.Set("groupXPPos", pos) end)
    end
    if not prefixed then
        prefixed = true
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    Place()
    frame.mover:SetShown(unlocked == true)
    for _, event in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UNIT_LEVEL", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    Prune()
    SendSoon(not active)
    active = true
    Refresh()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^groupXP") and key ~= "groupXPPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then
        frame.mover:Hide()
        Apply()
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
