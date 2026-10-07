-------------------------------------------------------------------------------
--  NaowhForever_GroupButtons.lua -- Group Tools on screen: Invite and Disband buttons that move
--  together in Unlock Mode, stacked or side by side.
--
--  Invite is a secure button running the game's own /invite, which invites your target; run
--  from it, the game's code reads the target's name, so it works in combat. Disband removes
--  everyone through addon code (QoL's Disband Group), which the game allows only out of combat.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local S = ns.QoLSettings
local Parts = ns.Shared.Parts

local GAP, FILL_ALPHA = 4, 0.9
local BLACK = { r = 0, g = 0, b = 0 }

local bar, moving, pending
local events = CreateFrame("Frame")

local function Enter(button)
    button.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.label:GetText(), 1, 1, 1)
    GameTooltip:AddLine(button.tip, T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

local function Leave(button)
    button.border:SetColor(BLACK.r, BLACK.g, BLACK.b, 1)
    GameTooltip:Hide()
end

-- The house button look, on a button that may be secure.
local function Style(button, text, tip)
    button.backdrop = Parts.HudBackdrop(button, { color = T.panel, alpha = FILL_ALPHA })
    button.border = button.backdrop.border
    button.label = ns.Font(button, 12)
    button.label:SetPoint("CENTER")
    button.label:SetText(text)
    button.tip = tip
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
end

local function Build()
    bar = CreateFrame("Frame", "NaowhForeverGroupButtons", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar.invite = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    bar.invite:RegisterForClicks("AnyUp", "AnyDown")
    bar.invite:SetAttribute("type1", "macro")
    bar.invite:SetAttribute("macrotext1", "/invite")
    Style(bar.invite, "Invite", "Invites your target. Works in combat.")
    bar.disband = CreateFrame("Button", nil, bar)
    bar.disband:SetScript("OnClick", function()
        if InCombatLockdown() then
            ns.Print("The group can be disbanded once the fight is over.")
            return
        end
        ns.DisbandGroup()
    end)
    Style(bar.disband, "Disband", "Removes everyone from your group. Group leader only, out of combat.")
    bar.mover = UI.AttachMover(bar, "Group Buttons", function(pos) S.Set("groupButtonsPos", pos) end,
        "QoL/Questing & Group", "QoL/Questing & Group:groupButtons")
end

-- The Invite button is secure, so the bar is built, shown, hidden and laid out out of combat.
local function Apply()
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = false
    if not (S.Get("enabled") and S.Get("groupButtons")) then
        if bar then bar:Hide() end
        return
    end
    if not bar then Build() end
    local w, h = S.Get("groupButtonsWidth"), S.Get("groupButtonsHeight")
    local font, size, outline = S.Get("groupButtonsFont"), S.Get("groupButtonsFontSize"), S.Get("groupButtonsOutline")
    local background = S.Get("groupButtonsBackground")
    for _, button in ipairs({ bar.invite, bar.disband }) do
        button:SetSize(w, h)
        button.backdrop:SetMode(background)
        Parts.HudFont(button.label, font, size, outline, background)
    end
    local stacked = S.Get("groupButtonsLayout") ~= "row"
    if stacked then
        bar:SetSize(w, h * 2 + GAP)
    else
        bar:SetSize(w * 2 + GAP, h)
    end
    bar.invite:ClearAllPoints()
    bar.invite:SetPoint("TOPLEFT")
    bar.disband:ClearAllPoints()
    if stacked then
        bar.disband:SetPoint("TOPLEFT", bar.invite, "BOTTOMLEFT", 0, -GAP)
    else
        bar.disband:SetPoint("TOPLEFT", bar.invite, "TOPRIGHT", GAP, 0)
    end
    bar:ClearAllPoints()
    local pos = S.Get("groupButtonsPos")
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
    bar.mover:SetShown(moving == true)
    bar:Show()
end

events:SetScript("OnEvent", function()
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if pending then Apply() end
end)
hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^groupButtons") and key ~= "groupButtonsPos" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function() moving = true; Apply() end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function() moving = false; Apply() end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local LAYOUT = { { stacked = "Stacked", row = "Side by Side" }, { "stacked", "row" } }

local function Disband()
    ns.DisbandGroup()
end

local function Invite()
    ns.PromptText("Invite which player?", "", 0, function(name) C_PartyInfo.InviteUnit(name) end)
end

local function LayoutSummary(store)
    return store.Get("groupButtonsLayout") == "row" and "Side by Side" or "Invite over Disband"
end

Settings.Page("QoL/Questing & Group", S):Card({
    id = "groupButtons", name = "On-Screen Buttons", order = 20, switch = "groupButtons",
    help = "Invite and Disband as buttons on your screen, to click without opening /nf. Invite "
        .. "invites your target and works in combat; Disband works out of combat. Move them "
        .. "with Move Elements.",
    summary = LayoutSummary,
    rows = {
        { key = "groupButtonsLayout", label = "Button Layout", choice = LAYOUT,
          help = "Invite over Disband, or side by side." },
        { label = "Disband Group", button = Disband, buttonText = "Disband", always = true,
          help = "Removes everyone from your group. Group leader only." },
        { label = "Invite Player", button = Invite, buttonText = "Invite", always = true,
          help = "Type a name and invite them. Handy when you play with the same people." },
        Settings.Group("Size"),
        { key = "groupButtonsWidth", label = "Button Width", slider = { 60, 200, 1 } },
        { key = "groupButtonsHeight", label = "Button Height", slider = { 16, 48, 1 } },
        Settings.Look("groupButtons", { text = true, size = { 8, 24, 1 }, background = "card" }),
    },
})
