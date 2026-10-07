-------------------------------------------------------------------------------
--  Slots.lua -- the character panel's slots in the BiS List's look: the icon cropped in a 1px
--  edge of its quality's colour, its item level in the corner, Forever's mark on what is new in
--  Forever, the enchant dot while a better enchant waits, and your BiS's star: the marks every
--  slot of ours has (Shared.Parts.ItemMarks). Where your BiS is something else, nothing here
--  says so: it shows in your bags with its star.
--
--  Blizzard's own slot buttons stay where they are and do what they do: ours is a frame over
--  each (state on it, none on theirs), painted from a post-hook of the game's slot update. With
--  the Naowh Character Panel, their art fades and ours draws the edge; with Slot Marks alone,
--  the marks go on the game's own panel (or EllesmereUI's) as it looks. Turned off, the art
--  comes back and ours hides. CP.SlotOver, CP.PaintEdge, CP.FadeSlot and CP.CropSlot are the
--  same on the Naowh Inspect Panel's slots (InspectPanel/).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local CP = ns.CharacterPanel
local B = ns.BiS
local Shared = ns.Shared
local Items, Parts, St = Shared.Items, Shared.Parts, Shared.Style

local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemLink = GetInventoryItemLink
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo

-- Inventory slot -> the game's button for it ("Character" .. name .. "Slot").
local SLOTS = {
    [0] = "Ammo", [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger0", [12] = "Finger1",
    [13] = "Trinket0", [14] = "Trinket1", [15] = "Back", [16] = "MainHand", [17] = "SecondaryHand",
    [18] = "Ranged", [19] = "Tabard",
}

local overs = {}         -- the game's slot button -> ours over it
local installed = false

CP.SLOTS = SLOTS

-- The game's art on a slot: its frame, its quality border and the slot's own border frame.
local function Fade(button, alpha)
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(alpha) end
    if button.IconBorder then button.IconBorder:SetAlpha(alpha) end
    if button.BorderFrame then button.BorderFrame:SetAlpha(alpha) end
end

local function Crop(button, on)
    local icon = button.icon
    if not icon then return end
    if on then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else icon:SetTexCoord(0, 1, 0, 1) end
end
CP.FadeSlot, CP.CropSlot = Fade, Crop

local function Paint(over)
    local slot = over.slot
    -- An empty slot is nil, and an empty ammo slot 0.
    local id = GetInventoryItemID("player", slot)
    if id == 0 then id = nil end
    over:Show()
    CP.PaintEdge(over, id)
    local link = id and S.Get("characterPanelLevels") and GetInventoryItemLink("player", slot)
    local marks = id and S.Get("characterPanelMarks")
    Parts.PaintItemMarks(over.marks, link and GetDetailedItemLevelInfo(link), marks and ns.IsBisItem(id) or nil,
        marks and Parts.IsForever("items", id))
    if S.Get("characterPanelEnchants") and id then
        B.View.PaintEnchantBadge(over.wand, slot)
    else
        over.wand:Hide()
    end
end

local function PaintAll()
    for _, over in pairs(overs) do Paint(over) end
end

-- The marks show with the Naowh Character Panel, or on the game's own panel with Slot Marks.
local function MarksOn()
    return CP.On() or (S.Get("enabled") == true and S.Get("characterPanelSlotMarks") == true)
end
CP.MarksOn = MarksOn

-- The game's update for a slot: its icon set again, so cropped again in our look, and ours
-- painted.
local function SlotUpdated(button)
    local over = overs[button]
    if not over or not MarksOn() then return end
    if CP.On() then Crop(button, true) end
    Paint(over)
end

--- The edge in the item's quality colour; black for an empty slot.
function CP.PaintEdge(over, id)
    local color = id and Items.QualityColor(id) or St.BORDER_RGB
    over.edge:SetColor(color.r, color.g, color.b, 1)
end

--- Ours over one of the game's slot buttons: our look's edge (over.look, shown with the panel's
--- look), the marks (Parts.ItemMarks), over.slot its inventory slot. Nothing on the game's button.
function CP.SlotOver(button, slot)
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button:GetFrameLevel() + 3)
    over.slot = slot
    -- Our look's edge, only with the Naowh Character Panel (the game's panel keeps its own).
    over.look = CreateFrame("Frame", nil, over)
    over.look:SetAllPoints()
    over.edge = ns.Border(over.look, St.BORDER_RGB)
    -- A black ring outside the quality's edge, the house's border, so the edge stands off the
    -- dark panel round it.
    local ring = CreateFrame("Frame", nil, over.look)
    ns.PixelInset(ring, -1, over)
    ns.Border(ring, St.BORDER_RGB)
    over.marks = Parts.ItemMarks(over, button:GetHeight())
    return over
end

local function Over(button, slot)
    local over = CP.SlotOver(button, slot)
    over.wand = B.View.EnchantBadge(over)
    return over
end

-- The first time it is on: ours over every slot, and the hooks (inert while it is off).
local function Install()
    installed = true
    for slot, name in pairs(SLOTS) do
        local button = _G["Character" .. name .. "Slot"]
        if button then
            overs[button] = Over(button, slot)
        end
    end
    hooksecurefunc("PaperDollItemSlotButton_Update", SlotUpdated)
    -- A new list or pick: the stars again.
    B.OnListChange(function() if MarksOn() then PaintAll() end end)
end

local function Apply()
    local styled, marked = CP.On(), MarksOn()
    if marked and not installed then Install() end
    if not installed then return end
    for button, over in pairs(overs) do
        Fade(button, styled and 0 or 1)
        Crop(button, styled)
        over.look:SetShown(styled)
        if marked then Paint(over) else over:Hide() end
    end
end
CP.ApplySlots = Apply

S.OnChange(function(key)
    if key == "enabled" or key:find("^characterPanel") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
