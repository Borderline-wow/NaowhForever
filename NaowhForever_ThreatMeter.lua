-------------------------------------------------------------------------------
--  NaowhForever_ThreatMeter.lua -- threat on your target for everyone in the group, one
--  bar each, sorted, with an optional pull aggro bar and a warning sound. Forever hands
--  the threat API over readable; a value that does come back secret skips that unit.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local S = UI.ModuleSettings("threatMeter", {
    enabled = false,
    width = 220, barHeight = 18, maxBars = 10,
    growUp = false, showHeader = true, ignorePets = false,
    showValue = true, showPercent = true,
    playerColorOn = false, playerColor = { r = 0.8, g = 0.1, b = 0.1 },
    tankColorOn = false, tankColor = { r = 0.1, g = 0.6, b = 0.1 },
    pullBar = true, pullColor = { r = 0.0, g = 0.55, b = 0.0 },
    warnSound = false, warnSoundKey = "none", warnAt = 80, warnSkipTank = true,
})
ns.ThreatMeterSettings = S

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local TEXT_PAD = 4
local GAP = 1

local PET_COLOR = { r = 0.45, g = 0.6, b = 0.45 }
local FALLBACK_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

local frame, pendingUpdate, followTicker, unlocked, warned
local rows = {}         -- bar widgets, created on demand
local entries = {}      -- reused threat entries, one per unit seen
local list = {}         -- the entries shown this update, sorted
local count = 0

local function On()
    return S.Get("enabled")
end

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Forever returns threat in display units already, not the x100 scale Classic's API uses.
local function ShortThreat(v)
    if v >= 1000000 then return ("%.1fm"):format(v / 1000000) end
    if v >= 1000 then return ("%.1fk"):format(v / 1000) end
    return tostring(math.floor(v + 0.5))
end

-- The mob whose threat table is shown: your target when you can attack it, otherwise what
-- your friendly target is fighting (a healer targeting the tank).
local function ThreatMob()
    if UnitExists("target") and UnitCanAttack("player", "target") then return "target" end
    if UnitExists("targettarget") and UnitCanAttack("player", "targettarget") then
        return "targettarget"
    end
end

-- A tank does not want to be warned about holding aggro: tank role, Bear or Dire Bear
-- Form, or Defensive Stance.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18
end

-------------------------------------------------------------------------------
--  Frame
-------------------------------------------------------------------------------
local function HeaderHeight()
    return S.Get("showHeader") and S.Get("barHeight") or 0
end

local function CreateRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row:SetMinMaxValues(0, 1)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.value = ns.Font(row, 12, "OUTLINE")
    row.value:SetPoint("RIGHT", row, "RIGHT", -TEXT_PAD, 0)
    row.value:SetJustifyH("RIGHT")
    row.name = ns.Font(row, 12, "OUTLINE")
    row.name:SetPoint("LEFT", row, "LEFT", TEXT_PAD, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -TEXT_PAD, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    rows[i] = row
    return row
end

local function Layout(shown)
    local bh, w, top = S.Get("barHeight"), S.Get("width"), HeaderHeight()
    local growUp = S.Get("growUp")
    frame:SetSize(w, math.max(top + shown * (bh + GAP) - (shown > 0 and GAP or 0), top, 1))
    for i = 1, shown do
        local row = rows[i] or CreateRow(i)
        local off = top + (i - 1) * (bh + GAP)
        row:ClearAllPoints()
        if growUp then
            row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, off)
        else
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -off)
        end
        row:SetSize(w, bh)
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    frame.header:ClearAllPoints()
    frame.header:SetPoint(growUp and "BOTTOMLEFT" or "TOPLEFT")
    frame.header:SetSize(w, math.max(top, 1))
    frame.header:SetShown(top > 0)
end

