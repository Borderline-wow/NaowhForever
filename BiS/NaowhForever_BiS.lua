-------------------------------------------------------------------------------
--  NaowhForever_BiS.lua -- the QoL BiS list: per gear slot per character, a ranked list of
--  picks (#1 is the BiS) from wowsrc.com's ranking for a spec (NaowhForever_BiSData.lua)
--  or by Alt+Shift-click, shared as an import string, and shown on item tooltips, in the
--  loot feed and as an alert when a listed item drops.
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

local lookup   -- itemID -> its best pick number (1 is BiS), rebuilt when the list changes
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

-- A slot's picks in order: slots[slot] is #1 and extra[slot] holds the rest.
local function Picks(list, slot)
    local picks = { list.slots[slot] }
    for _, id in ipairs(list.extra[slot] or {}) do picks[#picks + 1] = id end
    return picks
end

local function Store(list, slot, picks)
    local rest = {}
    for i = 2, #picks do rest[#rest + 1] = picks[i] end
    list.slots[slot], list.extra[slot] = picks[1], rest[1] and rest or nil
end

-- A two-hander and an off-hand cannot both be #1. The hand that did not just change gives
-- way, its next pick moving up; returns the picks taken out.
local function HandRule(list, changed)
    local cleared = {}
    while list.slots[16] and list.slots[17] and IsTwoHand(list.slots[16]) do
        local slot = changed == 17 and 16 or 17
        local picks = Picks(list, slot)
        cleared[#cleared + 1] = table.remove(picks, 1)
        Store(list, slot, picks)
    end
    return cleared
end

local function SayCleared(cleared)
    if #cleared == 0 then return end
    local names = {}
    for _, id in ipairs(cleared) do names[#names + 1] = Name(id) end
    ns.Print(("%s came off your BiS list: a two-hander and an off-hand cannot both be BiS.")
        :format(table.concat(names, ", ")))
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

-- A slot's ranked items under a spec key, else under the class's first spec.
local function Ranking(key, slot)
    for _, spec in ipairs(ns.BiSData.specs) do
        if spec.key == key then return spec.slots[slot] end
    end
    local spec = ClassSpecs()[1]
    return spec and spec.slots[slot]
end

-- A set of item IDs as a list in ranked order, anything unranked last.
local function Ranked(set, order)
    local pos, ids = {}, {}
    for i, id in ipairs(order or {}) do pos[id] = pos[id] or i end
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local pa, pb = pos[a] or math.huge, pos[b] or math.huge
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    return ids
end

-- One list per character, kept in the account store: personal, so it never travels in an
-- exported profile. Lists from before slots were a flat item list; each item moves into the
-- first slot it fits. 0.5.12 test builds kept extra[slot] as an unordered set of secondary
-- picks; those are put in ranked order behind the BiS pick. Whatever no longer fits is named
-- in chat once.
local function List()
    local account = ns.AccountSettings()
    account.bis = account.bis or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    local list = account.bis[key] or { name = "My BiS" }
    account.bis[key] = list
    list.extra = list.extra or {}
    local moved, dropped = false, {}
    if not list.slots then
        list.slots = {}
        for _, id in ipairs(list.items or {}) do
            local slot = FreeSlot(list.slots, id)
            if slot then list.slots[slot] = id else dropped[#dropped + 1] = Name(id) end
        end
        list.items = nil
        moved = true
    end
    for slot, set in pairs(list.extra) do
        if not set[1] then
            list.extra[slot] = Ranked(set, Ranking(list.spec, slot))
            Store(list, slot, Picks(list, slot))
            moved = true
        end
    end
    if moved then
        for _, id in ipairs(HandRule(list, 16)) do dropped[#dropped + 1] = Name(id) end
        if #dropped > 0 then
            ns.Print("Your BiS list now keeps a ranked list per slot. These did not fit: "
                .. table.concat(dropped, ", "))
        end
    end
    return list
end

local function CurrentSpec()
    local specs = ClassSpecs()
    local key = List().spec
    for _, spec in ipairs(specs) do
        if spec.key == key then return spec end
    end
    return specs[1]
end

-- The slot's ranked items the running client knows; an unknown ID never finishes loading.
local function Candidates(slot, spec)
    local ids = {}
    for _, id in ipairs(spec and spec.slots[slot] or {}) do
        if C_Item.GetItemInfoInstant(id) then ids[#ids + 1] = id end
    end
    return ids
end

local function Rebuild()
    lookup = {}
    local list = List()
    for slot in pairs(SLOT_NAME) do
        for rank, id in ipairs(Picks(list, slot)) do
            if not lookup[id] or rank < lookup[id] then lookup[id] = rank end
        end
    end
end

-- The item's best pick number, 1 being BiS.
function ns.IsBisItem(itemID)
    if not (On() and itemID) then return nil end
    if not lookup then Rebuild() end
    return lookup[itemID]
end

local function Changed()
    Rebuild()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

-- A slot is open for a #1 pick when it has none and the other hand's pick does not rule it out.
local function Open(slots, slot, itemID)
    if slots[slot] then return false end
    if slot == 17 then return not (slots[16] and IsTwoHand(slots[16])) end
    if slot == 16 and IsTwoHand(itemID) then return not slots[17] end
    return true
end

-- The next pick in the slot, #1 when it has none.
function ns.AddBisPick(slot, itemID)
    local list = List()
    local picks = Picks(list, slot)
    for _, id in ipairs(picks) do
        if id == itemID then return end
    end
    picks[#picks + 1] = itemID
    Store(list, slot, picks)
    SayCleared(HandRule(list, slot))
    Changed()
end

function ns.RemoveBisPick(slot, itemID)
    local list = List()
    local picks = Picks(list, slot)
    for i, id in ipairs(picks) do
        if id == itemID then
            table.remove(picks, i)
            break
        end
    end
    Store(list, slot, picks)
    SayCleared(HandRule(list, slot))
    Changed()
end

-- Swaps the pick with the one above (step -1) or below (step 1).
function ns.MoveBisPick(slot, itemID, step)
    local list = List()
    local picks = Picks(list, slot)
    for i, id in ipairs(picks) do
        local j = i + step
        if id == itemID and picks[j] then
            picks[i], picks[j] = picks[j], id
            break
        end
    end
    Store(list, slot, picks)
    SayCleared(HandRule(list, slot))
    Changed()
end

-- #1 in the first open slot the item fits, else the next pick in its first slot. Never
-- pushes out the other hand's BiS pick.
function ns.AddBisItem(value)
    local id = IDFrom(value)
    local fits = id and SlotsFor(id)
    if not fits then
        ns.Print("That is not an item you can equip.")
        return
    end
    if not lookup then Rebuild() end
    if lookup[id] then return end
    local list = List()
    for _, slot in ipairs(fits) do
        if Open(list.slots, slot, id) then
            ns.AddBisPick(slot, id)
            ns.Print(("Added %s to your BiS %s."):format(Name(id), SLOT_NAME[slot]))
            return
        end
    end
    local slot = fits[1]
    if not list.slots[slot] then
        ns.Print(("%s was not added: a two-hander and an off-hand cannot both be BiS. Pick it in the %s slot to swap them.")
            :format(Name(id), SLOT_NAME[slot]))
        return
    end
    ns.AddBisPick(slot, id)
    ns.Print(("Added %s to your BiS %s as #%d."):format(Name(id), SLOT_NAME[slot], #Picks(list, slot)))
end

function ns.RemoveBisItem(itemID)
    local list = List()
    for slot in pairs(SLOT_NAME) do
        local picks = Picks(list, slot)
        for i = #picks, 1, -1 do
            if picks[i] == itemID then table.remove(picks, i) end
        end
        Store(list, slot, picks)
    end
    SayCleared(HandRule(list, 16))
    Changed()
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
        v = 4, name = list.name, spec = list.spec, slots = list.slots, extra = list.extra,
    })))
end

local function ValidID(id)
    return type(id) == "number" and id > 0 and id < 2 ^ 31 and id == math.floor(id)
end

-- Parsed as data, never run: only a name, a spec key and item numbers in slots they fit are
-- kept. Version 1 strings are the old flat list, placed the same way an old saved list is;
-- version 2 strings have only BiS picks, and version 3 strings have unordered secondary
-- picks, put in the spec's ranked order.
local function Decode(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table") then return end
    -- Shown in chat and tooltips, so escape codes are neutralised.
    local name = type(data.name) == "string" and data.name:sub(1, 40):gsub("|", "||") or "Imported BiS"
    local spec = type(data.spec) == "string" and data.spec:sub(1, 40) or nil
    local list = { slots = {}, extra = {} }
    if data.v == 1 and type(data.items) == "table" then
        for _, id in ipairs(data.items) do
            local slot = ValidID(id) and FreeSlot(list.slots, id)
            if slot then list.slots[slot] = id end
        end
    elseif (data.v == 2 or data.v == 3 or data.v == 4) and type(data.slots) == "table" then
        for slot, id in pairs(data.slots) do
            if SLOT_NAME[slot] and ValidID(id) and Fits(id, slot) then list.slots[slot] = id end
        end
        for slot, more in pairs(data.v > 2 and type(data.extra) == "table" and data.extra or {}) do
            if SLOT_NAME[slot] and type(more) == "table" then
                if data.v == 3 then
                    local set = {}
                    for id, on in pairs(more) do
                        if on == true and ValidID(id) then set[id] = true end
                    end
                    more = Ranked(set, Ranking(spec, slot))
                end
                local picks = Picks(list, slot)
                local seen = {}
                for _, id in ipairs(picks) do seen[id] = true end
                for _, id in ipairs(more) do
                    if ValidID(id) and Fits(id, slot) and not seen[id] then
                        seen[id] = true
                        picks[#picks + 1] = id
                    end
                end
                Store(list, slot, picks)
            end
        end
    else
        return
    end
    HandRule(list, 16)
    return name, list.slots, list.extra, spec
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
    for _, rest in pairs(extra) do count = count + #rest end
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
    local rank = S.Get("bisTooltip") and ns.IsBisItem(id)
    if rank then
        tooltip:AddLine(TAG .. (rank > 1 and " #" .. rank or "") .. "  " .. List().name)
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
    local rank = link and not (issecretvalue and issecretvalue(link)) and ns.IsBisItem(IDFrom(link))
    if rank then
        ns.Print(TAG .. (rank > 1 and " #" .. rank or "") .. " " .. what .. ": " .. link)
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
--  The picker
-------------------------------------------------------------------------------
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local BIS_COLOR, EMPTY_COLOR = { 0.1, 0.85, 0.2 }, { 0, 0, 0 }
local BIS_TEXT = "|cff1ad933BiS|r"
local SOURCE_SEP = " \194\183 "   -- the middle dot wowsrc puts between boss and place
local PICKER_W, PICKER_H, PICK_ROW = 480, 560, 30

local function QualityHex(itemID)
    local q = C_Item.GetItemQualityByID(itemID)
    local c = q and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

local function RankText(rank)
    return rank == 1 and BIS_TEXT or ("|cffffd100#%d|r"):format(rank)
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

local pickerPanel, pickerSlot
local FillPicker

-- Icon, quality-coloured name and grey source, shared by both kinds of picker row.
local function ItemLine(row, x)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", x, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = ns.Font(row, 12, nil)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.num = ns.Font(row, 12, nil, T.muted)
    row.num:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
end

local function SetItemLine(row, num, id)
    local source = ns.BiSData.sources[id]
    row.id = id
    row.num:SetText(num)
    row.icon:SetTexture(C_Item.GetItemIconByID(id))
    row.text:SetText(QualityHex(id) .. Name(id) .. "|r" .. (source and "  |cff808080" .. source .. "|r" or ""))
end

local function NewPickRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PICK_ROW)
    row:EnableMouse(true)
    ItemLine(row, 32)
    row:SetScript("OnEnter", function(self) ItemTooltip(self, self.id) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.remove = ns.Button(row, "Remove", 64, 22, function()
        ns.RemoveBisPick(pickerSlot, row.id)
        FillPicker()
    end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.down = ns.Button(row, "Down", 48, 22, function()
        ns.MoveBisPick(pickerSlot, row.id, 1)
        FillPicker()
    end)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.up = ns.Button(row, "Up", 40, 22, function()
        ns.MoveBisPick(pickerSlot, row.id, -1)
        FillPicker()
    end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
    return row
end

local function NewCandidateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICK_ROW)
    local hover = ns.Solid(row, "BACKGROUND", T.accent, 0.12)
    hover:SetAllPoints()
    hover:Hide()
    ItemLine(row, 32)
    row.tag = ns.Font(row, 12, nil)
    row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.text:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
    row:SetScript("OnClick", function(self)
        ns.AddBisPick(pickerSlot, self.id)
        FillPicker()
    end)
    row:SetScript("OnEnter", function(self)
        hover:Show()
        ItemTooltip(self, self.id)
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)
    return row
end

-- Your picks in order with their controls, then the spec's ranking to pick from.
function FillPicker()
    local UI = ns.UI
    local content = pickerPanel.scroll.content
    UI.BeginReusableRows(content)
    local spec = CurrentSpec()
    local picks = Picks(List(), pickerSlot)
    local y = 0

    local head = UI.KeepFont(content, "picksHead", 12, nil, T.accent)
    head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    head:SetText("YOUR PICKS, BEST FIRST")
    y = y - 22
    local picked = {}
    for i, id in ipairs(picks) do
        picked[id] = i
        local row = UI.Keep(content, "pick", NewPickRow)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        SetItemLine(row, i == 1 and BIS_TEXT or i .. ".", id)
        row.up:SetShown(i > 1)
        row.down:SetShown(i < #picks)
        y = y - PICK_ROW
    end
    if #picks == 0 then
        local none = UI.KeepFont(content, "none", 12, nil, T.muted)
        none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 6)
        none:SetText("Nothing picked yet. The first item you click below is your BiS.")
        y = y - PICK_ROW
    end

    y = y - 14
    head = UI.KeepFont(content, "rankHead", 12, nil, T.accent)
    head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    head:SetText(spec and ("RANKED FOR " .. spec.name:upper()) or "RANKED")
    y = y - 22
    local ids = Candidates(pickerSlot, spec)
    for i, id in ipairs(ids) do
        local row = UI.Keep(content, "candidate", NewCandidateRow)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        SetItemLine(row, i .. ".", id)
        row.tag:SetText(picked[id] and RankText(picked[id]) or "")
        y = y - PICK_ROW
    end
    if #ids == 0 then
        local none = UI.KeepFont(content, "unranked", 12, nil, T.muted)
        none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 6)
        none:SetText("Nothing ranked for this slot.")
        y = y - PICK_ROW
    end
    content:SetHeight(-y)
end

local function OpenPicker(slot)
    local UI = ns.UI
    local spec = CurrentSpec()
    local dimmer, panel = ns.MakeModal(PICKER_W, PICKER_H, "bisPicker")
    pickerPanel, pickerSlot = panel, slot
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", 0, -16)
    head:SetText(spec and ("%s: %s"):format(ns.L(SLOT_NAME[slot]), spec.name) or ns.L(SLOT_NAME[slot]))
    panel.scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.content = CreateFrame("Frame", nil, sf)
        -- Sized off the panel: the scroll frame reads 0 wide until a layout pass has run.
        sf.content:SetSize(PICKER_W - 62, 1)
        sf:SetScrollChild(sf.content)
        return sf
    end)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -48)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 54)
    panel.scroll:SetVerticalScroll(0)
    UI.KeepButton(panel, "done", "Done", 100, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    FillPicker()
    dimmer:Show()

    local ids = Candidates(slot, spec)
    for _, id in ipairs(Picks(List(), slot)) do ids[#ids + 1] = id end
    OnLoaded(ids, function()
        if dimmer:IsShown() and pickerSlot == slot then FillPicker() end
    end)
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
-- The paperdoll: slot buttons down both sides of the character model, weapons underneath.
local SLOT_SIZE, SLOT_GAP, MODEL_GAP = 40, 6, 12
local LEFT_SLOTS = { 1, 2, 3, 15, 5, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }
local COLUMN_H = #RIGHT_SLOTS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
local DOLL_W = 380
local DOLL_H = COLUMN_H + MODEL_GAP + SLOT_SIZE + 16   -- room for Worn under the weapons

local function SlotTooltip(self)
    local picks = Picks(List(), self.slot)
    local label = ns.L(SLOT_NAME[self.slot])
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if picks[1] then
        GameTooltip:SetItemByID(picks[1])
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Your %s picks"):format(label), T.accent.r, T.accent.g, T.accent.b)
        for i, id in ipairs(picks) do
            GameTooltip:AddLine(("%d. %s%s|r"):format(i, QualityHex(id), Name(id)))
        end
        GameTooltip:AddLine("Click to change them.", 0.5, 0.5, 0.5)
    else
        GameTooltip:SetText(label)
        GameTooltip:AddLine("Click to pick your BiS from the ranking.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function NewSlotButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(20, 20)
    b.check:SetPoint("BOTTOMRIGHT", 5, -5)
    b.check:SetTexture(CHECK)
    b.check:SetVertexColor(BIS_COLOR[1], BIS_COLOR[2], BIS_COLOR[3])
    b.more = ns.Font(b, 11, "OUTLINE")
    b.more:SetPoint("TOPRIGHT", -3, -3)
    b.worn = ns.Font(b, 10, nil, T.muted)
    b.worn:SetText("Worn")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) OpenPicker(self.slot) end)
    b:SetScript("OnEnter", SlotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- side is where Worn goes, clear of the model: LEFT, RIGHT or BOTTOM.
local function SlotButton(doll, slot, x, y, side, marks)
    local b = ns.UI.Keep(doll, "slot", NewSlotButton)
    b:SetPoint("TOPLEFT", doll, "TOPLEFT", x, y)
    b.slot = slot
    local picks = Picks(List(), slot)
    local id = picks[1]
    b.worn:ClearAllPoints()
    if side == "LEFT" then
        b.worn:SetPoint("RIGHT", b, "LEFT", -4, 0)
    elseif side == "RIGHT" then
        b.worn:SetPoint("LEFT", b, "RIGHT", 4, 0)
    else
        b.worn:SetPoint("TOP", b, "BOTTOM", 0, -2)
    end
    b.check:SetShown(id ~= nil)
    b.more:SetText(#picks > 1 and "+" .. (#picks - 1) or "")
    if id then
        b.icon:SetTexture(C_Item.GetItemIconByID(id))
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.border:SetColorTexture(BIS_COLOR[1], BIS_COLOR[2], BIS_COLOR[3], 1)
        b.worn.slot, b.worn.itemID = slot, id
        b.worn:SetShown(Wearing(slot, id))
        marks[#marks + 1] = b.worn
    else
        local _, empty = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)
        b.icon:SetTexture(empty)
        b.icon:SetTexCoord(0, 1, 0, 1)
        b.border:SetColorTexture(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], 1)
        b.worn:Hide()
    end
end

local function NewDoll(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(DOLL_W, DOLL_H)
    local model = CreateFrame("PlayerModel", nil, f)
    model:SetPoint("TOPLEFT", f, "TOPLEFT", SLOT_SIZE + MODEL_GAP, 0)
    model:SetSize(DOLL_W - 2 * (SLOT_SIZE + MODEL_GAP), COLUMN_H)
    local band = ns.Solid(f, "BACKGROUND", T.panel, 0.35)
    band:SetAllPoints(model)
    -- A model frame drops its model while hidden.
    model:SetScript("OnShow", function(self) self:SetUnit("player") end)
    model:SetScript("OnEvent", function(self)
        if self:IsVisible() then self:RefreshUnit() end
    end)
    model:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    model:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    return f
end

local function Paperdoll(parent, x, y, marks)
    local doll = ns.UI.Keep(parent, "bisDoll", NewDoll)
    doll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local stride = (COLUMN_H - SLOT_SIZE) / (#LEFT_SLOTS - 1)
    for i, slot in ipairs(LEFT_SLOTS) do
        SlotButton(doll, slot, 0, -math.floor((i - 1) * stride + 0.5), "LEFT", marks)
    end
    for i, slot in ipairs(RIGHT_SLOTS) do
        SlotButton(doll, slot, DOLL_W - SLOT_SIZE, -(i - 1) * (SLOT_SIZE + SLOT_GAP), "RIGHT", marks)
    end
    local step = SLOT_SIZE + MODEL_GAP
    local left = (DOLL_W - #BOTTOM_SLOTS * step + MODEL_GAP) / 2
    for i, slot in ipairs(BOTTOM_SLOTS) do
        SlotButton(doll, slot, left + (i - 1) * step, -(COLUMN_H + MODEL_GAP), "BOTTOM", marks)
    end
end

-- Every pick grouped by where it comes from: places with the most BiS picks first, and in
-- each place BiS picks before the rest, best first.
local function SourceText()
    local list = List()
    local ranks, ids = {}, {}
    for slot in pairs(SLOT_NAME) do
        for rank, id in ipairs(Picks(list, slot)) do
            if not ranks[id] then ids[#ids + 1] = id end
            if not ranks[id] or rank < ranks[id] then ranks[id] = rank end
        end
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
        if ranks[id] == 1 then p.bis = p.bis + 1 end
        p.items[#p.items + 1] = { id = id, rank = ranks[id], detail = detail }
    end
    table.sort(places, function(a, b)
        if a.bis ~= b.bis then return a.bis > b.bis end
        if #a.items ~= #b.items then return #a.items > #b.items end
        return a.name < b.name
    end)

    local lines = {}
    for _, p in ipairs(places) do
        table.sort(p.items, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.id < b.id
        end)
        if #lines > 0 then lines[#lines + 1] = " " end
        lines[#lines + 1] = p.name
        for _, item in ipairs(p.items) do
            lines[#lines + 1] = ("    %s  %s%s|r%s"):format(RankText(item.rank),
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
    _, h = W:Note(parent, "Click a slot to pick its items from the ranking for your spec, best "
        .. "first: your BiS, then your 2nd, 3rd and so on. A slot shows its BiS with a green border "
        .. "and a check mark, and +N for the rest. Alt+Shift-click any item (bags, links, loot) to "
        .. "add it as the next pick for its slot, or again to take it off. Listed items say so on "
        .. "their tooltip, are tagged in the loot feed, and ring an alert when they drop or come up "
        .. "for a roll.", y); y = y - h

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
            tooltip = "Whose ranking the slot picker shows. Your picks stay as they are when you switch.",
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
    local gap = 48
    Paperdoll(parent, pad, y - 8, wornMarks[parent])
    local panelH = SourcePanel(parent, pad + DOLL_W + gap, y, width - DOLL_W - gap)
    return y - math.max(DOLL_H + 8, panelH)
end
