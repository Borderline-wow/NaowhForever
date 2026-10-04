-------------------------------------------------------------------------------
--  NaowhForever_CoTank.lua -- the QoL co-tank frame: a health bar for the other tank. Debuffs
--  go through Blizzard's aura container, the only thing that can draw secret aura data.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local RIGHTEOUS_FURY = 25780
local PALADIN = select(2, UnitClass("player")) == "PALADIN"

local frame, unlocked
local tank, fury
local debuffs, styleKey

local function On()
    return S.Get("enabled") and S.Get("coTank")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- Righteous Fury is an aura, so it is only readable while auras are not secret; the last
-- answer stands in until they are.
local function HasFury()
    if not C_Secrets.ShouldAurasBeSecret() then
        fury = C_UnitAuras.GetPlayerAuraBySpellID(RIGHTEOUS_FURY) ~= nil
    end
    return fury
end

-- The threat meter's test: tank role, Bear or Dire Bear Form, or Defensive Stance, plus
-- Righteous Fury for paladins.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18 or (PALADIN and HasFury())
end

-- Tank role, or the raid's Main Tank assignment.
local function FindOtherTank()
    local raid = IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or GetNumSubgroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        local isMe, role = UnitIsUnit(unit, "player"), UnitGroupRolesAssigned(unit)
        if not (Secret(isMe) or Secret(role) or isMe)
            and (role == "TANK" or GetPartyAssignment("MAINTANK", unit)) then
            return unit
        end
    end
end

-------------------------------------------------------------------------------
--  Debuffs
-------------------------------------------------------------------------------
-- Blizzard's own sated/hidden set, as NaowhUI keeps it.
local HIDDEN_DEBUFFS = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true,
    [1254550] = true, [308312] = true,
}

