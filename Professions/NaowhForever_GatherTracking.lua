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

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(button, { r = 0, g = 0, b = 0 })
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.15)

    button.label = ns.Font(button, 13, "OUTLINE", T.accentSoft)
    button.label:SetPoint("TOP", button, "BOTTOM", 0, -4)

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

    button.mover = UI.AttachMover(button, "Tracking", function(pos) S.Set("gatherPos", pos) end)
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
    button.icon:SetTexture(C_Spell.GetSpellTexture(shown.spell))
    local labels = {}
    for _, t in ipairs(#known > 0 and known or { TRACKINGS[1], TRACKINGS[2] }) do
        labels[#labels + 1] = t.label
    end
    button.label:SetText("Track " .. table.concat(labels, " / "))
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
