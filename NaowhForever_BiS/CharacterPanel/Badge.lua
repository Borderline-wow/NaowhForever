-------------------------------------------------------------------------------
--  Badge.lua -- your supporter badge on the character panel, big in the left pane's top
--  corner: Naowh's, a Developer's, a Moderator's or a Legendary Patron's in its own colour
--  with its glow and title (and since when, for a patron). Without one, nothing at all. While
--  ns.FEATURE_BADGES is 0 only the team's badges exist, and the setting's default holds.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local CP = ns.CharacterPanel

local INSET = 10             -- from the left pane's top-left corner
local EMBLEM = 44            -- the badge's art
-- The badge's middle, down from the left pane's top: the BiS List's link lines up on it.
CP.BADGE_MID = INSET + EMBLEM / 2
-- Its glow behind it: a little bigger and faint, a halo round the art, not a second blurred
-- copy over its edges.
local GLOW, GLOW_ALPHA = 1.25, 0.3
-- The badge art is 128px: drawn at a third of that it needs the mipmapped filter to stay sharp.
local FILTER = "TRILINEAR"
-- A drop shadow under the art and the text: the art's own shape in black, a little down and
-- right, so the badge stands off the panel.
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 2, -2, 0.7
local TITLE_SIZE, LINE_SIZE = 15, 11
local TEXT_GAP = 8           -- the title and its line, right of the art
local TIP_GAP = 4            -- the hover card, under the art

local frame, installed

local function BadgeOn()
    local wanted = S.Get("characterPanelBadge")
    if ns.FEATURE_BADGES ~= 1 then wanted = S.Default("characterPanelBadge") end
    if not (CP.On() and wanted == true) then return false end
    return ns.BadgeOf(UnitGUID("player")) ~= nil
end

local function Paint()
    local tier, entry = ns.BadgeOf(UnitGUID("player"))
    if not tier then
        frame:Hide()
        return
    end
    local c = tier.color
    frame.emblem:SetTexture(tier.large, nil, nil, FILTER)
    frame.shadow:SetTexture(tier.large, nil, nil, FILTER)
    frame.glow:SetTexture(tier.large, nil, nil, FILTER)
    frame.glow:SetVertexColor(c.r, c.g, c.b, GLOW_ALPHA)
    frame.title:SetText(type(entry) == "table" and entry.title or tier.title)
    -- A patron's since when; the team's badges say whose they are.
    frame.line:SetText(ns.BadgeSince(entry) or (tier == ns.BADGE_TIERS.legendary and "Naowh Forever"
        or "Naowh Forever Team"))
    frame.title:SetTextColor(c.r, c.g, c.b)
    -- As wide as what it shows, so it takes the mouse where you see it.
    local text = math.max(frame.title:GetStringWidth(), frame.line:GetStringWidth())
    frame:SetWidth(EMBLEM + TEXT_GAP + math.ceil(text))
end

local function Enter(self)
    -- The card under the art, where you are looking, not off the frame's far edge.
    if not ns.Shared.Parts.Tip(self, "ANCHOR_NONE") then return end
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", self.emblem, "BOTTOMLEFT", 0, -TIP_GAP)
    local tier = ns.BadgeOf(UnitGUID("player"))
    if not tier then return GameTooltip:Hide() end
    local c = tier.color
    GameTooltip:SetText(tier.label or ("Naowh Forever " .. tier.title), c.r, c.g, c.b)
    GameTooltip:AddLine(tier.about, T.fg.r, T.fg.g, T.fg.b, true)
    GameTooltip:Show()
end

local function Build()
    local left = CharacterFrame.LeftPaneHost
    frame = CreateFrame("Button", nil, left)
    frame:SetPoint("TOPLEFT", INSET, -INSET)
    frame:SetSize(EMBLEM + 150, EMBLEM)
    frame:SetFrameLevel(left:GetFrameLevel() + 60)   -- over the model, which sits at 50
    frame.glow = frame:CreateTexture(nil, "BACKGROUND")
    frame.glow:SetSize(EMBLEM * GLOW, EMBLEM * GLOW)
    frame.glow:SetPoint("CENTER", frame, "LEFT", EMBLEM / 2, 0)
    frame.glow:SetBlendMode("ADD")
    frame.emblem = frame:CreateTexture(nil, "ARTWORK")
    frame.emblem:SetSize(EMBLEM, EMBLEM)
    frame.emblem:SetPoint("LEFT")
    frame.shadow = frame:CreateTexture(nil, "BORDER")
    frame.shadow:SetSize(EMBLEM, EMBLEM)
    frame.shadow:SetPoint("CENTER", frame.emblem, "CENTER", SHADOW_X, SHADOW_Y)
    frame.shadow:SetVertexColor(0, 0, 0, SHADOW_ALPHA)
    frame.title = ns.Font(frame, TITLE_SIZE)
    frame.title:SetPoint("BOTTOMLEFT", frame.emblem, "RIGHT", TEXT_GAP, 1)
    frame.line = ns.Font(frame, LINE_SIZE, nil, T.muted)
    frame.line:SetPoint("TOPLEFT", frame.emblem, "RIGHT", TEXT_GAP, -2)
    for _, text in ipairs({ frame.title, frame.line }) do
        text:SetShadowColor(0, 0, 0, 0.8)
        text:SetShadowOffset(1, -1)
    end
    frame:SetScript("OnEnter", Enter)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    frame:SetScript("OnShow", Paint)
    CP.supportBadge = frame
end

local function Apply()
    local on = BadgeOn()
    if on and not installed and CharacterFrame then
        installed = true
        Build()
        CharacterFrame.LeftPaneHost:HookScript("OnShow", Apply)
    end
    if not installed then return end
    frame:SetShown(on)
    if on and frame:IsVisible() then Paint() end
end

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