-- One group per filter, so the icon cap is the whole row. isBossOrRoleAura is the engine's
-- own "boss aura or role aura" test, which needs only one group; the default sort has no
-- boss tiebreak, so a wide group would fill with older trash debuffs first.
local DEBUFF_GROUPS = {
    { key = "all",         filter = "HARMFUL" },
    { key = "important",   filter = "HARMFUL", cand = { isBossOrRoleAura = true } },
    { key = "nonplayer",   filter = "HARMFUL", cand = { isFromPlayerOrPlayerPet = false } },
    { key = "dispellable", filter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
}
for _, g in ipairs(DEBUFF_GROUPS) do
    g.cand = g.cand or {}
    g.cand.excludeSpellIDs = HIDDEN_DEBUFFS
end

local CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- The row's edge that meets the bar is the mirror of the bar corner: a row above puts its
-- BOTTOM on the bar's TOP.
local MIRROR = {
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
    BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
    CENTER = "CENTER",
}

local PREVIEW_ICONS = {
    [[Interface\Icons\Spell_Shadow_ShadowWordPain]],
    [[Interface\Icons\Spell_Fire_Immolation]],
    [[Interface\Icons\Spell_Frost_FrostNova]],
    [[Interface\Icons\Spell_Nature_Earthbind]],
    [[Interface\Icons\Spell_Shadow_CurseOfSargeras]],
    [[Interface\Icons\Spell_Holy_Silence]],
    [[Interface\Icons\Ability_Poisons]],
    [[Interface\Icons\Spell_Shadow_UnholyFrenzy]],
}

-- Bare seconds under a minute, then 2m / 1h / 1d. Seconds round up so it never reads 0
-- while time remains; the Up band at 60 stops a value just under a minute showing "0m".
local durationFormatter

local function DurationFormatter()
    if durationFormatter then return durationFormatter end
    local Up, Down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
    durationFormatter = C_StringUtil.CreateNumericRuleFormatter()
    durationFormatter:SetBreakpoints({
        { threshold = 0,     format = "%d",  step = 1, rounding = Up },
        { threshold = 60,    format = "%dm", step = 1, rounding = Up,   components = { { div = 60 } } },
        { threshold = 61,    format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600,  format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
    })
    return durationFormatter
end

-- Regions per engine button, kept off the button itself.
local buttons = setmetatable({}, { __mode = "k" })

local function Flow()
    local corner = CORNERS[S.Get("coTankDebuffPosition")] or "TOP"
    local grow = S.Get("coTankDebuffGrow")
    local point = MIRROR[corner]
    local h, v = grow, "UP"
    if grow == "CENTER" then
        -- A row that wraps away from the bar, not back through it.
        h, v = "RIGHT", point:find("TOP", 1, true) and "DOWN" or "UP"
    elseif grow == "UP" or grow == "DOWN" then
        h, v = "RIGHT", grow
    end
    return corner, point, h, v, grow == "UP" or grow == "DOWN"
end

-- Button calls are denied while auras are secret, so a restyle waits for them to clear.
local function StyleButton(button, r)
    local size = S.Get("coTankDebuffSize")
    local font = ns.UI.FontPath(S.Get("coTankFont"))
    button:SetSize(size, size)
    button:SetMouseMotionEnabled(S.Get("coTankDebuffTooltips"))
    r.duration:SetFont(font, S.Get("coTankDebuffDurationSize"), "OUTLINE")
    r.duration:SetShown(S.Get("coTankDebuffDuration"))
    r.stack:SetFont(font, S.Get("coTankDebuffStackSize"), "OUTLINE")
    r.stack:SetShown(S.Get("coTankDebuffStacks"))
end

-- Runs once per engine button, the only time parenting to the button is allowed. Fonts are
-- set before the engine is handed a font string: it writes text into them straight away.
local function InitButton(button)
    local r = {}
    buttons[button] = r
    -- The bar under the row is click-to-target.
    button:SetMouseClickEnabled(false)

    r.icon = button:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    r.cooldown:SetAllPoints()
    r.cooldown:SetReverse(true)
    r.cooldown:SetDrawEdge(false)
    r.cooldown:SetHideCountdownNumbers(true)
    ns.Border(r.cooldown, { r = 0, g = 0, b = 0 })

    -- Plain white strips the engine shows and tints by dispel type; which aura gets them
    -- is secret, so that call is the engine's.
    local ring = CreateFrame("Frame", nil, button)
    ring:SetAllPoints()
    ring:SetFrameLevel(r.cooldown:GetFrameLevel() + 3)
    local strips = {}
    for i = 1, 4 do
        strips[i] = ring:CreateTexture(nil, "OVERLAY")
        strips[i]:SetColorTexture(1, 1, 1, 1)
    end
    strips[1]:SetPoint("TOPLEFT"); strips[1]:SetPoint("TOPRIGHT"); strips[1]:SetHeight(2)
    strips[2]:SetPoint("BOTTOMLEFT"); strips[2]:SetPoint("BOTTOMRIGHT"); strips[2]:SetHeight(2)
    strips[3]:SetPoint("TOPLEFT", 0, -2); strips[3]:SetPoint("BOTTOMLEFT", 0, 2); strips[3]:SetWidth(2)
    strips[4]:SetPoint("TOPRIGHT", 0, -2); strips[4]:SetPoint("BOTTOMRIGHT", 0, 2); strips[4]:SetWidth(2)
    local ringOpts = { style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
        showWhenHarmful = true, showWhenHelpful = false }
    for i = 1, 4 do button:AddDispelTypeTexture(strips[i], ringOpts) end

    local text = CreateFrame("Frame", nil, button)
    text:SetAllPoints()
    text:SetFrameLevel(ring:GetFrameLevel() + 1)
    r.stack = ns.Font(text, 10, "OUTLINE")
    r.stack:SetPoint("BOTTOMRIGHT", 1, 1)
    r.duration = ns.Font(text, 10, "OUTLINE")
    r.duration:SetPoint("CENTER")
    StyleButton(button, r)

    button:SetIcon(r.icon)
    button:SetDurationCooldown(r.cooldown)
    button:SetApplicationCount(r.stack, {})
    button:SetDurationText(r.duration, { textFormatter = DurationFormatter() })
end

local function BuildDebuffs()
    C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    debuffs = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    debuffs:SetSize(1, 1)
    debuffs:SetFrameLevel(frame.bar:GetFrameLevel() + 5)
    for _, g in ipairs(DEBUFF_GROUPS) do
        debuffs:AddAuraGroup(g.key, g.filter, {
            maxFrameCount = 0,
            candidateFilters = g.cand,
            sortMethod = AuraContainerSortMethod.Default,
            initializeFrame = InitButton,
        })
    end
    debuffs:Hide()
end

local function LayoutDebuffs()
    local corner, point, h, v, vertical = Flow()
    local size, spacing = S.Get("coTankDebuffSize"), S.Get("coTankDebuffSpacing")
    local FD = AnchorUtil.FlowDirection
    debuffs:ClearAllPoints()
    debuffs:SetPoint(point, frame, corner, S.Get("coTankDebuffX"), S.Get("coTankDebuffY"))
    -- Flow starts on the far side of its travel: RIGHT begins at a LEFT corner.
    debuffs:SetFlowLayoutAnchorPoint((v == "DOWN" and "TOP" or "BOTTOM") .. (h == "LEFT" and "RIGHT" or "LEFT"))
    debuffs:SetFlowLayoutGrowthDirection(h == "LEFT" and FD.Left or FD.Right, v == "DOWN" and FD.Down or FD.Up)
    debuffs:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    -- A vertical row is one column. The 0.4 slack stops the engine's rounding dropping
    -- the last icon when the width equals the content exactly.
    debuffs:SetFlowLayoutMaximumLineSize(vertical and size + 0.4 or nil)

    local layout = { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing }
    local active = S.Get("coTankDebuffFilter")
    for _, g in ipairs(DEBUFF_GROUPS) do
        if g.key == active then
            debuffs:SetAuraGroupMaxFrameCount(g.key, S.Get("coTankDebuffCap"))
            debuffs:SetAuraGroupCandidateFilters(g.key, g.cand)
            debuffs:SetAuraGroupLayout(g.key, layout)
        else
            debuffs:SetAuraGroupMaxFrameCount(g.key, 0)
        end
    end

    local key = table.concat({ S.Get("coTankDebuffSize"), S.Get("coTankFont"),
        tostring(S.Get("coTankDebuffTooltips")), tostring(S.Get("coTankDebuffDuration")),
        S.Get("coTankDebuffDurationSize"), tostring(S.Get("coTankDebuffStacks")),
        S.Get("coTankDebuffStackSize") }, "|")
    if key ~= styleKey and not C_Secrets.ShouldAurasBeSecret() then
        for button, r in pairs(buttons) do StyleButton(button, r) end
        styleKey = key
    end
end

-- Plain textures, not engine buttons: the engine only draws auras the unit really has.
local function ShowPreviewDebuffs(show)
    local host = frame.previewDebuffs
    if not show then
        if host then host:Hide() end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetFrameLevel(frame.bar:GetFrameLevel() + 5)
        host.icons = {}
        for i, path in ipairs(PREVIEW_ICONS) do
            local icon = CreateFrame("Frame", nil, host)
            icon.tex = icon:CreateTexture(nil, "ARTWORK")
            icon.tex:SetAllPoints()
            icon.tex:SetTexture(path)
            icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            ns.Border(icon, { r = 0, g = 0, b = 0 })
            host.icons[i] = icon
        end
        frame.previewDebuffs = host
    end

    local corner, point, h, v, vertical = Flow()
    local size, spacing = S.Get("coTankDebuffSize"), S.Get("coTankDebuffSpacing")
    local n = math.min(S.Get("coTankDebuffCap"), #host.icons)
    local run = n * size + math.max(0, n - 1) * spacing
    host:ClearAllPoints()
    host:SetPoint(point, frame, corner, S.Get("coTankDebuffX"), S.Get("coTankDebuffY"))
    host:SetSize(vertical and size or run, vertical and run or size)
    for i, icon in ipairs(host.icons) do
        icon:SetShown(i <= n)
        if i <= n then
            local off = (i - 1) * (size + spacing)
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            if vertical then
                local from = v == "DOWN" and "TOP" or "BOTTOM"
                icon:SetPoint(from, host, from, 0, v == "DOWN" and -off or off)
            else
                local from = h == "LEFT" and "RIGHT" or "LEFT"
                icon:SetPoint(from, host, from, h == "LEFT" and -off or off, 0)
            end
        end
    end
    host:Show()
end

-------------------------------------------------------------------------------
--  Frame
-------------------------------------------------------------------------------
local function Build()
    frame = CreateFrame("Button", "NaowhForeverCoTank", UIParent, "SecureUnitButtonTemplate")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("type1", "target")
    frame.bg = ns.Solid(frame, "BACKGROUND", T.bg, 1)
    frame.bg:SetAllPoints()
    ns.Border(frame, { r = 0, g = 0, b = 0 })

    frame.bar = CreateFrame("StatusBar", nil, frame)
    ns.PixelInset(frame.bar, 1)
    frame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.name = ns.Font(frame.bar, 12, "OUTLINE")
    frame.name:SetPoint("CENTER")

    -- Dragging it places it on the screen again, as NaowhQOL's did.
    frame.mover = ns.UI.AttachMover(frame, "Co-Tank", function(pos)
        S.Set("coTankPos", pos)
        S.Set("coTankAnchor", "UIParent")
    end, "QoL/Combat", "QoL/Combat:coTank")
end

-- Anchored to another frame by name, centre on centre plus the X and Y offsets; otherwise
-- wherever it was dragged. A name that matches no frame falls back to the screen.
local function Place()
    local pos = S.Get("coTankPos")
    local anchor = _G[S.Get("coTankAnchor")]
    frame:ClearAllPoints()
    if anchor ~= UIParent and type(anchor) == "table" and anchor.GetObjectType then
        frame:SetPoint("CENTER", anchor, "CENTER", S.Get("coTankX"), S.Get("coTankY"))
    elseif pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
end

local function UpdateHealth()
    frame.bar:SetMinMaxValues(0, UnitHealthMax(tank))
    frame.bar:SetValue(UnitHealth(tank))
end

local function SetName(name, classColor)
    if not S.Get("coTankName") then
        frame.name:SetText("")
        return
    end
    local length = S.Get("coTankNameLength")
    if length > 0 and not Secret(name) then name = strsub(name, 1, length) end
    frame.name:SetText(name)
    local c = S.Get("coTankNameClassColor") and classColor or S.Get("coTankNameColor")
    frame.name:SetTextColor(c.r, c.g, c.b, 1)
end

local function Paint()
    local _, class = UnitClass(tank)
    local classColor = not Secret(class) and RAID_CLASS_COLORS[class]
    local c = S.Get("coTankClassColor") and classColor or S.Get("coTankColor")
    frame.bar:SetStatusBarColor(c.r, c.g, c.b)
    SetName(UnitName(tank), classColor)
    UpdateHealth()
end

local function Preview()
    local c = S.Get("coTankColor")
    frame.bar:SetStatusBarColor(c.r, c.g, c.b)
    frame.bar:SetMinMaxValues(0, 100)
    frame.bar:SetValue(75)
    SetName("TankName", nil)
end

local events = CreateFrame("Frame")
local unitEvents = CreateFrame("Frame")
local Refresh

events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then
        local was = fury
        if HasFury() == was then return end
    end
    Refresh()
end)

unitEvents:SetScript("OnEvent", function(_, event)
    if event == "UNIT_NAME_UPDATE" then
        Paint()
    else
        UpdateHealth()
    end
end)

function Refresh()
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    events:UnregisterAllEvents()
    unitEvents:UnregisterAllEvents()
    tank = nil
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    if PALADIN then events:RegisterUnitEvent("UNIT_AURA", "player") end

    tank = PlayerIsTank() and FindOtherTank() or nil
    frame:SetAttribute("unit", tank)
    frame:SetSize(S.Get("coTankWidth"), S.Get("coTankHeight"))
    frame.bg:SetAlpha(S.Get("coTankBgAlpha"))
    frame.name:SetFont(ns.UI.FontPath(S.Get("coTankFont")), S.Get("coTankFontSize"), "OUTLINE")
    Place()
    frame.mover:SetShown(unlocked == true)

    local showDebuffs = S.Get("coTankDebuffs")
    if tank then
        for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }) do
            unitEvents:RegisterUnitEvent(event, tank)
        end
        Paint()
    elseif unlocked then
        Preview()
    end
    ShowPreviewDebuffs(showDebuffs and not tank and unlocked == true)

    if showDebuffs and tank then
        if not debuffs then BuildDebuffs() end
        LayoutDebuffs()
        debuffs:SetUnit(tank)
        debuffs:Show()
        debuffs:UpdateAllAuras()
    elseif debuffs then
        debuffs:Hide()
    end
    frame:SetShown(tank ~= nil or unlocked == true)
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^coTank") and key ~= "coTankPos") then Refresh() end
end)
hooksecurefunc(ns, "Apply", function() Refresh() end)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Refresh()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Refresh()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() Refresh() end)

