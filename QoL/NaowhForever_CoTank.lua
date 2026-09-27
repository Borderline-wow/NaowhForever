-------------------------------------------------------------------------------
--  NaowhForever_CoTank.lua -- the QoL co-tank frame: a health bar for the other tank in
--  your group while you are tanking. Click it to target them.
--
--  A secure unit button, so its unit, size, position and visibility only change out of
--  combat; a roster or setting change mid-fight waits for the fight to end.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local MAX_DEBUFFS = 5

local frame, unlocked, inCombat
local tank

local function On()
    return S.Get("enabled") and S.Get("coTank")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- The threat meter's test: tank role, Bear or Dire Bear Form, or Defensive Stance.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18
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
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.name = ns.Font(frame.bar, 12, "OUTLINE")
    frame.name:SetPoint("CENTER")

    frame.debuffs = {}
    -- Dragging it places it on the screen again, as NaowhQOL's did.
    frame.mover = ns.UI.AttachMover(frame, "Co-Tank", function(pos)
        S.Set("coTankPos", pos)
        S.Set("coTankAnchor", "UIParent")
    end)
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

local function DebuffIcon(i)
    local icon = frame.debuffs[i]
    if not icon then
        icon = CreateFrame("Frame", nil, frame)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon.count = ns.Font(icon, 10, "OUTLINE")
        icon.count:SetPoint("BOTTOMRIGHT", 1, 0)
        frame.debuffs[i] = icon
    end
    local size = S.Get("coTankHeight")
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", frame, "RIGHT", 2 + (i - 1) * (size + 2), 0)
    return icon
end

-- Out of combat only: the client withdraws auras from addons during a fight, and on some
-- pulls before it, when GetAuraDataByIndex raises instead of returning nil.
local function UpdateDebuffs()
    local shown = 0
    if tank and S.Get("coTankDebuffs") and not inCombat and not C_Secrets.ShouldAurasBeSecret() then
        for i = 1, MAX_DEBUFFS do
            local aura = C_UnitAuras.GetAuraDataByIndex(tank, i, "HARMFUL")
            if not aura then break end
            local icon = DebuffIcon(i)
            icon.tex:SetTexture(aura.icon)
            icon.count:SetText(aura.applications > 1 and aura.applications or "")
            icon:Show()
            shown = i
        end
    end
    for i = shown + 1, #frame.debuffs do frame.debuffs[i]:Hide() end
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
    UpdateDebuffs()
end

local function Preview()
    local c = S.Get("coTankColor")
    frame.bar:SetStatusBarColor(c.r, c.g, c.b)
    frame.bar:SetMinMaxValues(0, 100)
    frame.bar:SetValue(75)
    SetName("TankName", nil)
    UpdateDebuffs()
end

local events = CreateFrame("Frame")
local unitEvents = CreateFrame("Frame")
local Refresh

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if frame then UpdateDebuffs() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then inCombat = false end
    Refresh()
end)

unitEvents:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then
        UpdateDebuffs()
    elseif event == "UNIT_NAME_UPDATE" then
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
    inCombat = false
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end

    tank = PlayerIsTank() and FindOtherTank() or nil
    frame:SetAttribute("unit", tank)
    frame:SetSize(S.Get("coTankWidth"), S.Get("coTankHeight"))
    frame.bg:SetAlpha(S.Get("coTankBgAlpha"))
    frame.name:SetFont(ns.UI.FontPath(S.Get("coTankFont")), S.Get("coTankFontSize"), "OUTLINE")
    Place()
    frame.mover:SetShown(unlocked == true)
    if tank then
        for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_NAME_UPDATE" }) do
            unitEvents:RegisterUnitEvent(event, tank)
        end
        Paint()
    elseif unlocked then
        Preview()
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
