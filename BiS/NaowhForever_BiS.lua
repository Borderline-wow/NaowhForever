-------------------------------------------------------------------------------
--  NaowhForever_BiS.lua -- the QoL BiS list: per gear slot per character, one BiS pick and
--  any number of secondary picks from wowsrc.com's ranked list for a spec
--  (NaowhForever_BiSData.lua) or by Alt+Shift-click, shared as an import string, and shown
--  on item tooltips, in the loot feed and as an alert when a listed item drops.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PREFIX = "!NBIS1!"
local TAG = "|cff0091edNaowh BiS|r"

-- Inventory slot numbers, in page order.
local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
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

local lookup   -- itemID -> "bis" or "secondary", rebuilt when the list changes
local wornMarks = {}   -- built page -> its worn marks, rechecked when gear changes

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

local function Wearing(slot, itemID)
    if GetInventoryItemID("player", slot) == itemID then return true end
    local pair = (slot == 11 and 12) or (slot == 12 and 11) or (slot == 13 and 14) or (slot == 14 and 13)
    return pair and GetInventoryItemID("player", pair) == itemID
end

-- A two-hander and an off-hand cannot be worn together; returns the off-hand it took out.
local function DropOffHand(slots)
    if slots[16] and slots[17] and IsTwoHand(slots[16]) then
        local off = slots[17]
        slots[17] = nil
        return off
    end
end

-- One list per character, kept in the account store: personal, so it never travels in an
-- exported profile. slots holds each slot's BiS pick, extra[slot] its secondary picks as a
-- set. Lists from before slots were a flat item list; each item moves into the first slot
-- it fits, and whatever no longer fits is named in chat once.
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
        local off = DropOffHand(list.slots)
        if off then dropped[#dropped + 1] = Name(off) end
        list.items = nil
        if #dropped > 0 then
            ns.Print("Your BiS list now keeps one item per slot. These did not fit: "
                .. table.concat(dropped, ", "))
        end
    end
    list.extra = list.extra or {}
    return list
end

local function Rebuild()
    lookup = {}
    local list = List()
    for _, set in pairs(list.extra) do
        for id in pairs(set) do lookup[id] = "secondary" end
    end
    for _, id in pairs(list.slots) do lookup[id] = "bis" end
end

-- "bis" or "secondary" for an item on the list.
function ns.IsBisItem(itemID)
    if not (On() and itemID) then return nil end
    if not lookup then Rebuild() end
    return lookup[itemID]
end

local function Changed()
    Rebuild()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

local function SetExtra(slot, itemID, on)
    local extra = List().extra
    local set = extra[slot] or {}
    set[itemID] = on or nil
    extra[slot] = next(set) and set or nil
end

-- Setting a two-hander clears the off-hand and the reverse; returns what it cleared.
local function SetSlot(slot, itemID)
    local slots = List().slots
    local cleared
    if slot == 16 and IsTwoHand(itemID) then
        cleared, slots[17] = slots[17], nil
    elseif slot == 17 and slots[16] and IsTwoHand(slots[16]) then
        cleared, slots[16] = slots[16], nil
    end
    slots[slot] = itemID
    SetExtra(slot, itemID, nil)
    Changed()
    return cleared
end

-- A slot is open for a BiS pick when it has none and the other hand's pick does not rule it out.
local function Open(slots, slot, itemID)
    if slots[slot] then return false end
    if slot == 17 then return not (slots[16] and IsTwoHand(slots[16])) end
    if slot == 16 and IsTwoHand(itemID) then return not slots[17] end
    return true
end

-- The BiS pick of the first open slot the item fits, else a secondary pick in its first slot.
function ns.AddBisItem(value)
    local id = IDFrom(value)
    local fits = id and SlotsFor(id)
    if not fits then
        ns.Print("That is not an item you can equip.")
        return
    end
    if not lookup then Rebuild() end
    if lookup[id] then return end
    local slots = List().slots
    for _, slot in ipairs(fits) do
        if Open(slots, slot, id) then
            SetSlot(slot, id)
            ns.Print(("Added %s to your BiS %s."):format(Name(id), SLOT_NAME[slot]))
            return
        end
    end
    SetExtra(fits[1], id, true)
    Changed()
    ns.Print(("Added %s to your BiS %s as a secondary pick."):format(Name(id), SLOT_NAME[fits[1]]))
end

-- From a slot's dropdown.
function ns.SetBisSlot(slot, itemID)
    local cleared = SetSlot(slot, itemID)
    if cleared then
        ns.Print(("%s came off your BiS list: a two-hander and an off-hand cannot both be listed.")
            :format(Name(cleared)))
    end
end

function ns.SetBisSecondary(slot, itemID, on)
    local slots = List().slots
    if on and slots[slot] == itemID then slots[slot] = nil end
    SetExtra(slot, itemID, on)
    Changed()
end

function ns.ClearBisPick(slot, itemID)
    local slots = List().slots
    if slots[slot] == itemID then slots[slot] = nil end
    SetExtra(slot, itemID, nil)
    Changed()
end

local function ClearSlot(slot)
    local list = List()
    list.slots[slot], list.extra[slot] = nil, nil
    Changed()
end

function ns.RemoveBisItem(itemID)
    local list = List()
    for s, id in pairs(list.slots) do
        if id == itemID then list.slots[s] = nil end
    end
    for s in pairs(list.extra) do SetExtra(s, itemID, nil) end
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

-- The slot's ranked items, then any picks the ranking lacks; returns them and the ranked count.
-- An ID the running client does not know never finishes loading, so it is left out.
local function Candidates(slot, spec)
    local list = List()
    local ids, seen = {}, {}
    local function Add(id)
        if not seen[id] and C_Item.GetItemInfoInstant(id) then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(spec and spec.slots[slot] or {}) do Add(id) end
    local ranked = #ids
    if list.slots[slot] then Add(list.slots[slot]) end
    for id in pairs(list.extra[slot] or {}) do Add(id) end
    return ids, ranked
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
        v = 3, name = list.name, spec = list.spec, slots = list.slots, extra = list.extra,
    })))
