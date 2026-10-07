-------------------------------------------------------------------------------
--  Slots.lua -- the inspect window's slots in the character panel's look (CP.SlotOver): the
--  icon cropped in an edge of its quality's colour, its item level, Forever's mark, their BiS
--  star when their Naowh Forever told us their list (TheirBiS.lua), the green arrow on what
--  would be an upgrade for you by your stat weights, and an orange dot on a slot an enchanter
--  could enchant that has none. Painted from a post-hook of the game's inspect slot update;
--  the gear check (upgrades, unenchanted and empty slots) is read once per refresh, for the
--  GUID shown only, and IP.Gear() hands it to the Player tab. The upgrade's size is added to
--  the slot's own tooltip.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local IP = ns.InspectPanel
local CP = ns.CharacterPanel
local B = ns.BiS
local SW = ns.StatWeights
local Shared = ns.Shared
local Items, Parts, St = Shared.Items, Shared.Parts, Shared.Style

local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemLink = GetInventoryItemLink
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo

local MAIN, OFF = 16, 17
local BARE_TIP = "No enchant"

local overs = {}
local installed = false
local gear = { up = {}, bare = {}, bareCount = 0, empty = 0, ups = 0 }

function IP.Gear(guid)
    if guid ~= nil and gear.guid == guid then return gear end
end

local function Paint(over)
    local unit, guid = IP.Current()
    local slot = over.slot
    local id = unit and GetInventoryItemID(unit, slot)
    if id == 0 then id = nil end
    over:Show()
    CP.PaintEdge(over, id)
    local link = id and GetInventoryItemLink(unit, slot)
    local fresh = id ~= nil and gear.guid == guid
    Parts.PaintItemMarks(over.marks, link and GetDetailedItemLevelInfo(link), id and IP.TheirRank(guid, slot, id),
        id and Parts.IsForever("items", id), fresh and gear.up[slot] ~= nil)
    over.bare:SetShown(fresh and gear.bare[slot] == true)
end

local function PaintAll()
    for _, over in pairs(overs) do Paint(over) end
end

function IP.PaintSlots()
    if IP.On() then PaintAll() end
end

local function SlotUpdated(button)
    local over = overs[button]
    if not over or not IP.On() then return end
    CP.CropSlot(button, true)
    Paint(over)
end

local function ReadGear(unit, guid)
    local key = SW.ActiveSpec()
    local weights = key and SW.For(key)
    local power = weights and SW.Power(weights)
    local main = GetInventoryItemID(unit, MAIN)
    local twoHand = main and Items.IsTwoHand(main)
    wipe(gear.up)
    wipe(gear.bare)
    gear.guid, gear.bareCount, gear.empty, gear.ups = guid, 0, 0, 0
    for _, entry in ipairs(Items.GEAR_SLOTS) do
        local slot = entry[1]
        local id = GetInventoryItemID(unit, slot)
        local link = id and GetInventoryItemLink(unit, slot)
        if not id then
            if not (slot == OFF and twoHand) then gear.empty = gear.empty + 1 end
        elseif not link then
            IP.Wait()
        else
            local gain = weights and SW.BestGain(id, link, weights, power)
            if gain then
                gear.up[slot] = gain
                gear.ups = gear.ups + 1
            end
            if B.Enchants.SLOTS[slot] then
                local can, current = B.Enchants.Enchantable(link)
                if can and current == 0 then
                    gear.bare[slot] = true
                    gear.bareCount = gear.bareCount + 1
                end
            end
        end
    end
    local level = C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel(unit)
    gear.level = level and level > 0 and math.floor(level + 0.5) or nil
    if not IP.HasGear(unit, guid) then gear.guid = nil end
end

local function Refreshed(unit, guid)
    if guid and IP.Ready(guid) then ReadGear(unit, guid) end
    PaintAll()
end

local function SpecName()
    local spec = SW.Spec(SW.ActiveSpec() or "")
    return spec and spec.name
end

local function OnItemTooltip(tooltip)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or not IP.On() then return end
    local over = overs[tooltip:GetOwner()]
    if not over then return end
    local _, guid = IP.Current()
    local gain = guid and gear.guid == guid and gear.up[over.slot]
    if not gain then return end
    tooltip:AddLine(Parts.UpgradeLine(gain, SpecName()))
end

local function Install()
    installed = true
    for slot, name in pairs(CP.SLOTS) do
        local button = _G["Inspect" .. name .. "Slot"]
        if button then
            local over = CP.SlotOver(button, slot)
            over.bare = B.View.EnchantBadge(over, { color = St.WARN_RGB, tip = BARE_TIP })
            overs[button] = over
        end
    end
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", SlotUpdated)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

IP.OnApply(function(on)
    if on and not installed then Install() end
    if not installed then return end
    for button, over in pairs(overs) do
        CP.FadeSlot(button, on and 0 or 1)
        CP.CropSlot(button, on)
        over.look:SetShown(on)
        if on then Paint(over) else over:Hide() end
    end
end)
IP.OnRefresh(Refreshed)
