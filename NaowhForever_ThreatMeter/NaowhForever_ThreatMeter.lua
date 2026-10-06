-------------------------------------------------------------------------------
--  NaowhForever_ThreatMeter.lua -- threat on your target for everyone in the group, one
--  bar each, sorted, with an optional pull aggro bar and a warning sound. Forever hands
--  the threat API over readable; a value that does come back secret skips that unit. The
--  Meter card's preview edits in place: its corner, wheel, clicks and row menu set the settings.
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

local Look = {}

function Look.New(frame)
    frame.rows = {}
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
    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetHeight(FOOTER)
    frame.footer.state = ns.Font(frame.footer, 10, "OUTLINE", T.muted)
    frame.footer.state:SetPoint("LEFT"); frame.footer.state:SetJustifyH("LEFT")
    frame.footer.range = ns.Font(frame.footer, 10, "OUTLINE", T.muted)
    frame.footer.range:SetPoint("RIGHT", -12, 0)
    frame.empty = ns.Font(frame, 12, "OUTLINE", T.muted)
    frame.empty:SetPoint("CENTER", 0, -10); frame.empty:SetText("Waiting for threat")
end

local frame, pendingUpdate, followTicker, unlocked, warned
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

function Look.Row(f, i)
    local row = CreateFrame("StatusBar", nil, f)
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
    f.rows[i] = row
    return row
end

function Look.Layout(f, total, first, bh, gap, fontSize)
    local w, top = math.max(240, S.Get("width")), HeaderHeight()
    local minHeight = math.max(120, top + FOOTER + 2 * INSET + bh)
    local h = math.max(minHeight, S.Get("height"))
    if not f.sizing then f:SetSize(w, h) else w, h = f:GetWidth(), f:GetHeight() end
    local iconSize = math.min(32, bh - 6)
    local iconWidth = S.Get("showIcons") and iconSize + 6 or 0
    local rankWidth = S.Get("showRanks") and 18 or 0
    local columns = (S.Get("showPercent") and 45 or 0) + (S.Get("showValue") and 54 or 0)
    if columns > 0 then
        local available = w - 2 * INSET - 2 * TEXT_PAD - iconWidth - rankWidth - 5 - 48
        fontSize = math.max(8, math.min(fontSize, available * 12 / columns))
    end
    local capacity = math.max(1, math.floor((h - top - FOOTER - 2 * INSET + gap) / (bh + gap)))
    first = math.max(0, math.min(first, total - capacity))
    local shown = math.min(total - first, capacity)
    local growUp = S.Get("growUp")
    local statusTop = S.Get("statusPos") == "top"
    local above, below = top + (statusTop and FOOTER or 0), statusTop and 0 or FOOTER
    local texture, font = S.Get("texture"), FontPath()
    local showRanks, showIcons = S.Get("showRanks"), S.Get("showIcons")
    local showPercent, showValue = S.Get("showPercent"), S.Get("showValue")
    local last = f.laid
    if not last then last = { gen = 0 }; f.laid = last end
    if f.sizing or last.w ~= w or last.h ~= h or last.bh ~= bh or last.gap ~= gap or last.fontSize ~= fontSize
        or last.iconSize ~= iconSize or last.growUp ~= growUp or last.above ~= above or last.below ~= below
        or last.texture ~= texture or last.font ~= font or last.showRanks ~= showRanks
        or last.showIcons ~= showIcons or last.showPercent ~= showPercent or last.showValue ~= showValue then
        last.w, last.h, last.bh, last.gap, last.fontSize, last.iconSize = w, h, bh, gap, fontSize, iconSize
        last.growUp, last.above, last.below, last.texture, last.font = growUp, above, below, texture, font
        last.showRanks, last.showIcons, last.showPercent, last.showValue = showRanks, showIcons, showPercent, showValue
        last.gen = last.gen + 1
        f.header:SetSize(w, math.max(top, 1))
        f.header:SetShown(top > 0)
        f.footer:ClearAllPoints()
        if statusTop then
            f.footer:SetPoint("TOPLEFT", 8, -top); f.footer:SetPoint("TOPRIGHT", -8, -top)
        else
            f.footer:SetPoint("BOTTOMLEFT", 8, 0); f.footer:SetPoint("BOTTOMRIGHT", -8, 0)
        end
    end
    local rows = f.rows
    for i = 1, shown do
        local row = rows[i] or Look.Row(f, i)
        if row.laid ~= last.gen then
            row.laid = last.gen
            row:ClearAllPoints()
            if growUp then row:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", INSET, below + INSET + (i - 1) * (bh + gap))
            else row:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -above - INSET - (i - 1) * (bh + gap)) end
            row:SetSize(w - 2 * INSET, bh)
            row:SetStatusBarTexture(texture == "flat" and "Interface\\Buttons\\WHITE8X8"
                or "Interface\\AddOns\\NaowhForever\\Media\\NaowhGradient.tga")
            local left = TEXT_PAD
            row.rank:ClearAllPoints(); row.rank:SetPoint("LEFT", left, 0); row.rank:SetWidth(16)
            row.rank:SetShown(showRanks)
            if showRanks then left = left + 18 end
            row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", left, 0); row.icon:SetSize(iconSize, iconSize)
            row.icon:SetShown(showIcons)
            left = left + iconWidth
            local percentWidth = showPercent and 45 * fontSize / 12 or 0
            local valueWidth = showValue and 54 * fontSize / 12 or 0
            row.percent:ClearAllPoints(); row.percent:SetPoint("RIGHT", -TEXT_PAD, 0); row.percent:SetWidth(math.max(1, percentWidth))
            row.value:ClearAllPoints(); row.value:SetPoint("RIGHT", -TEXT_PAD - percentWidth, 0); row.value:SetWidth(math.max(1, valueWidth))
            row.name:ClearAllPoints(); row.name:SetPoint("LEFT", left, 0)
            row.name:SetPoint("RIGHT", -TEXT_PAD - percentWidth - valueWidth - 5, 0)
            row.name:SetFont(font, fontSize, "OUTLINE")
            row.value:SetFont(font, fontSize, "OUTLINE")
            row.percent:SetFont(font, fontSize, "OUTLINE")
        end
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    f.background:SetAlpha(S.Get("backgroundAlpha"))
    f.empty:SetShown(shown == 0)
    if last.total ~= total or last.first ~= first or last.shown ~= shown then
        last.total, last.first, last.shown = total, first, shown
        f.footer.range:SetText(total > 0 and ((first + 1) .. "-" .. (first + shown) .. " / " .. total) or "")
    end
    return shown, first