end

local function ValidID(id)
    return type(id) == "number" and id > 0 and id < 2 ^ 31 and id == math.floor(id)
end

-- Parsed as data, never run: only a name, a spec key and item numbers in slots they fit are
-- kept. Version 1 strings are the old flat list, placed the same way an old saved list is;
-- version 2 strings have no secondary picks.
local function Decode(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table") then return end
    local slots, extra = {}, {}
    if data.v == 1 and type(data.items) == "table" then
        for _, id in ipairs(data.items) do
            local slot = ValidID(id) and FreeSlot(slots, id)
            if slot then slots[slot] = id end
        end
    elseif (data.v == 2 or data.v == 3) and type(data.slots) == "table" then
        for slot, id in pairs(data.slots) do
            if SLOT_NAME[slot] and ValidID(id) and Fits(id, slot) then slots[slot] = id end
        end
        for slot, set in pairs(data.v == 3 and type(data.extra) == "table" and data.extra or {}) do
            if SLOT_NAME[slot] and type(set) == "table" then
                for id, on in pairs(set) do
                    if on == true and ValidID(id) and Fits(id, slot) and slots[slot] ~= id then
                        extra[slot] = extra[slot] or {}
                        extra[slot][id] = true
                    end
                end
            end
        end
    else
        return
    end
    DropOffHand(slots)
    -- Shown in chat and tooltips, so escape codes are neutralised.
    local name = type(data.name) == "string" and data.name:sub(1, 40):gsub("|", "||") or "Imported BiS"
    local spec = type(data.spec) == "string" and data.spec:sub(1, 40) or nil
    return name, slots, extra, spec
end

-- Also the entry point for a curated list delivered in a profile pack.
function ns.ImportBisList(text, quiet)
    local name, slots, extra, spec = Decode(text)
    if not name then
        ns.Print("That is not a Naowh BiS list.")
        return false
    end
    local count = 0
    for _ in pairs(slots) do count = count + 1 end
    for _, set in pairs(extra) do
        for _ in pairs(set) do count = count + 1 end
    end
    local function Apply()
        local list = List()
        list.name, list.slots, list.extra = name, slots, extra
        if spec then list.spec = spec end
        Changed()
        ns.Print(("Imported %s: %d items."):format(name, count))
    end
    if quiet then Apply() else
        ns.Confirm(("Replace your BiS list with %s (%d items)?"):format(name, count), Apply)
    end
    return true
end

-------------------------------------------------------------------------------
--  Showing it
-------------------------------------------------------------------------------
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local pick = S.Get("bisTooltip") and ns.IsBisItem(id)
    if pick then
        tooltip:AddLine(TAG .. "  " .. List().name .. (pick == "secondary" and " (secondary)" or ""))
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
    local pick = link and not (issecretvalue and issecretvalue(link)) and ns.IsBisItem(IDFrom(link))
    if pick then
        ns.Print(TAG .. " " .. (pick == "secondary" and "secondary " or "") .. what .. ": " .. link)
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, rollID)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        for _, marks in pairs(wornMarks) do
            for _, mark in ipairs(marks) do mark:SetShown(Wearing(mark.slot, mark.itemID)) end
        end
        return
    end
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
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

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
local ROW_H, ICON, STRIDE, MAX_ICONS = 56, 28, 32, 10
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local BIS_COLOR, SECONDARY_COLOR, OTHER_COLOR = { 0.1, 0.85, 0.2 }, { 1, 0.82, 0 }, { 0, 0, 0 }
local BIS_TEXT, SECONDARY_TEXT = "|cff1ad933BiS|r", "|cffffd100Secondary|r"
local SOURCE_SEP = " \194\183 "   -- the middle dot wowsrc puts between boss and place

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

