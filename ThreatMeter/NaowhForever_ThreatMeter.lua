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
    width = 280, height = 240, barHeight = 24, maxBars = 40,
    source = "target", focusEnabled = false, visibility = "threat",
    locked = true, barSpacing = 3, fontSize = 12, font = "",
    showIcons = true, showRanks = true, highlightPlayer = true,
    backgroundAlpha = 0.94, barAlpha = 0.72, texture = "smooth", percentMode = "pull",
    growUp = false, showHeader = true, ignorePets = false, statusPos = "bottom",
    showValue = true, showPercent = true,
    playerColorOn = false, playerColor = { r = 0.8, g = 0.1, b = 0.1 },
    tankColorOn = false, tankColor = { r = 0.1, g = 0.6, b = 0.1 },
    pullBar = true, pullColor = { r = 0.0, g = 0.55, b = 0.0 },
    themeColors = false,
    warnSound = false, warnSoundKey = "none", warnAt = 80, warnSkipTank = true,
})
ns.ThreatMeterSettings = S

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local TEXT_PAD = 8
local INSET, FOOTER = 8, 24
local Update, RequestUpdate, RenderSample, Render
local renderedTitle, renderedPlayer
local offset, currentMob, warnedMob, preview = 0, nil, nil, false
local updateGeneration = 0
local threatEventsOn = false
local events

local FALLBACK_COLOR = { r = 0.6, g = 0.6, b = 0.6 }
-- The window's own blue-tinted dark scheme; ns.ThemeTint swaps in the player's theme colors.
local WINDOW_BG = { r = 0.025, g = 0.04, b = 0.055 }
local WINDOW_EDGE = { r = 0.10, g = 0.19, b = 0.24 }
local HEADER_BG = { r = 0.04, g = 0.075, b = 0.095 }
local ROW_BG = { r = 0.065, g = 0.085, b = 0.105 }

local frame, pendingUpdate, followTicker, unlocked, warned
local rows = {}         -- bar widgets, created on demand
local entries = {}      -- reused threat entries, one per unit seen
local list = {}         -- the entries shown this update, sorted
local count = 0

local function On()
    return S.Get("enabled")
end

local function Readable(v)
    return not (issecretvalue and issecretvalue(v)) and v ~= nil
end

-- Forever returns threat in display units already, not the x100 scale Classic's API uses.
local function ShortThreat(v)
    if v >= 1000000 then return ("%.1fm"):format(v / 1000000) end
    if v >= 1000 then return ("%.1fk"):format(v / 1000) end
    return tostring(math.floor(v + 0.5))
end

-- The mob whose threat table is shown: your target when you can attack it, otherwise what
-- your friendly target is fighting (a healer targeting the tank).
local function TrackedUnit()
    return S.Get("focusEnabled") and S.Get("source") == "focus" and "focus" or "target"
end

local function Attackable(unit)
    local exists, hostile = UnitExists(unit), UnitCanAttack("player", unit)
    return Readable(exists) and exists and Readable(hostile) and hostile
end

local function ThreatMob()
    local tracked = TrackedUnit()
    if Attackable(tracked) then return tracked end
    local other = tracked == "focus" and "focustarget" or "targettarget"
    if Attackable(other) then return other end
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
    return S.Get("showHeader") and 48 or 0
end

local function FontPath()
    local key = S.Get("font")
    return UI.FontPath(key)
end

local function CreateRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetMinMaxValues(0, 1)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT"); row.edge:SetPoint("BOTTOMLEFT"); row.edge:SetWidth(2)
    row.rank = ns.Font(row, 10, "OUTLINE", T.muted)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.value = ns.Font(row, 12, "OUTLINE")
    row.value:SetJustifyH("RIGHT")
    row.percent = ns.Font(row, 12, "OUTLINE")
    row.percent:SetJustifyH("RIGHT")
    row.name = ns.Font(row, 12, "OUTLINE")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    rows[i] = row
    return row
end

local function ResizeMetrics()
    local start = frame.resizeStart
    if not start then return S.Get("barHeight"), S.Get("barSpacing"), S.Get("fontSize") end
    local chrome = HeaderHeight() + FOOTER + 2 * INSET
    local ratio = math.max(1, frame:GetHeight() - chrome) / start.contentHeight
    local textRatio = math.min(ratio, frame:GetWidth() / start.width)
    return math.max(12, math.min(72, start.barHeight * ratio)),
        math.max(0, math.min(16, start.spacing * ratio)),
        math.max(8, math.min(24, start.fontSize * textRatio))
