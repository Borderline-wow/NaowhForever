-------------------------------------------------------------------------------
--  NaowhForever_HealerMana.lua -- the QoL healer mana list: every healer in your group and
--  their mana, lowest first, with a cup by anyone drinking. Read from the units themselves, so
--  nobody else needs the addon. A healer has the healer role, or no role and a healing class.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

local MANA, MANA_TOKEN = 0, "MANA"  -- Enum.PowerType.Mana, and its name in UNIT_POWER_UPDATE
local DRINK_SPELL = 430             -- Drink: its name, in the client's language, is the buff's
local DRINK_ICON = "Interface\\Icons\\INV_Drink_07"
local HEALER_CLASSES = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }
local UPDATE_DELAY = 0.25           -- a burst of mana ticks is one redraw
-- A row is its font size and ROW_PAD tall; PAD is the card round the rows.
local BASE_SIZE, ROW_PAD, PAD, ICON_GAP, COLUMN_GAP = 12, 4, 6, 4, 8
local ICON_CROP = 0.07              -- the icon's own edge, cut off inside our border
local ICON_DROP = 1                 -- the Naowh font sits low in its line: the cup moves down to it
-- Mana under these shares shows in the running low and the nearly out colour.
local LOW, OUT = 0.6, 0.3
local PCT_FORMAT = "%.1f%%"
local DEAD, OFFLINE, UNKNOWN = "Dead", "Offline", "--"
local NO_RANK = math.huge
local PLACE = { point = "LEFT", relPoint = "LEFT", x = 40, y = -120 }
local UNIT_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_AURA" }
local GROUP_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }

local frame, unlocked, pending, drinkName, shareCurve
local look = 0                      -- bumped by a look setting, so rows restyle once
local rows, members, list, tracked, rank, units = {}, {}, {}, {}, {}, {}
local backdrops = setmetatable({}, { __mode = "k" })  -- each owner's card: the list's and the preview's

local function On()
    return S.Get("enabled") and S.Get("healerMana")
end

-- Unit data can come back secret in restricted content; it is never compared then.
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- Dungeons and raids, or any group.
local function Here()
    if not IsInGroup() then return false end
    if S.Get("healerManaWhere") == "group" then return true end
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function IsHealer(unit, class)
    local role = UnitGroupRolesAssigned(unit)
    if Secret(role) then role = nil end
    if role == "HEALER" then return true end
    if role == "TANK" or role == "DAMAGER" then return false end
    return HEALER_CLASSES[class] == true
end

