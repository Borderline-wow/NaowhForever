-------------------------------------------------------------------------------
--  NaowhForever_BiS.lua -- the QoL BiS list: one item per gear slot per character, picked
--  from wowsrc.com's ranked list for a spec (NaowhForever_BiSData.lua), by Alt+Shift-click
--  or by item ID, shared as an import string, and shown on item tooltips, in the loot feed
--  and as an alert when a listed item drops.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PREFIX = "!NBIS1!"
local TAG = "|cff0091edNaowh BiS|r"

-- Inventory slot numbers in character pane order.
local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
    { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
    { 11, "Ring 1" }, { 12, "Ring 2" }, { 13, "Trinket 1" }, { 14, "Trinket 2" },
    { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}
local SLOT_NAME = {}
for _, s in ipairs(SLOTS) do SLOT_NAME[s[1]] = s[2] end

-- Where an item can go, first choice first.
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local lookup   -- itemID -> true, rebuilt when the list changes

local function On()
    return S.Get("bis")
end

local function IDFrom(value)
    if type(value) == "number" then return value end
    return tonumber(tostring(value):match("item:(%d+)") or tostring(value):match("^%s*(%d+)%s*$"))
end

local function SlotsFor(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return EQUIP_SLOTS[equipLoc]
end

local function Fits(itemID, slot)
    for _, s in ipairs(SlotsFor(itemID) or {}) do
        if s == slot then return true end
    end
    return false
end

local function IsTwoHand(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc == "INVTYPE_2HWEAPON"
end

local function Name(itemID)
    return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

-- The first slot the item can go in that is still empty.
local function FreeSlot(slots, itemID)
    for _, s in ipairs(SlotsFor(itemID) or {}) do
        if not slots[s] then return s end
    end
end

-- One list per character, kept in the account store: personal, so it never travels in an
-- exported profile. Lists from before slots were a flat item list; each item moves into the
-- first slot it fits, and whatever no longer fits is named in chat once.
local function List()
    local account = ns.AccountSettings()
    account.bis = account.bis or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    local list = account.bis[key] or { name = "My BiS" }
    account.bis[key] = list
    if not list.slots then
        list.slots = {}
        local dropped = {}
        for _, id in ipairs(list.items or {}) do
            local slot = FreeSlot(list.slots, id)
            if slot then list.slots[slot] = id else dropped[#dropped + 1] = Name(id) end
        end
        list.items = nil
        if #dropped > 0 then
            ns.Print("Your BiS list now keeps one item per slot. These did not fit: "
                .. table.concat(dropped, ", "))
        end
    end
    return list
end

local function Rebuild()
    lookup = {}
    for _, id in pairs(List().slots) do lookup[id] = true end
end

function ns.IsBisItem(itemID)
    if not (On() and itemID) then return false end
    if not lookup then Rebuild() end
    return lookup[itemID] == true
end

local function Changed()
    Rebuild()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

-- A two-hander and an off-hand cannot be worn together, so setting one clears the other.
local function SetSlot(slot, itemID)
    local slots = List().slots
    for s, id in pairs(slots) do
        if id == itemID and s ~= slot then slots[s] = nil end
    end
    slots[slot] = itemID
    if slot == 16 and IsTwoHand(itemID) then slots[17] = nil end
    if slot == 17 and slots[16] and IsTwoHand(slots[16]) then slots[16] = nil end
    Changed()
end

local function ClearSlot(slot)
    List().slots[slot] = nil
    Changed()
end

-- Into the first empty slot the item fits, or over the first one when they are all taken.
function ns.AddBisItem(value)
    local id = IDFrom(value)
    local fits = id and SlotsFor(id)
    if not fits then
        ns.Print("That is not an item you can equip.")
        return
    end
    if ns.IsBisItem(id) then return end
    local slots = List().slots
    local slot = FreeSlot(slots, id) or fits[1]
    local replaced = slots[slot]
    SetSlot(slot, id)
    if replaced then
        ns.Print(("%s replaces %s in your BiS %s."):format(Name(id), Name(replaced), SLOT_NAME[slot]))
    else
        ns.Print(("Added %s to your BiS %s."):format(Name(id), SLOT_NAME[slot]))
    end
end

function ns.RemoveBisItem(itemID)
    local slots = List().slots
    for s, id in pairs(slots) do
        if id == itemID then slots[s] = nil end
    end
    Changed()
end

-------------------------------------------------------------------------------
--  wowsrc.com rankings
-------------------------------------------------------------------------------
local function ClassSpecs()
    local _, class = UnitClass("player")
    local out = {}
    for _, spec in ipairs(ns.BiSData.specs) do
        if spec.class == class then out[#out + 1] = spec end
    end
    return out
end

-- The spec whose rankings the page shows: the one picked last, else the class's first.
local function CurrentSpec()
    local specs = ClassSpecs()
    local key = List().spec
    for _, spec in ipairs(specs) do
        if spec.key == key then return spec end
    end
    return specs[1]
end

-------------------------------------------------------------------------------
--  Sharing
-------------------------------------------------------------------------------
local function Codec()
    return LibStub("LibSerialize"), LibStub("LibDeflate")
end

function ns.ExportBisList()
    local LS, LD = Codec()
    local list = List()
    return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({
        v = 2, name = list.name, spec = list.spec, slots = list.slots,
    })))
end

local function ValidID(id)
    return type(id) == "number" and id > 0 and id < 2 ^ 31 and id == math.floor(id)
end

-- Parsed as data, never run: only a name, a spec key and item numbers in slots they fit are
-- kept. Version 1 strings are the old flat list, placed the same way an old saved list is.
local function Decode(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table") then return end
    local slots = {}
    if data.v == 1 and type(data.items) == "table" then
        for _, id in ipairs(data.items) do
            local slot = ValidID(id) and FreeSlot(slots, id)
            if slot then slots[slot] = id end
        end
    elseif data.v == 2 and type(data.slots) == "table" then
        for slot, id in pairs(data.slots) do
            if SLOT_NAME[slot] and ValidID(id) and Fits(id, slot) then slots[slot] = id end
        end
    else
        return
    end
    -- Shown in chat and tooltips, so escape codes are neutralised.
    local name = type(data.name) == "string" and data.name:sub(1, 40):gsub("|", "||") or "Imported BiS"
    local spec = type(data.spec) == "string" and data.spec:sub(1, 40) or nil
    return name, slots, spec
end

-- Also the entry point for a curated list delivered in a profile pack.
function ns.ImportBisList(text, quiet)
    local name, slots, spec = Decode(text)
    if not name then
        ns.Print("That is not a Naowh BiS list.")
        return false
    end
    local count = 0
    for _ in pairs(slots) do count = count + 1 end
    local function Apply()
        local list = List()
        list.name, list.slots = name, slots
        if spec then list.spec = spec end
        Changed()
        ns.Print(("Imported %s: %d slots."):format(name, count))
    end
    if quiet then Apply() else
        ns.Confirm(("Replace your BiS list with %s (%d slots)?"):format(name, count), Apply)
    end
    return true
end

-------------------------------------------------------------------------------
--  Showing it
-------------------------------------------------------------------------------
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    if S.Get("bisTooltip") and ns.IsBisItem(id) then
        tooltip:AddLine(TAG .. "  " .. List().name)
    end
end)

-- Alt+Shift-click an item anywhere it can be clicked to add it, or take it off again.
hooksecurefunc("HandleModifiedItemClick", function(link)
    if not (On() and IsAltKeyDown() and IsShiftKeyDown()) then return end
    local id = IDFrom(link)
    if not id then return end
    if ns.IsBisItem(id) then
        ns.RemoveBisItem(id)
        ns.Print("Removed " .. Name(id) .. " from your BiS list.")
    else
        ns.AddBisItem(id)
    end
end)

-- LOOT_READY can fire more than once for one loot window; each item alerts once.
local alerted = {}

local function Alert(link, what)
    if link and not (issecretvalue and issecretvalue(link)) and ns.IsBisItem(IDFrom(link)) then
        ns.Print(TAG .. " " .. what .. ": " .. link)
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, rollID)
    if event == "LOOT_CLOSED" then
        wipe(alerted)
        return
    end
    if not (On() and S.Get("bisLootAlert")) then return end
    if event == "START_LOOT_ROLL" then
        Alert(GetLootRollItemLink(rollID), "roll")
        return
    end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and not (issecretvalue and issecretvalue(link)) and not alerted[link] then
            alerted[link] = true
            Alert(link, "drop")
        end
    end
end)
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("START_LOOT_ROLL")

-- A listed item's roll frame glows while it is open. Forever's roll frames are unverified, so
-- a missing one just goes without the glow.
local function MarkRoll(frame)
    local LCG = LibStub("LibCustomGlow-1.0")
    local link = frame.rollID and GetLootRollItemLink(frame.rollID)
    if On() and S.Get("bisLootAlert") and link and ns.IsBisItem(IDFrom(link)) then
        LCG.PixelGlow_Start(frame, { 0, 0.57, 0.93, 1 }, 12, nil, nil, 2, 0, 0, nil, "NaowhBiS")
    else
        LCG.PixelGlow_Stop(frame, "NaowhBiS")
    end
end

for i = 1, 4 do
    local frame = _G["GroupLootFrame" .. i]
    if frame then
        frame:HookScript("OnShow", MarkRoll)
        frame:HookScript("OnHide", function(self) LibStub("LibCustomGlow-1.0").PixelGlow_Stop(self, "NaowhBiS") end)
    end
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
local ROW_H, ICON = 44, 30
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function QualityHex(itemID)
    local q = C_Item.GetItemQualityByID(itemID)
    local c = q and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

local function ItemTooltip(owner, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

local function Wearing(slot, itemID)
    if GetInventoryItemID("player", slot) == itemID then return true end
    local pair = (slot == 11 and 12) or (slot == 12 and 11) or (slot == 13 and 14) or (slot == 14 and 13)
    return pair and GetInventoryItemID("player", pair) == itemID
end

-- The slot's ranked candidates as an anchored dropdown, opened once their names have loaded.
-- The same menu as the house dropdowns, so it closes on an outside click and scrolls when long.
local function OpenPicker(anchor, slot)
    local spec = CurrentSpec()
    local ids = spec and spec.slots[slot] or {}
    if #ids == 0 then
        ns.Print("wowsrc.com has no picks for this slot. Alt+Shift-click an item to add it.")
        return
    end
    local container = ContinuableContainer:Create()
    for _, id in ipairs(ids) do container:AddContinuable(Item:CreateFromItemID(id)) end
    container:ContinueOnLoad(function()
        if not anchor:IsVisible() then return end
        local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
        desc:SetScrollMode(420)
        desc:CreateTitle(("%s: %s, ranked by wowsrc.com"):format(ns.L(SLOT_NAME[slot]), spec.name))
        for rank, id in ipairs(ids) do
            local text = ("%d.  |T%s:18|t  %s%s|r"):format(rank, C_Item.GetItemIconByID(id), QualityHex(id), Name(id))
            local source = ns.BiSData.sources[id]
            if source then text = text .. "  |cff808080" .. source .. "|r" end
            local button = desc:CreateRadio(text,
                function() return List().slots[slot] == id end,
                function() SetSlot(slot, id) end)
            button:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
        end
        Menu.GetManager():OpenMenu(anchor, desc, AnchorUtil.CreateAnchor("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2))
    end)
end

local function SlotRow(parent, y, slot, label, lit)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", ns.UI.CONTENT_PAD, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ns.UI.CONTENT_PAD, y)
    local band = ns.Solid(row, "BACKGROUND", T.panel, 0.35)
    band:SetAllPoints()
    band:SetShown(lit)
    local hover = ns.Solid(row, "BORDER", T.accent, 0.08)
    hover:SetAllPoints()
    hover:Hide()

    local name = ns.Font(row, 12, nil, T.muted)
    name:SetPoint("LEFT", 20, 0)
    name:SetText(ns.L(label))

    local id = List().slots[slot]
    local function Pick() OpenPicker(row, slot) end
    row:SetScript("OnClick", Pick)
    row:SetScript("OnEnter", function(self)
        hover:Show()
        if id then ItemTooltip(self, id) end
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)

    if not id then
        ns.Button(row, "Pick it", 90, 24, Pick):SetPoint("LEFT", 130, 0)
        return ROW_H
    end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 130, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Item.GetItemIconByID(id))

    local item = ns.Font(row, 13, nil)
    item:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    item:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    item:SetJustifyH("LEFT")
    item:SetWordWrap(false)
    local source = ns.Font(row, 11, nil, T.muted)
    source:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
    source:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    source:SetJustifyH("LEFT")
    source:SetWordWrap(false)
    source:SetText(ns.BiSData.sources[id] or "")
    Item:CreateFromItemID(id):ContinueOnItemLoad(function()
        item:SetText(QualityHex(id) .. Name(id) .. "|r")
    end)

    local remove = CreateFrame("Button", nil, row)
    remove:SetSize(18, 18)
    remove:SetPoint("RIGHT", -16, 0)
    remove:SetNormalTexture(NOT_READY)
    remove:SetScript("OnClick", function() ClearSlot(slot) end)
    remove:SetScript("OnEnter", function(self)
        ns.UI.ShowWidgetTooltip(self, "Clear this slot", { anchor = "cursor" })
    end)
    remove:SetScript("OnLeave", function() ns.UI.HideWidgetTooltip() end)

    if Wearing(slot, id) then
        local worn = row:CreateTexture(nil, "ARTWORK")
        worn:SetSize(18, 18)
        worn:SetPoint("RIGHT", remove, "LEFT", -12, 0)
        worn:SetTexture(READY)
    end
    return ROW_H
end

function ns.BuildQoLBiSPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Pick an item for each slot from wowsrc.com's ranking for your spec, or "
        .. "Alt+Shift-click any item (bags, links, loot) to put it in its slot, or again to take it "
        .. "off. Listed items say so on their tooltip, are tagged in the loot feed, and ring an "
        .. "alert when they drop or come up for a roll.", y); y = y - h

    _, h = W:SectionHeader(parent, "BIS LIST" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bis", "BiS List", "Tracks your list and marks the items on it."),
        S.Toggle("bisTooltip", "Show on Tooltips", "A Naowh BiS line on listed items.", "bis")
    ); y = y - h

    local specs = ClassSpecs()
    local values, order = {}, {}
    for _, spec in ipairs(specs) do
        values[spec.key] = spec.name
        order[#order + 1] = spec.key
    end
    _, h = W:DualRow(parent, y,
        S.Toggle("bisLootAlert", "Drop Alert",
            "A chat line and a sound when a listed item is in the loot window or up for a roll, and a glow on its roll frame.", "bis"),
        #specs > 0 and { type = "dropdown", text = "Rankings For", values = values, order = order,
            tooltip = "Whose ranking each slot's dropdown shows. Your picks stay as they are when you switch.",
            getValue = function() local spec = CurrentSpec(); return spec and spec.key end,
            setValue = function(v) List().spec = v end }
        or { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Add Item by ID", y, function()
        ns.PromptText("Item ID or link to add", "", 0, ns.AddBisItem)
    end); y = y - h
    _, h = W:Button(parent, "Import a BiS List", y, function()
        ns.PromptText("Paste a Naowh BiS list", "", 0, function(text) ns.ImportBisList(text) end)
    end); y = y - h
    _, h = W:Button(parent, "Export My BiS List", y, function()
        ns.PromptText("Copy this to share your list", ns.ExportBisList(), 0, function() end)
    end); y = y - h

    _, h = W:SectionHeader(parent, "GEAR  |cff808080rankings from wowsrc.com|r", y); y = y - h
    for i, s in ipairs(SLOTS) do
        y = y - SlotRow(parent, y, s[1], s[2], i % 2 == 1)
    end
    return y
end