end

local function Layout()
    local bh, gap, fontSize = S.Get("barHeight"), S.Get("barSpacing"), S.Get("fontSize")
    if frame.sizing then bh, gap, fontSize = ResizeMetrics() end
    frame:SetResizeBounds(240, math.max(120, HeaderHeight() + FOOTER + 2 * INSET + bh), 520, 700)
    local shown
    shown, offset = Look.Layout(frame, math.min(#list, S.Get("maxBars")), offset, bh, gap, fontSize)
    frame.source.label:SetText(TrackedUnit() == "focus" and "Focus" or "Target")
    frame.source:SetShown(S.Get("focusEnabled"))
    frame.lock.label:SetText(S.Get("locked") and "L" or "U")
    local statusTop = S.Get("statusPos") == "top"
    frame.grip:SetShown(not unlocked and not (statusTop and S.Get("locked")))
    frame.grip:SetAlpha(S.Get("locked") and 0.4 or 1)
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
    Look.New(frame)
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
    ns.AllowOffscreen(frame)
    frame:SetScript("OnHide", function()
        if frame.moving or frame.sizing then
            frame:StopMovingOrSizing(); frame.moving, frame.sizing = false, false
        end
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) offset = math.max(0, offset - delta); Update() end)
    frame.mover = UI.AttachMover(frame, "Threat Meter", function(pos) S.Set("threatPos", pos) end,
        "Threat Meter/Settings", "Threat Meter/Settings:meter")
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

local RAID, RAID_PETS, PARTY, PARTY_PETS = {}, {}, {}, {}
local OWNER, GROUP_UNIT = { player = "player", pet = "player" }, { player = true, pet = true }
for i = 1, MAX_RAID_MEMBERS do RAID[i], RAID_PETS[i] = "raid" .. i, "raidpet" .. i end
for i = 1, MAX_PARTY_MEMBERS do PARTY[i], PARTY_PETS[i] = "party" .. i, "partypet" .. i end
for _, pair in ipairs({ { RAID, RAID_PETS }, { PARTY, PARTY_PETS } }) do
    for i, unit in ipairs(pair[1]) do
        local pet = pair[2][i]
        OWNER[unit], OWNER[pet] = unit, unit
        GROUP_UNIT[unit], GROUP_UNIT[pet] = true, true
    end
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
    local owner = OWNER[unit]
    e.isPet = owner ~= unit
    local _, class = UnitClass(owner)
    if Readable(class) then e.class = class end
end

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
local function FillPull(e, me, tankRaw)
    e.unit, e.name, e.raw, e.scaled, e.tanking = nil, "Pull Aggro", me.raw * 100 / me.scaled, 100, false
    e.isPlayer, e.pull, e.isPet, e.class, e.order = false, true, false, nil, 0
    e.rawPct = tankRaw and tankRaw > 0 and e.raw * 100 / tankRaw or nil
end

local function AddPullEntry(me, tankRaw)
    if not (me and not me.tanking and me.scaled > 0) then return end
    FillPull(NextEntry(), me, tankRaw)
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

function Look.State(me)
    if me and me.tanking then return "HOLDING AGGRO" end
    if me then return ("YOU %.0f%% TO PULL"):format(me.scaled) end
    return "NO PLAYER THREAT"
end

local classIcons = {}
local function ClassIcon(class)
    local path = classIcons[class]
    if not path then path = "Interface\\Icons\\ClassIcon_" .. class; classIcons[class] = path end
    return path
end

function Look.Paint(f, shownList, first, shown, title, state)
    local top = shownList[1] and shownList[1].raw or 0
    f.header.text:SetText(title)
    local rank = 0
    for _, e in ipairs(shownList) do
        if not e.pull then rank = rank + 1 end
        e.rank = rank
    end
    local rowBg = ns.ThemeTint("panel", ROW_BG)
    local showValue, showPercent = S.Get("showValue"), S.Get("showPercent")
    local tankPercent = S.Get("percentMode") == "tank"
    for i = 1, shown do
        local e, row = shownList[first + i], f.rows[i]
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
            or e.class and ClassIcon(e.class) or "Interface\\Icons\\Ability_Hunter_BeastCall")
        row.icon:SetDesaturated(e.isPet == true)
        local value = showValue and e.raw or false
        if row.shownValue ~= value then
            row.shownValue = value
            row.value:SetText(value and ShortThreat(value) or "")
        end
        local percent = e.scaled
        if tankPercent then percent = e.rawPct end
        percent = showPercent and percent or false
        if row.shownPercent ~= percent then
            row.shownPercent = percent
            row.percent:SetText(percent and ("%.0f%%"):format(percent) or "")
        end
        local danger = not e.pull and not e.tanking and e.scaled >= S.Get("warnAt")
        row.percent:SetTextColor(1, danger and 0.35 or 1, danger and 0.25 or 1)
    end
    f.footer.state:SetText(state)