end

local function Layout()
    local bh, w, top = S.Get("barHeight"), math.max(240, S.Get("width")), HeaderHeight()
    local gap, fontSize = S.Get("barSpacing"), S.Get("fontSize")
    if frame.sizing then bh, gap, fontSize = ResizeMetrics() end
    local minHeight = math.max(120, top + FOOTER + 2 * INSET + bh)
    local h = math.max(minHeight, S.Get("height"))
    frame:SetResizeBounds(240, minHeight, 520, 700)
    if not frame.sizing then frame:SetSize(w, h) else w, h = frame:GetWidth(), frame:GetHeight() end
    local iconSize = math.min(32, bh - 6)
    local iconWidth = S.Get("showIcons") and iconSize + 6 or 0
    local rankWidth = S.Get("showRanks") and 18 or 0
    local columns = (S.Get("showPercent") and 45 or 0) + (S.Get("showValue") and 54 or 0)
    if columns > 0 then
        local available = w - 2 * INSET - 2 * TEXT_PAD - iconWidth - rankWidth - 5 - 48
        fontSize = math.max(8, math.min(fontSize, available * 12 / columns))
    end
    local capacity = math.max(1, math.floor((h - top - FOOTER - 2 * INSET + gap) / (bh + gap)))
    local total = math.min(#list, S.Get("maxBars"))
    offset = math.max(0, math.min(offset, total - capacity))
    local shown = math.min(total - offset, capacity)
    local growUp = S.Get("growUp")
    local statusTop = S.Get("statusPos") == "top"
    local above, below = top + (statusTop and FOOTER or 0), statusTop and 0 or FOOTER
    for i = 1, shown do
        local row = rows[i] or CreateRow(i)
        row:ClearAllPoints()
        if growUp then row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET, below + INSET + (i - 1) * (bh + gap))
        else row:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -above - INSET - (i - 1) * (bh + gap)) end
        row:SetSize(w - 2 * INSET, bh)
        row:SetStatusBarTexture(S.Get("texture") == "flat" and "Interface\\Buttons\\WHITE8X8"
            or "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga")
        local left = TEXT_PAD
        row.rank:ClearAllPoints(); row.rank:SetPoint("LEFT", left, 0); row.rank:SetWidth(16)
        row.rank:SetShown(S.Get("showRanks"))
        if S.Get("showRanks") then left = left + 18 end
        row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", left, 0); row.icon:SetSize(iconSize, iconSize)
        row.icon:SetShown(S.Get("showIcons"))
        left = left + iconWidth
        local percentWidth = S.Get("showPercent") and 45 * fontSize / 12 or 0
        local valueWidth = S.Get("showValue") and 54 * fontSize / 12 or 0
        row.percent:ClearAllPoints(); row.percent:SetPoint("RIGHT", -TEXT_PAD, 0); row.percent:SetWidth(math.max(1, percentWidth))
        row.value:ClearAllPoints(); row.value:SetPoint("RIGHT", -TEXT_PAD - percentWidth, 0); row.value:SetWidth(math.max(1, valueWidth))
        row.name:ClearAllPoints(); row.name:SetPoint("LEFT", left, 0)
        row.name:SetPoint("RIGHT", -TEXT_PAD - percentWidth - valueWidth - 5, 0)
        local font = FontPath()
        row.name:SetFont(font, fontSize, "OUTLINE")
        row.value:SetFont(font, fontSize, "OUTLINE")
        row.percent:SetFont(font, fontSize, "OUTLINE")
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    frame.header:SetSize(w, math.max(top, 1))
    frame.header:SetShown(top > 0)
    frame.footer:ClearAllPoints()
    if statusTop then
        frame.footer:SetPoint("TOPLEFT", 8, -top); frame.footer:SetPoint("TOPRIGHT", -8, -top)
    else
        frame.footer:SetPoint("BOTTOMLEFT", 8, 0); frame.footer:SetPoint("BOTTOMRIGHT", -8, 0)
    end
    frame.background:SetAlpha(S.Get("backgroundAlpha"))
    frame.source.label:SetText(TrackedUnit() == "focus" and "Focus" or "Target")
    frame.source:SetShown(S.Get("focusEnabled"))
    frame.lock.label:SetText(S.Get("locked") and "L" or "U")
    frame.grip:SetShown(not unlocked and not (statusTop and S.Get("locked")))
    frame.grip:SetAlpha(S.Get("locked") and 0.4 or 1)
    frame.empty:SetShown(shown == 0)
    frame.footer.range:SetText(total > 0 and ((offset + 1) .. "-" .. (offset + shown) .. " / " .. total) or "")
    return shown
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

