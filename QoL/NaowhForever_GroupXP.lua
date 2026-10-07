-------------------------------------------------------------------------------
--  NaowhForever_GroupXP.lua -- the QoL group XP bars, fed by addon messages from every member
--  running Naowh Forever; the setting only shows the bars. Messages: "2 guid level xp max" is
--  someone's numbers, "R" asks everyone for theirs. Numbers are kept only for a GUID in the group.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts = ns.Shared.Parts

local PREFIX = "NaowhGroupXP"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local GUID_PATTERN = "^Player%-%d+%-%x+$"
local MAX_LEVEL, MAX_XP = 1000, 2 ^ 31
local GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
-- At the default Font Size; a bigger font makes the rows taller and the names wider.
local ROW_H, NAME_W, GAP, BASE_SIZE = 18, 90, 2, 12
local ROW_PAD = ROW_H - BASE_SIZE
local TEXT_SMALLER = 1 -- the bar's text, under the name's size

local frame, unlocked, sendQueued, sendAfterCombat, requestPending
-- GUID -> { level, xp, max }, from their messages. Forever's addon message sender is the
-- character's full name with surname, which no unit API returns, so members are matched by GUID.
local others = {}
local rows = {}
local mine, units, roster, members, shown, entries, inGroup = {}, {}, {}, {}, {}, {}, {}

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
    mine.level, mine.xp, mine.max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    return mine
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
    C_ChatInfo.SendAddonMessage(PREFIX, ("2 %s %d %d %d"):format(UnitGUID("player"), own.level, own.xp, own.max),
        channel)
end

-- XP arrives with every kill, so sends are held to one every two seconds. request also asks
-- the group for their numbers.
local function SendSoon(request)
    if request then requestPending = true end
    if sendQueued then return end
    sendQueued = true
    C_Timer.After(2, function()
        sendQueued = false
        Send()
    end)
end