end

function Render(title, me)
    renderedTitle, renderedPlayer = title, me
    local shown = Layout()
    Look.Paint(frame, list, offset, shown, title, (preview or unlocked) and "PREVIEW" or Look.State(me))
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
        if not Readable(unit) or not GROUP_UNIT[unit] then return end
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

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group

local OFF = "Turn on the Threat Meter"
local STAGE_H, STAGE_MARGIN = 300, 16
local NOTE_ROOM, NOTE_BOTTOM, NOTE_SIZE = 28, 8, 11
local HINT = "Drag the corner to resize. Wheel: row height (Shift: spacing, Ctrl: text). Right-click a row "
    .. "for what it shows. Click the name or status line to change them."
local OFF_HINT = "Turn on the Threat Meter to edit it here."
local EDIT_LEVEL, TOP_LEVEL = 10, 12
local HOVER_ALPHA = 0.12
local GRIP_SIZE, GRIP_INSET = 16, 2
local HEADER_STUB = 8
local WIDTH_RANGE, HEIGHT_RANGE = { 240, 520, 1 }, { 120, 700, 1 }
local ROW_H_RANGE, SPACING_RANGE, TEXT_RANGE = { 12, 72, 1 }, { 0, 16, 1 }, { 8, 24, 1 }
local SAMPLES = {
    solo = { title = "Defias Pillager",
        { you = true, raw = 1850, scaled = 100, tanking = true } },
    tanking = { title = "Edwin VanCleef",
        { you = true, raw = 12400, scaled = 100, tanking = true },
        { name = "Rogue", class = "ROGUE", raw = 9100, scaled = 67 },
        { name = "Mage", class = "MAGE", raw = 7300, scaled = 45 },
        { name = "Wolf", class = "HUNTER", pet = true, raw = 4200, scaled = 31 },
        { name = "Priest", class = "PRIEST", raw = 3100, scaled = 19 } },
    pulling = { title = "Edwin VanCleef",
        { you = true, raw = 10560, scaled = 96 },
        { name = "Tank", class = "WARRIOR", raw = 10000, scaled = 100, tanking = true },
        { name = "Healer", class = "PRIEST", raw = 4400, scaled = 34 },
        { name = "Hunter", class = "HUNTER", raw = 3900, scaled = 30 } },
}
local STATES = {
    { key = "solo", label = "Solo", tip = "On your own, holding the mob." },
    { key = "tanking", label = "Tanking", tip = "Your group on a boss you are tanking." },
    { key = "pulling", label = "Pulling Aggro", tip = "Close to pulling aggro off the tank." },
}
local VISIBILITY = { always = "Always", threat = "With Threat", combat = "In Combat", group = "In a Group" }
local SHOW = { VISIBILITY, { "always", "threat", "combat", "group" } }
local SOURCE = { { target = "Target", focus = "Focus" }, { "target", "focus" } }
local PERCENT = { { pull = "Pull Aggro", tank = "Tank Threat" }, { "pull", "tank" } }
local STATUS = { { bottom = "Bottom", top = "Top" }, { "bottom", "top" } }
local TEXTURE = { { smooth = "Naowh Gradient", flat = "Flat" }, { "smooth", "flat" } }
local ROW_TOGGLES = {
    { "showValue", "Show Threat" },
    { "showPercent", "Show Percent" },
    { "showIcons", "Class Icons" },
    { "showRanks", "Rank Numbers" },
    { "highlightPlayer", "Highlight Your Row" },
}
local TIPS = {
    { "grip", "Drag the corner", "Width and Height" },
    { "header", "Click the name", "Show Target Name" },
    { "status", "Click the status line", "Status Line" },
    { "rows", "Wheel on the rows", "Row Height" },
    { "rows", "Shift + wheel", "Row Spacing" },
    { "rows", "Ctrl + wheel", "Text Size" },
    { "rows", "Right-click a row", "What Rows Show" },
}