local function SavePosition()
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = frame:GetLeft() * scale, frame:GetTop() * scale - UIParent:GetHeight()
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    S.Set("threatPos", { point = "TOPLEFT", relPoint = "TOPLEFT", x = x, y = y })
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverThreatMeter", UIParent)
    frame:SetMovable(true); frame:SetClampedToScreen(true); frame:SetResizable(true)
    frame:SetResizeBounds(240, 120, 520, 700)
    frame.background = ns.Solid(frame, "BACKGROUND", ns.ThemeTint("bg", WINDOW_BG), 1)
    frame.background:SetAllPoints()
    ns.Border(frame, ns.ThemeTint("line", WINDOW_EDGE))
    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT")
    ns.Solid(frame.header, "BACKGROUND", ns.ThemeTint("panel", HEADER_BG), 1):SetAllPoints()
    local line = ns.Solid(frame.header, "OVERLAY", T.accent, 0.8)
    line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(2)
    frame.header.kicker = ns.Font(frame.header, 9, "OUTLINE", T.accent)
    frame.header.kicker:SetPoint("TOPLEFT", 10, -7); frame.header.kicker:SetText("THREAT")
    frame.header.text = ns.Font(frame.header, 13, "OUTLINE")
    frame.header.text:SetPoint("BOTTOMLEFT", 10, 7)
    frame.header.text:SetPoint("RIGHT", -82, 0)
    frame.header.text:SetJustifyH("LEFT"); frame.header.text:SetWordWrap(false)
    frame.source = ns.Button(frame.header, "Target", 58, 18, function()
        S.Set("source", TrackedUnit() == "focus" and "target" or "focus")
    end)
    frame.source:SetPoint("TOPRIGHT", -8, -5)
    ns.Tooltip(frame.source, "Threat Source", "Click to switch between your target and focus.")
    frame.lock = ns.Button(frame.header, "L", 22, 18, function() S.Set("locked", not S.Get("locked")) end)
    frame.lock:SetPoint("BOTTOMRIGHT", -34, 5)
    ns.Tooltip(frame.lock, "Window Lock", "Unlock to drag the header and resize with the bottom-right grip.")
    local settings = ns.Button(frame.header, "...", 22, 18, function() ns.OpenOptionsWindow("Threat Meter") end)
    settings:SetPoint("BOTTOMRIGHT", -8, 5)
    ns.Tooltip(settings, "Threat Meter Settings")
    frame.header:EnableMouse(true); frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if not S.Get("locked") and not unlocked and not InCombatLockdown() then frame.moving = true; frame:StartMoving() end
    end)
    frame.header:SetScript("OnDragStop", function() if frame.moving then frame:StopMovingOrSizing(); frame.moving = false; SavePosition() end end)
    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetHeight(FOOTER)
    frame.footer.state = ns.Font(frame.footer, 10, "OUTLINE", T.muted)
    frame.footer.state:SetPoint("LEFT"); frame.footer.state:SetJustifyH("LEFT")
    frame.footer.range = ns.Font(frame.footer, 10, "OUTLINE", T.muted)
    frame.footer.range:SetPoint("RIGHT", -12, 0)
    frame.empty = ns.Font(frame, 12, "OUTLINE", T.muted)
    frame.empty:SetPoint("CENTER", 0, -10); frame.empty:SetText("Waiting for threat")
    frame.grip = CreateFrame("Button", nil, frame)
    frame.grip:SetSize(20, 20)
    frame.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    ns.Tooltip(frame.grip, "Resize Threat Meter", "Drag to resize. Turn off Lock Window first; resizing is available outside combat.")
    frame.grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or S.Get("locked") or unlocked or InCombatLockdown() then return end
        SavePosition()
        frame.resizeStart = { contentHeight = math.max(1, frame:GetHeight() - HeaderHeight() - FOOTER - 2 * INSET),
            width = frame:GetWidth(), barHeight = S.Get("barHeight"), spacing = S.Get("barSpacing"), fontSize = S.Get("fontSize") }
        frame.sizing = true; frame:StartSizing("BOTTOMRIGHT")
    end)
    frame.grip:SetScript("OnMouseUp", function()
        if not frame.sizing then return end
        local bh, gap, fontSize = ResizeMetrics()
        local width, height = frame:GetWidth(), frame:GetHeight()
        frame:StopMovingOrSizing(); frame.sizing = false; frame.resizeStart = nil
        S.Set("barHeight", bh); S.Set("barSpacing", gap); S.Set("fontSize", fontSize)
        S.Set("width", math.floor(width + 0.5)); S.Set("height", math.floor(height + 0.5))
        SavePosition(); Update()
    end)
    frame:SetScript("OnSizeChanged", function()
        if frame.sizing then Render(renderedTitle, renderedPlayer) end
    end)
    frame:SetScript("OnHide", function()
        if frame.moving or frame.sizing then
            frame:StopMovingOrSizing(); frame.moving, frame.sizing = false, false
        end
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) offset = math.max(0, offset - delta); Update() end)
    frame.mover = UI.AttachMover(frame, "Threat Meter", function(pos) S.Set("threatPos", pos) end, "Threat Meter/Meter")
    frame:Hide(); Place()
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
    local tanking, _, scaled, rawPct, raw = UnitDetailedThreatSituation(unit, mob)
    if not (Readable(raw) and Readable(scaled) and Readable(tanking)) or raw <= 0 then return end
    local e = NextEntry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = unit, UnitName(unit), raw, scaled, tanking
    local own = UnitIsUnit(unit, "player")
    e.isPlayer, e.pull = Readable(own) and own, nil
    e.rawPct = Readable(rawPct) and rawPct or nil
    e.order, e.class = count, nil
    local owner = unit == "pet" and "player" or unit:gsub("pet", "")
    e.isPet = owner ~= unit
    local _, class = UnitClass(owner)
    if Readable(class) then e.class = class end
