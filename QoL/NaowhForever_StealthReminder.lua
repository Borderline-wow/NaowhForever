-------------------------------------------------------------------------------
--  NaowhForever_StealthReminder.lua -- the QoL stealth, stance, aura and form reminders. Forever
--  does not expose your spec, so a druid or priest picks their form on the options page.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

-- GetShapeshiftFormID values, the same ones the threat meter reads.
local CAT, TRAVEL, AQUATIC, BEAR, DIRE_BEAR, FLIGHT, SHADOWFORM, SWIFT_FLIGHT, MOONKIN =
    1, 3, 4, 5, 8, 27, 28, 29, 31
local DRUID_FORMS = {
    cat = { [CAT] = true },
    bear = { [BEAR] = true, [DIRE_BEAR] = true },
    moonkin = { [MOONKIN] = true },
}
local TRAVEL_FORMS = { [TRAVEL] = true, [AQUATIC] = true, [FLIGHT] = true, [SWIFT_FLIGHT] = true }
local FORM_TEXT = { WARRIOR = "CHECK STANCE", PALADIN = "CHECK AURA", DRUID = "CHECK FORM",
    PRIEST = "SHADOWFORM" }

local stealthFrame, formFrame, unlocked, inCombat, class
local alarm, alarmTicker

local function On(key)
    if key == "formReminder" then return false end -- Retained for later review.
    return S.Get("enabled") and S.Get(key)
end

local function Color(key, classKey)
    if S.Get(classKey) then return RAID_CLASS_COLORS[class] end
    return S.Get(key)
end

local function Build(label, posKey, defaultY)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.text = ns.Font(frame, 22, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.posKey, frame.defaultY = posKey, defaultY
    frame.mover = UI.AttachMover(frame, label, function(pos) S.Set(posKey, pos) end, "QoL/General", "QoL/General:Enable Stealth Reminder")
    frame:Hide()
    return frame
end

local function Style(frame, fontKey, sizeKey)
    local size = S.Get(sizeKey)
    frame.text:SetFont(UI.FontPath(S.Get(fontKey)), size, "OUTLINE")
    frame:SetSize(300, size + 12)
    frame.mover:SetShown(unlocked == true)
    local pos = S.Get(frame.posKey)
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, frame.defaultY)
    end
end

local function Paint(frame, text, c)
    frame.text:SetText(text)
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame:Show()
end

local function Suppressed()
    if UnitIsDeadOrGhost("player") or IsMounted() or UnitOnTaxi("player") then return true end
    if S.Get("reminderInGroup") and not IsInGroup() then return true end
    return S.Get("reminderHideResting") and IsResting()
end

-- "stealthed", "missing", or nil when neither applies. Hidden in combat either way.
local function StealthState()
    if inCombat then return nil end
    local form = GetShapeshiftFormID()
    local druid = class == "DRUID" and not TRAVEL_FORMS[form]
        and (S.Get("stealthDruid") == "always" or form == CAT)
    if class ~= "ROGUE" and not druid then return nil end
    return IsStealthed() and "stealthed" or "missing"
end

local function FormMissing()
    if S.Get("formCombatOnly") and not inCombat then return false end
    if S.Get("formInstanceOnly") then
        local _, kind = IsInInstance()
        if kind ~= "party" and kind ~= "raid" then return false end
    end
    local form = GetShapeshiftFormID()
    if class == "WARRIOR" or class == "PALADIN" then
        return GetNumShapeshiftForms() > 0 and GetShapeshiftForm() == 0
    elseif class == "DRUID" then
        local want = DRUID_FORMS[S.Get("formDruid")]
        return want ~= nil and not TRAVEL_FORMS[form] and not want[form]
    elseif class == "PRIEST" then
        return S.Get("formShadowform") and GetNumShapeshiftForms() > 0 and form ~= SHADOWFORM
    end
    return false
end

local function PlayAlarm()
    UI._PlayLSMSound(UI.SoundPathFor(S.Get("formSoundKey")))
end

-- Plays as the warning appears, then again every Repeat Every seconds while it stays up.
local function SetAlarm(on)
    on = on and true or false
    if on == alarm then return end
    alarm = on
    if alarmTicker then
        alarmTicker:Cancel()
        alarmTicker = nil
    end
    if not on then return end
    PlayAlarm()
    local every = S.Get("formSoundInterval")
    if every > 0 then alarmTicker = C_Timer.NewTicker(every, PlayAlarm) end
end

local function Update()
    local suppressed = Suppressed()
    if stealthFrame then
        local state = On("stealthReminder") and (unlocked and "missing" or not suppressed and StealthState())
        if state == "stealthed" and not S.Get("stealthShowStealthed") then state = nil end
        if state == "stealthed" then
            Paint(stealthFrame, S.Get("stealthText"), Color("stealthColor", "stealthClassColor"))
        elseif state == "missing" then
            Paint(stealthFrame, S.Get("warningText"), Color("warningColor", "warningClassColor"))
        else
            stealthFrame:Hide()
        end
    end
    local warn = formFrame and On("formReminder") and (unlocked or not suppressed and FormMissing())
    if warn then
        local text = S.Get("formText")
        Paint(formFrame, text ~= "" and text or FORM_TEXT[class] or "CHECK STANCE",
            Color("formColor", "formClassColor"))
    elseif formFrame then
        formFrame:Hide()
    end
    SetAlarm(warn and not unlocked and S.Get("formSound"))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    Update()
end)

local function Apply()
    events:UnregisterAllEvents()
    SetAlarm(false)
    class = select(2, UnitClass("player"))
    local stealthOn, formOn = On("stealthReminder"), On("formReminder")
    if stealthOn and not stealthFrame then
        stealthFrame = Build("Stealth Reminder", "stealthPos", 150)
    end
    if formOn and not formFrame then
        formFrame = Build("Form Reminder", "formPos", 110)
    end
    if stealthFrame then Style(stealthFrame, "stealthFont", "stealthFontSize") end
    if formFrame then Style(formFrame, "formFont", "formFontSize") end
    if stealthOn or formOn then
        inCombat = UnitAffectingCombat("player")
        for _, event in ipairs({ "UPDATE_STEALTH", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED",
            "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE",
            "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
            "PLAYER_ENTERING_WORLD" }) do
            events:RegisterEvent(event)
        end
    end
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "stealthPos" or key == "formPos" then return end
    if key == "enabled" or key:find("^stealth") or key:find("^warning") or key:find("^form")
        or key:find("^reminder") then
        Apply()
    end
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