local function Enabled() return On() and true or false end
local function Needs(key) return function() return On() and S.Get(key) and true or false end end
local function OwnBar() return On() and S.Get("playerColorOn") and not S.Get("themeColors") end

local function Shade(key)
    return function()
        local c = BarColor(key)
        return c.r, c.g, c.b, 1
    end
end

local function Picked(key)
    return function(r, g, b) S.Set(key, { r = r, g = g, b = b }) end
end

local function SampleList(shot, state)
    local sample = SAMPLES[state]
    local out, pool = shot.list, shot.pool
    wipe(out)
    local _, class = UnitClass("player")
    local me, tankRaw
    for i, s in ipairs(sample) do
        if not (s.pet and S.Get("ignorePets")) then
            local e = pool[i]
            if not e then e = {}; pool[i] = e end
            e.unit, e.name = nil, s.you and (UnitName("player") or "You") or s.name
            e.raw, e.scaled, e.tanking = s.raw, s.scaled, s.tanking == true
            e.isPlayer, e.pull, e.isPet, e.order = s.you == true, false, s.pet == true, i
            e.class = s.you and class or s.class
            if e.tanking then tankRaw = e.raw end
            if e.isPlayer then me = e end
            out[#out + 1] = e
        end
    end
    for _, e in ipairs(out) do e.rawPct = tankRaw and e.raw * 100 / tankRaw or nil end
    if S.Get("pullBar") and me and not me.tanking then
        local e = pool[#sample + 1]
        if not e then e = {}; pool[#sample + 1] = e end
        FillPull(e, me, tankRaw)
        out[#out + 1] = e
    end
    table.sort(out, ByThreat)
    return sample.title, me
end

local function Snap(v, range)
    local low, high, step = range[1], range[2], range[3]
    v = low + math.floor((v - low) / step + 0.5) * step
    return math.max(low, math.min(high, v))
end

local function HideTip(shot)
    if GameTooltip:GetOwner() == shot.meter then GameTooltip:Hide() end
end

local function ShowTip(shot)
    local part, fg = shot.part, T.fg
    GameTooltip:SetOwner(shot.meter, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Edit the Meter", fg.r, fg.g, fg.b)
    for i = 1, #TIPS do
        local tip = TIPS[i]
        local c = tip[1] == part and T.accent or T.muted
        GameTooltip:AddDoubleLine(tip[2], tip[3], c.r, c.g, c.b, c.r, c.g, c.b)
    end
    GameTooltip:Show()
end

local function Unhover(shot)
    shot.part = nil
    shot.grip:Hide()
    HideTip(shot)
end

local function PartEnter(hit)
    local shot = hit.shot
    shot.part = hit.part
    if hit.wash then hit.wash:Show() end
    shot.grip:Show()
    if not shot.sizing then ShowTip(shot) end
end

local function PartLeave(hit)
    if hit.wash then hit.wash:Hide() end
    local shot = hit.shot
    if not shot.sizing and not shot.meter:IsMouseOver() then Unhover(shot) end
end

local function HeaderClick()
    S.Set("showHeader", not S.Get("showHeader"))
end

local function StatusClick()
    local order, current = STATUS[2], S.Get("statusPos")
    local picked = order[1]
    for i = 1, #order do
        if order[i] == current then
            picked = order[i % #order + 1]
            break
        end
    end
    S.Set("statusPos", picked)
end

local function RowsWheel(_, delta)
    local key, range = "barHeight", ROW_H_RANGE
    if IsControlKeyDown() then
        key, range = "fontSize", TEXT_RANGE
    elseif IsShiftKeyDown() then
        key, range = "barSpacing", SPACING_RANGE
    end
    local v = Snap(S.Get(key) + delta * range[3], range)
    if v ~= S.Get(key) then S.Set(key, v) end
end

local function Toggled(key)
    return S.Get(key) == true
end

local function Toggle(key)
    S.Set(key, not S.Get(key))
end

local function RowMenu(_, root)
    root:CreateTitle("Rows Show")
    for i = 1, #ROW_TOGGLES do
        local t = ROW_TOGGLES[i]
        root:CreateCheckbox(t[2], Toggled, Toggle, t[1])
    end
end

local function RowsUp(hit, button)
    if button ~= "RightButton" then return end
    HideTip(hit.shot)
    MenuUtil.CreateContextMenu(hit, RowMenu)
end

local function Fit(shot)
    local f, area = shot.meter, shot.area
    local w, h = f:GetWidth(), f:GetHeight()
    local roomW, roomH = area:GetWidth(), area:GetHeight()
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    if roomH > 0 and h > 0 and h * scale > roomH then scale = roomH / h end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", area, "CENTER", 0, 0)
end

local function PlaceHits(shot, shown)
    local f, header, rows = shot.meter, shot.headerHit, shot.rowsHit
    header:ClearAllPoints()
    if S.Get("showHeader") then
        header:SetAllPoints(f.header)
    else
        header:SetPoint("TOPLEFT", f, "TOPLEFT")
        header:SetPoint("TOPRIGHT", f, "TOPRIGHT")
        header:SetHeight(HEADER_STUB)
    end
    rows:ClearAllPoints()
    rows:SetShown(shown > 0)
    if shown == 0 then return end
    local first, last = f.rows[1], f.rows[shown]
    if S.Get("growUp") then first, last = last, first end
    rows:SetPoint("TOPLEFT", first, "TOPLEFT")
    rows:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT")
end

local function EndSize(shot)
    if not shot.sizing then return false end
    shot.grip:SetScript("OnUpdate", nil)
    shot.sizing, shot.meter.sizing = false, false
    return true
end

local function SizeUpdate(grip)
    local shot = grip.shot
    local f = shot.meter
    local scale = f:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local least = math.ceil(HeaderHeight() + FOOTER + 2 * INSET + S.Get("barHeight"))
    local w = Snap(shot.fromW + x / scale - shot.fromX, WIDTH_RANGE)
    local h = math.max(least, Snap(shot.fromH + shot.fromY - y / scale, HEIGHT_RANGE))
    if w == shot.sizeW and h == shot.sizeH then return end
    shot.sizeW, shot.sizeH, shot.resized = w, h, true
    f:SetSize(w, h)
    local shown = Look.Layout(f, shot.total, 0, S.Get("barHeight"), S.Get("barSpacing"), S.Get("fontSize"))
    if shown ~= shot.shown then
        shot.shown = shown
        Look.Paint(f, shot.list, 0, shown, shot.title, shot.status)
        PlaceHits(shot, shown)
    end
end

local function SizeStart(grip, button)
    local shot = grip.shot
    if button ~= "LeftButton" or shot.sizing then return end
    local f = shot.meter
    local scale = f:GetEffectiveScale()
    local x, y = GetCursorPosition()
    shot.fromX, shot.fromY = x / scale, y / scale
    shot.fromW, shot.fromH = f:GetWidth(), f:GetHeight()
    shot.sizeW, shot.sizeH, shot.resized = shot.fromW, shot.fromH, false
    shot.sizing, f.sizing = true, true
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", shot.area, "CENTER", -shot.fromW / 2, shot.fromH / 2)
    HideTip(shot)
    grip:SetScript("OnUpdate", SizeUpdate)
end

local function SizeStop(grip)
    local shot = grip.shot
    if not EndSize(shot) then return end
    Fit(shot)
    if shot.resized then
        if shot.sizeW ~= S.Get("width") then S.Set("width", shot.sizeW) end
        if shot.sizeH ~= S.Get("height") then S.Set("height", shot.sizeH) end
    end
    if not shot.meter:IsMouseOver() then Unhover(shot) end
end

local function PreviewHidden(shot)
    EndSize(shot)
    Unhover(shot)
end

local function NewHit(shot, kind, part, wash)
    local hit = CreateFrame(kind, nil, shot.edit)
    hit.shot, hit.part = shot, part
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", PartEnter)
    hit:SetScript("OnLeave", PartLeave)
    if wash then
        hit.wash = ns.Solid(hit, "OVERLAY", T.accent, HOVER_ALPHA)
        hit.wash:SetAllPoints()
        hit.wash:Hide()
    end
    return hit
end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.area = CreateFrame("Frame", nil, shot)
    shot.area:SetPoint("TOPLEFT", STAGE_MARGIN, -STAGE_MARGIN)
    shot.area:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, STAGE_MARGIN + NOTE_ROOM)
    local f = CreateFrame("Frame", nil, shot)
    shot.meter = f
    Look.New(f)
    shot.list, shot.pool = {}, {}
    f.shot, f.part = shot, "meter"
    f:SetScript("OnEnter", PartEnter)
    f:SetScript("OnLeave", PartLeave)
    shot.edit = CreateFrame("Frame", nil, f)
    shot.edit:SetAllPoints()
    shot.headerHit = NewHit(shot, "Button", "header", true)
    shot.headerHit:SetScript("OnClick", HeaderClick)
    shot.statusHit = NewHit(shot, "Button", "status", true)
    shot.statusHit:SetAllPoints(f.footer)
    shot.statusHit:SetScript("OnClick", StatusClick)
    shot.rowsHit = NewHit(shot, "Frame", "rows", true)
    shot.rowsHit:EnableMouseWheel(true)
    shot.rowsHit:SetScript("OnMouseWheel", RowsWheel)
    shot.rowsHit:SetScript("OnMouseUp", RowsUp)
    local grip = NewHit(shot, "Button", "grip", false)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -GRIP_INSET, GRIP_INSET)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", SizeStart)
    grip:SetScript("OnMouseUp", SizeStop)
    grip:Hide()
    shot.grip = grip
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.note:SetPoint("BOTTOMLEFT", STAGE_MARGIN, NOTE_BOTTOM)
    shot.note:SetPoint("BOTTOMRIGHT", -STAGE_MARGIN, NOTE_BOTTOM)
    shot:SetScript("OnHide", PreviewHidden)
    return shot
end

local function PaintPreview(shot, state)
    EndSize(shot)
    local f = shot.meter
    local title, me = SampleList(shot, state)
    local total = math.min(#shot.list, S.Get("maxBars"))
    local shown = Look.Layout(f, total, 0, S.Get("barHeight"), S.Get("barSpacing"), S.Get("fontSize"))
    local status = Look.State(me)
    Look.Paint(f, shot.list, 0, shown, title, status)
    shot.title, shot.status, shot.total, shot.shown = title, status, total, shown
    Fit(shot)
    local editable = Enabled()
    f:EnableMouse(editable)
    shot.edit:SetShown(editable)
    shot.note:SetText(editable and HINT or OFF_HINT)
    if not editable then
        Unhover(shot)
        return
    end
    local level = f:GetFrameLevel()
    shot.edit:SetFrameLevel(level + EDIT_LEVEL)
    shot.headerHit:SetFrameLevel(level + TOP_LEVEL)
    shot.grip:SetFrameLevel(level + TOP_LEVEL)
    PlaceHits(shot, shown)
end

local function Headline()
    if not On() then return "Threat Meter is off" end
    return TrackedUnit() == "focus" and "Tracking threat on your focus" or "Tracking threat on your target"
end

local function Detail()
    local shown = "Shown " .. (VISIBILITY[S.Get("visibility")] or VISIBILITY.threat):lower()
    if S.Get("warnSound") then return ("%s, warns at %d%% of pulling aggro."):format(shown, S.Get("warnAt")) end
    return shown .. ". Unlock its window to drag and resize it, or place it with Move Elements."
end

local function MeterSummary(store)
    return ("%d by %d, %s"):format(store.Get("width"), store.Get("height"),
        (VISIBILITY[store.Get("visibility")] or VISIBILITY.threat):lower())
end

local function WarningSummary(store)
    return ("At %d%%"):format(store.Get("warnAt"))
end

local page = Settings.Page("Threat Meter/Settings", S)

page:Window({
    headline = Headline,
    detail = Detail,
})

page:Card({
    id = "meter", name = "Meter", order = 10,
    help = "Threat on your target or focus for everyone in your group, one bar each. A friendly target "
        .. "shows the enemy it is fighting. Scroll the meter for more entries; unlock its window to drag "
        .. "and resize it, or place it with Move Elements.",
    summary = MeterSummary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Tracking"),
        { key = "focusEnabled", label = "Focus Tracking", toggle = true, needs = Enabled, why = OFF,
          help = "Adds target and focus switching to the meter's title bar." },
        { key = "source", label = "Track", choice = SOURCE, needs = Needs("focusEnabled"),
          why = "Needs Focus Tracking" },
        { key = "visibility", label = "Show", choice = SHOW, needs = Enabled, why = OFF,
          help = "With Threat: hidden until someone in your group has threat on the mob." },
        { key = "percentMode", label = "Percent Of", choice = PERCENT, needs = Enabled, why = OFF,
          help = "Pull Aggro: 100% takes aggro. Tank Threat: 100% equals the current tank's threat." },
        { key = "ignorePets", label = "Ignore Pets", toggle = true, needs = Enabled, why = OFF,
          help = "Leave hunter and warlock pets off the meter." },
        { key = "maxBars", label = "Maximum Entries", slider = { 1, 80, 1 }, needs = Enabled, why = OFF },
        Group("Window"),
        { key = "width", label = "Width", slider = WIDTH_RANGE, needs = Enabled, why = OFF },
        { key = "height", label = "Window Height", slider = HEIGHT_RANGE, needs = Enabled, why = OFF },
        { key = "locked", label = "Lock Window", toggle = true, needs = Enabled, why = OFF,
          help = "Off: drag the title bar or resize with the corner grip, outside combat. Move Elements "
              .. "works either way." },
        { key = "showHeader", label = "Show Target Name", toggle = true, needs = Enabled, why = OFF,
          help = "A title bar naming the mob the threat is on." },
        { key = "statusPos", label = "Status Line", choice = STATUS, needs = Enabled, why = OFF,
          help = "Where your distance to pulling aggro and the entry count sit: under the bars, or between "
              .. "the title bar and the bars." },
        { key = "growUp", label = "Grow Upward", toggle = true, needs = Enabled, why = OFF,
          help = "New bars stack above the first instead of below." },
        { key = "backgroundAlpha", label = "Background Opacity", slider = { 0, 100, 5 }, unit = "%",
          scale = 0.01, needs = Enabled, why = OFF },
        Group("Rows"),
        { key = "barHeight", label = "Row Height", slider = ROW_H_RANGE, needs = Enabled, why = OFF },
        { key = "barSpacing", label = "Row Spacing", slider = SPACING_RANGE, needs = Enabled, why = OFF },
        { key = "showValue", label = "Show Threat", toggle = true, needs = Enabled, why = OFF },
        { key = "showPercent", label = "Show Percent", toggle = true, needs = Enabled, why = OFF,
          help = "Uses the Percent Of setting: Pull Aggro or Tank Threat." },
        { key = "showIcons", label = "Class Icons", toggle = true, needs = Enabled, why = OFF,
          help = "Pets use their owner's class icon, desaturated." },
        { key = "showRanks", label = "Rank Numbers", toggle = true, needs = Enabled, why = OFF },
        { key = "highlightPlayer", label = "Highlight Your Row", toggle = true, needs = Enabled, why = OFF },
        { key = "texture", label = "Bar Texture", choice = TEXTURE, needs = Enabled, why = OFF },
        { key = "barAlpha", label = "Bar Opacity", slider = { 10, 100, 5 }, unit = "%", scale = 0.01,
          needs = Enabled, why = OFF },
        Group("Text"),
        { key = "font", label = "Font", font = true, needs = Enabled, why = OFF },
        { key = "fontSize", label = "Text Size", slider = TEXT_RANGE, needs = Enabled, why = OFF },
        Group("Colours"),
        { key = "playerColorOn", label = "Colour Your Bar", toggle = true, needs = Enabled, why = OFF,
          help = "Your own bar in one colour instead of your class colour." },
        { key = "playerColor", label = "Your Colour", colour = true, get = Shade("playerColor"),
          set = Picked("playerColor"), needs = OwnBar, why = "Needs Colour Your Bar, theme off" },
        { key = "themeColors", label = "Apply Theme to Your Bar", toggle = true, needs = Needs("playerColorOn"),
          why = "Needs Colour Your Bar",
          help = "Your bar in a darker shade of your theme's Accent instead of the colour picked above. The "
              .. "tank and pull aggro colours stay as picked." },
        { key = "tankColorOn", label = "Colour the Tank", toggle = true, needs = Enabled, why = OFF,
          help = "Whoever holds aggro in one colour." },
        { key = "tankColor", label = "Tank Colour", colour = true, needs = Needs("tankColorOn"),
          why = "Needs Colour the Tank" },
        { key = "pullBar", label = "Pull Aggro Bar", toggle = true, needs = Enabled, why = OFF,
          help = "A bar at the threat where you would pull aggro, so the gap to it is easy to read." },
        { key = "pullColor", label = "Pull Aggro Colour", colour = true, needs = Needs("pullBar"),
          why = "Needs Pull Aggro Bar" },
        { label = "Show It on Screen", buttonText = "Preview", needs = Enabled, why = OFF,
          button = function() ns.PreviewThreatMeter() end,
          help = "Shows the meter with sample bars where it sits on your screen, for ten seconds. Out of "
              .. "combat only." },
    },
})

page:Card({
    id = "warning", name = "Warning Sound", order = 20, switch = "warnSound",
    help = "Plays once when your threat climbs past the threshold, and again only after it drops back below.",
    summary = WarningSummary,
    rows = {
        { key = "warnAt", label = "Warn At", slider = { 50, 100, 1 }, unit = "%", needs = Enabled, why = OFF },
        { key = "warnSoundKey", label = "Sound", sound = true, needs = Enabled, why = OFF },
        { key = "warnSkipTank", label = "Not While Tanking", toggle = true, needs = Enabled, why = OFF,
          help = "No warning in a tank role, Bear Form or Defensive Stance." },
    },
})