end

local RAID, RAID_PETS, PARTY, PARTY_PETS = {}, {}, {}, {}
for i = 1, MAX_RAID_MEMBERS do RAID[i], RAID_PETS[i] = "raid" .. i, "raidpet" .. i end
for i = 1, MAX_PARTY_MEMBERS do PARTY[i], PARTY_PETS[i] = "party" .. i, "partypet" .. i end

local function Collect(mob)
    Clear()
    local pets = not S.Get("ignorePets")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            Add(RAID[i], mob)
            if pets then Add(RAID_PETS[i], mob) end
        end
    else
        Add("player", mob)
        if pets then Add("pet", mob) end
        for i = 1, GetNumSubgroupMembers() do
            Add(PARTY[i], mob)
            if pets then Add(PARTY_PETS[i], mob) end
        end
    end
end

local function ByThreat(a, b)
    if a.raw == b.raw then return a.order < b.order end
    return a.raw > b.raw
end

-- Where you pull aggro: scaled percent is threat against your own pull line (100 = you
-- take it), so the line is your threat scaled up to 100.
local function AddPullEntry(me, tankRaw)
    if not (me and not me.tanking and me.scaled > 0) then return end
    local e = NextEntry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = nil, "Pull Aggro", me.raw * 100 / me.scaled, 100, false
    e.isPlayer, e.pull, e.isPet, e.class, e.order = false, true, false, nil, 0
    e.rawPct = tankRaw and tankRaw > 0 and e.raw * 100 / tankRaw or nil
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
-- Apply Theme to Your Bar: your bar in a darker shade of the theme's Accent, so the white names
-- and numbers stay readable on it. The tank and pull aggro bars keep their own colors, which
-- tell the roles apart. The shade is built once, on first use, after the theme is applied.
local yourShade
local function ThemedColor(key)
    if key ~= "playerColor" then return nil end
    yourShade = yourShade or { r = T.accent.r * 0.75, g = T.accent.g * 0.75, b = T.accent.b * 0.75 }
    return yourShade
end

-- The color a bar setting paints with: the theme's while the switch is on, else the picked one.
local function BarColor(key)
    return S.Get("themeColors") and ThemedColor(key) or S.Get(key)
end

local function RowColor(e)
    if e.pull then return BarColor("pullColor") end
    if e.isPlayer and S.Get("playerColorOn") then return BarColor("playerColor") end
    if e.tanking and S.Get("tankColorOn") then return BarColor("tankColor") end
    return e.class and RAID_CLASS_COLORS[e.class] or FALLBACK_COLOR
