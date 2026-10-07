-------------------------------------------------------------------------------
--  NaowhForever_Durability.lua -- the QoL low durability warning, shading from pink to red as
--  your gear wears down.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local PINK = { r = 1, g = 0.41, b = 0.71 }
local RED = { r = 1, g = 0, b = 0 }
local FLOOR_PCT = 15    -- fully red at or below this
local WIDTH, ROOM = 300, 10   -- the frame's width, and its height over the font size

local frame, unlocked, inCombat

local function On()
    return S.Get("enabled") and S.Get("durability")
end

local function Lowest()
    local lowest
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return lowest
end

local function Show(pct, threshold)
    local t = math.max(0, math.min(1, (pct - FLOOR_PCT) / math.max(1, threshold - FLOOR_PCT)))
    local top = S.Get("durabilityTheme") and T.accent or PINK
    frame.text:SetTextColor(RED.r + t * (top.r - RED.r), RED.g + t * (top.g - RED.g),
        RED.b + t * (top.b - RED.b), 1)
    frame.text:SetText(("Low Durability: %d%%"):format(pct))
    -- Fitted to the text only with a background, so elements anchored to it keep their spot.
    frame:SetWidth(frame.mode == "none" and WIDTH or frame.text:GetStringWidth() + 2 * St.CARD_PAD)
    frame:Show()
end

local function Update()
    local threshold = S.Get("durabilityBelow")
    if unlocked then
        Show(20, threshold)
        return
    end
    local lowest = not inCombat and Lowest()
    if lowest and lowest < threshold then
        Show(math.floor(lowest), threshold)
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
        frame = CreateFrame("Frame", "NaowhForeverDurability", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.text = ns.Font(frame, 22, "OUTLINE")
        frame.text:SetPoint("CENTER")
        frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
        ns.AlertStack(frame, 3)
    end
    local size = S.Get("durabilityFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("durabilityBackground"))
    Parts.HudFont(frame.text, S.Get("durabilityFont"), size, S.Get("durabilityOutline"), frame.mode)
    frame:SetSize(WIDTH, size + ROOM)
    inCombat = UnitAffectingCombat("player")
    events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^durability") then Apply() end
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

local function DurabilitySummary(store)
    return ("Warns below %d%%"):format(store.Get("durabilityBelow"))
end

local Settings = ns.Shared.Settings

Settings.Page("QoL/Loot & Items", S):Card({
    id = "durability", name = "Durability", order = 80, switch = "durability",
    help = "Text on screen when any piece of gear drops below the threshold. Hidden in "
        .. "combat. Move it with Move Elements.",
    summary = DurabilitySummary,
    rows = {
        { key = "durabilityBelow", label = "Warn Below", slider = { 5, 100, 1 }, unit = "%" },
        Settings.Look("durability", { text = true, size = { 10, 48, 1 }, background = "card" }),
        Settings.Group("Colours"),
        { key = "durabilityTheme", label = "Apply Theme to Text Colour", toggle = true,
          help = "Shades from the theme's accent colour to red instead of from pink." },
    },
})