local function Units()
    wipe(units)
    if S.Get("healerManaShowSelf") then units[1] = "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local me = UnitIsUnit(unit, "player")
            if not Secret(me) and not me then units[#units + 1] = unit end
        end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- The healers in the group, one kept entry each, refilled on a roster change.
local function Roster()
    wipe(list)
    wipe(tracked)
    for _, unit in ipairs(Units()) do
        local name, guid = UnitName(unit), UnitGUID(unit)
        local _, class = UnitClass(unit)
        if name and guid and not (Secret(name) or Secret(guid) or Secret(class)) and IsHealer(unit, class) then
            local n = #list + 1
            local m = members[n] or {}
            members[n] = m
            if m.guid ~= guid then m.pct, m.drinking = nil, false end
            m.unit, m.name, m.class, m.guid = unit, name, class, guid
            list[n] = m
            tracked[unit] = m
        end
    end
end

-- Auras go secret during boss pulls; the last answer stands until they clear.
local function Drinking(m)
    if not S.Get("healerManaDrinking") or C_Secrets.ShouldAurasBeSecret() then return end
    drinkName = drinkName or C_Spell.GetSpellName(DRINK_SPELL)
    if not (drinkName and C_UnitAuras.GetAuraDataBySpellName) then return end
    m.drinking = C_UnitAuras.GetAuraDataBySpellName(m.unit, drinkName, "HELPFUL") ~= nil
end

-- A druid in a form keeps the last share it showed.
local function Read(m)
    local unit = m.unit
    local online, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
    if Secret(online) then online = true end
    if Secret(dead) then dead = false end
    m.state = (not online and OFFLINE) or (dead and DEAD) or nil
    local cur, max = UnitPower(unit, MANA), UnitPowerMax(unit, MANA)
    m.secret = (Secret(cur) or Secret(max)) == true
    if not m.secret and max > 0 then m.pct = cur / max end
end

-- Dead and offline last, then the lowest mana, then by name.
local function Less(a, b)
    if (a.state ~= nil) ~= (b.state ~= nil) then return b.state ~= nil end
    local pa, pb = a.pct or NO_RANK, b.pct or NO_RANK
    if pa ~= pb then return pa < pb end
    if a.name ~= b.name then return a.name < b.name end
    return a.guid < b.guid
end

-- While a share is secret it cannot be compared: each keeps its place from the last plain
-- sort, and anyone new goes last.
local function Held(a, b)
    local ra, rb = rank[a.guid] or NO_RANK, rank[b.guid] or NO_RANK
    if ra ~= rb then return ra < rb end
    if a.name ~= b.name then return a.name < b.name end
    return a.guid < b.guid
end

local function Sort()
    for i = 1, #list do
        if list[i].secret then
            table.sort(list, Held)
            return
        end
    end
    table.sort(list, Less)
    wipe(rank)
    for i = 1, #list do rank[list[i].guid] = i end
end

local function ManaColour(pct)
    if pct < OUT then return St.TIME_OUT_RGB end
    if pct < LOW then return St.TIME_LOW_RGB end
    return St.TIME_OK_RGB
end

-- A secret share is turned into 0 to 100 and written by the client. UnitPowerPercent is newer
-- than the rest, so this reports whether it could, and is called through pcall: a client that
-- refuses the secret shows "--" rather than a Lua error in a boss fight.
local function SecretShare(fs, unit)
    if not (UnitPowerPercent and C_CurveUtil) then return false end
    if not shareCurve then
        shareCurve = C_CurveUtil.CreateCurve()
        shareCurve:SetType(Enum.LuaCurveType.Linear)
        shareCurve:AddPoint(0, 0)
        shareCurve:AddPoint(1, 100)
    end
    fs:SetFormattedText(PCT_FORMAT, UnitPowerPercent(unit, MANA, false, shareCurve))
    return true
end

local function Colour(fs, c)
    fs:SetTextColor(c.r, c.g, c.b)
end

local Look = {}

function Look.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(DRINK_ICON)
    row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.icon:SetPoint("LEFT", 0, -ICON_DROP)
    row.pct = ns.Font(row, BASE_SIZE, "OUTLINE")
    row.pct:SetPoint("RIGHT")
    row.pct:SetJustifyH("RIGHT")
    row.name = ns.Font(row, BASE_SIZE, "OUTLINE")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

function Look.Style(row, size, iconRoom)
    local font, outline, background = S.Get("healerManaFont"), S.Get("healerManaOutline"), S.Get("healerManaBackground")
    row:SetHeight(size + ROW_PAD)
    Parts.HudFont(row.name, font, size, outline, background)
    Parts.HudFont(row.pct, font, size, outline, background)
    row.icon:SetSize(size, size)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", iconRoom, 0)
    row.name:SetPoint("RIGHT", row.pct, "LEFT", -COLUMN_GAP, 0)
    row.look = look
end

function Look.Paint(row, m, drinks)
    row.name:SetText(m.name)
    Colour(row.name, RAID_CLASS_COLORS[m.class] or T.fg)
    row.icon:SetShown(drinks and m.drinking == true)
    if m.state then
        row.pct:SetText(m.state)
        Colour(row.pct, m.state == DEAD and St.RED_RGB or T.muted)
    elseif m.secret then
        Colour(row.pct, T.fg)
        local ok, shown = pcall(SecretShare, row.pct, m.unit)
        if not (ok and shown) then row.pct:SetText(UNKNOWN) end
    elseif m.pct then
        row.pct:SetText(PCT_FORMAT:format(m.pct * 100))
        Colour(row.pct, ManaColour(m.pct))
    else
        row.pct:SetText(UNKNOWN)
        Colour(row.pct, T.muted)
    end
    row:Show()
end

-- One row per entry on owner's own card, sized to fit them.
function Look.Rows(owner, pool, entries)
    local size, drinks = S.Get("healerManaFontSize"), S.Get("healerManaDrinking")
    local iconRoom = drinks and size + ICON_GAP or 0
    local step = size + ROW_PAD
    local backdrop = backdrops[owner] or Parts.HudBackdrop(owner)
    backdrops[owner] = backdrop
    backdrop:SetMode(S.Get("healerManaBackground"))
    owner:SetSize(S.Get("healerManaWidth"), #entries * step + 2 * PAD)
    for i, m in ipairs(entries) do
        local row = pool[i]
        if not row then
            row = Look.NewRow(owner)
            pool[i] = row
        end
        if row.look ~= look then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * step)
            row:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * step)
            Look.Style(row, size, iconRoom)
        end
        Look.Paint(row, m, drinks)
    end
    for i = #entries + 1, #pool do pool[i]:Hide() end
