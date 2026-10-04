-------------------------------------------------------------------------------
--  View/Toast.lua -- Drop Alert's on-screen alert (ns.BiS.Toast), drawn the same way live and
--  in its settings preview: the item's icon, your star where you put it (on the icon's
--  corner, before the name, or hidden), the name in its quality's colour, and a line of what
--  you pick: what happened, your rank, the slot, where it drops, how much stronger it makes
--  you. Its border (none, black, the item's quality, BiS orange), background, size and glow
--  are yours too. Live ones stack under a holder you move in Unlock Mode, each fading after a
--  while; nothing is made before the first.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local B = ns.BiS
local S = B.Settings
local Shared = ns.Shared
local Items, Parts, St = Shared.Items, Shared.Parts, Shared.Style

local Toast = {}
B.Toast = Toast

local W, H, ICON, PAD, STAR = 300, 54, 38, 8, 16
local STAR_LIFT = 5   -- frame levels the star sits above the icon, over its badge (+3) too
local STACK_GAP = 6
local MAX_SHOWN = 3
local FADE = 0.3
local BLACK = { r = 0, g = 0, b = 0 }
local DOT = "  \194\183  "

-- What happened, in its own colour.
local EVENTS = {
    roll = { "Up for a roll", T.accentSoft }, dropped = { "Dropped", T.fg }, yours = { "Yours!", St.HAVE_RGB },
}
Toast.EVENTS = EVENTS
local RANK_WORDS = { "Your BiS", "Your second pick" }

-------------------------------------------------------------------------------
--  One alert
-------------------------------------------------------------------------------
---@return Frame toast
function Toast.New(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(W, H)
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.glow:SetPoint("TOPLEFT", -3, 3)
    f.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    f.bg = ns.Solid(f, "BACKGROUND", T.bg, 1)
    f.bg:SetAllPoints()
    f.edge = ns.Border(f, BLACK)
    local icon = Parts.ItemIcon(f, ICON)
    icon:SetPoint("LEFT", PAD, 0)
    f.iconFrame, f.icon = icon, icon.texture
    -- The icon is a frame of its own, so a texture on the alert would sit under it: the star
    -- is drawn on a frame above the icon and its corner badge.
    f.overlay = CreateFrame("Frame", nil, f)
    f.overlay:SetAllPoints()
    f.overlay:SetFrameLevel(icon:GetFrameLevel() + STAR_LIFT)
    f.star = f.overlay:CreateTexture(nil, "OVERLAY")
    f.star:SetTexture(St.STAR)
    f.star:SetSize(STAR, STAR)
    f.name = ns.Font(f, 13)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.detail = ns.Font(f, 11, nil, T.muted)
    f.detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", PAD, 2)
    f.detail:SetPoint("RIGHT", -PAD, 0)
    f.detail:SetJustifyH("LEFT")
    f.detail:SetWordWrap(false)
    return f
end

-- How much stronger it makes you, for your list's spec; nil where it is no gain.
local function Gain(id, slot)
    local SW, spec = ns.StatWeights, B.Lists.CurrentSpec()
    local weights = SW and spec and SW.For(spec.key)
    if not (weights and slot) then return nil end
    local gain = SW.Gain(id, slot, weights, SW.Power(weights))
    return gain and gain >= 0.5 and gain or nil
end

-- The line under the name, from the parts you show.
local function Detail(id, rank, event, slot)
    local parts = {}
    if S.Get("bisToastEvent") then
        local what = EVENTS[event]
        parts[#parts + 1] = ns.Color(what[2], what[1])
    end
    if S.Get("bisToastRank") then
        parts[#parts + 1] = ns.Color(Parts.RankColor(rank), RANK_WORDS[rank] or ("Your #%d pick"):format(rank))
    end
    if S.Get("bisToastSlot") and slot then parts[#parts + 1] = ns.L(Items.SLOT_NAME[slot]) end
    if S.Get("bisToastSource") then
        local source = ns.BiSSource(id)
        if source then parts[#parts + 1] = Parts.Plain(source) end
    end
    local gain = S.Get("bisToastGain") and Gain(id, slot)
    if gain then parts[#parts + 1] = St.UPGRADE_CODE .. "+" .. math.floor(gain + 0.5) .. "%|r" end
    return table.concat(parts, DOT)
end

local function BorderColor(id, rank)
    local border = S.Get("bisToastBorder")
    if border == "quality" then return Items.QualityColor(id) or BLACK end
    if border == "rank" then return Parts.RankColor(rank) end
    if border == "black" then return BLACK end
    return nil
end

--- Paints the alert for an item (an ID or a link) by your choices.
---@param event "roll"|"dropped"|"yours"
function Toast.Paint(f, item, rank, event)
    local id = Items.IDFrom(item)
    local slot = B.Lists.SlotOf(id)
    f:SetScale(S.Get("bisToastScale"))
    f.bg:SetAlpha(S.Get("bisToastAlpha"))
    local border = BorderColor(id, rank) or BLACK
    f.edge:SetColor(border.r, border.g, border.b, S.Get("bisToastBorder") == "none" and 0 or 1)
    local glow = S.Get("bisToastGlow") and Parts.RankColor(rank)
    f.glow:SetShown(glow ~= nil and glow ~= false)
    if glow then f.glow:SetVertexColor(glow.r, glow.g, glow.b, 0.35) end
    f.icon:SetTexture(C_Item.GetItemIconByID(id))
    Parts.MarkForever(f.iconFrame, id)
    local place = S.Get("bisToastStar")
    local color = Parts.RankColor(rank)
    f.star:SetVertexColor(color.r, color.g, color.b)
    f.star:SetShown(place ~= "none")
    f.star:ClearAllPoints()
    f.name:ClearAllPoints()
    if place == "name" then
        f.star:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", PAD, 0)
        f.name:SetPoint("LEFT", f.star, "RIGHT", 4, 0)
    else
        if place == "iconRight" then
            f.star:SetPoint("CENTER", f.iconFrame, "TOPRIGHT", -2, -2)
        else
            f.star:SetPoint("CENTER", f.iconFrame, "TOPLEFT", 2, -2)
        end
        f.name:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", PAD, -2)
    end
    f.name:SetPoint("RIGHT", -PAD, 0)
    f.name:SetText(Items.QualityHex(id) .. Items.Name(id) .. "|r")
    f.detail:SetText(Detail(id, rank, event, slot))
end

-------------------------------------------------------------------------------
--  Live: a stack under the holder, each fading out
-------------------------------------------------------------------------------
local holder, shown, pool = nil, {}, {}

local function Place()
    local pos = S.Get("bisToastPos")
    holder:ClearAllPoints()
    if pos then
        holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        holder:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    holder:SetScale(S.Get("bisToastScale"))
end

local function Restack()
    for i, f in ipairs(shown) do
        f:ClearAllPoints()
        f:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * (H + STACK_GAP))
    end
end

local function Release(f)
    f:Hide()
    for i, other in ipairs(shown) do
        if other == f then table.remove(shown, i) break end
    end
    pool[#pool + 1] = f
    Restack()
end

local function Finished(group)
    Release(group:GetParent())
end

local function NewLive()
    local f = Toast.New(holder)
    f:SetScale(1)   -- the holder carries the size
    f.fade = f:CreateAnimationGroup()
    local fadeIn = f.fade:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(FADE)
    fadeIn:SetOrder(1)
    f.fadeOut = f.fade:CreateAnimation("Alpha")
    f.fadeOut:SetFromAlpha(1)
    f.fadeOut:SetToAlpha(0)
    f.fadeOut:SetDuration(FADE)
    f.fadeOut:SetOrder(2)
    f.fade:SetScript("OnFinished", Finished)
    return f
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "NaowhForeverBiSDropAlert", UIParent)
    holder:SetSize(W, H)
    holder:SetFrameStrata("HIGH")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder.mover = ns.UI.AttachMover(holder, "BiS Drop Alert", function(pos) S.Set("bisToastPos", pos) end,
        "BiS List/Settings")
    return holder
end

--- Shows the alert for an item; the oldest goes when more than a few are up.
function Toast.Show(item, rank, event)
    Holder()
    Place()
    local f = table.remove(pool) or NewLive()
    if #shown >= MAX_SHOWN then shown[1].fade:Stop(); Release(shown[1]) end
    Toast.Paint(f, item, rank, event)
    f:SetScale(1)
    shown[#shown + 1] = f
    Restack()
    f.fadeOut:SetStartDelay(S.Get("bisToastTime"))
    f:Show()
    f.fade:Stop()
    f.fade:Play()
end

-- Unlock Mode: the holder with a sample to drag, while Drop Alert and its alert are on.
local function Unlock(on)
    if not (on and B.On() and S.Get("bisLootAlert") and S.Get("bisToast")) then
        if holder then holder.mover:Hide() end
        return
    end
    Holder()
    Place()
    holder.mover:Show()
end

hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function() Unlock(true) end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function() Unlock(false) end)
