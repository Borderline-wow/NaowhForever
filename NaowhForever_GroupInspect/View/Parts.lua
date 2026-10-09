-- Parts.lua: the pieces Group Inspect's cards, rows and preview share: class and role icons, names, kickers, badges.
local ns = _G.NaowhForever

local T = ns.THEME
local S = ns.QoLSettings
local GI = ns.GroupInspect
local UI = GI.UI
local St = UI.Style
local Parts = ns.Shared.Parts

local TITLE_RGB = St.TIP_TITLE_RGB

function UI.FitName(fs, text, maxW, size, minSize)
    local path = ns.UIFontPath()
    fs:SetWidth(maxW)
    if fs.fitSize ~= size then
        fs.fitSize = size
        fs:SetFont(path, size, "")
    end
    fs:SetText(text)
    local width = fs:GetUnboundedStringWidth()
    while width > maxW and size > minSize do
        size = size - 1
        fs.fitSize = size
        fs:SetFont(path, size, "")
        width = fs:GetUnboundedStringWidth()
    end
    return math.min(width, maxW)
end

function UI.ClassIcon(parent, size)
    local icon = Parts.ItemIcon(parent, size)
    icon.texture:SetTexture(St.CLASS_ICONS)
    return icon
end

function UI.PaintClass(icon, classFile)
    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    icon.texture:SetShown(coords ~= nil)
    if not coords then return end
    Parts.ClassCrop(icon.texture, coords)
end

function UI.RoleIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:Hide()
    return icon
end

function UI.PaintRole(icon, role)
    local atlas = role and St.ROLE_ATLAS[role]
    icon:SetShown(atlas ~= nil)
    if atlas then icon:SetAtlas(atlas) end
    return atlas ~= nil
end

function UI.Kicker(parent, text)
    local kicker = ns.Font(parent, St.KICKER_SIZE, nil, T.accentSoft)
    kicker:SetText(text)
    return kicker
end

local function BadgesOn()
    if ns.FEATURE_BADGES == ns.BADGES_LIVE then return S.Get("badgeChat") == true end
    return S.Default("badgeChat") == true
end

function UI.BadgeOf(guid)
    if not (guid and ns.BadgeOf and BadgesOn()) then return nil end
    return ns.BadgeOf(guid)
end

local function BadgeEnter(badge)
    if GameTooltip:IsForbidden() then return end
    local tier = UI.BadgeOf(badge.holder.guid)
    if not (tier and Parts.Tip(badge, "ANCHOR_TOP")) then return end
    GameTooltip:SetText(tier.tooltipLine or tier.title or "", TITLE_RGB.r, TITLE_RGB.g, TITLE_RGB.b)
    if tier.about then GameTooltip:AddLine(tier.about, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:Show()
end

function UI.Badge(parent, holder)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(St.BADGE, St.BADGE)
    badge.icon = Parts.Smooth(badge:CreateTexture(nil, "ARTWORK"))
    badge.icon:SetAllPoints()
    badge.holder = holder
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", BadgeEnter)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    badge:Hide()
    return badge
end

function UI.PaintBadge(badge, guid)
    local tier = UI.BadgeOf(guid)
    local texture = tier and tier.chat
    badge:SetShown(texture ~= nil)
    if texture then badge.icon:SetTexture(texture) end
    return texture ~= nil
end

local function NameEnter(hit)
    if GameTooltip:IsForbidden() then return end
    local guid = hit.holder.guid
    local rec = guid and GI.Member(guid)
    if not (rec and Parts.Tip(hit, "ANCHOR_TOP")) then return end
    local color = UI.ClassColor(rec.classFile)
    GameTooltip:SetText(rec.name or UI.WAITING, color.r, color.g, color.b)
    GameTooltip:AddLine(UI.LevelText(rec.level, rec.classFile), T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

function UI.NameHit(parent, holder)
    local hit = CreateFrame("Frame", nil, parent)
    hit.holder = holder
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", NameEnter)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    return hit
end
