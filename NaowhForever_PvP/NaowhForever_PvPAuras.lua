-------------------------------------------------------------------------------
--  NaowhForever_PvPAuras.lua -- PvP Auras: your target's short buffs (Divine Shield, Evasion,
--  Ice Block, Blessing of Protection, Sprint), the crowd control on them and the debuffs you
--  pick, as rows of large icons; every crowd control ability and debuff is switched on its
--  own. A second panel does the same for your focus, with their name and class above it, so a
--  Sap or Polymorph on one enemy keeps counting down while you fight another. Forever closes
--  auras to addons in combat, so Blizzard's AuraContainer picks and draws them. Forever's
--  classic spells carry none of its PvP aura flags, and it lets an addon pick an enemy's
--  debuffs by spell ID but not their buffs: crowd control and debuffs come from spell IDs
--  (Data/NaowhForever_PvPSpells.lua), buffs by their length and dispel type. A container does
--  not follow a new target or focus by itself, so a change rebuilds it. The time left is the
--  game's own countdown, coloured by a curve the game evaluates: yellow, then red and blinking
--  near the end. Before the first row, the shields on the unit added up: the game hands the
--  amount over secret, so it is shown as given, inside a frame clipped to a bar that is full
--  while any shield is up and empty without one: the number shows only while there is a
--  shield, and nothing reads it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.PvPSettings
local UI = ns.UI
local T = ns.THEME
local SPELLS = ns.PvPSpells

local BORDER = 1
local ICON_CROP = 0.08
local ICON_GAP = 3
local ROW_GAP = 4
local TIME_SIZE = 0.34
local COUNT_SIZE = 0.3
local TEXT_INSET = 2
local MIN_TEXT = 8
local SORT_DEFAULT = 0
local BLACK = { r = 0, g = 0, b = 0 }
local MAGIC = { Magic = true }
local ROWS = { "buffs", "cc", "debuffs" }
local MAX_KEY = { buffs = "buffMax", cc = "ccMax", debuffs = "debuffMax" }
local ABSORB_TEXT = "%d"
-- Without the buffs row there is no shield icon beside the number to say what it is.
local ABSORB_ICON_TEXT = "|TInterface\\Icons\\Spell_Holy_PowerWordShield:0:0:0:0:64:64:5:59:5:59|t %d"
local ABSORB_SIZE = 0.42
local ABSORB_RGB = { r = 0.55, g = 0.82, b = 1 }
local NAME_SIZE = 0.42
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_CROP = 0.02
local BLINK = 0.5
local WHITE_RGBA, YELLOW_RGBA = { 1, 1, 1, 1 }, { 1, 0.82, 0, 1 }
local RED_RGBA, FAINT_RGBA = { 1, 0.2, 0.2, 1 }, { 1, 0.2, 0.2, 0.3 }

local DISPLAYS = {
    { key = "target", unit = "target", frame = "NaowhForeverPvPAuras", name = "PvP Auras", posKey = "pos",
      changed = "PLAYER_TARGET_CHANGED", rows = { buffs = "buffs", cc = "cc", debuffs = "debuffs" } },
    { key = "focus", unit = "focus", frame = "NaowhForeverPvPAurasFocus", name = "PvP Auras: Focus",
      posKey = "focusPos", changed = "PLAYER_FOCUS_CHANGED", switch = "focus", nameKey = "focusName",
      rows = { buffs = "focusBuffs", cc = "focusCC", debuffs = "focusDebuffs" } },
}

local buttons = {}
local unlocked, pendingResize, built
local buffFilters = {}
local lists = {
    cc = { ids = {}, filters = {}, version = 0 },
    debuffs = { ids = {}, filters = {}, version = 0 },
}

local function Readable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function On()
    return S.Get("enabled") == true and S.Get("auras") == true
end

local function DisplayOn(d)
    return d.switch == nil or S.Get(d.switch) == true
end

local function RowOn(d, row)
    return S.Get(d.rows[row]) == true
end

local function Size()
    return S.Get("size")
end

local function TextSize(ratio)
    return math.max(MIN_TEXT, math.floor(Size() * ratio + 0.5))
end

-------------------------------------------------------------------------------
--  The time left: compact ("12s", "2m"), white, then yellow, then red and blinking at the end
-------------------------------------------------------------------------------
local formatter, timerOptions, timerSignature

local function Formatter()
    if formatter then return formatter end
    formatter = C_StringUtil.CreateSecondsFormatter()
    formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    formatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)
    formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    formatter:SetRounding(Enum.SecondsFormatterRounding.RoundUp)
    formatter:SetDesiredUnitCount(1)
    return formatter
end

local function Color(rgba)
    return CreateColor(rgba[1], rgba[2], rgba[3], rgba[4])
end