end

function Render(title, me)
    renderedTitle, renderedPlayer = title, me
    local shown = Layout()
    local top = list[1] and list[1].raw or 0
    frame.header.text:SetText(title)
    local rank = 0
    for _, e in ipairs(list) do
        if not e.pull then rank = rank + 1 end
        e.rank = rank
    end
    local rowBg = ns.ThemeTint("panel", ROW_BG)
    for i = 1, shown do
        local e, row = list[offset + i], rows[i]
        local c = RowColor(e)
        row:SetStatusBarColor(c.r, c.g, c.b, S.Get("barAlpha"))
        row.bg:SetColorTexture(rowBg.r, rowBg.g, rowBg.b, 1)
        local own = e.isPlayer and S.Get("highlightPlayer")
        row.edge:SetColorTexture(own and T.accent.r or c.r, own and T.accent.g or c.g, own and T.accent.b or c.b, 1)
        row:SetValue(top > 0 and e.raw / top or 0)
        row.rank:SetText(e.pull and "-" or tostring(e.rank))
        row.name:SetText(e.name)
        row.name:SetTextColor(1, 1, 1)
        if own then
            local mark = ns.ThemeTint("accent", nil)   -- the accent, darkened, once it was changed
            if mark then row.bg:SetColorTexture(mark.r * 0.27, mark.g * 0.27, mark.b * 0.27, 1)
            else row.bg:SetColorTexture(0.04, 0.19, 0.25, 1) end
        end
        row.icon:SetTexture(e.pull and "Interface\\Icons\\Ability_Warrior_Challange"
            or e.class and ("Interface\\Icons\\ClassIcon_" .. e.class) or "Interface\\Icons\\Ability_Hunter_BeastCall")
        row.icon:SetDesaturated(e.isPet == true)
        row.value:SetText(S.Get("showValue") and ShortThreat(e.raw) or "")
        local percent = e.scaled
        if S.Get("percentMode") == "tank" then percent = e.rawPct end
        row.percent:SetText(S.Get("showPercent") and percent and ("%.0f%%"):format(percent) or "")
        local danger = not e.pull and not e.tanking and e.scaled >= S.Get("warnAt")
        row.percent:SetTextColor(1, danger and 0.35 or 1, danger and 0.25 or 1)
    end
    if preview or unlocked then frame.footer.state:SetText("PREVIEW")
    elseif me and me.tanking then frame.footer.state:SetText("HOLDING AGGRO")
    elseif me then frame.footer.state:SetText(("YOU %.0f%% TO PULL"):format(me.scaled))
    else frame.footer.state:SetText("NO PLAYER THREAT") end
end

local function CheckWarning(me)
    if not S.Get("warnSound") then warned = false; return end
    local over = me and not me.tanking and me.scaled >= S.Get("warnAt")
        and not (S.Get("warnSkipTank") and PlayerIsTank())
    if over and not warned then UI._PlayLSMSound(UI.SoundPathFor(S.Get("warnSoundKey"))) end
    warned = over
end

function RenderSample()
    Clear()
    local samples = { { "Tank", 10000, 100, true }, { UnitName("player"), 8200, 82 },
        { "Healer", 6100, 61 }, { "Hunter", 3400, 34 } }
    for i, s in ipairs(samples) do
        local e = NextEntry()
        e.unit, e.name, e.raw, e.scaled, e.tanking = "player", s[1], s[2], s[3], s[4] == true
        e.isPlayer, e.pull = i == 2, false
    end
    local classes = { "WARRIOR", "PALADIN", "PRIEST", "HUNTER" }
    for i, e in ipairs(list) do e.class, e.isPet, e.order, e.rawPct = classes[i], false, i, e.scaled end
    if S.Get("pullBar") then AddPullEntry(list[2], 10000) end
    table.sort(list, ByThreat)
    Render("Training Dummy")
end


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

local function SetThreatEvents(on)
    if threatEventsOn == on then return end
    threatEventsOn = on
    if on then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

