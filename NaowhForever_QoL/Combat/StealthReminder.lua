-- StealthReminder.lua: the QoL stealth, stance, aura and form reminders.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local UI = ns.UI
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local WIDTH = 300
local FONT_SIZE = 22
local HEIGHT_ROOM = 12
local STEALTH_Y, FORM_Y = 150, 110
local TEXT_RANGE = { 10, 60, 1 }
local PAGE = "QoL/Combat"
local CARD = "QoL/Combat:stealthReminder"

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
local EVENTS = { "UPDATE_STEALTH", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_ENTERING_WORLD" }
local DRUID_STEALTH = { { cat = "In Cat Form", always = "In Any Form" }, { "cat", "always" } }

local TEXT_FORM = "CHECK STANCE"
local TEXT_STEALTH_MOVER = "Stealth Reminder"
local TEXT_FORM_MOVER = "Form Reminder"

local stealthFrame, formFrame, unlocked, inCombat, class
local alarm, alarmTicker
local events = CreateFrame("Frame")

local function On(key)
    if key == "formReminder" then return false end
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
    frame.text = ns.Font(frame, FONT_SIZE, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    frame.posKey, frame.defaultY = posKey, defaultY
    frame.mover = UI.AttachMover(frame, label, function(pos) S.Set(posKey, pos) end, PAGE, CARD)
    frame:Hide()
    return frame
end

local function Restyle(frame, prefix)
    local size = S.Get(prefix .. "FontSize")
    frame.mode = frame.backdrop:SetMode(S.Get(prefix .. "Background"))
    Parts.HudFont(frame.text, S.Get(prefix .. "Font"), size, S.Get(prefix .. "Outline"), frame.mode)
    frame:SetSize(WIDTH, size + HEIGHT_ROOM)
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
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Suppressed()
    if UnitIsDeadOrGhost("player") or IsMounted() or UnitOnTaxi("player") then return true end
    if S.Get("reminderInGroup") and not IsInGroup() then return true end
    return S.Get("reminderHideResting") and IsResting()
end

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

local function UpdateStealth(suppressed)
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

local function UpdateForm(suppressed)
    local warn = formFrame and On("formReminder") and (unlocked or not suppressed and FormMissing())
    if warn then
        local text = S.Get("formText")
        Paint(formFrame, text ~= "" and text or FORM_TEXT[class] or TEXT_FORM, Color("formColor", "formClassColor"))
    elseif formFrame then
        formFrame:Hide()
    end
    return warn
end

local function Update()
    local suppressed = Suppressed()
    if stealthFrame then UpdateStealth(suppressed) end
    local warn = UpdateForm(suppressed)
    SetAlarm(warn and not unlocked and S.Get("formSound"))
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    Update()
end

local function Apply()
    events:UnregisterAllEvents()
    SetAlarm(false)
    class = select(2, UnitClass("player"))
    local stealthOn, formOn = On("stealthReminder"), On("formReminder")
    if stealthOn and not stealthFrame then
        stealthFrame = Build(TEXT_STEALTH_MOVER, "stealthPos", STEALTH_Y)
    end
    if formOn and not formFrame then
        formFrame = Build(TEXT_FORM_MOVER, "formPos", FORM_Y)
    end
    if stealthFrame then Restyle(stealthFrame, "stealth") end
    if formFrame then Restyle(formFrame, "form") end
    if stealthOn or formOn then
        inCombat = UnitAffectingCombat("player")
        for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    end
    Update()
end

events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", function(key)
    if key == "stealthPos" or key == "formPos" then return end
    if key == "enabled" or key:find("^stealth") or key:find("^warning") or key:find("^form")
        or key:find("^reminder") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideUnlockMode", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Group = ns.Shared.Settings.Group

local function StealthedOn() return S.Get("stealthShowStealthed") end
local function WarningOwnColour() return not S.Get("warningClassColor") end
local function StealthedOwnColour() return S.Get("stealthShowStealthed") and not S.Get("stealthClassColor") end

ns.Shared.Settings.Page(PAGE, S):Card({
    id = "stealthReminder", name = "Stealth Reminder", order = 30, switch = "stealthReminder",
    help = "Out-of-combat stealth status for rogues and druids: a reminder while you are not in "
        .. "stealth. Move it in the HUD Editor.",
    rows = {
        Group("When"),
        { key = "reminderInGroup", label = "Only In a Group", toggle = true,
          help = "Reminds you only while you are in a group." },
        { key = "reminderHideResting", label = "Hide While Resting", toggle = true,
          help = "No reminder in an inn or a city." },
        { key = "stealthShowStealthed", label = "Show While Stealthed", toggle = true,
          help = "The stealthed text while you are in stealth, as well as the reminder when you "
              .. "are not." },
        { key = "stealthDruid", label = "Druids", choice = DRUID_STEALTH,
          help = "In Cat Form reminds a druid only while in Cat Form. In Any Form reminds in every "
              .. "form but travel forms, for a druid who prowls between fights." },
        Group("Messages"),
        { key = "warningText", label = "Out of Stealth Text", text = true,
          help = "What it says while you are out of stealth." },
        { key = "stealthText", label = "Stealthed Text", text = true, needs = "stealthShowStealthed",
          help = "What it says while you are in stealth." },
        ns.Shared.Settings.Look("stealth", { text = true, size = TEXT_RANGE, background = "card" }),
        Group("Colours"),
        { key = "warningClassColor", label = "Out of Stealth in Class Colour", toggle = true },
        { key = "warningColor", label = "Out of Stealth Colour", colour = true, needs = WarningOwnColour,
          why = "Class colour is on" },
        { key = "stealthClassColor", label = "Stealthed in Class Colour", toggle = true, needs = StealthedOn,
          why = "Needs Show While Stealthed" },
        { key = "stealthColor", label = "Stealthed Colour", colour = true, needs = StealthedOwnColour },
    },
})