-- Remaining seconds to colour: red under warnAt (blinking, if asked), yellow under twice that.
local function WarnCurve(warnAt, blink)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, Color(RED_RGBA))
    if blink then
        local at, faint = BLINK, true
        while at < warnAt do
            curve:AddPoint(at, Color(faint and FAINT_RGBA or RED_RGBA))
            at, faint = at + BLINK, not faint
        end
    end
    curve:AddPoint(warnAt, Color(YELLOW_RGBA))
    curve:AddPoint(warnAt * 2, Color(WHITE_RGBA))
    return curve
end

local function TimerOptions()
    local warn = S.Get("warn") == true
    local signature = (warn and "1" or "0") .. S.Get("warnAt") .. (S.Get("warnBlink") and "1" or "0")
    if signature ~= timerSignature then
        timerSignature = signature
        timerOptions = { textFormatter = Formatter() }
        if warn then
            timerOptions.textColor = { curve = WarnCurve(S.Get("warnAt"), S.Get("warnBlink") == true),
                property = Enum.DurationTextBindingProperty.RemainingDuration }
        end
    end
    return timerOptions, timerSignature
end

-------------------------------------------------------------------------------
--  An icon: the same look on an aura button and on the settings preview's plain frames
-------------------------------------------------------------------------------
local function StyleButton(button)
    local size = Size()
    button:SetSize(size, size)
    button.timeText:SetFont(ns.UIFontPath(), TextSize(TIME_SIZE), "OUTLINE")
    button.countText:SetFont(ns.UIFontPath(), TextSize(COUNT_SIZE), "OUTLINE")
    button.timeText:SetShown(S.Get("timer") == true)
    button.countText:SetShown(S.Get("count") == true)
    if button.aura then
        local options, signature = TimerOptions()
        if button.timerSignature ~= signature then
            button.timerSignature = signature
            button:SetDurationText(button.timeText, options)
        end
    end
end

local function NewIcon(frame)
    local ground = frame:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(BLACK.r, BLACK.g, BLACK.b, 1)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    frame.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    frame.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    frame.swipe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.swipe:SetAllPoints(frame.icon)
    frame.swipe:SetDrawEdge(false)
    frame.swipe:SetHideCountdownNumbers(true)
    frame.swipe:SetReverse(true)
    local text = CreateFrame("Frame", nil, frame)
    text:SetAllPoints()
    text:SetFrameLevel(frame.swipe:GetFrameLevel() + 1)
    frame.timeText = text:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetPoint("BOTTOM", 0, TEXT_INSET)
    frame.countText = text:CreateFontString(nil, "OVERLAY")
    frame.countText:SetPoint("TOPRIGHT", -TEXT_INSET, -TEXT_INSET)
    StyleButton(frame)
end