function Update()
    pendingUpdate = false
    if not frame then return end
    if not On() then SetFollow(false); frame:Hide(); return end
    if unlocked or preview then
        SetThreatEvents(false); SetFollow(false); RenderSample(); frame:Show(); return
    end
    local mob = ThreatMob()
    currentMob = mob
    SetThreatEvents(mob ~= nil)
    local visible = S.Get("visibility")
    local combat = InCombatLockdown()
    if mob then
        local fighting = UnitAffectingCombat(mob)
        combat = combat or Readable(fighting) and fighting
    end
    if visible == "combat" and not combat or visible == "group" and not IsInGroup() then
        SetFollow(false); frame:Hide(); return
    end
    SetFollow(mob ~= nil and mob ~= TrackedUnit() and combat)
    if mob then Collect(mob) else Clear() end
    if #list == 0 then
        warned, warnedMob = false, nil
        if visible == "threat" then frame:Hide(); return end
        Render(mob and UnitName(mob) or "No target"); frame:Show(); return
    end
    local me, tankRaw
    for _, e in ipairs(list) do
        if e.isPlayer then me = e end
        if e.tanking then tankRaw = e.raw end
    end
    local guid = UnitGUID(mob)
    if Readable(guid) and guid ~= warnedMob then warned, warnedMob, offset = false, guid, 0 end
    CheckWarning(me)
    if S.Get("pullBar") then AddPullEntry(me, tankRaw) end
    table.sort(list, ByThreat)
    Render(UnitName(mob), me); frame:Show()
end

function RequestUpdate()
    if pendingUpdate or not On() then return end
    pendingUpdate = true
    local generation = updateGeneration
    C_Timer.After(UPDATE_DELAY, function() if generation == updateGeneration then Update() end end)
end

events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        if (event == "PLAYER_FOCUS_CHANGED") ~= (TrackedUnit() == "focus") then return end
        warned, warnedMob, offset = false, nil, 0
    elseif event == "PLAYER_REGEN_DISABLED" then
        preview = false
        if frame and (frame.sizing or frame.moving) then frame:StopMovingOrSizing(); frame.sizing, frame.moving = false, false end
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        if not Readable(unit) or not currentMob then return end
        local same = UnitIsUnit(unit, currentMob)
        if Readable(same) and not same then return end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_PET" then
        if not Readable(unit) then return end
        if unit ~= "player" and unit ~= "pet" and not unit:match("^party%d+$")
            and not unit:match("^raid%d+$") and not unit:match("^partypet%d+$") and not unit:match("^raidpet%d+$") then return end
    end
    RequestUpdate()
end)

-- Hide When Empty became a Show option. Runs once per profile.
local function MigrateVisibility()
    local db = S.DB()
    if db.visibilityMerged then return end
    db.visibilityMerged = true
    local hideEmpty = db.onlyWithThreat
    if hideEmpty == nil then hideEmpty = true end   -- the old default
    db.onlyWithThreat = nil
    -- In Combat with it on becomes With Threat too: a mob only has a threat list while it is
    -- being fought. In a Group cannot hide the empty window any more; the changelog says so.
    local v = db.visibility
    if hideEmpty and (v == nil or v == "always" or v == "combat") then
        db.visibility = "threat"
    elseif db.visibility == nil then
        db.visibility = "always"   -- had it off on purpose; keep showing when empty
    end
end

local function Apply()
    MigrateVisibility()
    events:UnregisterAllEvents()
    threatEventsOn = false
    updateGeneration = updateGeneration + 1; pendingUpdate = false
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
        events:RegisterEvent("PLAYER_FOCUS_CHANGED")
        events:RegisterEvent("UNIT_PET")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterUnitEvent("UNIT_FLAGS", "target", "focus", "pet")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    Update()
end

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
local function ColorRow(k, text, on, themed)
    return { type = "colorpicker", text = text, hasAlpha = false,
        getValue = function()
            local c = BarColor(k)
            return c.r, c.g, c.b
        end,
        setValue = function(r, g, b)
            S.Set(k, { r = r, g = g, b = b })
            RequestUpdate()
        end,
        disabled = function()
            return not S.Get("enabled") or on and not S.Get(on) or (themed and S.Get("themeColors")) or false
        end,
        disabledTooltip = themed and "Turn off Apply Theme to Your Bar to pick this color." or nil }
end