end

local SAMPLE = {
    { name = "Priest", class = "PRIEST", guid = "1", pct = 0.18 },
    { name = "Druid", class = "DRUID", guid = "2", pct = 0.47, drinking = true },
    { name = "Shaman", class = "SHAMAN", guid = "3", pct = 0.83 },
    { name = "Paladin", class = "PALADIN", guid = "4", state = DEAD },
}

local function Redraw()
    if not frame then return end
    if unlocked then
        Look.Rows(frame, rows, SAMPLE)
        frame:Show()
        return
    end
    if not (On() and Here()) or #list == 0 then
        frame:Hide()
        return
    end
    for i = 1, #list do Read(list[i]) end
    Sort()
    Look.Rows(frame, rows, list)
    frame:Show()
end

local function Flush()
    pending = false
    Redraw()
end

local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(UPDATE_DELAY, Flush)
end

local function Place()
    local pos = S.Get("healerManaPos") or PLACE
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local events = CreateFrame("Frame")
local Apply

-- Unit events are heard only while the list shows, roster events while it is on.
function Apply()
    if not On() then
        events:UnregisterAllEvents()
        wipe(list)
        wipe(tracked)
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverHealerMana", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.mover = ns.UI.AttachMover(frame, "Healer Mana", function(pos) S.Set("healerManaPos", pos) end,
            "QoL/Combat", "QoL/Combat:healerMana")
    end
    for _, event in ipairs(GROUP_EVENTS) do events:RegisterEvent(event) end
    local here = Here()
    for _, event in ipairs(UNIT_EVENTS) do
        if here then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    wipe(list)
    wipe(tracked)
    if here then
        Roster()
        for i = 1, #list do Drinking(list[i]) end
    end
    Place()
    frame.mover:SetShown(unlocked == true)
    Redraw()
end

events:SetScript("OnEvent", function(_, event, unit, powerType)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
        Apply()
        return
    end
    if Secret(unit) then return end
    local m = tracked[unit]
    if not m then return end
    if event == "UNIT_AURA" then
        local was = m.drinking
        Drinking(m)
        if m.drinking == was then return end
    elseif event == "UNIT_POWER_UPDATE" and (Secret(powerType) or powerType ~= MANA_TOKEN) then
        return
    end
    Soon()
end)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^healerMana") and key ~= "healerManaPos") then
        look = look + 1
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", function() Apply() end)
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
boot:SetScript("OnEvent", function() Apply() end)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local STAGE_H, NOTE_Y, NOTE_SIZE, STAGE_MARGIN = 150, 10, 11, 16
local STATES = {
    { key = "group", label = "In a Group", tip = "Your healers' mana, with sample healers." },
}
local WHERE = { { instance = "Dungeons & Raids", group = "Any Group" }, { "instance", "group" } }

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.group = CreateFrame("Frame", nil, preview)
    preview.rows = {}
    preview.note = ns.Font(preview, NOTE_SIZE, nil, T.muted)
    preview.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return preview
end

local function PaintPreview(preview)
    local group = preview.group
    preview.note:SetText(S.Get("healerManaWhere") == "group" and "Shown while you are in a group."
        or "Shown in dungeons and raids.")
    Look.Rows(group, preview.rows, SAMPLE)
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
    return ("%s, %d wide"):format(WHERE[1][store.Get("healerManaWhere")] or WHERE[1].instance,
        store.Get("healerManaWidth"))
end

Settings.Page("QoL/Combat", S):Card({
    id = "healerMana", name = "Healer Mana", order = 45, switch = "healerMana",
    help = "Your group's healers and their mana, lowest first.",
    summary = Summary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "healerManaWhere", label = "Show In", choice = WHERE },
        { key = "healerManaShowSelf", label = "Show Yourself", toggle = true,
          help = "Your own mana among the healers'." },
        { key = "healerManaDrinking", label = "Mark Drinking", toggle = true,
          help = "A cup beside a healer who is drinking." },
        Settings.Group("Size"),
        { key = "healerManaWidth", label = "Width", slider = { 100, 300, 5 } },
        Settings.Look("healerMana", { text = true, size = { 8, 20, 1 }, background = "card" }),
    },
})
