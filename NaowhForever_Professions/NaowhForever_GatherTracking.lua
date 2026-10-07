-------------------------------------------------------------------------------
--  NaowhForever_GatherTracking.lua -- a clickable icon on screen while you know Find Herbs,
--  Find Minerals or Find Fish but track none of them. Click it to start tracking: left-click
--  casts the first you know, right-click the second, middle-click the third.
--
--  Casting is Blizzard-only, so the icon is a secure spell button. Secure frames cannot show,
--  hide or change spell in combat: it hides as combat starts and catches up once it ends.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.ProfessionSettings
local UI = ns.UI
local T = ns.THEME
local Parts = ns.Shared.Parts

local FIND_HERBS, FIND_MINERALS, FIND_FISH = 2383, 2580, 43308
-- Find Fish sits among Fishing's unlearned recipes with no source recorded yet; it only
-- counts while `gatherFish` is on.
local TRACKINGS = {
    { spell = FIND_HERBS, label = "Herbs" },
    { spell = FIND_MINERALS, label = "Minerals" },
    { spell = FIND_FISH, label = "Fish", key = "gatherFish" },
}
local CLICKS = { { "1", "Left-click" }, { "2", "Right-click" }, { "3", "Middle-click" } }

local button, unlocked, pending

local Look = {}

function Look.New(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(frame, { r = 0, g = 0, b = 0 })
    frame.label = ns.Font(frame, 13, "OUTLINE", T.accentSoft)
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -4)
end

function Look.Fill(frame, size, texture, text)
    frame:SetSize(size, size)
    frame.icon:SetTexture(texture)
    Parts.HudFont(frame.label, S.Get("gatherFont"), S.Get("gatherFontSize"), S.Get("gatherOutline"))
    frame.label:SetText(text)
end

local function On()
    return S.Get("enabled") and S.Get("gatherReminder")
end

-- Whether a tracking spell is switched on, from the minimap's tracking list. Read either way
-- round, as a table or as values, since which one Forever returns was not pinned down.
local function Tracking(spellID)
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" then
            if info.spellID == spellID then return info.active == true end
        else
            local _, _, active, _, _, id = C_Minimap.GetTrackingInfo(i)
            if id == spellID then return active == true end
        end
    end
    return false
end

local function Known()
    local known, any = {}, false
    for _, t in ipairs(TRACKINGS) do
        if C_SpellBook.IsSpellKnown(t.spell) and (not t.key or S.Get(t.key)) then
            known[#known + 1] = t
            if Tracking(t.spell) then any = true end
        end
    end
    return known, any
end

local function Suppressed()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return true end
    return IsInInstance() and not S.Get("gatherInInstances")
end

local function Build()
    button = CreateFrame("Button", "NaowhForeverGatherTracking", UIParent, "SecureActionButtonTemplate")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)

    Look.New(button)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.15)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Not Tracking", 1, 0.82, 0)
        for i, t in ipairs(self.known or {}) do
            local name = C_Spell.GetSpellName(t.spell) or t.label
            GameTooltip:AddLine(CLICKS[i][2] .. ": " .. name, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button.mover = UI.AttachMover(button, "Tracking", function(pos) S.Set("gatherPos", pos) end, "Professions/Settings", "Professions/Settings:gather")
    button:Hide()
end

local function Place()
    local pos = S.Get("gatherPos")
    button:ClearAllPoints()
    if pos then
        button:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 260, 120)
    end
end

local function Arm(known)
    button.known = known
    for i, click in ipairs(CLICKS) do
        local t = known[i]
        button:SetAttribute("type" .. click[1], t and "spell" or nil)
        button:SetAttribute("spell" .. click[1], t and t.spell or nil)
    end
    local shown = known[1] or TRACKINGS[1]
    local labels = {}
    for _, t in ipairs(#known > 0 and known or { TRACKINGS[1], TRACKINGS[2] }) do
        labels[#labels + 1] = t.label
    end
    Look.Fill(button, S.Get("gatherIconSize"), C_Spell.GetSpellTexture(shown.spell),
        "Track " .. table.concat(labels, " / "))
end

local function Update(event)
    if not button then return end
    -- InCombatLockdown() is still false while PLAYER_REGEN_DISABLED is handled: the last
    -- moment the button can be hidden.
    if event == "PLAYER_REGEN_DISABLED" then
        button:Hide()
        return
    end
    -- Combat's end updates it again.
    if InCombatLockdown() then return end
    local known, any = Known()
    Arm(known)
    if unlocked then
        button:Show()
    else
        button:SetShown(On() and #known > 0 and not any and not Suppressed())
    end
end

local Apply
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and pending then
        pending = nil
        return Apply()
    end
    Update(event)
end)

-- A setting changed in combat, or logging in during one, applies once the fight ends.
function Apply()
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    events:UnregisterAllEvents()
    if not (On() or unlocked) then
        if button then button:Hide() end
        return
    end
    if not button then Build() end
    local size = S.Get("gatherIconSize")
    button:SetSize(size, size)
    Place()
    button.mover:SetShown(unlocked == true)
    for _, event in ipairs({ "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
        "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^gather") and key ~= "gatherPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
-- Unlock Mode only shows the icon while the reminder is on, so it is never built for nothing.
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local GATHER_OFF = "Turn on Professions"
local PREVIEW_LIFT = 8
local PREVIEW_STATES = {
    { key = "untracked", label = "Not Tracking", tip = "What shows while you know a find but track none." },
}

local function ModuleOn() return S.Get("enabled") == true end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetPoint("CENTER", 0, PREVIEW_LIFT)
    Look.New(preview)
    return preview
end

local function PaintPreview(preview)
    Look.Fill(preview, S.Get("gatherIconSize"), C_Spell.GetSpellTexture(FIND_HERBS), "Track Herbs / Minerals")
end

local function GatherSummary(store)
    return ("%d px icon%s"):format(store.Get("gatherIconSize"),
        store.Get("gatherInInstances") and ", in instances too" or "")
end

Settings.Page("Professions/Settings", S):Card({
    id = "gather", name = "Tracking Reminder", order = 50, switch = "gatherReminder",
    help = "Shows an icon on screen while you know Find Herbs, Find Minerals or Find Fish but are tracking none "
        .. "of them. Click it to start tracking: left-click for the first, right-click for the second, "
        .. "middle-click for the third. Hover it to see which is which. Hidden in combat. Move it in the HUD Editor.",
    summary = GatherSummary,
    studio = { height = 130, states = PREVIEW_STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        { key = "gatherInInstances", label = "Show in Dungeons and Raids", toggle = true, needs = ModuleOn,
          why = GATHER_OFF, help = "Also reminds you inside instances. Off by default: few have herbs or ore." },
        { key = "gatherFish", label = "Include Find Fish", toggle = true, needs = ModuleOn, why = GATHER_OFF,
          help = "Counts Find Fish as a tracking to remind you of, once you have learned it. Turn off if you only "
              .. "track fish now and then." },
        Settings.Group("Size"),
        { key = "gatherIconSize", label = "Icon Size", slider = { 24, 80, 1 }, needs = ModuleOn, why = GATHER_OFF,
          help = "How big the reminder icon is." },
        Settings.Look("gather", { text = true, size = { 8, 24, 1 }, needs = ModuleOn, why = GATHER_OFF }),
    },
})
