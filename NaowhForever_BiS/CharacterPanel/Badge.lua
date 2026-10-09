-- Badge.lua: the supporter badge plate: the badge's art, its title and line, and its hover card (CP.BadgePlate).
local ns = _G.NaowhForever

local T = ns.THEME
local CP = ns.CharacterPanel
local C = CP.C

local EMBLEM = C.EMBLEM
local PLATE_TEXT_W = 150
local GLOW, GLOW_ALPHA = 1.25, 0.3
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 2, -2, 0.7
local SHADOW_RGB = C.BLACK_RGB
local TITLE_SIZE, LINE_SIZE = 15, 11
local TEXT_GAP = 8
local TITLE_LIFT, LINE_DROP = 1, 2
local TIP_GAP = 4
local TEXT_FOREVER = "Naowh Forever"
local TEXT_TEAM = "Naowh Forever Team"
local TEXT_TIER = "Naowh Forever "

local function Enter(self)
    if not ns.Shared.Parts.Tip(self, "ANCHOR_NONE") then return end
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", self.emblem, "BOTTOMLEFT", 0, -TIP_GAP)
    local tier = ns.BadgeOf(self.guid)
    if not tier then return GameTooltip:Hide() end
    local c = tier.color
    if self.compact then
        GameTooltip:SetText(self.title:GetText(), c.r, c.g, c.b)
        GameTooltip:AddLine(self.line:GetText(), T.muted.r, T.muted.g, T.muted.b)
    else
        GameTooltip:SetText(tier.label or (TEXT_TIER .. tier.title), c.r, c.g, c.b)
    end
    GameTooltip:AddLine(tier.about, T.fg.r, T.fg.g, T.fg.b, true)
    GameTooltip:Show()
end

local function TextShadow(text)
    text:SetShadowColor(SHADOW_RGB.r, SHADOW_RGB.g, SHADOW_RGB.b, C.SHADOW_ALPHA)
    text:SetShadowOffset(C.SHADOW_X, -C.SHADOW_X)
end

local function Art(frame)
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
    frame.shadow:SetVertexColor(SHADOW_RGB.r, SHADOW_RGB.g, SHADOW_RGB.b, SHADOW_ALPHA)
end

CP.BADGE_MID = C.BADGE_INSET + EMBLEM / 2
CP.BADGE_INSET = C.BADGE_INSET

function CP.PaintBadgePlate(frame, guid)
    frame.guid = guid
    local tier, entry = ns.BadgeOf(guid)
    if not tier then
        frame:Hide()
        return false
    end
    local c = tier.color
    frame.emblem:SetTexture(tier.large, nil, nil, C.FILTER)
    frame.shadow:SetTexture(tier.large, nil, nil, C.FILTER)
    frame.glow:SetTexture(tier.large, nil, nil, C.FILTER)
    frame.glow:SetVertexColor(c.r, c.g, c.b, GLOW_ALPHA)
    frame.title:SetText(type(entry) == "table" and entry.title or tier.title)
    frame.line:SetText(ns.BadgeSince(entry) or (tier == ns.BADGE_TIERS.legendary and TEXT_FOREVER or TEXT_TEAM))
    frame.title:SetTextColor(c.r, c.g, c.b)
    if frame.compact then
        frame:SetWidth(EMBLEM)
        return true
    end
    local text = math.max(frame.title:GetStringWidth(), frame.line:GetStringWidth())
    frame:SetWidth(EMBLEM + TEXT_GAP + math.ceil(text))
    return true
end

function CP.BadgePlate(parent, compact)
    local frame = CreateFrame("Button", nil, parent)
    frame.compact = compact
    frame:SetSize(compact and EMBLEM or EMBLEM + PLATE_TEXT_W, EMBLEM)
    Art(frame)
    frame.title = ns.Font(frame, TITLE_SIZE)
    frame.title:SetPoint("BOTTOMLEFT", frame.emblem, "RIGHT", TEXT_GAP, TITLE_LIFT)
    frame.line = ns.Font(frame, LINE_SIZE, nil, T.muted)
    frame.line:SetPoint("TOPLEFT", frame.emblem, "RIGHT", TEXT_GAP, -LINE_DROP)
    TextShadow(frame.title)
    TextShadow(frame.line)
    frame.title:SetShown(not compact)
    frame.line:SetShown(not compact)
    frame:SetScript("OnEnter", Enter)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    return frame
end
