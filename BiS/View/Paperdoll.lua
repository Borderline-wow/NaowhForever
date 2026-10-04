-------------------------------------------------------------------------------
--  View/Paperdoll.lua -- your character as the game's character frame lays it out
--  (ns.BiS.View.Paperdoll): eight slots down each side, the weapons underneath, each showing
--  the slot's BiS in its quality's edge with a check once it is yours (green while you wear
--  it). Over the model a switch: it wears
--  your whole BiS, or what you wear now (where hovering a slot tries its BiS on); drag it to
--  turn it, scroll to zoom, right-click to set it straight. Under it, what your BiS gets you
--  over what you wear. Hover a slot to light its row; a click opens its picker.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Tip = ns.Shared.Parts.Tip
local T = ns.THEME
local B = ns.BiS
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts

local St = B.Style
local SLOT, SLOT_GAP, MODEL_GAP, DOLL_W = St.SLOT, St.SLOT_GAP, St.MODEL_GAP, St.DOLL_W
local LOOK_W, TURN_SPEED, ZOOM_STEP, ZOOM_MAX = St.LOOK_W, St.TURN_SPEED, St.ZOOM_STEP, St.ZOOM_MAX
local CAMERA, GAINS_H, BORDER_RGB = St.CAMERA, St.GAINS_H, St.BORDER_RGB
local WORN_DROP = 2     -- what you wear: its green line this far under the icon
local PLACE_DOT = St.PLACE_DOT

-- The game's own order: shirt and tabard on the left too, shown but not for picking.
local LEFT_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }
local COSMETIC = { [4] = "Shirt", [19] = "Tabard" }
local COLUMN_H = #RIGHT_SLOTS * (SLOT + SLOT_GAP) - SLOT_GAP
local TOP_H = St.TAB_H + 8     -- the switch's strip over the slots and the model, clear of the hat
local DOLL_H = TOP_H + COLUMN_H + MODEL_GAP + SLOT + GAINS_H

