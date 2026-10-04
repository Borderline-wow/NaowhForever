-------------------------------------------------------------------------------
--  NaowhForever_GroupXP.lua -- the QoL group XP bars, fed by addon messages from every member
--  running Naowh Forever; the setting only shows the bars. Messages: "2 guid level xp max" is
--  someone's numbers, "R" asks everyone for theirs.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PREFIX = "NaowhGroupXP"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local GRADIENT = "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga"
local ROW_H, NAME_W, GAP = 18, 90, 2

local frame, unlocked, sendQueued, sendAfterCombat, requestPending
-- GUID -> { level, xp, max }, from their messages. Forever's addon message sender is the
-- character's full name with surname, which no unit API returns, so members are matched by GUID.
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
    local list = {}
    for _, unit in ipairs(units) do
        local name, guid = UnitName(unit), UnitGUID(unit)
        local _, class = UnitClass(unit)
        if name and guid and not (Secret(name) or Secret(guid) or Secret(class)) then
            list[#list + 1] = { unit = unit, name = name, class = class, guid = guid }
        end
    end
    return list
end

local Look = {}

function Look.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
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
    return row
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
    owner:SetSize(S.Get("groupXPWidth"), #list * (ROW_H + GAP) - GAP)
    for i, m in ipairs(list) do
        local row = pool[i] or Look.NewRow(owner)
        pool[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + GAP))
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + GAP))
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
    local list = {}
    if unlocked then
        Look.Sample(list, true)
    elseif On() and IsInGroup() then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or S.Get("groupXPShowSelf") then
                local level = UnitLevel(m.unit)
                if Secret(level) then level = nil end
                list[#list + 1] = { name = m.name, class = m.class, level = level,
                    data = m.unit == "player" and Own() or others[m.guid] }
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
    local inGroup = {}
    for _, m in ipairs(Roster()) do inGroup[m.guid] = true end
    for guid in pairs(others) do
        if not inGroup[guid] then others[guid] = nil end
    end
end

local function OnMessage(msg)
    if Secret(msg) then return end
    if msg == "R" then
        SendSoon()
        return
    end
    local guid, level, xp, max = msg:match("^2 (%S+) (%d+) (%d+) (%d+)$")
    if not guid or guid == UnitGUID("player") then return end
    others[guid] = { level = tonumber(level), xp = tonumber(xp), max = tonumber(max) }
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
        local prefix, msg, channel = ...
        if prefix == PREFIX and GROUP_CHANNELS[channel] then OnMessage(msg) end
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
            "QoL/Leveling & Travel", "QoL/Leveling & Travel:groupXP")
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

Settings.Page("QoL/Leveling & Travel", S):Card({
    id = "groupXP", name = "Group XP", order = 30, switch = "groupXP",
    help = "A bar per group member with their level and how far through it they are. Every member running "
        .. "Naowh Forever shares their experience, even with this off; anyone else shows their level. "
        .. "Updates wait until combat ends. Move it in Unlock Mode.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "groupXPShowSelf", label = "Show Yourself", toggle = true,
          help = "Your own bar among the group's." },
        { key = "groupXPWidth", label = "Width", slider = { 160, 500, 10 } },
    },
})
