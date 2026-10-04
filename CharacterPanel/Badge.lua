-------------------------------------------------------------------------------
--  Badge.lua -- your supporter badge on the character panel, big in the left pane's top
--  corner: Naowh's, a Developer's, a Moderator's or a Legendary Patron's in its own colour
--  with its glow and title (and since when, for a patron). Without one, nothing, unless
--  Legendary Badge Preview (off by default) shows the Legendary badge in grey: click it for
--  what it is and where it shows, with more on Naowh's Discord. It informs and asks for
--  nothing (Blizzard's add-on policy keeps donation requests out of the game).
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
local GREY_ALPHA = 0.55      -- the badge you have not got yet
local TEXT_GAP = 8           -- the title and its line, right of the art
local TIP_GAP = 4            -- the hover card, under the art
-- The card for the badge you have not got: what it is, where it shows, how it looks on a name,
-- and Naowh's Discord for more.
local CARD_W, CARD_H, PAD = 480, 352, 20
local CARD_EMBLEM = 64
-- Who wears it, and who sees it: only players with the addon see a badge.
local PITCH = "Worn by our Legendary supporters, and seen by the whole Naowh Forever community."
-- Where the badge shows, each as the Badges module shows it.
-- One line each: the card is as wide as it is.
local PERKS = {
    "Your badge next to your name in chat",
    "A card with your title and support date on hover",
    "A plate over your player tooltip",
    "A banner when you join someone's group",
    "Your badge on your character panel",
}
local PERK_H = 20
local SAMPLE = "Ready for Deadmines?"
-- The sample's speaker: a name and a class colour of our own, not yours. Without brackets: a
-- Global Font can draw chat's brackets round.
local SAMPLE_NAME, SAMPLE_CLASS = "Dieman", "WARRIOR"
-- The badge in the sample, this far up from the line's middle: chat's markup drops it 1px for
-- the game's chat font, which left it low on the card's line (seen in game, 4 Oct 2026).
local SAMPLE_BADGE_Y = 1
local ALREADY = "Have the badge? My Badge Code gives you a code to send us on Discord."

local frame, installed

local function BadgeOn()
    if not (CP.On() and S.Get("characterPanelBadge") == true) then return false end
    return S.Get("characterPanelBadgeAsk") == true or ns.BadgeOf(UnitGUID("player")) ~= nil
end

-- How a name reads in chat with the badge: the name in its class's colour, the badge after it,
-- as the Badges module writes it. Hover it for the card people see.
local function Sample(tier)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[SAMPLE_CLASS]
    local named = color and ("|c%s%s|r"):format(color.colorStr, SAMPLE_NAME) or SAMPLE_NAME
    local badge = ("|T%s:0:0:0:%d|t"):format(tier.chat, SAMPLE_BADGE_Y)
    return ("%s %s: %s"):format(named, badge, SAMPLE)
end

local function SampleEnter()
    ns.ShowBadgeCard("legendary", SAMPLE_NAME)
end

local function ShowPitch()
    local UI = ns.UI
    local tier = ns.BADGE_TIERS.legendary
    local c = tier.color
    local dimmer, panel = ns.MakeModal(CARD_W, CARD_H, "badgePitch")
    local strip = UI.Keep(panel, "strip", function(p) return ns.Solid(p, "OVERLAY", c, 1) end)
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    -- The emblem in full colour, the way it looks once yours, its glow behind it.
    local glow = UI.Keep(panel, "glow", function(p)
        local g = p:CreateTexture(nil, "ARTWORK")
        g:SetBlendMode("ADD")
        return g
    end)
    glow:SetSize(CARD_EMBLEM * GLOW, CARD_EMBLEM * GLOW)
    glow:SetTexture(tier.large, nil, nil, FILTER)
    glow:SetVertexColor(c.r, c.g, c.b, GLOW_ALPHA)
    local art = UI.Keep(panel, "art", function(p) return p:CreateTexture(nil, "OVERLAY") end)
    art:SetSize(CARD_EMBLEM, CARD_EMBLEM)
    art:SetPoint("TOPLEFT", PAD, -PAD - 4)
    art:SetTexture(tier.large, nil, nil, FILTER)
    glow:SetPoint("CENTER", art)
    local head = UI.KeepFont(panel, "head", 18, "OUTLINE", c)
    head:SetPoint("TOPLEFT", art, "TOPRIGHT", 14, -2)
    head:SetText("The Legendary Badge")
    local pitch = UI.KeepFont(panel, "pitch", 12, nil, T.fg)
    pitch:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    pitch:SetWidth(CARD_W - PAD * 2 - CARD_EMBLEM - 14)
    pitch:SetJustifyH("LEFT")
    pitch:SetText(PITCH)
    -- What you get: one line each, the chat badge as its mark.
    local gets = UI.KeepFont(panel, "gets", 10, nil, T.accentSoft)
    gets:SetPoint("TOPLEFT", PAD, -(PAD + CARD_EMBLEM + 24))
    gets:SetText("WHERE IT SHOWS")
    local mark = ("|T%s:14:14|t  "):format(tier.chat)
    for i, perk in ipairs(PERKS) do
        local line = UI.KeepFont(panel, "perk" .. i, 12, nil, T.fg)
        line:SetPoint("TOPLEFT", gets, "BOTTOMLEFT", 0, -6 - (i - 1) * PERK_H)
        line:SetWidth(CARD_W - PAD * 2)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:SetText(mark .. perk)
    end
    -- How it looks: a chat line with your name wearing it.
    local looks = UI.KeepFont(panel, "looks", 10, nil, T.accentSoft)
    looks:SetPoint("TOPLEFT", gets, "BOTTOMLEFT", 0, -14 - #PERKS * PERK_H)
    looks:SetText("HOW IT LOOKS")
    local box = UI.Keep(panel, "sampleBox", function(p)
        local f = CreateFrame("Frame", nil, p)
        ns.Solid(f, "BACKGROUND", T.bg, 1):SetAllPoints()
        ns.Border(f, ns.Shared.Style.BORDER_RGB)
        f:EnableMouse(true)
        f:SetScript("OnEnter", SampleEnter)
        f:SetScript("OnLeave", ns.HideBadgeCard)
        return f
    end)
    box:SetPoint("TOPLEFT", looks, "BOTTOMLEFT", 0, -6)
    box:SetSize(CARD_W - PAD * 2, 28)
    -- In the game's chat font, so it reads as the chat line it will be.
    local sample = UI.KeepFont(box, "sample", 13, nil, T.fg)
    sample:SetFontObject(ChatFontNormal)
    sample:SetTextColor(1, 1, 1)
    sample:SetPoint("LEFT", 10, 0)
    sample:SetText(Sample(tier))
    local already = UI.KeepFont(panel, "already", 10, nil, T.muted)
    already:SetPoint("BOTTOMLEFT", PAD, 14 + 26 + 8)
    already:SetText(ALREADY)
    -- More on Discord, its link to copy (the game opens no browser), or your badge code.
    local more = UI.KeepButton(panel, "more", "More Info on Discord", 170, 26, function()
        dimmer:Hide()
        ns.ShowCopyLine("Naowh's Discord", ns.NAOWH_DISCORD, tier.large)
    end)
    more:SetPoint("BOTTOMLEFT", PAD, 14)
    UI.KeepButton(panel, "code", "My Badge Code", 120, 26, function()
        dimmer:Hide()
        ns.ShowBadgeCode()
    end):SetPoint("LEFT", more, "RIGHT", 8, 0)
    UI.KeepButton(panel, "close", "Close", 96, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOMRIGHT", -PAD, 14)
    dimmer:Show()
end

local function Paint()
    local tier, entry = ns.BadgeOf(UnitGUID("player"))
    frame.has = tier ~= nil
    local shown = tier or ns.BADGE_TIERS.legendary
    local c = tier and shown.color or T.muted
    frame.emblem:SetTexture(shown.large, nil, nil, FILTER)
    frame.shadow:SetTexture(shown.large, nil, nil, FILTER)
    frame.shadow:SetAlpha(tier and 1 or GREY_ALPHA)
    frame.glow:SetTexture(shown.large, nil, nil, FILTER)
    frame.emblem:SetDesaturated(not tier)
    frame.emblem:SetAlpha(tier and 1 or GREY_ALPHA)
    frame.glow:SetShown(tier ~= nil)
    if tier then
        local glow = shown.color
        frame.glow:SetVertexColor(glow.r, glow.g, glow.b, GLOW_ALPHA)
        frame.title:SetText(type(entry) == "table" and entry.title or shown.title)
        -- A patron's since when; the team's badges say whose they are.
        frame.line:SetText(ns.BadgeSince(entry) or (tier == ns.BADGE_TIERS.legendary and "Naowh Forever"
            or "Naowh Forever Team"))
        frame.line:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
    else
        frame.title:SetText("Legendary Badge")
        frame.line:SetText("Learn more")
        local o = shown.color
        frame.line:SetTextColor(o.r, o.g, o.b)
    end
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
    local shown = tier or ns.BADGE_TIERS.legendary
    local c = shown.color
    GameTooltip:SetText(shown.label or ("Naowh Forever " .. shown.title), c.r, c.g, c.b)
    GameTooltip:AddLine(shown.about, T.fg.r, T.fg.g, T.fg.b, true)
    if not tier then
        GameTooltip:AddLine("Click for more.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    end
    GameTooltip:Show()
end

local function Clicked(self)
    if not self.has then ShowPitch() end
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
    frame:SetScript("OnClick", Clicked)
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
