-------------------------------------------------------------------------------
--  NaowhForever_TalentPoints.lua -- the QoL unspent talent points reminder: text on screen
--  while you have talent points to spend. Hidden in combat.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local GOLD = { r = 1, g = 0.82, b = 0 }
local WIDTH, ROOM = 300, 10   -- the frame's width, and its height over the font size

local frame, unlocked, inCombat

local function On()
    return S.Get("enabled") and S.Get("talentPoints")
end

local function Show(points)
    frame.text:SetText(points == 1 and "1 Unspent Talent Point" or ("%d Unspent Talent Points"):format(points))
    -- Fitted to the text only with a background, so elements anchored to it keep their spot.
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Update()
    if unlocked then
        Show(2)
        return
    end
    local unspent, classPoints, specPoints = C_ClassTalents.HasUnspentTalentPoints()
    if unspent and not inCombat then
        Show(classPoints + specPoints)
    else
        frame:Hide()
    end
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
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverTalentPoints", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.text = ns.Font(frame, 22, "OUTLINE")
        frame.text:SetPoint("CENTER")
        frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
        ns.AlertStack(frame, 2)
    end
    local size = S.Get("talentPointsFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("talentPointsBackground"))
    Parts.HudFont(frame.text, S.Get("talentPointsFont"), size, S.Get("talentPointsOutline"), frame.mode)
    local c = S.Get("talentPointsTheme") and T.accent or GOLD
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame:SetSize(WIDTH, size + ROOM)
    inCombat = UnitAffectingCombat("player")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("TRAIT_CONFIG_UPDATED")
    events:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^talentPoints") then Apply() end
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

local Settings = ns.Shared.Settings

Settings.Page("QoL/Questing & Group", S):Card({
    id = "talentPoints", name = "Talent Points", order = 30, switch = "talentPoints",
    help = "Text on screen while you have talent points to spend. Hidden in combat. Move it with "
        .. "Move Elements.",
    rows = {
        Settings.Look("talentPoints", { text = true, size = { 10, 48, 1 }, background = "card" }),
        Settings.Group("Colours"),
        { key = "talentPointsTheme", label = "Apply Theme to Text Colour", toggle = true,
          help = "The text in the theme's accent colour instead of gold." },
    },
})