local function InitButton(button)
    button.aura = true
    NewIcon(button)
    button:SetIcon(button.icon)
    button:SetDurationCooldown(button.swipe)
    button:SetApplicationCount(button.countText)
    buttons[#buttons + 1] = button
end

local ROW_LAYOUT = { elementSpacing = ICON_GAP, lineSpacing = ROW_GAP, groupLineSpacing = ROW_GAP, forceNewLine = true }

-------------------------------------------------------------------------------
--  What each row lets through
-------------------------------------------------------------------------------
local function BuffFilters()
    buffFilters.maxDuration = S.Get("buffLength")
    buffFilters.includeDispelTypes = S.Get("buffMagicOnly") and MAGIC or nil
    return buffFilters
end

-- The spell IDs of the entries switched on (prefix .. entry.key), into ids; the signature says
-- which were, so an unchanged choice is not rebuilt.
local function Pick(entries, prefix, ids)
    local parts = {}
    wipe(ids)
    for _, entry in ipairs(entries) do
        local on = S.Get(prefix .. entry.key) == true
        parts[#parts + 1] = on and "1" or "0"
        if on then
            for id in pairs(entry.ids) do ids[id] = true end
        end
    end
    return table.concat(parts)
end

-- Spell IDs typed in by hand, any separator.
local function AddTyped(text, ids)
    for id in tostring(text or ""):gmatch("%d+") do ids[tonumber(id)] = true end
end

-- Each list rebuilt when its choice changed; its version tells a container it has a new one.
local function RefreshLists()
    local cc = lists.cc
    local signature = Pick(SPELLS.crowdControl, "cc_", cc.ids) .. (S.Get("ccOther") and "1" or "0")
    if S.Get("ccOther") then
        for id in pairs(SPELLS.otherCrowdControl) do cc.ids[id] = true end
    end
    if signature ~= cc.signature then
        cc.signature, cc.version = signature, cc.version + 1
        cc.filters.includeSpellIDs = cc.ids
    end
    local debuffs = lists.debuffs
    local extra = S.Get("debuffExtra") or ""
    signature = Pick(SPELLS.debuffs, "debuff_", debuffs.ids) .. "|" .. extra
    AddTyped(extra, debuffs.ids)
    if signature ~= debuffs.signature then
        debuffs.signature, debuffs.version = signature, debuffs.version + 1
        debuffs.filters.includeSpellIDs = debuffs.ids
    end
end

-------------------------------------------------------------------------------
--  A panel: its holder, Blizzard's container, the absorb and (focus) the name above it
-------------------------------------------------------------------------------
local function Build(d)
    local holder = CreateFrame("Frame", d.frame, UIParent)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    container:SetPoint("TOPLEFT")
    container:SetUnit(d.unit)
    local filters = { buffs = BuffFilters(), cc = lists.cc.filters, debuffs = lists.debuffs.filters }
    for _, row in ipairs(ROWS) do
        container:AddAuraGroup(row, row == "buffs" and "HELPFUL" or "HARMFUL", {
            maxFrameCount = S.Get(MAX_KEY[row]), sortMethod = SORT_DEFAULT, initializeFrame = InitButton,
            layout = ROW_LAYOUT, candidateFilters = filters[row],
        })
    end
    d.applied = { cc = lists.cc.version, debuffs = lists.debuffs.version }
    holder.mover = UI.AttachMover(holder, d.name, function(pos) S.Set(d.posKey, pos) end, "PvP/Auras",
        "PvP/Auras:auras")

    local absorb = CreateFrame("StatusBar", nil, holder)
    absorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    absorb:SetStatusBarColor(0, 0, 0, 0)
    absorb:SetMinMaxValues(0, 1)
    absorb:SetValue(0)
    absorb.clip = CreateFrame("Frame", nil, absorb)
    absorb.clip:SetClipsChildren(true)
    absorb.clip:SetPoint("TOPLEFT", absorb:GetStatusBarTexture(), "TOPLEFT")
    absorb.clip:SetPoint("BOTTOMRIGHT", absorb:GetStatusBarTexture(), "BOTTOMRIGHT")
    absorb.text = absorb.clip:CreateFontString(nil, "OVERLAY")
    absorb.text:SetPoint("RIGHT", absorb, "RIGHT")
    absorb.text:SetJustifyH("RIGHT")

    if d.nameKey then
        local header = CreateFrame("Frame", nil, holder)
        header.class = header:CreateTexture(nil, "ARTWORK")
        header.class:SetTexture(CLASS_ICONS)
        header.class:SetPoint("LEFT")
        header.name = header:CreateFontString(nil, "OVERLAY")
        header.name:SetPoint("LEFT", header.class, "RIGHT", ICON_GAP * 2, 0)
        header.name:SetJustifyH("LEFT")
        header.name:SetWordWrap(false)
        d.header = header
    end
    d.holder, d.container, d.absorb = holder, container, absorb
    built = true
end

-- The shields on the unit, as the game gives them: never compared, only shown.
local function UpdateAbsorb(d)
    local absorb = d.absorb
    if not absorb or not absorb:IsShown() then return end
    if not UnitExists(d.unit) then
        absorb:SetValue(0)
        return
    end
    local amount = UnitGetTotalAbsorbs(d.unit)
    absorb:SetValue(amount)
    absorb.text:SetFormattedText(RowOn(d, "buffs") and ABSORB_TEXT or ABSORB_ICON_TEXT, amount)
end

-- Your focus's name in their class's colour, with their class's icon; nothing without a focus.
local function UpdateHeader(d)
    local header = d.header
    if not header then return end
    local shown = S.Get(d.nameKey) == true and UnitExists(d.unit)
    header:SetShown(shown)
    if not shown then return end
    header.name:SetText(UnitName(d.unit))
    local _, classFile = UnitClass(d.unit)
    local readable = Readable(classFile)
    local color = readable and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local coords = readable and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if color then
        header.name:SetTextColor(color.r, color.g, color.b)
    else
        header.name:SetTextColor(1, 1, 1)
    end
    header.class:SetShown(coords ~= nil)
    if coords then
        header.class:SetTexCoord(coords[1] + CLASS_CROP, coords[2] - CLASS_CROP, coords[3] + CLASS_CROP,
            coords[4] - CLASS_CROP)
    end
end

local function Place(d)
    local pos = S.Get(d.posKey)
    d.holder:ClearAllPoints()
    d.holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function Layout(d)
    local size, rows, wide = Size(), 0, 1
    for _, row in ipairs(ROWS) do
        if RowOn(d, row) then rows, wide = rows + 1, math.max(wide, S.Get(MAX_KEY[row])) end
    end
    rows = math.max(rows, 1)
    d.holder:SetSize(wide * size + (wide - 1) * ICON_GAP, rows * size + (rows - 1) * ROW_GAP)
    local absorbSize = TextSize(ABSORB_SIZE)
    d.absorb.text:SetFont(ns.UIFontPath(), absorbSize, "OUTLINE")
    d.absorb.text:SetTextColor(ABSORB_RGB.r, ABSORB_RGB.g, ABSORB_RGB.b)
    d.absorb:SetSize(size * 2, absorbSize + 4)
    d.absorb:ClearAllPoints()
    d.absorb:SetPoint("RIGHT", d.holder, "TOPLEFT", -ICON_GAP * 2, -size / 2)
    if d.header then
        local nameSize = TextSize(NAME_SIZE)
        d.header.name:SetFont(ns.UIFontPath(), nameSize, "OUTLINE")
        d.header.class:SetSize(nameSize + 4, nameSize + 4)
        d.header:SetSize(d.holder:GetWidth(), nameSize + 4)
        d.header:ClearAllPoints()
        d.header:SetPoint("BOTTOMLEFT", d.holder, "TOPLEFT", 0, ROW_GAP)
    end
end

local function Rows(d)
    for _, row in ipairs(ROWS) do
        d.container:SetAuraGroupEnabled(row, RowOn(d, row))
        d.container:SetAuraGroupMaxFrameCount(row, S.Get(MAX_KEY[row]))
    end
    d.container:SetAuraGroupCandidateFilters("buffs", BuffFilters())
    for list, data in pairs(lists) do
        if d.applied[list] ~= data.version then
            d.applied[list] = data.version
            d.container:SetAuraGroupCandidateFilters(list, data.filters)
        end
    end
end

local function ResizeButtons()
    if InCombatLockdown() then
        pendingResize = true
        return
    end
    pendingResize = false
    for i = 1, #buttons do StyleButton(buttons[i]) end
end

local events = CreateFrame("Frame")

local function Hide(d)
    if not d.holder then return end
    d.container:SetEnabled(false)
    d.holder:Hide()
    d.holder.mover:Hide()
end

local function Apply()
    if not On() and not built then
        events:UnregisterAllEvents()
        return
    end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    events:UnregisterAllEvents()
    if not On() then
        for _, d in ipairs(DISPLAYS) do Hide(d) end
        return
    end
    RefreshLists()
    local absorbUnits = {}
    for _, d in ipairs(DISPLAYS) do
        if DisplayOn(d) then
            events:RegisterEvent(d.changed)
            if not d.holder then Build(d) end
            Rows(d)
            Layout(d)
            Place(d)
            d.container:SetEnabled(true)
            d.holder:Show()
            d.absorb:SetShown(S.Get("absorb") == true)
            if S.Get("absorb") then absorbUnits[#absorbUnits + 1] = d.unit end
            UpdateAbsorb(d)
            UpdateHeader(d)
            d.holder.mover:SetShown(unlocked == true)
        else
            Hide(d)
        end
    end
    if absorbUnits[1] then events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", absorbUnits[1], absorbUnits[2]) end
    ResizeButtons()
end

events:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        for _, d in ipairs(DISPLAYS) do
            if d.unit == unit then UpdateAbsorb(d) end
        end
        return
    end
    for _, d in ipairs(DISPLAYS) do
        if event == d.changed and d.container then
            d.container:UpdateAllAuras()
            UpdateAbsorb(d)
            UpdateHeader(d)
            return
        end
    end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if pendingResize then ResizeButtons() end
    Apply()
end)

S.OnChange(function(key)
    if key ~= "pos" and key ~= "focusPos" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  The card's preview: your target or your focus, with sample buffs, crowd control and
--  debuffs, by the same settings
-------------------------------------------------------------------------------
local ICONS = "Interface\\Icons\\"
local SAMPLE_BUFFS = {
    { icon = "Spell_Holy_DivineIntervention", length = 12, magic = true, left = 9 },
    { icon = "Spell_Shadow_ShadowWard", length = 15, left = 11 },
    { icon = "Ability_Rogue_Sprint", length = 15, left = 6 },
    { icon = "Spell_Holy_SealOfProtection", length = 10, magic = true, left = 2 },
    { icon = "Ability_GhoulFrenzy", length = 15, left = 12, count = 3 },
    { icon = "Spell_Holy_PowerWordShield", length = 30, magic = true, left = 24 },
    { icon = "Spell_Nature_Lightning", length = 20, magic = true, left = 17 },
}
local SAMPLE_CC = {
    { key = "cc_sap", left = 38 }, { key = "cc_polymorph", left = 27 }, { key = "cc_kidneyShot", left = 4 },
    { key = "cc_fear", left = 8 }, { key = "cc_frostNova", left = 2 }, { key = "cc_silence", left = 3 },
    { key = "cc_hammerOfJustice", left = 5 }, { key = "cc_mindControl", left = 12 },
}
local SAMPLE_DEBUFFS = {
    { key = "debuff_mortalStrike", left = 7 }, { key = "debuff_woundPoison", left = 11, count = 4 },
    { key = "debuff_cripplingPoison", left = 9 }, { key = "debuff_curseOfTongues", left = 26 },
    { key = "debuff_hamstring", left = 13 }, { key = "debuff_frostShock", left = 6 },
}
local SAMPLE_FOCUS = { name = "Kalerith", class = "MAGE" }
local STAGE_MARGIN, NOTE_ROOM, NOTE_SIZE, NOTE_Y = 14, 24, 11, 9
local STATES = {
    { key = "target", label = "Target" },
    { key = "focus", label = "Focus", needs = "focus" },
}

-- The icon each switch key stands for, from the spell lists.
local iconOf = {}
for _, entry in ipairs(SPELLS.crowdControl) do iconOf["cc_" .. entry.key] = entry.icon end
for _, entry in ipairs(SPELLS.debuffs) do iconOf["debuff_" .. entry.key] = entry.icon end

local function HeaderRoom()
    return TextSize(NAME_SIZE) + 4 + ROW_GAP
end

local function StageHeight()
    return STAGE_MARGIN * 2 + NOTE_ROOM + HeaderRoom() + Size() * 3 + ROW_GAP * 2
end

local function NewPreview(stage)
    local shot = CreateFrame("Frame", nil, stage)
    shot:SetAllPoints()
    shot.rows = { {}, {}, {} }
    shot.absorb = shot:CreateFontString(nil, "OVERLAY")
    shot.class = shot:CreateTexture(nil, "ARTWORK")
    shot.class:SetTexture(CLASS_ICONS)
    shot.name = shot:CreateFontString(nil, "OVERLAY")
    shot.note = ns.Font(shot, NOTE_SIZE, nil, T.muted)
    shot.note:SetPoint("BOTTOM", 0, NOTE_Y)
    return shot
end

local function BuffShown(sample)
    return sample.length <= S.Get("buffLength") and (sample.magic or not S.Get("buffMagicOnly"))
end

local function SwitchedOn(sample)
    return S.Get(sample.key) == true
end

-- The colour the game's curve gives that many seconds left (the blink's bright half).
local function TimeColor(left)
    if not S.Get("warn") then return WHITE_RGBA end
    local warnAt = S.Get("warnAt")
    if left < warnAt then return RED_RGBA end
    if left < warnAt * 2 then return YELLOW_RGBA end
    return WHITE_RGBA
end

-- How many of a row's samples pass, at most max.
local function Passing(samples, shown, max)
    local n = 0
    for _, sample in ipairs(samples) do
        if n < max and shown(sample) then n = n + 1 end
    end
    return n
end

-- A row's samples that pass, at most max, centred across the stage at y.
local function PaintRow(shot, row, samples, shown, max, y)
    local size, icons, n = Size(), shot.rows[row], 0
    local count = Passing(samples, shown, max)
    local first = -(count - 1) * (size + ICON_GAP) / 2
    for _, sample in ipairs(samples) do
        if n < count and shown(sample) then
            n = n + 1
            local f = icons[n]
            if not f then
                f = CreateFrame("Frame", nil, shot)
                NewIcon(f)
                icons[n] = f
            end
            StyleButton(f)
            f.icon:SetTexture(sample.icon and ICONS .. sample.icon or iconOf[sample.key])
            f.timeText:SetText(Formatter():Format(sample.left))
            local c = TimeColor(sample.left)
            f.timeText:SetTextColor(c[1], c[2], c[3], c[4])
            f.countText:SetText(sample.count and tostring(sample.count) or "")
            f:ClearAllPoints()
            f:SetPoint("TOP", shot, "TOP", first + (n - 1) * (size + ICON_GAP), -y)
            f:Show()
        end
    end
    for i = n + 1, #icons do icons[i]:Hide() end
    return n
end

local PREVIEW_ROWS = {
    { key = "buffs", samples = SAMPLE_BUFFS, shown = BuffShown },
    { key = "cc", samples = SAMPLE_CC, shown = SwitchedOn },
    { key = "debuffs", samples = SAMPLE_DEBUFFS, shown = SwitchedOn },
}

local function PaintHeader(shot, d, y)
    local named = d.nameKey ~= nil and S.Get(d.nameKey) == true
    shot.name:SetShown(named)
    shot.class:SetShown(named)
    if not named then return end
    local nameSize = TextSize(NAME_SIZE)
    shot.name:SetFont(ns.UIFontPath(), nameSize, "OUTLINE")
    shot.name:SetText(SAMPLE_FOCUS.name)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[SAMPLE_FOCUS.class]
    if color then shot.name:SetTextColor(color.r, color.g, color.b) end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[SAMPLE_FOCUS.class]
    shot.class:SetShown(coords ~= nil)
    if coords then
        shot.class:SetTexCoord(coords[1] + CLASS_CROP, coords[2] - CLASS_CROP, coords[3] + CLASS_CROP,
            coords[4] - CLASS_CROP)
    end
    shot.class:SetSize(nameSize + 4, nameSize + 4)
    shot.class:ClearAllPoints()
    shot.class:SetPoint("BOTTOMRIGHT", shot, "TOP", -ICON_GAP, -y)
    shot.name:ClearAllPoints()
    shot.name:SetPoint("LEFT", shot.class, "RIGHT", ICON_GAP * 2, 0)
end

local function PaintPreview(shot, state)
    local d = state == "focus" and DISPLAYS[2] or DISPLAYS[1]
    local rows = 0
    for _, row in ipairs(PREVIEW_ROWS) do
        if RowOn(d, row.key) then rows = rows + 1 end
    end
    local block = rows * Size() + math.max(rows - 1, 0) * ROW_GAP
    local y = math.floor((StageHeight() - NOTE_ROOM - block + HeaderRoom()) / 2)
    PaintHeader(shot, d, y - ROW_GAP)
    local drawn, anyRow = 0, false
    for i, row in ipairs(PREVIEW_ROWS) do
        local on = RowOn(d, row.key)
        drawn = drawn + PaintRow(shot, i, row.samples, row.shown, on and S.Get(MAX_KEY[row.key]) or 0, y)
        if on then
            anyRow = true
            y = y + Size() + ROW_GAP
        end
    end
    -- The sample absorb before the first row drawn, as the real one sits before the first row.
    local first
    for i = 1, #PREVIEW_ROWS do
        local icon = shot.rows[i][1]
        if not first and icon and icon:IsShown() then first = icon end
    end
    shot.absorb:SetFont(ns.UIFontPath(), TextSize(ABSORB_SIZE), "OUTLINE")
    shot.absorb:SetTextColor(ABSORB_RGB.r, ABSORB_RGB.g, ABSORB_RGB.b)
    shot.absorb:SetFormattedText(RowOn(d, "buffs") and ABSORB_TEXT or ABSORB_ICON_TEXT, 1240)
    shot.absorb:ClearAllPoints()
    if first then shot.absorb:SetPoint("RIGHT", first, "LEFT", -ICON_GAP * 2, 0) end
    shot.absorb:SetShown(S.Get("absorb") == true and first ~= nil)
    if not anyRow then
        shot.note:SetText("Every row is off: nothing shows.")
    elseif drawn == 0 then
        shot.note:SetText("Nothing in these samples passes your settings.")
    elseif d.nameKey then
        shot.note:SetText("Your focus, set with NF Focus: their timers keep counting while you fight someone else.")
    else
        shot.note:SetText("Your target in a fight: short buffs, crowd control, then your debuffs.")
    end
end

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local Settings = ns.Shared.Settings
local Group = Settings.Group
local OFF = "Turn on PvP"

local function Enabled() return S.Get("enabled") == true end

local function Needs(key)
    return function() return S.Get("enabled") == true and S.Get(key) == true end
end

local buffsOn = Needs("buffs")
local timerOn, warnOn, focusOn = Needs("timer"), Needs("warn"), Needs("focus")

-- NF Focus, the Macros module's focus macro, is how a player sets their focus: Naowh's Forge
-- opens on its Smart Macros, where it can be dragged to a bar.
local function ForgeReady()
    return focusOn() and ns.OpenMacroWindow ~= nil
end

local function OpenForge()
    ns.OpenFromOptions(function() ns.OpenMacroWindow("smart") end)
end

local function Summary(store)
    local parts = {}
    if store.Get("buffs") then parts[#parts + 1] = ("buffs up to %ds"):format(store.Get("buffLength")) end
    if store.Get("cc") then parts[#parts + 1] = "crowd control" end
    if store.Get("debuffs") then parts[#parts + 1] = "your debuffs" end
    if #parts == 0 then return "Nothing shown" end
    return "Your target's " .. table.concat(parts, ", ") .. (store.Get("focus") and ", and your focus" or "")
end

-------------------------------------------------------------------------------
--  The spell grids: one icon per crowd control ability or debuff, a row per class; lit while
--  it shows, dimmed while it does not. Click one to flip it, hover for its spell.
-------------------------------------------------------------------------------
local TILE, TILE_GAP, GRID_ROW, GRID_LABEL_W, GRID_MARGIN, GRID_NOTE = 30, 4, 36, 120, 14, 22
local LIT_ALPHA, IDLE_ALPHA, OFF_ALPHA = 1, 0.6, 0.3
local GRID_STATES = { { key = "spells", label = "Spells" } }

local function Groups(entries)
    local groups, last = {}, nil
    for _, entry in ipairs(entries) do
        if not last or last.name ~= entry.group then
            last = { name = entry.group, entries = {} }
            groups[#groups + 1] = last
        end
        last.entries[#last.entries + 1] = entry
    end
    return groups
end

local CC_GROUPS, DEBUFF_GROUPS = Groups(SPELLS.crowdControl), Groups(SPELLS.debuffs)

local function PaintTile(tile)
    local on = S.Get(tile.key) == true
    tile.icon:SetDesaturated(not on)
    tile:SetAlpha(on and (tile.needs() and LIT_ALPHA or IDLE_ALPHA) or OFF_ALPHA)
    local c = on and T.accent or BLACK
    tile.edge:SetColor(c.r, c.g, c.b, 1)
end

local function TileEnter(tile)
    GameTooltip:SetOwner(tile, "ANCHOR_TOP")
    GameTooltip:SetSpellByID(tile.entry.spell)
    local hint = S.Get(tile.key) and "Shown: click to hide it." or "Hidden: click to show it."
    GameTooltip:AddLine(hint, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    GameTooltip:Show()
end

local function TileLeave()
    GameTooltip:Hide()
end

local function GridNote(shot)
    local on, total = 0, #shot.tiles
    for _, tile in ipairs(shot.tiles) do
        if S.Get(tile.key) then on = on + 1 end
    end
    shot.note:SetText(("%d of %d shown. Click a spell to show or hide it; hover for the spell."):format(on, total))
end

local function TileClick(tile)
    S.Set(tile.key, not S.Get(tile.key))
    PaintTile(tile)
    GridNote(tile:GetParent())
    TileEnter(tile)
end

local function GridHeight(groups)
    return function() return GRID_MARGIN * 2 + #groups * GRID_ROW + GRID_NOTE end
end

local function NewGrid(groups, prefix, needs)
    return function(stage)
        local shot = CreateFrame("Frame", nil, stage)
        shot:SetAllPoints()
        shot.tiles = {}
        for i, group in ipairs(groups) do
            local y = GRID_MARGIN + (i - 1) * GRID_ROW
            local label = ns.Font(shot, 12, nil, T.muted)
            label:SetPoint("LEFT", shot, "TOPLEFT", GRID_MARGIN, -(y + TILE / 2))
            label:SetText(group.name)
            for j, entry in ipairs(group.entries) do
                local tile = Settings.EditZone(shot, { click = TileClick, enter = TileEnter, leave = TileLeave })
                tile:SetSize(TILE, TILE)
                tile:SetPoint("TOPLEFT", shot, "TOPLEFT", GRID_MARGIN + GRID_LABEL_W + (j - 1) * (TILE + TILE_GAP), -y)
                ns.Solid(tile, "BACKGROUND", BLACK, 1):SetAllPoints()
                tile.icon = tile:CreateTexture(nil, "ARTWORK")
                tile.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
                tile.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
                tile.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
                tile.icon:SetTexture(entry.icon)
                tile.edge = ns.Border(tile, BLACK)
                tile.entry, tile.key, tile.needs = entry, prefix .. entry.key, needs
                shot.tiles[#shot.tiles + 1] = tile
            end
        end
        shot.note = ns.Font(shot, 11, nil, T.muted)
        shot.note:SetPoint("BOTTOMLEFT", GRID_MARGIN, 8)
        return shot
    end
end

local function PaintGrid(shot)
    for _, tile in ipairs(shot.tiles) do PaintTile(tile) end
    GridNote(shot)
end

-- Every entry of a list switched to one value.
local function SetAll(entries, prefix, value)
    return function()
        for _, entry in ipairs(entries) do S.Set(prefix .. entry.key, value) end
    end
end

local page = Settings.Page("PvP/Auras", S)

page:Card({
    id = "auras", name = "PvP Auras", order = 10, switch = "auras",
    help = "Your target's short buffs, the crowd control on them and the debuffs you pick, as large icons that keep working in combat.",
    summary = Summary,
    studio = { height = StageHeight, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Look"),
        { key = "size", label = "Icon Size", slider = { 24, 64, 1 }, needs = Enabled, why = OFF },
        { key = "count", label = "Show Stacks", toggle = true, needs = Enabled, why = OFF },
        Group("Time Left"),
        { key = "timer", label = "Show Time Left", toggle = true, needs = Enabled, why = OFF },
        { key = "warn", label = "Warn Before It Ends", toggle = true, needs = timerOn, why = "Needs Show Time Left",
          help = "The time left turns yellow, then red near the end, so you see crowd control about to break." },
        { key = "warnAt", label = "Red Under", slider = { 1, 10, 1 }, unit = "s", needs = warnOn,
          why = "Needs Warn Before It Ends", help = "The seconds left when the time turns red; it turns yellow at twice that." },
        { key = "warnBlink", label = "Blink When Red", toggle = true, needs = warnOn, why = "Needs Warn Before It Ends",
          help = "The red time left blinks, to catch your eye." },
        Group("Buffs"),
        { key = "buffs", label = "Short Buffs", toggle = true, needs = Enabled, why = OFF,
          help = "Your target's buffs that last a short while, like Divine Shield, Evasion or Sprint." },
        { key = "buffLength", label = "Up To", slider = { 5, 120, 5 }, unit = "s", needs = buffsOn,
          why = "Needs Short Buffs",
          help = "The longest a buff can last to show; longer ones like Arcane Intellect stay hidden." },
        { key = "buffMagicOnly", label = "Only Magic Buffs", toggle = true, needs = buffsOn, why = "Needs Short Buffs",
          help = "Only buffs a dispel or purge can take off." },
        { key = "buffMax", label = "Max Buffs", slider = { 1, 10, 1 }, needs = Enabled, why = OFF },
        { key = "absorb", label = "Show Absorb", toggle = true, needs = Enabled, why = OFF,
          help = "Before the icons, in blue, how much the shields still absorb while one is up, with a shield icon when buffs are hidden." },
        Group("Crowd Control"),
        { key = "cc", label = "Crowd Control", toggle = true, needs = Enabled, why = OFF,
          help = "The crowd control on your target; pick which in the Crowd Control card below." },
        { key = "ccMax", label = "Max Crowd Control", slider = { 1, 10, 1 }, needs = Enabled, why = OFF },
        Group("Debuffs"),
        { key = "debuffs", label = "Debuffs", toggle = true, needs = Enabled, why = OFF,
          help = "The debuffs on your target you pick in the Debuffs card below, like Mortal Strike." },
        { key = "debuffMax", label = "Max Debuffs", slider = { 1, 10, 1 }, needs = Enabled, why = OFF },
        Group("Focus"),
        { key = "focus", label = "Focus Panel", toggle = true, needs = Enabled, why = OFF,
          help = "A second panel for your focus, to keep Sap or Polymorph's time on one enemy while you fight another." },
        { label = "Focus Macro", buttonText = "Open Forge", button = OpenForge, needs = ForgeReady,
          why = "Needs Focus Panel and the Macros module",
          help = "NF Focus in Naowh's Forge focuses the enemy under your mouse, or your target: drag it to a bar." },
        { key = "focusName", label = "Focus Name", toggle = true, needs = focusOn, why = "Needs Focus Panel",
          help = "Your focus's name, tinted by class, with their class icon above the panel." },
        { key = "focusBuffs", label = "Focus Short Buffs", toggle = true, needs = focusOn, why = "Needs Focus Panel" },
        { key = "focusCC", label = "Focus Crowd Control", toggle = true, needs = focusOn, why = "Needs Focus Panel" },
        { key = "focusDebuffs", label = "Focus Debuffs", toggle = true, needs = focusOn, why = "Needs Focus Panel" },
    },
})

page:Card({
    id = "crowdControl", name = "Crowd Control", order = 20,
    help = "Which crowd control shows, by ability: every rank, and the same spell from items and creatures.",
    studio = { height = GridHeight(CC_GROUPS), states = GRID_STATES, new = NewGrid(CC_GROUPS, "cc_", Enabled),
               paint = PaintGrid },
    rows = {
        Group("Everything Else"),
        { key = "ccOther", label = "Other Crowd Control", toggle = true, needs = Enabled, why = OFF,
          help = "Crowd control from creatures and anything not in the grid." },
        Group("All at Once"),
        { label = "Show Every Spell", buttonText = "Show All", button = SetAll(SPELLS.crowdControl, "cc_", true),
          needs = Enabled, why = OFF, help = "Lights every spell in the grid." },
        { label = "Hide Every Spell", buttonText = "Hide All", button = SetAll(SPELLS.crowdControl, "cc_", false),
          needs = Enabled, why = OFF, help = "Dims every spell, to light only the few you want." },
    },
})

page:Card({
    id = "debuffs", name = "Debuffs", order = 30,
    help = "Which debuffs show beside crowd control: off until you light them.",
    studio = { height = GridHeight(DEBUFF_GROUPS), states = GRID_STATES, new = NewGrid(DEBUFF_GROUPS, "debuff_", Enabled),
               paint = PaintGrid },
    rows = {
        Group("Your Own"),
        { key = "debuffExtra", label = "Spell IDs", text = true, wide = true, needs = Enabled, why = OFF,
          help = "More debuffs to show by spell ID, separated by spaces or commas (Wowhead has the ID)." },
        Group("All at Once"),
        { label = "Show Every Debuff", buttonText = "Show All", button = SetAll(SPELLS.debuffs, "debuff_", true),
          needs = Enabled, why = OFF, help = "Lights every debuff in the grid." },
        { label = "Hide Every Debuff", buttonText = "Hide All", button = SetAll(SPELLS.debuffs, "debuff_", false),
          needs = Enabled, why = OFF, help = "Dims every debuff in the grid." },
    },
})