function ns.BuildThreatMeterPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Track group threat on your target or focus. Friendly units show the enemy "
        .. "they are fighting. Scroll for more entries; unlock the window to drag and resize it, "
        .. "or position it in Unlock Mode.", y); y = y - h

    _, h = W:SectionHeader(parent, "METER", y); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Tracking" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("focusEnabled", "Enable Focus Tracking", "Adds target/focus switching to the header."),
        S.Dropdown("source", "Track", { target = "Target", focus = "Focus" }, { "target", "focus" }, nil, "focusEnabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("visibility", "Show",
            { always = "Always", threat = "With Threat", combat = "In Combat", group = "In a Group" },
            { "always", "threat", "combat", "group" },
            "With Threat: hidden until someone in your group has threat on the mob."),
        S.Dropdown("percentMode", "Percent Of", { pull = "Pull Aggro", tank = "Tank Threat" }, { "pull", "tank" },
            "Pull Aggro: 100% takes aggro. Tank Threat: 100% equals the current tank's threat.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "10-Second Preview", buttonText = "Preview", onClick = function() ns.PreviewThreatMeter() end }
    ); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Layout" .. UI.STATUS.untested }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("width", "Width", 240, 520, 1, nil, "enabled"),
        S.Slider("height", "Window Height", 120, 700, 1, nil, "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("maxBars", "Maximum Entries", 1, 80, 1, nil, "enabled"),
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
        S.Dropdown("statusPos", "Status Line", { bottom = "Bottom", top = "Top" }, { "bottom", "top" },
            "Where your distance to pulling aggro and the entry count sit: under the bars, or "
            .. "between the title bar and the bars.", "enabled"),
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showValue", "Show Threat", nil, "enabled"),
        S.Toggle("showPercent", "Show Percent",
            "Uses the selected Pull Aggro or Tank Threat percentage mode.", "enabled")
    ); y = y - h

    _, h = W:DualRow(parent, y,
        S.Slider("barHeight", "Row Height", 12, 72, 1),
        S.Slider("barSpacing", "Row Spacing", 0, 16, 1)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("locked", "Lock Window", "Off: drag the header or resize with the corner grip outside combat. Unlock Mode remains available."),
        S.Toggle("highlightPlayer", "Highlight Your Row")
    ); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Appearance" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showIcons", "Class Icons", "Pets use their owner's class icon, desaturated."),
        S.Toggle("showRanks", "Rank Numbers")
    ); y = y - h
    local fonts, fontOrder = UI.FontChoices(S.Get("font"))
    _, h = W:DualRow(parent, y,
        S.Dropdown("font", "Font", fonts, fontOrder),
        S.Slider("fontSize", "Text Size", 8, 24, 1)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("backgroundAlpha", "Background Opacity", 0, 1, 0.05),
        S.Slider("barAlpha", "Bar Opacity", 0.1, 1, 0.05)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Dropdown("texture", "Bar Texture", { smooth = "Naowh Gradient", flat = "Flat" }, { "smooth", "flat" }),
        { type = "label", text = "Mouse wheel scrolls the roster" }
    ); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Colours" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("playerColorOn", "Color Your Bar", "Your own bar in one color instead of your class color.",
            "enabled"),
        ColorRow("playerColor", "Your Color", "playerColorOn", true)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("themeColors", "Apply Theme to Your Bar",
            "Your bar in a darker shade of your theme's Accent instead of the color picked "
            .. "above. The tank and pull aggro colors stay as picked.", "playerColorOn"),
        { type = "label", text = "" }
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
    _, h = W:Feature(parent, y,
        S.Toggle("warnSound", "Warning Sound",
            "Plays once when your threat climbs past the threshold, and again only after it "
            .. "drops back below.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("warnAt", "Warn At (%)", 50, 100, 1, nil, "warnSound"),
        S.SoundDropdown("warnSoundKey", "Sound", names, order, nil, "warnSound")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("warnSkipTank", "Not While Tanking",
            "No warning in a tank role, Bear Form or Defensive Stance.", "warnSound"),
        { type = "label", text = "" }
    ); y = y - h

    return y
end

local previewGeneration = 0
function ns.PreviewThreatMeter()
    if not On() then ns.Print("Enable Threat Meter first.") return end
    if InCombatLockdown() then ns.Print("Preview is available outside combat.") return end
    previewGeneration = previewGeneration + 1
    local generation = previewGeneration
    preview = true
    Update()
    C_Timer.After(10, function()
        if generation == previewGeneration then preview = false; Update() end
    end)
end

hooksecurefunc(S, "Set", function(key)
    if key == "threatPos" then return end
    if key == "source" or key == "focusEnabled" then offset, warned, warnedMob = 0, false, nil end
    if key == "enabled" then previewGeneration = previewGeneration + 1; preview = false; Apply() else RequestUpdate() end
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