-- Runs fn once every item in ids has loaded its name.
local function OnLoaded(ids, fn)
    if #ids == 0 then
        fn()
        return
    end
    local container = ContinuableContainer:Create()
    for _, id in ipairs(ids) do container:AddContinuable(Item:CreateFromItemID(id)) end
    container:ContinueOnLoad(fn)
end

-- The slot's candidates as an anchored dropdown, each with a submenu to make it the BiS
-- pick, a secondary pick, or neither. The same menu as the house dropdowns, so it closes on
-- an outside click and scrolls when long.
local function OpenPicker(anchor, slot)
    local spec = CurrentSpec()
    local ids, ranked = Candidates(slot, spec)
    OnLoaded(ids, function()
        if not anchor:IsVisible() then return end
        local list = List()
        local extra = list.extra[slot] or {}
        local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
        desc:SetScrollMode(420)
        desc:CreateTitle(spec and ("%s: %s"):format(ns.L(SLOT_NAME[slot]), spec.name) or ns.L(SLOT_NAME[slot]))
        for i, id in ipairs(ids) do
            local text = ("%s|T%s:18|t  %s%s|r"):format(i <= ranked and (i .. ".  ") or "",
                C_Item.GetItemIconByID(id), QualityHex(id), Name(id))
            local source = ns.BiSData.sources[id]
            if source then text = text .. "  |cff808080" .. source .. "|r" end
            local picked = list.slots[slot] == id or extra[id]
            if list.slots[slot] == id then text = text .. "  " .. BIS_TEXT
            elseif extra[id] then text = text .. "  " .. SECONDARY_TEXT end
            local item = desc:CreateButton(text)
            item:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
            item:CreateRadio(ns.L("Best in Slot"),
                function() return List().slots[slot] == id end,
                function()
                    ns.SetBisSlot(slot, id)
                    return MenuResponse.CloseAll
                end)
            item:CreateCheckbox(ns.L("Secondary"),
                function() return extra[id] == true end,
                function()
                    ns.SetBisSecondary(slot, id, not extra[id])
                    return MenuResponse.CloseAll
                end)
            if picked then
                item:CreateButton(ns.L("Remove"), function()
                    ns.ClearBisPick(slot, id)
                    return MenuResponse.CloseAll
                end)
            end
        end
        Menu.GetManager():OpenMenu(anchor, desc, AnchorUtil.CreateAnchor("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2))
    end)
end

local function NewSlotRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.band = ns.Solid(row, "BACKGROUND", T.panel, 0.35)
    row.band:SetAllPoints()
    local hover = ns.Solid(row, "BORDER", T.accent, 0.08)
    hover:SetAllPoints()
    hover:Hide()
    row:SetScript("OnClick", function(self) OpenPicker(self, self.slot) end)
    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    row.name = ns.Font(row, 12, nil, T.muted)
    row.name:SetPoint("LEFT", 14, 0)

    row.icons = {}
    for i = 1, MAX_ICONS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(ICON, ICON)
        b:SetPoint("TOPLEFT", row, "TOPLEFT", 96 + (i - 1) * STRIDE, -6)
        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.check = b:CreateTexture(nil, "OVERLAY")
        b.check:SetSize(18, 18)
        b.check:SetPoint("BOTTOMRIGHT", 5, -5)
        b.check:SetTexture(CHECK)
        b.check:SetVertexColor(BIS_COLOR[1], BIS_COLOR[2], BIS_COLOR[3])
        b:SetScript("OnClick", function(self) OpenPicker(self, row.slot) end)
        b:SetScript("OnEnter", function(self) ItemTooltip(self, self.id) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.icons[i] = b
    end

    row.item = ns.Font(row, 12, nil)
    row.item:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 96, 6)
    row.item:SetPoint("RIGHT", row, "RIGHT", -56, 0)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)

    local remove = CreateFrame("Button", nil, row)
    remove:SetSize(18, 18)
    remove:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    remove:SetNormalTexture(NOT_READY)
    remove:SetScript("OnClick", function() ClearSlot(row.slot) end)
    remove:SetScript("OnEnter", function(self)
        ns.UI.ShowWidgetTooltip(self, "Clear this slot", { anchor = "cursor" })
    end)
    remove:SetScript("OnLeave", function() ns.UI.HideWidgetTooltip() end)
    row.remove = remove

    row.worn = ns.Font(row, 11, nil, T.muted)
    row.worn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 6)
    row.worn:SetText("Worn")
    return row