local Group = ns.Shared.Settings.Group
local FILTER = { { important = "Boss & Important", nonplayer = "Non-Player Auras", all = "All Debuffs",
    dispellable = "Dispellable by You" }, { "important", "nonplayer", "all", "dispellable" } }
local POSITION = { { top = "Above", bottom = "Below", left = "Left", right = "Right", topleft = "Top Left",
    topright = "Top Right", bottomleft = "Bottom Left", bottomright = "Bottom Right", center = "Centre" },
    { "top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright", "center" } }
local GROW = { { CENTER = "Centred", RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" },
    { "CENTER", "RIGHT", "LEFT", "UP", "DOWN" } }
local FROM_ANCHOR = "From the centre of the anchor frame. Only used while anchored to a frame."

local function OwnHealthColour() return not S.Get("coTankClassColor") end
local function OwnNameColour() return S.Get("coTankName") and not S.Get("coTankNameClassColor") end

local function Summary(store)
    return ("%d by %d%s"):format(store.Get("coTankWidth"), store.Get("coTankHeight"),
        store.Get("coTankDebuffs") and ", with debuffs" or "")
end

ns.Shared.Settings.Page("QoL/Combat", S):Card({
    id = "coTank", name = "Co-Tank Frame", order = 40, switch = "coTank",
    help = "A small health bar for the other tank in your group, shown while you are tanking: "
        .. "tank role, Bear Form, Defensive Stance or Righteous Fury. The other tank is whoever has "
        .. "the tank role or the raid's Main Tank assignment. Click it to target them. Changes made "
        .. "in combat apply when the fight ends. Move it in Unlock Mode.",
    summary = Summary,
    rows = {
        Group("Size"),
        { key = "coTankWidth", label = "Width", slider = { 50, 400, 5 } },
        { key = "coTankHeight", label = "Height", slider = { 10, 80, 1 } },
        Group("Health"),
        { key = "coTankClassColor", label = "Class Colour Health", toggle = true },
        { key = "coTankColor", label = "Health Colour", colour = true, needs = OwnHealthColour,
          why = "Class colour is on" },
        { key = "coTankBgAlpha", label = "Background Opacity", slider = { 0, 100, 5 }, unit = "%", scale = 0.01 },
        Group("Name"),
        { key = "coTankName", label = "Show Name", toggle = true },
        { key = "coTankNameLength", label = "Name Length", slider = { 0, 20, 1 }, needs = "coTankName",
          help = "Cuts the name to this many letters. 0 shows it whole." },
        { key = "coTankNameClassColor", label = "Class Colour Name", toggle = true, needs = "coTankName" },
        { key = "coTankNameColor", label = "Name Colour", colour = true, needs = OwnNameColour,
          why = "Needs Show Name, class colour off" },
        { key = "coTankFont", label = "Font", font = true, needs = "coTankName" },
        { key = "coTankFontSize", label = "Font Size", slider = { 8, 24, 1 }, needs = "coTankName" },
        Group("Position"),
        { key = "coTankAnchor", label = "Anchor to a Frame", text = true, wide = true,
          help = "Frame to anchor to, such as PlayerFrame. UIParent puts it back on the screen, and so "
              .. "does dragging it in Unlock Mode." },
        { key = "coTankX", label = "X Offset", slider = { -2000, 2000, 1 }, help = FROM_ANCHOR },
        { key = "coTankY", label = "Y Offset", slider = { -2000, 2000, 1 }, help = FROM_ANCHOR },
        Group("Debuffs"),
        { key = "coTankDebuffs", label = "Co-Tank Debuffs", toggle = true,
          help = "Shows the other tank's debuffs beside their health bar, in combat too: tank-buster "
              .. "stacks, boss debuffs and anything you can dispel." },
        { key = "coTankDebuffFilter", label = "Filter", choice = FILTER, needs = "coTankDebuffs" },
        { key = "coTankDebuffCap", label = "Max Icons", slider = { 1, 8, 1 }, needs = "coTankDebuffs" },
        { key = "coTankDebuffSize", label = "Icon Size", slider = { 10, 48, 1 }, needs = "coTankDebuffs" },
        { key = "coTankDebuffPosition", label = "Position", choice = POSITION, needs = "coTankDebuffs" },
        { key = "coTankDebuffGrow", label = "Grow", choice = GROW, needs = "coTankDebuffs" },
        { key = "coTankDebuffX", label = "Offset X", slider = { -200, 200, 1 }, needs = "coTankDebuffs" },
        { key = "coTankDebuffY", label = "Offset Y", slider = { -200, 200, 1 }, needs = "coTankDebuffs" },
        { key = "coTankDebuffSpacing", label = "Spacing", slider = { 0, 12, 1 }, needs = "coTankDebuffs" },
        { key = "coTankDebuffTooltips", label = "Show Tooltips", toggle = true, needs = "coTankDebuffs",
          help = "Off by default: the bar under the icons is click-to-target." },
        { key = "coTankDebuffDuration", label = "Show Time Left", toggle = true, needs = "coTankDebuffs" },
        { key = "coTankDebuffDurationSize", label = "Time Left Size", slider = { 6, 20, 1 },
          needs = { "coTankDebuffs", "coTankDebuffDuration" } },
        { key = "coTankDebuffStacks", label = "Show Stacks", toggle = true, needs = "coTankDebuffs" },
        { key = "coTankDebuffStackSize", label = "Stacks Size", slider = { 6, 20, 1 },
          needs = { "coTankDebuffs", "coTankDebuffStacks" } },
    },
})