local function Place()
    local pos = S.Get("threatPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 400, -100)
    end
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverThreatMeter", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    ns.Solid(frame, "BACKGROUND", T.bg, 0.6):SetAllPoints()
    ns.Border(frame)
    frame.header = CreateFrame("Frame", nil, frame)
    ns.Solid(frame.header, "BACKGROUND", T.bg, 0.9):SetAllPoints()
    frame.header.text = ns.Font(frame.header, 12, "OUTLINE", T.accent)
    frame.header.text:SetPoint("LEFT", TEXT_PAD, 0)
    frame.header.text:SetPoint("RIGHT", -TEXT_PAD, 0)
    frame.header.text:SetJustifyH("LEFT")
    frame.header.text:SetWordWrap(false)
    frame.mover = UI.AttachMover(frame, "Threat Meter", function(pos) S.Set("threatPos", pos) end)
    frame:Hide()
    Place()
end

-------------------------------------------------------------------------------
--  Threat data
-------------------------------------------------------------------------------
local function NextEntry()
    count = count + 1
    local e = entries[count]
    if not e then e = {}; entries[count] = e end
    list[#list + 1] = e
    return e
end

local function Clear()
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
end

local function Add(unit, mob)
    if not UnitExists(unit) then return end
    local tanking, _, scaled, _, raw = UnitDetailedThreatSituation(unit, mob)
    if not (Readable(raw) and Readable(scaled) and Readable(tanking)) or raw <= 0 then return end
    local e = NextEntry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = unit, UnitName(unit), raw, scaled, tanking
    e.isPlayer, e.pull = UnitIsUnit(unit, "player"), nil
end

local function Collect(mob)
    Clear()
    local pets = not S.Get("ignorePets")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            Add("raid" .. i, mob)
            if pets then Add("raidpet" .. i, mob) end
        end
    else
        Add("player", mob)
        if pets then Add("pet", mob) end
        for i = 1, GetNumSubgroupMembers() do
            Add("party" .. i, mob)
            if pets then Add("partypet" .. i, mob) end
        end
    end
end

local function ByThreat(a, b) return a.raw > b.raw end

-- Where you pull aggro: scaled percent is threat against your own pull line (100 = you
-- take it), so the line is your threat scaled up to 100.
local function AddPullEntry(me)
    if not (me and not me.tanking and me.scaled > 0) then return end
    local e = NextEntry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = nil, "Pull Aggro", me.raw * 100 / me.scaled, 100, false
    e.isPlayer, e.pull = false, true
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function ClassColor(unit)
    if not UnitIsPlayer(unit) then return PET_COLOR end
    local _, classFile = UnitClass(unit)
    return classFile and RAID_CLASS_COLORS[classFile] or FALLBACK_COLOR
end

local function RowColor(e)
    if e.pull then return S.Get("pullColor") end
    if e.isPlayer and S.Get("playerColorOn") then return S.Get("playerColor") end
    if e.tanking and S.Get("tankColorOn") then return S.Get("tankColor") end
    return ClassColor(e.unit)
end

local function ValueText(e)
    local v, p = S.Get("showValue"), S.Get("showPercent") and not e.pull
    if v and p then return ("%s  %d%%"):format(ShortThreat(e.raw), e.scaled) end
    if v then return ShortThreat(e.raw) end
    if p then return ("%d%%"):format(e.scaled) end
    return ""
end

local function Render(title)
    local shown = math.min(#list, S.Get("maxBars"))
    local top = list[1] and list[1].raw or 0
    Layout(shown)
    -- Names go straight to SetText: a name can come back secret, and a secret cannot be
    -- tested for nil.
    frame.header.text:SetText(title)
    for i = 1, shown do
        local e, row = list[i], rows[i]
        local c = RowColor(e)
        row:SetStatusBarColor(c.r, c.g, c.b, 1)
        row.bg:SetColorTexture(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.6)
        row:SetValue(top > 0 and e.raw / top or 0)
        row.name:SetText(e.name)
        row.value:SetText(ValueText(e))
    end
end

local function CheckWarning(me)
    if not S.Get("warnSound") then return end
    local over = me and not me.tanking and me.scaled >= S.Get("warnAt")
        and not (S.Get("warnSkipTank") and PlayerIsTank())
    if over and not warned then UI._PlayLSMSound(UI.SoundPathFor(S.Get("warnSoundKey"))) end
    warned = over
end

local function RenderSample()
    Clear()
    local samples = { { "Tank", 10000, 100, true }, { UnitName("player"), 8200, 82 },
        { "Healer", 6100, 61 }, { "Hunter", 3400, 34 } }
    for i, s in ipairs(samples) do
        local e = NextEntry()
        e.unit, e.name, e.raw, e.scaled, e.tanking = "player", s[1], s[2], s[3], s[4] == true
        e.isPlayer, e.pull = i == 2, false
    end
    AddPullEntry(list[2])
    table.sort(list, ByThreat)
    Render("Threat Meter")
end

local Update

-- UNIT_THREAT_LIST_UPDATE names a real unit token (target, a nameplate, a boss), never
-- targettarget, so while the meter follows a friendly target's enemy nothing reports that
-- mob's threat moving. Re-read on a short interval in that one case, and only in combat.
local function SetFollow(on)
    if on and not followTicker then
        followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, function() Update() end)
    elseif not on and followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

function Update()
    pendingUpdate = false
    if not frame then return end
    if unlocked then
        SetFollow(false)
        RenderSample()
        frame:Show()
        return
    end
    if not On() then
        SetFollow(false)
        frame:Hide()
        return
    end
    local mob = ThreatMob()
    SetFollow(mob == "targettarget" and InCombatLockdown())
    if mob then Collect(mob) end
    if not mob or #list == 0 then
        warned = false
        frame:Hide()
        return
    end
    local me
    for i = 1, #list do
        if list[i].isPlayer then me = list[i] break end
    end
    CheckWarning(me)
    if S.Get("pullBar") then AddPullEntry(me) end
    table.sort(list, ByThreat)
    Render(UnitName(mob))
    frame:Show()
end

-- Threat updates arrive per unit, so a raid pull is a burst; one redraw per short window
-- covers the whole burst.
local function RequestUpdate()
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(UPDATE_DELAY, Update)
end

-- Every mob's threat list reports, nameplates included; only the target's matters here
-- (a followed targettarget is read on the ticker).
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_THREAT_LIST_UPDATE" and not (unit and UnitIsUnit(unit, "target")) then return end
    RequestUpdate()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        SetFollow(false)
        warned = false
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Place()
    frame.mover:SetShown(unlocked == true)
    if On() then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterUnitEvent("UNIT_TARGET", "target")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    Update()
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
local function ColorRow(k, text, on)
    return { type = "colorpicker", text = text, hasAlpha = false,
        getValue = function()
            local c = S.Get(k)
            return c.r, c.g, c.b
        end,
        setValue = function(r, g, b)
            S.Set(k, { r = r, g = g, b = b })
            RequestUpdate()
        end,
        disabled = function() return not (S.Get("enabled") and S.Get(on)) end }
end

function ns.BuildThreatMeterPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Threat on your target for everyone in your group, one bar each, "
        .. "sorted. With a friendly target, like a healer on the tank, it shows what they are "
        .. "fighting. Move it in Unlock Mode.", y); y = y - h

    _, h = W:SectionHeader(parent, "LAYOUT" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("width", "Width", 120, 400, 1, nil, "enabled"),
        S.Slider("barHeight", "Bar Height", 12, 32, 1, nil, "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("maxBars", "Most Bars", 1, 40, 1, nil, "enabled"),
        S.Toggle("growUp", "Grow Upward", "New bars stack above the first instead of below.",
            "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showHeader", "Show Target Name", "A title bar naming the mob the threat is on.",
            "enabled"),
        S.Toggle("ignorePets", "Ignore Pets", "Leave hunter and warlock pets off the meter.",
            "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showValue", "Show Threat", nil, "enabled"),
        S.Toggle("showPercent", "Show Percent",
            "How close each player is to pulling aggro: 100% takes it.", "enabled")
    ); y = y - h

    _, h = W:SectionHeader(parent, "COLORS", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("playerColorOn", "Color Your Bar", "Your own bar in one color instead of your class color.",
            "enabled"),
        ColorRow("playerColor", "Your Color", "playerColorOn")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("tankColorOn", "Color the Tank", "Whoever holds aggro in one color.", "enabled"),
        ColorRow("tankColor", "Tank Color", "tankColorOn")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("pullBar", "Pull Aggro Bar",
            "A bar at the threat where you would pull aggro, so the gap to it is easy to read.",
            "enabled"),
        ColorRow("pullColor", "Pull Aggro Color", "pullBar")
    ); y = y - h

    local _, names, order = ns.SoundChoices()
    names.none = "None"
    table.insert(order, 1, "none")
    _, h = W:SectionHeader(parent, "WARNING", y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("warnSound", "Warning Sound",
            "Plays once when your threat climbs past the threshold, and again only after it "
            .. "drops back below.", "enabled"),
        S.Slider("warnAt", "Warn At (%)", 50, 100, 1, nil, "warnSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("warnSoundKey", "Sound", names, order, nil, "warnSound"),
        S.Toggle("warnSkipTank", "Not While Tanking",
            "No warning in a tank role, Bear Form or Defensive Stance.", "warnSound")
    ); y = y - h

    return y
end

hooksecurefunc(S, "Set", function(key)
    if key == "threatPos" then return end
    if key == "enabled" then Apply() else RequestUpdate() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