-- The weapons go in their hand; the ranged slot is left out, as trying it on takes a hand.
local HAND = { [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }

local LOOKS = { { key = "bis", label = "Your BiS" }, { key = "now", label = "Now" } }


-------------------------------------------------------------------------------
--  The model: your BiS on it, or what you wear; turned by dragging, zoomed by scrolling
-------------------------------------------------------------------------------
local function TryOn(model, slot, id)
    model:TryOn(select(2, C_Item.GetItemInfo(id)) or "item:" .. id, HAND[slot])
end

local function Dress(model)
    local doll = model:GetParent()
    model:SetUnit("player")
    if doll.look ~= "bis" or not doll.list then return end
    model:Undress()
    local idle = B.OffHandIdle(doll.list)
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        local id = doll.list.slots[slot]
        if id and slot ~= 18 and not (slot == 17 and idle) then TryOn(model, slot, id) end
    end
end

local function Straighten(model)
    model.rotation, model.zoom = 0, 0
    model:SetRotation(0)
    model:SetPortraitZoom(0)
    if model.SetCamDistanceScale then model:SetCamDistanceScale(CAMERA) end
end

local function Turn(model)
    local x = GetCursorPosition()
    model.rotation = model.turnFrom + (x - model.turnAt) * TURN_SPEED
    model:SetRotation(model.rotation)
end

local function ModelDown(model, button)
    if button ~= "LeftButton" then return end
    model.turnAt, model.turnFrom = GetCursorPosition(), model.rotation
    model:SetScript("OnUpdate", Turn)
end

local function ModelUp(model, button)
    model:SetScript("OnUpdate", nil)
    if button == "RightButton" then Straighten(model) end
end

local function ModelWheel(model, delta)
    model.zoom = math.max(0, math.min(ZOOM_MAX, model.zoom + delta * ZOOM_STEP))
    model:SetPortraitZoom(model.zoom)
end

local function ModelShown(model)
    model:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    model:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    Dress(model)
end

local function ModelHidden(model)
    model:UnregisterAllEvents()
    model:SetScript("OnUpdate", nil)
end

-------------------------------------------------------------------------------
--  The slots
-------------------------------------------------------------------------------
local function CosmeticEnter(button)
    if not Tip(button, "ANCHOR_RIGHT") then return end
    GameTooltip:SetText(COSMETIC[button.slot], 1, 1, 1)
    GameTooltip:AddLine("No stats: wear what you like.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function SlotEnter(button)
    local doll = button:GetParent()
    doll.onHover(button.slot)
    local slot = button.slot
    local picks = B.Picks(doll.list, slot, doll.picks)
    local label = ns.L(Items.SLOT_NAME[slot])
    if not Tip(button, "ANCHOR_RIGHT") then return end
    if not picks[1] then
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine("Click to pick your BiS.", T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
        return GameTooltip:Show()
    end
    if doll.look == "now" and slot ~= 18 then TryOn(doll.model, slot, picks[1]) end
    GameTooltip:SetItemByID(picks[1])
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Your %s picks"):format(label), T.accentSoft.r, T.accentSoft.g, T.accentSoft.b)
    for rank, id in ipairs(picks) do
        GameTooltip:AddLine(Parts.RankMark(rank) .. " " .. Items.QualityHex(id) .. Items.Name(id) .. "|r")
    end
    if slot == 17 and B.OffHandIdle(doll.list) then
        GameTooltip:AddLine("Unused while your main hand's BiS is a two-hander.", 1, 0.82, 0, true)
    elseif not Items.Owned(picks[1]) then
        GameTooltip:AddLine("Not yours yet.", T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:AddLine("Click to change them.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function SlotLeave(button)
    local doll = button:GetParent()
    doll.onHover(nil)
    if doll.look == "now" then Dress(doll.model) end
    GameTooltip:Hide()
end

local function SlotClicked(button)
    button:GetParent().onClick(button.slot, button)
end

local function SlotButton(doll, slot, x, y)
    local button = CreateFrame("Button", nil, doll)
    button:SetSize(SLOT, SLOT)
    button:SetPoint("TOPLEFT", x, y)
    button.slot = slot
    local icon = Parts.ItemIcon(button, SLOT)
    icon:SetAllPoints()
    button.iconFrame, button.icon, button.edge = icon, icon.texture, icon.edge
    if COSMETIC[slot] then
        button.icon:SetTexture(select(2, C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)))
        button.icon:SetTexCoord(0, 1, 0, 1)
        button.icon:SetDesaturated(true)
        button:SetAlpha(0.5)
        button:SetScript("OnEnter", CosmeticEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        return
    end
    button.wand = B.View.EnchantBadge(button)
    -- The marks every slot of ours has (its item level, Forever's mark; no star, as every slot
    -- here is your BiS); and what you wear, a green line under the icon, as the list's rows
    -- have one at their edge.
    button.marks = Parts.ItemMarks(icon, SLOT)
    button.worn = ns.Solid(button, "ARTWORK", St.HAVE_RGB, 1)
    button.worn:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -WORN_DROP)
    button.worn:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -WORN_DROP)
    button.worn:SetHeight(2)
    button.worn:Hide()
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", SlotClicked)
    button:SetScript("OnEnter", SlotEnter)
    button:SetScript("OnLeave", SlotLeave)
    doll.buttons[#doll.buttons + 1] = button
end

-------------------------------------------------------------------------------
--  The doll
-------------------------------------------------------------------------------
local Doll = {}

-- A number that changes when a slot's BiS, or what you wear, does: the model is dressed and
-- the gains read again only then.
local function Outfit(list)
    local sum = 0
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        local slot = gear[1]
        sum = sum + (list.slots[slot] or 0) * slot + (GetInventoryItemID("player", slot) or 0) * (slot + 20)
    end
    return sum
end

-- Again, now that an item has loaded.
function Doll:Refresh()
    self.outfit = nil
    self:Paint(self.list)
end

function Doll:Paint(list)
    self.list = list
    for _, button in ipairs(self.buttons) do
        local slot = button.slot
        local id = list.slots[slot]
        if id then
            button.icon:SetTexture(C_Item.GetItemIconByID(id))
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            button.icon:SetTexture(select(2, C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)))
            button.icon:SetTexCoord(0, 1, 0, 1)
        end
        local edge = id and Items.QualityColor(id) or BORDER_RGB
        button.edge:SetColor(edge.r, edge.g, edge.b, 1)
        button.icon:SetDesaturated(slot == 17 and B.OffHandIdle(list))
        button.worn:SetShown(id ~= nil and Items.Wearing(slot, id))
        Parts.PaintItemMarks(button.marks, id and (B.Rankings.ItemLevel(id) or C_Item.GetDetailedItemLevelInfo(id)),
            nil, Parts.IsForever("items", id))
        B.View.PaintEnchantBadge(button.wand, slot)
    end
    local outfit = Outfit(list)
    if outfit == self.outfit then return end
    self.outfit = outfit
    Dress(self.model)
    local gains = B.View.PaintScoreCard(self.gainsBlock, list, self.look)
    if gains.waiting then
        local ids = wipe(self.ids)
        for _, gear in ipairs(Items.GEAR_SLOTS) do ids[#ids + 1] = list.slots[gear[1]] end
        Items.OnLoaded(ids, self.refreshFn)
    end
end

function Doll:SetLook(key)
    self.look = key
    Parts.PaintTabs(self.looks, key)
    Dress(self.model)
    B.View.PaintScoreLook(self.gainsBlock, key)
end

-- onHover(slot or nil) and onClick(slot, button) are the caller's.
function B.View.Paperdoll(parent, onHover, onClick)
    local doll = Mixin(CreateFrame("Frame", nil, parent), Doll)
    doll:SetSize(DOLL_W, DOLL_H)
    doll.buttons, doll.picks, doll.ids, doll.onHover, doll.onClick = {}, {}, {}, onHover, onClick
    doll.look = "bis"
    doll.refreshFn = function() doll:Refresh() end
    local model = CreateFrame("DressUpModel", nil, doll)
    model:SetPoint("TOPLEFT", SLOT + MODEL_GAP, -TOP_H)
    model:SetSize(DOLL_W - 2 * (SLOT + MODEL_GAP), COLUMN_H)
    ns.Solid(doll, "BACKGROUND", T.panel, 0.35):SetAllPoints(model)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnShow", ModelShown)
    model:SetScript("OnHide", ModelHidden)
    model:SetScript("OnEvent", Dress)
    model:SetScript("OnMouseDown", ModelDown)
    model:SetScript("OnMouseUp", ModelUp)
    model:SetScript("OnMouseWheel", ModelWheel)
    Straighten(model)
    doll.model = model
    doll.looks = Parts.Tabs(doll, LOOK_W, LOOKS, function(key) doll:SetLook(key) end)
    doll.looks:SetPoint("TOP", doll, "TOP", 0, 0)
    Parts.PaintTabs(doll.looks, doll.look)
    local hint = ns.Font(doll, 10, nil, T.muted)
    hint:SetPoint("BOTTOM", model, "BOTTOM", 0, 6)
    hint:SetText("Drag to turn" .. PLACE_DOT .. "Scroll to zoom" .. PLACE_DOT .. "Right-click to reset")
    for i, slot in ipairs(LEFT_SLOTS) do SlotButton(doll, slot, 0, -(TOP_H + (i - 1) * (SLOT + SLOT_GAP))) end
    for i, slot in ipairs(RIGHT_SLOTS) do
        SlotButton(doll, slot, DOLL_W - SLOT, -(TOP_H + (i - 1) * (SLOT + SLOT_GAP)))
    end
    local step = SLOT + MODEL_GAP
    local left = (DOLL_W - #BOTTOM_SLOTS * step + MODEL_GAP) / 2
    for i, slot in ipairs(BOTTOM_SLOTS) do
        SlotButton(doll, slot, left + (i - 1) * step, -(TOP_H + COLUMN_H + MODEL_GAP))
    end
    -- The score card under the weapons.
    doll.gainsBlock = B.View.ScoreCard(doll, DOLL_W)
    doll.gainsBlock:SetPoint("TOPLEFT", 0, -(TOP_H + COLUMN_H + MODEL_GAP + SLOT + MODEL_GAP))
    -- A new frame starts shown, so OnShow only covers later shows.
    ModelShown(model)
    return doll
end