end

local function SlotRow(parent, x, y, width, slot, label, lit, spec)
    local row = ns.UI.Keep(parent, "slot", NewSlotRow)
    row:SetSize(width, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    row.band:SetShown(lit)
    row.name:SetText(ns.L(label))

    local list = List()
    local bis = list.slots[slot]
    local extra = list.extra[slot] or {}
    row.slot, row.id = slot, bis

    -- The BiS pick, then secondary picks, then the rest in ranked order.
    local ids = Candidates(slot, spec)
    local shown = {}
    if bis and C_Item.GetItemInfoInstant(bis) then shown[1] = bis end
    for _, id in ipairs(ids) do
        if extra[id] then shown[#shown + 1] = id end
    end
    for _, id in ipairs(ids) do
        if id ~= bis and not extra[id] then shown[#shown + 1] = id end
    end
    local room = math.min(MAX_ICONS, math.floor((width - 96 - 56 + STRIDE - ICON) / STRIDE))
    for i, b in ipairs(row.icons) do
        local id = i <= room and shown[i] or nil
        b:SetShown(id ~= nil)
        if id then
            b.id = id
            b.icon:SetTexture(C_Item.GetItemIconByID(id))
            local c = (id == bis and BIS_COLOR) or (extra[id] and SECONDARY_COLOR) or OTHER_COLOR
            b.border:SetColorTexture(c[1], c[2], c[3], 1)
            b.check:SetShown(id == bis)
        end
    end

    row.remove:SetShown(bis ~= nil or next(extra) ~= nil)
    row.worn:Hide()
    if not bis then
        row.item:SetText("|cff808080" .. (next(extra) and "No BiS picked yet" or #ids > 0
            and "Click an item to pick it" or "Nothing ranked for this slot") .. "|r")
        return
    end
    local worn = row.worn
    worn.slot, worn.itemID = slot, bis
    worn:SetShown(Wearing(slot, bis))
    local marks = wornMarks[parent]
    marks[#marks + 1] = worn

    local source = ns.BiSData.sources[bis]
    row.item:SetText("")
    Item:CreateFromItemID(bis):ContinueOnItemLoad(function()
        if row.id == bis then
            row.item:SetText(QualityHex(bis) .. Name(bis) .. "|r"
                .. (source and "  |cff808080" .. source .. "|r" or ""))
        end
    end)
end

-- Every pick grouped by where it comes from: places with the most BiS picks first, and in
-- each place BiS picks before secondary ones.
local function SourceText()
    local list = List()
    local kinds, ids = {}, {}
    for _, set in pairs(list.extra) do
        for id in pairs(set) do
            if not kinds[id] then ids[#ids + 1] = id end
            kinds[id] = "secondary"
        end
    end
    for _, id in pairs(list.slots) do
        if not kinds[id] then ids[#ids + 1] = id end
        kinds[id] = "bis"
    end
    if #ids == 0 then
        return "|cff808080Pick items for your slots and this lists where each one comes from.|r", ids
    end

    local places, byName = {}, {}
    for _, id in ipairs(ids) do
        local source = ns.BiSData.sources[id] or "Source not listed"
        local detail, place = source:match("^(.*)" .. SOURCE_SEP .. "(.+)$")
        place = place or source
        local p = byName[place]
        if not p then
            p = { name = place, bis = 0, items = {} }
            byName[place] = p
            places[#places + 1] = p
        end
        if kinds[id] == "bis" then p.bis = p.bis + 1 end
        p.items[#p.items + 1] = { id = id, bis = kinds[id] == "bis", detail = detail }
    end
    table.sort(places, function(a, b)
        if a.bis ~= b.bis then return a.bis > b.bis end
        if #a.items ~= #b.items then return #a.items > #b.items end
        return a.name < b.name
    end)

    local lines = {}
    for _, p in ipairs(places) do
        table.sort(p.items, function(a, b)
            if a.bis ~= b.bis then return a.bis end
            return a.id < b.id
        end)
        if #lines > 0 then lines[#lines + 1] = " " end
        lines[#lines + 1] = p.name
        for _, item in ipairs(p.items) do
            lines[#lines + 1] = ("    %s  %s%s|r%s"):format(item.bis and BIS_TEXT or SECONDARY_TEXT,
                QualityHex(item.id), Name(item.id), item.detail and ("  |cff808080" .. item.detail .. "|r") or "")
        end
    end
    return table.concat(lines, "\n"), ids
end

local function NewSourcePanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    local title = ns.Font(f, 12, nil, T.accent)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -8)
    title:SetText("WHERE YOUR ITEMS DROP")
    local sep = ns.Solid(f, "ARTWORK", T.line, 1)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -26)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -26)
    sep:SetHeight(1)
    f.body = ns.Font(f, 12, nil)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
    f.body:SetPoint("RIGHT", f, "RIGHT")
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(3)
    return f
end

-- Returns the panel's height.
local function SourcePanel(parent, x, y, width)
    local f = ns.UI.Keep(parent, "bisSources", NewSourcePanel)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetWidth(width)
    local text, ids = SourceText()
    f.body:SetText(text)
    OnLoaded(ids, function() f.body:SetText((SourceText())) end)
    local h = 36 + f.body:GetStringHeight()
    f:SetHeight(h)
    return h
end

function ns.BuildQoLBiSPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    -- The main window and the BiS window can each have the page built. A build the window
    -- has since thrown away is unparented, and its marks go with it.
    for page in pairs(wornMarks) do
        if not page:GetParent() then wornMarks[page] = nil end
    end
    wornMarks[parent] = {}
    _, h = W:Note(parent, "Click a slot to pick its best in slot (green, with a check) and any "
        .. "secondary picks (yellow) from the ranking for your spec. Alt+Shift-click any item (bags, "
        .. "links, loot) to add it, as the slot's BiS if it has none or else as a secondary pick, or "
        .. "again to take it off. Listed items say so on their tooltip, are tagged in the loot feed, "
        .. "and ring an alert when they drop or come up for a roll.", y); y = y - h

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
    _, h = W:Button(parent, "Import a BiS List", y, function()
        ns.PromptText("Paste a Naowh BiS list", "", 0, function(text) ns.ImportBisList(text) end)
    end); y = y - h
    _, h = W:Button(parent, "Export My BiS List", y, function()
        ns.PromptText("Copy this to share your list", ns.ExportBisList(), 0, function() end)
    end); y = y - h

    _, h = W:SectionHeader(parent, "GEAR", y); y = y - h
    local pad = UI.CONTENT_PAD
    local width = parent:GetWidth() - pad * 2
    if width <= 0 then width = 910 end
    local gap = 24
    local left = math.floor(width * 0.6)
    local spec = CurrentSpec()
    for i, s in ipairs(SLOTS) do
        SlotRow(parent, pad, y - (i - 1) * ROW_H, left, s[1], s[2], i % 2 == 1, spec)
    end
    local panelH = SourcePanel(parent, pad + left + gap, y, width - left - gap)
    return y - math.max(#SLOTS * ROW_H, panelH)
end
