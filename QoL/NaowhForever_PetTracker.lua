-------------------------------------------------------------------------------
--  NaowhForever_PetTracker.lua -- the QoL pet tracker: a warning while a pet is missing, passive
--  or low. Health is secret in combat, so a step curve turns it into the warning's alpha.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

local CALL_PET, SUMMON_IMP = 883, 688
local ICON = 132161
local DISMOUNT_DELAY = 5
-- Demonic Sacrifice leaves one of these on the warlock in place of the demon.
local SACRIFICE_BUFFS = { 18789, 18790, 18791, 18792 }

local frame, curve, unlocked, class
local mounted, dismountTimer, sacrificed

local function On()
    return S.Get("enabled") and S.Get("petTracker")
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverPetTracker", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(ICON)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.text = ns.Font(frame, 20, "OUTLINE")
    frame.mover = UI.AttachMover(frame, "Pet Tracker", function(pos) S.Set("petTrackerPos", pos) end, "QoL/Combat", "QoL/Combat:petTracker")
    frame:Hide()
end

local function Place()
    local pos = S.Get("petTrackerPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function Style()
    local size = S.Get("petFontSize")
    frame.text:SetFont(UI.FontPath(S.Get("petFont")), size, "OUTLINE")
    local c = S.Get("petClassColor") and RAID_CLASS_COLORS[class] or S.Get("petColor")
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame.text:ClearAllPoints()
    if S.Get("petShowIcon") then
        frame.icon:SetSize(size + 12, size + 12)
        frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon:Show()
        frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    else
        frame.icon:Hide()
        frame.text:SetPoint("CENTER")
    end
    frame:SetSize(220, size + 16)
end

local function BuildCurve()
    local below = S.Get("petLowHealthBelow") / 100
    curve = curve or C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(below - 0.001, 1)
    curve:AddPoint(below, 0)
    curve:AddPoint(1, 0)
end

local function ShouldHavePet()
    if class == "HUNTER" then return C_SpellBook.IsSpellKnown(CALL_PET) end
    if class == "WARLOCK" then return C_SpellBook.IsSpellKnown(SUMMON_IMP) and not sacrificed end
    return false
end

-- Out of combat only: in combat the client hides the player's own auras from addons, so the
-- last answer from before the fight stands.
local function CheckSacrifice()
    if class ~= "WARLOCK" or C_Secrets.ShouldAurasBeSecret() then return end
    sacrificed = false
    for _, id in ipairs(SACRIFICE_BUFFS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id) then
            sacrificed = true
            return
        end
    end
end

local function IsPassive()
    if not PetHasActionBar() then return false end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" then return isActive == true end
    end
    return false
end

local function Warning()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    if S.Get("petHideMounted") and (mounted or dismountTimer) then return end
    if S.Get("petCombatOnly") and not UnitAffectingCombat("player") then return end
    if S.Get("petInstanceOnly") and not IsInInstance() then return end
    if not ShouldHavePet() then return end
    if not UnitExists("pet") then return "petMissingText" end
    if S.Get("petPassive") and IsPassive() then return "petPassiveText" end
    if S.Get("petLowHealth") and not UnitIsDeadOrGhost("pet") then return "petLowHealthText", true end
end

local function Update()
    if unlocked then
        frame.text:SetText(S.Get("petMissingText"))
        frame:SetAlpha(1)
        frame:Show()
        return
    end
    local key, lowHealth = Warning()
    if not key then
        frame:Hide()
        return
    end
    frame.text:SetText(S.Get(key))
    if lowHealth then
        frame:SetAlpha(UnitHealthPercent("pet", true, curve))
    else
        frame:SetAlpha(1)
    end
    frame:Show()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local was = mounted
        mounted = IsMounted()
        if dismountTimer then dismountTimer:Cancel(); dismountTimer = nil end
        -- A pet can take a few seconds to come back after dismounting.
        if was and not mounted then
            dismountTimer = C_Timer.NewTimer(DISMOUNT_DELAY, function()
                dismountTimer = nil
                Update()
            end)
        end
    elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" then
        CheckSacrifice()
    elseif event == "UNIT_HEALTH" and unit ~= "pet" then
        return
    end
    Update()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        if dismountTimer then dismountTimer:Cancel(); dismountTimer = nil end
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    class = select(2, UnitClass("player"))
    Place()
    Style()
    BuildCurve()
    frame.mover:SetShown(unlocked == true)
    if On() then
        mounted = IsMounted()
        CheckSacrifice()
        for _, event in ipairs({ "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
            "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
            "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
            events:RegisterEvent(event)
        end
        events:RegisterUnitEvent("UNIT_HEALTH", "pet")
        events:RegisterUnitEvent("UNIT_MAXHEALTH", "pet")
        if class == "WARLOCK" then events:RegisterUnitEvent("UNIT_AURA", "player") end
    end
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^pet") and key ~= "petTrackerPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Group = ns.Shared.Settings.Group

local function OwnColour() return not S.Get("petClassColor") end

local function Summary(store)
    local parts = "Missing"
    if store.Get("petPassive") then parts = parts .. ", passive" end
    if store.Get("petLowHealth") then parts = parts .. (", below %d%%"):format(store.Get("petLowHealthBelow")) end
    return parts
end

ns.Shared.Settings.Page("QoL/Combat", S):Card({
    id = "petTracker", name = "Pet Tracker", order = 100, switch = "petTracker",
    help = "A warning while a hunter or warlock has no pet out. A warlock who sacrificed their "
        .. "demon is left alone. Move it in Unlock Mode.",
    summary = Summary,
    rows = {
        Group("Warnings"),
        { key = "petPassive", label = "Warn While Passive", toggle = true,
          help = "Also warns while your pet is set to passive." },
        { key = "petLowHealth", label = "Warn on Low Pet Health", toggle = true,
          help = "Also warns while your pet's health is under the threshold, in combat too." },
        { key = "petLowHealthBelow", label = "Low Health Below", slider = { 5, 90, 1 }, unit = "%",
          needs = "petLowHealth" },
        Group("When"),
        { key = "petCombatOnly", label = "Only In Combat", toggle = true },
        { key = "petInstanceOnly", label = "Only In Dungeons & Raids", toggle = true },
        { key = "petHideMounted", label = "Hide While Mounted", toggle = true,
          help = "Also hidden for a few seconds after you dismount, while the pet comes back." },
        Group("Text"),
        { key = "petMissingText", label = "Missing Text", text = true, help = "Text while your pet is missing." },
        { key = "petPassiveText", label = "Passive Text", text = true, needs = "petPassive",
          help = "Text while your pet is passive." },
        { key = "petLowHealthText", label = "Low Health Text", text = true, needs = "petLowHealth",
          help = "Text while your pet is low on health." },
        { key = "petShowIcon", label = "Show Icon", toggle = true },
        { key = "petClassColor", label = "Class Colour", toggle = true },
        { key = "petColor", label = "Colour", colour = true, needs = OwnColour, why = "Class colour is on" },
        { key = "petFont", label = "Font", font = true },
        { key = "petFontSize", label = "Font Size", slider = { 12, 48, 1 } },
    },
})
