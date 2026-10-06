-------------------------------------------------------------------------------
--  View/Bags.lua -- the marks every slot of ours has (Shared.Parts.ItemMarks), on the items in
--  your bags: an item's level in the bottom-right, your BiS's star in the bottom-left,
--  Forever's mark in the top-left, and the green upgrade arrow in the top-right on gear better
--  than what you wear by your spec's stat weights (the gear tooltip's "+N% upgrade", BiS or
--  not). In the game's bags, or in EllesmereUI's (its bags, reagent bag and bank) through the
--  hook it offers other addons for their marks.
--
--  Ours is a frame over each bag button, kept in our own table (nothing stored on theirs), and
--  painted after the bag paints the slot. Off, nothing is hooked or made; turned off after
--  being on, ours hide and EllesmereUI's hook is let go. Item levels show on gear only.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local B = ns.BiS
local Shared = ns.Shared
local Items, Parts, Bags = Shared.Items, Shared.Parts, Shared.Bags
local SW = ns.StatWeights

local GetContainerItemID = C_Container.GetContainerItemID
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local GetTime = GetTime

local OVERLAY = "NaowhForever"   -- our name on EllesmereUI's list of item overlays

local sets = {}         -- a bag's item button -> our marks over it
local ellesmere = {}    -- EllesmereUI's buttons among them, whose own item level ours stands in for
local installed, registered = false, false
-- Your spec's weights and what your gear is worth by them, read once a frame: a bag paints
-- every slot in one go, EllesmereUI one slot per call.
local weights, power, readAt

local function On()
    return B.On() and S.Get("bisBagMarks") == true
end

local function Marks(button, over)
    local set = sets[button]
    if not set then
        set = Parts.ItemMarks(over, button:GetHeight())
        sets[button] = set
    end
    return set
end

local function Weights()
    local now = GetTime()
    if now ~= readAt then
        readAt = now
        local key = SW.ActiveSpec()
        weights = key and SW.For(key)
        power = weights and SW.Power(weights)
    end
    return weights, power
end

-- An item's marks; none for an empty slot. Its level and arrow on gear only (a level on a
-- potion says nothing).
---@return boolean shown whether it shows an item level
local function Paint(set, id, link)
    if not id then
        set:Hide()
        return false
    end
    set:Show()
    local gear = Items.SlotsFor(id) ~= nil
    local level = gear and GetDetailedItemLevelInfo(link or id) or nil
    local upgrade = gear and SW.BestGain(id, link, Weights()) ~= nil
    return Parts.PaintItemMarks(set, level, ns.IsBisItem(id), Parts.IsForever("items", id), upgrade)
end

-------------------------------------------------------------------------------
--  The game's bags
-------------------------------------------------------------------------------
local function GameBag(frame)
    if not On() then return end
    for _, button in frame:EnumerateValidItems() do
        local bag, slot = button:GetBagID(), button:GetID()
        local id = GetContainerItemID(bag, slot)
        local set = sets[button] or (id and Marks(button, button))
        if set then Paint(set, id, id and GetContainerItemLink(bag, slot)) end
    end
end

-------------------------------------------------------------------------------
--  EllesmereUI's bags
-------------------------------------------------------------------------------
-- Its own marks in our corners: its BoE word in the bottom-left puts our star after it, and
-- Pawn's upgrade arrow in the bottom-right our item level before it.
local function Corners(set, button)
    local bind = button.BindTypeText
    local word = bind and bind:GetText()
    set.rank:ClearAllPoints()
    if word and word ~= "" then
        set.rank:SetPoint("LEFT", bind, "RIGHT", 1, 0)
    else
        set.rank:SetPoint("BOTTOMLEFT", Parts.MARK_IN, Parts.MARK_IN)
    end
    local arrow = button.UpgradeIcon
    set.level:ClearAllPoints()
    if arrow and arrow:IsShown() then
        set.level:SetPoint("RIGHT", arrow, "LEFT")
    else
        set.level:SetPoint("BOTTOMRIGHT", -Parts.MARK_IN, Parts.MARK_IN)
    end
end

-- EllesmereUI's item level, back as it had it (or hidden while ours stands in for it).
local function TheirLevel(button, alpha)
    if button.ItemLevelText then button.ItemLevelText:SetAlpha(alpha) end
end

-- Called by EllesmereUI for each slot it paints: data is its slot's, for the call only.
local function EllesmereSlot(button, data)
    local info = data.info
    local id = info and info.itemID
    local set = sets[button]
    if not set then
        if not id then return end
        set = Marks(button, button._textOverlay or button)
        ellesmere[button] = true
    end
    local shown = Paint(set, id, data.itemLink)
    if not id then return end
    Corners(set, button)
    TheirLevel(button, shown and 0 or 1)
end

-------------------------------------------------------------------------------
--  On and off
-------------------------------------------------------------------------------
local function Repaint()
    Bags.RepaintGame(GameBag)
    if registered then Bags.RefreshEllesmere() end
end

local function Install()
    installed = true
    Bags.OnGameUpdate(GameBag)
    -- A new list or pick: the stars again.
    B.OnListChange(function() if On() then Repaint() end end)
end

local function Apply()
    local on = On()
    if on and not installed then Install() end
    if not installed then return end
    local bags = Bags.Ellesmere()
    if bags and on ~= registered then
        registered = on
        if on then
            bags.RegisterItemOverlayIcon(OVERLAY, EllesmereSlot)
        else
            bags.UnregisterItemOverlayIcon(OVERLAY)
        end
    end
    if on then
        Repaint()
        return
    end
    for button, set in pairs(sets) do
        set:Hide()
        if ellesmere[button] then TheirLevel(button, 1) end
    end
end
B.ApplyBagMarks = Apply

S.OnChange(function(key)
    if key == "enabled" or key == "bis" or key == "bisBagMarks" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