-- You first, then the group in its own order.
local function Roster()
    wipe(units)
    units[1] = "player"
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local me = UnitIsUnit(unit, "player")
            if not Secret(me) and not me then units[#units + 1] = unit end
        end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    wipe(roster)
    for _, unit in ipairs(units) do
        local name, guid = UnitName(unit), UnitGUID(unit)
        local _, class = UnitClass(unit)
        if name and guid and not (Secret(name) or Secret(guid) or Secret(class)) then
            local n = #roster + 1
            local m = members[n] or {}
            members[n] = m
            m.unit, m.name, m.class, m.guid = unit, name, class, guid
            roster[n] = m
        end
    end
    return roster
end

local Look = {}

function Look.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = ns.Font(row, BASE_SIZE, "OUTLINE")
    row.name:SetPoint("LEFT")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("BOTTOMRIGHT")
    row.bar:SetMinMaxValues(0, 1)
    row.bg = ns.Solid(row.bar, "BACKGROUND", T.bg)
    row.bg:SetAllPoints()
    ns.Border(row.bar, { r = 0, g = 0, b = 0 })
    row.text = ns.Font(row.bar, BASE_SIZE - TEXT_SMALLER, "OUTLINE")
    row.text:SetPoint("CENTER")
    return row
end

function Look.Style(row, size)
    local font, outline = S.Get("groupXPFont"), S.Get("groupXPOutline")
    local nameW = NAME_W * size / BASE_SIZE
    row:SetHeight(math.max(ROW_H, size + ROW_PAD))
    Parts.HudFont(row.name, font, size, outline)
    row.name:SetWidth(nameW - 4)
    Parts.HudFont(row.text, font, size - TEXT_SMALLER, outline)
    row.bar:SetPoint("TOPLEFT", nameW, 0)
    row.bar:SetStatusBarTexture(ns.UI.TexturePath(S.Get("groupXPTexture"), GRADIENT))
    row.bar:SetStatusBarColor(T.accent.r, T.accent.g, T.accent.b)
    row.bg:SetColorTexture(T.bg.r, T.bg.g, T.bg.b, S.Get("groupXPBgAlpha"))
end

-- data is nil for a member without the addon, who shows their level only.
function Look.Paint(row, name, class, level, data)
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

function Look.Rows(owner, pool, list)
    local size = S.Get("groupXPFontSize")
    local step = math.max(ROW_H, size + ROW_PAD) + GAP
    owner:SetSize(S.Get("groupXPWidth"), #list * step - GAP)
    for i, m in ipairs(list) do
        local row = pool[i] or Look.NewRow(owner)
        pool[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * step)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * step)
        Look.Style(row, size)
        Look.Paint(row, m.name, m.class, m.level, m.data)
    end
    for i = #list + 1, #pool do pool[i]:Hide() end
end

function Look.Sample(list, withSelf)
    if withSelf then
        local _, class = UnitClass("player")
        list[#list + 1] = { name = UnitName("player"), class = class, data = Own() }
    end
    for _, m in ipairs(SAMPLE) do list[#list + 1] = m end
    return list
end

local function Refresh()
    if not frame then return end
    wipe(shown)
    local list = shown
    if unlocked then
        Look.Sample(list, true)
    elseif On() and IsInGroup() then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or S.Get("groupXPShowSelf") then
                local level = UnitLevel(m.unit)
                if Secret(level) then level = nil end
                local n = #list + 1
                local e = entries[n] or {}
                entries[n] = e
                e.name, e.class, e.level = m.name, m.class, level
                e.data = m.unit == "player" and Own() or others[m.guid]
                list[n] = e
            end
        end
    end
    if #list == 0 then
        frame:Hide()
        return
    end
    Look.Rows(frame, rows, list)
    frame:Show()
end

-- Someone who left the group keeps nothing behind.
local function Prune()
    wipe(inGroup)
    for _, m in ipairs(Roster()) do inGroup[m.guid] = true end
    for guid in pairs(others) do
        if not inGroup[guid] then others[guid] = nil end
    end
end

local function OnMessage(msg, channel, sender)
    if msg == "R" then
        SendSoon()
        return
    end
    local guid, level, xp, max = msg:match("^2 (%S+) (%d+) (%d+) (%d+)$")
    if not guid or not guid:find(GUID_PATTERN) or guid == UnitGUID("player") then return end
    level, xp, max = tonumber(level), tonumber(xp), tonumber(max)
    if level > MAX_LEVEL or xp > MAX_XP or max > MAX_XP or not ns.SenderIs(sender, channel, guid) then return end
    local data = others[guid] or {}
    others[guid] = data
    data.level, data.xp, data.max = level, xp, max
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
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then return end
        if prefix == PREFIX and GROUP_CHANNELS[channel] then OnMessage(msg, channel, sender) end
        return
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        Prune()
        SendSoon(event == "PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        SendSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not sendAfterCombat then return end
        sendAfterCombat = false
        Send()
        return
    end
    Refresh()
end)

local function Apply()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverGroupXP", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.mover = ns.UI.AttachMover(frame, "Group XP", function(pos) S.Set("groupXPPos", pos) end,
            "QoL/XP", "QoL/XP:groupXP")
    end
    Place()
    frame.mover:SetShown(unlocked == true)
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
boot:SetScript("OnEvent", function()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    for _, event in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UNIT_LEVEL", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    Prune()
    Apply()
end)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 130, 10, 11, 16
local STATES = {
    { key = "group", label = "In a Group", tip = "Your group's bars, with sample members." },
}

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.group = CreateFrame("Frame", nil, preview)
    preview.rows, preview.list = {}, {}
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    preview.note:SetText("Shown while you are in a group.")
    return preview
end

local function PaintPreview(preview)
    local list, group = preview.list, preview.group
    wipe(list)
    Look.Rows(group, preview.rows, Look.Sample(list, S.Get("groupXPShowSelf")))
    local w, h = group:GetWidth(), group:GetHeight()
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2 - NOTE_Y * 2
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h > 0 and h * scale > roomH then scale = roomH / h end
    group:SetScale(scale)
    group:ClearAllPoints()
    group:SetPoint("CENTER", preview, "CENTER", 0, NOTE_Y / scale)
end

local function Summary(store)
    return ("%d wide%s"):format(store.Get("groupXPWidth"), store.Get("groupXPShowSelf") and ", with you" or "")
end

Settings.Page("QoL/XP", S):Card({
    id = "groupXP", name = "Group XP", order = 30, switch = "groupXP",
    help = "A bar per group member with their level and how far through it they are. Every member running "
        .. "Naowh Forever shares their experience, even with this off; anyone else shows their level. "
        .. "Updates wait until combat ends. Move it in the HUD Editor.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "groupXPShowSelf", label = "Show Yourself", toggle = true,
          help = "Your own bar among the group's." },
        Settings.Group("Size"),
        { key = "groupXPWidth", label = "Width", slider = { 160, 500, 10 } },
        Settings.Look("groupXP", { text = true, size = { 8, 20, 1 }, bar = "Naowh Gradient", background = "alpha" }),
    },
})
