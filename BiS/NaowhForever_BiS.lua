-------------------------------------------------------------------------------
--  NaowhForever_BiS.lua -- the QoL BiS list: per gear slot per character, a ranked list of
--  picks (#1 is the BiS) from wowsrc.com's ranking for a spec (NaowhForever_BiSData.lua),
--  the dungeon drops the class can use (NaowhForever_DungeonLoot.lua) or by
--  Alt+Shift-click, shared as an import string, and shown on item tooltips, in the
--  loot feed and as an alert when a listed item drops.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local PREFIX = "!NBIS1!"
local function Tag() return ns.Color("accent", "Naowh BiS") end
-- The loot roll glow; ns.ThemeTint swaps in the player's Accent.
local BIS_GLOW = { r = 0, g = 0.57, b = 0.93 }

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
local wornMarks = {}   -- built page -> its slot buttons, repainted when gear changes
-- Which pick each slot's icon shows once its rank button has been clicked, this session.
local shownPick = {}
local ShowPick

local function On()
    return S.Get("bis")
end

local function IDFrom(value)
    if type(value) == "number" then return value end
    return tonumber(tostring(value):match("item[:=](%d+)") or tostring(value):match("^%s*(%d+)%s*$"))
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

-- The pick a slot shows on the paperdoll and in the list: the one its rank button was
-- stepped to, else the one you wear, else the BiS.
local function ShownRank(slot, picks)
    local rank = shownPick[slot]
    if rank and picks[rank] then return rank end
    for i, id in ipairs(picks) do
        if Wearing(slot, id) then return i end
    end
    return 1
end

local function RankLabel(rank)
    return rank == 1 and "BiS" or rank == 2 and "2nd" or rank == 3 and "3rd" or "#" .. rank
end

local WORN_COLOR = { r = 0.1, g = 0.85, b = 0.2 }


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

-- A two-hander as the main hand's #1 leaves the off hand unused. Its picks are kept, not
-- counted, until the main hand's #1 is a one-hander again.
local function OffHandIdle(list)
    return list.slots[16] ~= nil and IsTwoHand(list.slots[16])
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

-- Lists are kept per class in the account store, so every character of a class shares them
-- and none travels in an exported profile; each character remembers which one it uses, by
-- id. A character's own list from before lists were shared joins its class's lists the first
-- time it logs in, named for the character unless it already had a name of its own.
local function ClassLists()
    local account = ns.AccountSettings()
    local _, class = UnitClass("player")
    account.bisLists = account.bisLists or {}
    local store = account.bisLists[class] or { lists = {}, nextID = 1 }
    account.bisLists[class] = store
    account.bisActive = account.bisActive or {}
    return store, account
end

local function AddList(store, list)
    list.id = store.nextID
    store.nextID = store.nextID + 1
    store.lists[#store.lists + 1] = list
    return list
end

local function Taken(store, name, except)
    for _, l in ipairs(store.lists) do
        if l ~= except and l.name:lower() == name:lower() then return true end
    end
    return false
end

local function FreeName(store, name)
    local try, n = name, 1
    while Taken(store, try) do
        n = n + 1
        try = ("%s %d"):format(name, n)
    end
    return try
end

local function CharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Lists from before slots were a flat item list; each item moves into the first slot it
-- fits. 0.5.12 test builds kept extra[slot] as an unordered set of secondary picks; those
-- are put in ranked order behind the BiS pick. Whatever no longer fits is named in chat once.
local function List()
    local store, account = ClassLists()
    local key = CharKey()
    local old = account.bis and account.bis[key]
    if old then
        old.name = FreeName(store, (not old.name or old.name == "My BiS") and UnitName("player") or old.name)
        account.bisActive[key] = AddList(store, old).id
        account.bis[key] = nil
    end
    local list
    for _, l in ipairs(store.lists) do
        if l.id == account.bisActive[key] then list = l end
    end
    list = list or store.lists[1] or AddList(store, { name = "My BiS" })
    account.bisActive[key] = list.id
    list.extra = list.extra or {}
    local dropped = {}
    if not list.slots then
        list.slots = {}
        for _, id in ipairs(list.items or {}) do
            local slot = FreeSlot(list.slots, id)
            if slot then list.slots[slot] = id else dropped[#dropped + 1] = Name(id) end
        end
        list.items = nil
    end
    for slot, set in pairs(list.extra) do
        if not set[1] then
            list.extra[slot] = Ranked(set, Ranking(list.spec, slot))
            Store(list, slot, Picks(list, slot))
        end
    end
    if #dropped > 0 then
        ns.Print("Your BiS list now keeps a ranked list per slot. These did not fit: "
            .. table.concat(dropped, ", "))
    end
    return list
end

-- Keep the active fields in place for existing readers and share strings. Park each
-- spec's own tables when switching, so edits and imports cannot replace another spec.
local function SwitchListSpec(key)
    local list = List()
    local first = ClassSpecs()[1]
    local previous = list.spec or (first and first.key)
    if not key or key == previous then
        list.spec = previous
        return list
    end
    list.bySpec = list.bySpec or {}
    if previous then
        list.bySpec[previous] = { slots = list.slots, extra = list.extra }
    end
    local nextList = list.bySpec[key] or { slots = {}, extra = {} }
    list.slots, list.extra = nextList.slots, nextList.extra
    list.spec = key
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

function ns.IsBisItem(itemID)
    if not (On() and itemID) then return nil end
    if not lookup then Rebuild() end
    return lookup[itemID]
end

local function Changed()
    Rebuild()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

function ns.SetBisSpec(key)
    for _, spec in ipairs(ClassSpecs()) do
        if spec.key == key then
            SwitchListSpec(key)
            Changed()
            return
        end
    end
end

-- Names are shown in chat and tooltips, so escape codes are neutralised.
local function CleanName(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    return (name:sub(1, 40):gsub("|", "||"))
end

-- For the list dropdown: id -> name in the order they were made, and the one in use.
function ns.BisListChoices()
    local id = List().id
    local values, order = {}, {}
    for _, l in ipairs((ClassLists()).lists) do
        values[l.id], order[#order + 1] = l.name, l.id
    end
    return values, order, id
end

function ns.SelectBisList(id)
    local store, account = ClassLists()
    for _, l in ipairs(store.lists) do
        if l.id == id then
            account.bisActive[CharKey()] = id
            Changed()
            return
        end
    end
end

-- An empty list, ranked for the spec the current one is ranked for, and switched to.
function ns.NewBisList(name)
    name = CleanName(name)
    if not name then return false, "the name is empty" end
    local current = CurrentSpec()
    local store, account = ClassLists()
    if Taken(store, name) then return false, "that name is taken" end
    local list = AddList(store, { name = name, spec = current and current.key, slots = {}, extra = {} })
    account.bisActive[CharKey()] = list.id
    Changed()
    return true
end

function ns.RenameBisList(name)
    name = CleanName(name)
    if not name then return false, "the name is empty" end
    local list = List()
    if Taken((ClassLists()), name, list) then return false, "that name is taken" end
    list.name = name
    Changed()
    return true
end

-- Every character using it moves to the class's first list, or a new empty one.
function ns.DeleteBisList()
    local list = List()
    local lists = (ClassLists()).lists
    for i, l in ipairs(lists) do
        if l == list then table.remove(lists, i) break end
    end
    Changed()
end

function ns.AddBisPick(slot, itemID)
    local list = List()
    local picks = Picks(list, slot)
    for _, id in ipairs(picks) do
        if id == itemID then return end
    end
    picks[#picks + 1] = itemID
    Store(list, slot, picks)
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
    Changed()
end

-- #1 in the first empty slot the item fits, else the next pick in its first slot.
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
        if not list.slots[slot] then
            ns.AddBisPick(slot, id)
            ns.Print(("Added %s to your BiS %s."):format(Name(id), SLOT_NAME[slot]))
            return
        end
    end
    local slot = fits[1]
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
        local store, account = ClassLists()
        local list = AddList(store, { name = FreeName(store, name), spec = spec, slots = slots, extra = extra })
        account.bisActive[CharKey()] = list.id
        Changed()
        ns.Print(("Imported %s: %d items."):format(list.name, count))
    end
    if quiet then Apply() else
        ns.Confirm(("Add %s (%d items) as a new BiS list?"):format(name, count), Apply)
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
        tooltip:AddLine(Tag() .. (rank > 1 and " #" .. rank or "") .. "  " .. List().name)
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
        ns.Print(Tag() .. (rank > 1 and " #" .. rank or "") .. " " .. what .. ": " .. link)
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, rollID)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        for _, marks in pairs(wornMarks) do
            for _, b in ipairs(marks) do ShowPick(b) end
        end
        -- The list beside the paperdoll says which pick is worn too.
        if next(wornMarks) then ns.UI:RefreshPage(true) end
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
        local glow = ns.ThemeTint("accent", BIS_GLOW)
        LCG.PixelGlow_Start(frame, { glow.r, glow.g, glow.b, 1 }, 12, nil, nil, 2, 0, 0, nil, "NaowhBiS")
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
local EMPTY_COLOR = { 0, 0, 0 }
local BIS_TEXT = "|cff1ad933BiS|r"
local SOURCE_SEP = " \194\183 "   -- the middle dot wowsrc puts between boss and place
local PICKER_W, PICKER_H, PICK_ROW = 520, 600, 40
local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
local CHEVRON, CROSS = MEDIA .. "chevron_up.tga", MEDIA .. "cross.tga"

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

-- Runs fn, at most once a frame, as items in ids load their names. An item the server fails
-- to load never calls back, so a ContinuableContainer over ids would never finish.
local function OnLoaded(ids, fn)
    local queued
    local function Refresh()
        if queued then return end
        queued = true
        C_Timer.After(0, function()
            queued = false
            fn()
        end)
    end
    for _, id in ipairs(ids) do
        if not C_Item.IsItemDataCachedByID(id) then ItemEventListener:AddCallback(id, Refresh) end
    end
end

local pickerPanel, pickerSlot
local allDrops = false   -- dungeon drops at every level, not only near yours
local FillPicker

local function NewIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.border = ns.Border(f)
    return f
end

-- An item, or with no item the empty texture of emptySlot.
local function SetIcon(f, id, emptySlot)
    local c = T.line
    if id then
        f.tex:SetTexture(C_Item.GetItemIconByID(id))
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local q = C_Item.GetItemQualityByID(id)
        c = q and ITEM_QUALITY_COLORS[q] or c
    else
        local _, empty = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(emptySlot)
        f.tex:SetTexture(empty)
        f.tex:SetTexCoord(0, 1, 0, 1)
    end
    f.border:SetColor(c.r, c.g, c.b, 1)
end

local function GlyphButton(parent, texture, tip, onClick)
    local b = ns.Button(parent, "", 22, 22, onClick)
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetSize(12, 12)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetTexture(texture)
    b.glyph:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    b:HookScript("OnEnter", function(self)
        self.glyph:SetVertexColor(T.fg.r, T.fg.g, T.fg.b)
        ns.UI.ShowWidgetTooltip(self, tip)
    end)
    b:HookScript("OnLeave", function(self)
        self.glyph:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
        ns.UI.HideWidgetTooltip()
    end)
    return b
end

-- The caller anchors the right ends of text and detail.
local function ItemLine(row, x)
    row.icon = NewIcon(row, 30)
    row.icon:SetPoint("LEFT", x, 0)
    row.text = ns.Font(row, 13, nil)
    row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.detail = ns.Font(row, 11, nil, T.muted)
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.num = ns.Font(row, 12, nil, T.muted)
    row.num:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
end

-- Where an item comes from: wowsrc's wording, else the dungeon that drops it.
function ns.BiSSource(itemID)
    local loot = ns.BiSDungeonLoot[itemID]
    return ns.BiSData.sources[itemID] or (loot and loot[5])
end

local function ReqLevel(itemID)
    local loot = ns.BiSDungeonLoot[itemID]
    return loot and loot[4] or select(5, C_Item.GetItemInfo(itemID))
end

local function Detail(itemID)
    local parts = { ns.BiSSource(itemID) or "Source not listed" }
    local loot = ns.BiSDungeonLoot[itemID]
    if loot then parts[#parts + 1] = "ilvl " .. loot[3] end
    local req = ReqLevel(itemID)
    if req and req > 1 then
        parts[#parts + 1] = (req > UnitLevel("player") and "|cffff8040Req %d|r" or "Req %d"):format(req)
    end
    return table.concat(parts, SOURCE_SEP)
end

local function SetItemLine(row, num, id)
    row.id = id
    row.num:SetText(num)
    SetIcon(row.icon, id)
    row.text:SetText(QualityHex(id) .. Name(id) .. "|r"
        .. (pickerSlot and Wearing(pickerSlot, id) and "  |cff1ad933Worn|r" or ""))
    row.detail:SetText(Detail(id))
end

-- The armor type a class wears, by the item's required level: mail and plate are learned at
-- 40, as in classic. Types are NaowhForever_DungeonLoot.lua's.
local ARMOR = { MAGE = 1, PRIEST = 1, WARLOCK = 1, ROGUE = 2, DRUID = 2, HUNTER = 3, SHAMAN = 3,
    WARRIOR = 4, PALADIN = 4 }
local ARMOR_BEFORE_40 = { HUNTER = 2, SHAMAN = 2, WARRIOR = 3, PALADIN = 3 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
-- A weapon in the off hand takes dual wield, which only these classes learn, as in classic.
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
-- Enum.ItemWeaponSubclass values each class can learn, as in classic.
local WEAPONS = {
    DRUID = { 4, 5, 10, 13, 15 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    MAGE = { 7, 10, 15, 19 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    PRIEST = { 4, 10, 15, 19 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    WARLOCK = { 7, 10, 15, 19 },
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
}
for class, subs in pairs(WEAPONS) do
    local set = {}
    for _, sub in ipairs(subs) do set[sub] = true end
    WEAPONS[class] = set
end

local function Usable(class, item)
    local itemClass, sub, req = item[1], item[2], item[4]
    if itemClass == 2 then return WEAPONS[class][sub] == true end
    if sub == 0 then return true end
    if sub == 6 then return SHIELD[class] == true end
    if RELIC[sub] then return RELIC[sub] == class end
    return sub == (req < 40 and ARMOR_BEFORE_40[class] or ARMOR[class])
end

-- Dungeon drops for the slot that your class can use and the ranking leaves out, highest
-- required level first; near keeps only those within 10 levels of yours.
local function DungeonDrops(slot, ranked, near)
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local loot = ns.BiSDungeonLoot
    local skip = {}
    for _, id in ipairs(ranked) do skip[id] = true end
    local ids = {}
    for id, item in pairs(loot) do
        if not skip[id] and Usable(class, item) and Fits(id, slot)
            and not (slot == 17 and item[1] == 2 and not DUAL_WIELD[class])
            and (not near or math.abs(item[4] - level) <= 10) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        if loot[a][4] ~= loot[b][4] then return loot[a][4] > loot[b][4] end
        if loot[a][3] ~= loot[b][3] then return loot[a][3] > loot[b][3] end
        return a < b
    end)
    return ids
end

local function NewPickRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PICK_ROW)
    row:EnableMouse(true)
    ns.Solid(row, "BACKGROUND", T.bg, 0.6):SetAllPoints()
    ItemLine(row, 40)
    row:SetScript("OnEnter", function(self) ItemTooltip(self, self.id) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.remove = GlyphButton(row, CROSS, "Remove", function()
        ns.RemoveBisPick(pickerSlot, row.id)
        FillPicker()
    end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.down = GlyphButton(row, CHEVRON, "Move down", function()
        ns.MoveBisPick(pickerSlot, row.id, 1)
        FillPicker()
    end)
    row.down.glyph:SetTexCoord(0, 1, 1, 0)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.up = GlyphButton(row, CHEVRON, "Move up", function()
        ns.MoveBisPick(pickerSlot, row.id, -1)
        FillPicker()
    end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
    row.detail:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
    return row
end

local function NewCandidateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICK_ROW)
    local hover = ns.Solid(row, "BACKGROUND", T.accent, 0.12)
    hover:SetAllPoints()
    hover:Hide()
    ItemLine(row, 40)
    row.tag = ns.Font(row, 12, nil)
    row.tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.text:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
    row.detail:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
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

local function Heading(content, key, text, y)
    local head = ns.UI.KeepFont(content, key, 12, nil, T.accent)
    head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    head:SetText(text)
    local line = ns.UI.Keep(content, key .. "Line", function(p) return ns.Solid(p, "ARTWORK", T.line, 1) end)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 18)
    line:SetPoint("RIGHT", content, "RIGHT")
    line:SetHeight(1)
    return y - 26
end

local function Empty(content, key, text, y)
    local none = ns.UI.KeepFont(content, key, 12, nil, T.muted)
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 8)
    none:SetText(text)
    return y - 32
end

function FillPicker()
    local UI = ns.UI
    local content = pickerPanel.scroll.content
    UI.BeginReusableRows(content)
    local spec = CurrentSpec()
    local picks = Picks(List(), pickerSlot)
    local y = Heading(content, "picksHead", "YOUR PICKS, BEST FIRST", 0)
    local picked = {}
    for i, id in ipairs(picks) do
        picked[id] = i
        local row = UI.Keep(content, "pick", NewPickRow)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        SetItemLine(row, i == 1 and BIS_TEXT or i .. ".", id)
        row.up:SetShown(i > 1)
        row.down:SetShown(i < #picks)
        y = y - PICK_ROW - 2
    end
    if #picks == 0 then
        y = Empty(content, "none", "Nothing picked yet. The first item you click below is your BiS.", y)
    end

    y = Heading(content, "rankHead", spec and ("RANKED FOR " .. spec.name:upper()) or "RANKED", y - 16)
    local ids = Candidates(pickerSlot, spec)
    for _, id in ipairs(ids) do
        local row = UI.Keep(content, "candidate", NewCandidateRow)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        SetItemLine(row, "", id)
        row.tag:SetText(picked[id] and RankText(picked[id]) or "")
        y = y - PICK_ROW
    end
    if #ids == 0 then y = Empty(content, "unranked", "Nothing ranked for this slot.", y) end

    y = Heading(content, "dropsHead", allDrops and "DUNGEON DROPS" or "DUNGEON DROPS NEAR YOUR LEVEL", y - 16)
    UI.KeepButton(content, "dropsAll", allDrops and "Near My Level" or "Show All", 110, 20, function()
        allDrops = not allDrops
        FillPicker()
    end):SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y + 28)
    local drops = DungeonDrops(pickerSlot, ids, not allDrops)
    for _, id in ipairs(drops) do
        local row = UI.Keep(content, "candidate", NewCandidateRow)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        SetItemLine(row, "", id)
        row.tag:SetText(picked[id] and RankText(picked[id]) or "")
        y = y - PICK_ROW
    end
    if #drops == 0 then
        y = Empty(content, "noDrops", allDrops and "No dungeon drops for this slot that you can use."
            or "No dungeon drops for this slot within 10 levels of yours.", y)
    end
    content:SetHeight(-y)
end

-- An item ID, an item link or a Wowhead item URL, added as the slot's next pick.
local function AddByID(box)
    local id = IDFrom(box:GetText())
    if not (id and C_Item.GetItemInfoInstant(id)) then
        ns.Print("There is no item with that ID.")
        return
    end
    if not Fits(id, pickerSlot) then
        ns.Print(("%s does not go in the %s slot."):format(Name(id), ns.L(SLOT_NAME[pickerSlot])))
        return
    end
    ns.AddBisPick(pickerSlot, id)
    box:SetText("")
    box:ClearFocus()
    FillPicker()
    local slot = pickerSlot
    OnLoaded({ id }, function()
        if pickerPanel:IsVisible() and pickerSlot == slot then FillPicker() end
    end)
end

local function NewIDBox(panel)
    local box = ns.NewEditBox(panel)
    box.hint = ns.Font(box, 12, nil, T.muted)
    box.hint:SetPoint("LEFT", 7, 0)
    box.hint:SetText("Item ID, link or Wowhead URL")
    local function Hint(self) self.hint:SetShown(self:GetText() == "" and not self:HasFocus()) end
    box:SetScript("OnTextChanged", Hint)
    box:SetScript("OnEditFocusGained", Hint)
    box:SetScript("OnEditFocusLost", Hint)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", AddByID)
    return box
end

local function OpenPicker(slot)
    local UI = ns.UI
    local spec = CurrentSpec()
    local dimmer, panel = ns.MakeModal(PICKER_W, PICKER_H, "bisPicker")
    pickerPanel, pickerSlot = panel, slot
    local head = UI.KeepFont(panel, "head", 15, "OUTLINE")
    head:SetPoint("TOPLEFT", 22, -18)
    head:SetText(ns.L(SLOT_NAME[slot]))
    local sub = UI.KeepFont(panel, "sub", 12, nil, T.muted)
    sub:SetPoint("LEFT", head, "RIGHT", 10, 0)
    sub:SetText(spec and spec.name or "")
    panel.scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.content = CreateFrame("Frame", nil, sf)
        -- Sized off the panel: the scroll frame reads 0 wide until a layout pass has run.
        sf.content:SetSize(PICKER_W - 64, 1)
        sf:SetScrollChild(sf.content)
        return sf
    end)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -52)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -42, 62)
    panel.scroll:SetVerticalScroll(0)
    local sep = UI.Keep(panel, "footLine", function(p) return ns.Solid(p, "ARTWORK", T.line, 1) end)
    sep:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 52)
    sep:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 52)
    sep:SetHeight(1)
    local box = UI.Keep(panel, "idBox", NewIDBox)
    box:SetSize(250, 26)
    box:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 22, 14)
    box:SetText("")
    UI.KeepButton(panel, "addID", "Add", 60, 26, function() AddByID(box) end)
        :SetPoint("LEFT", box, "RIGHT", 6, 0)
    UI.KeepButton(panel, "done", "Done", 90, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 14)
    FillPicker()
    dimmer:Show()

    local ids = Candidates(slot, spec)
    for _, id in ipairs(DungeonDrops(slot, ids, false)) do ids[#ids + 1] = id end
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
local DOLL_H = COLUMN_H + MODEL_GAP + SLOT_SIZE + 16   -- room for the rank buttons under the weapons
local openSlots = {}   -- slots whose picks the panel lists in full, for the session

local function SlotTooltip(self)
    local list = List()
    local picks = Picks(list, self.slot)
    local label = ns.L(SLOT_NAME[self.slot])
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if picks[1] then
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Your %s picks"):format(label), T.accent.r, T.accent.g, T.accent.b)
        for i, id in ipairs(picks) do
            GameTooltip:AddLine(("%d. %s%s|r"):format(i, QualityHex(id), Name(id)))
        end
        if self.slot == 17 and OffHandIdle(list) then
            GameTooltip:AddLine("Unused while your Main Hand BiS is a two-hander.", 1, 0.82, 0)
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
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.more = ns.Font(b, 11, "OUTLINE")
    b.more:SetPoint("TOPRIGHT", -3, -3)
    b.rank = CreateFrame("Button", nil, b)
    b.rank:SetSize(26, 14)
    b.rank:SetFrameLevel(b:GetFrameLevel() + 2)
    ns.Solid(b.rank, "BACKGROUND", T.panel, 0.9):SetAllPoints()
    b.rank.border = ns.Border(b.rank)
    b.rank.label = ns.Font(b.rank, 9, "OUTLINE")
    b.rank.label:SetPoint("CENTER", 0, 0)
    b.rank:SetScript("OnClick", function()
        shownPick[b.slot] = b.shown % #b.picks + 1
        ns.UI:RefreshPage(true)
    end)
    b.rank:SetScript("OnEnter", function(self)
        ns.UI.ShowWidgetTooltip(self, "Click to step through your picks for this slot. Green "
            .. "while the item shown is the one you have on.")
    end)
    b.rank:SetScript("OnLeave", function() ns.UI.HideWidgetTooltip() end)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) OpenPicker(self.slot) end)
    b:SetScript("OnEnter", function(self)
        self:GetParent().lines[self.slot].hover:Show()
        SlotTooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self:GetParent().lines[self.slot].hover:Hide()
        GameTooltip:Hide()
    end)
    return b
end

-- A 1px border in the item's quality colour, painted again once the client has the item.
local function PaintQuality(b, id)
    local q = C_Item.GetItemQualityByID(id)
    local c = q and ITEM_QUALITY_COLORS[q]
    if c then
        b.border:SetColorTexture(c.r, c.g, c.b, 1)
        return
    end
    b.border:SetColorTexture(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], 1)
    OnLoaded({ id }, function()
        if b.itemID == id then PaintQuality(b, id) end
    end)
end

-- The button names the rank the slot shows, green while that item is equipped.
function ShowPick(b)
    local rank = ShownRank(b.slot, b.picks)
    local id = b.picks[rank]
    b.shown, b.itemID = rank, id
    b.icon:SetTexture(C_Item.GetItemIconByID(id))
    PaintQuality(b, id)
    local worn = Wearing(b.slot, id)
    b.rank.label:SetText(RankLabel(rank))
    local c = worn and WORN_COLOR or T.muted
    b.rank.label:SetTextColor(c.r, c.g, c.b, 1)
    b.rank.border:SetColor(c.r, c.g, c.b, worn and 1 or 0.5)
end

-- side is where the slot sits: its rank button goes toward the model, or under the weapons.
local function SlotButton(doll, slot, x, y, side, marks)
    local b = ns.UI.Keep(doll, "slot", NewSlotButton)
    b:SetPoint("TOPLEFT", doll, "TOPLEFT", x, y)
    b.slot = slot
    local list = List()
    local picks = Picks(list, slot)
    local id = picks[1]
    b.icon:SetDesaturated(slot == 17 and OffHandIdle(list))
    b.rank:ClearAllPoints()
    if side == "LEFT" then
        b.rank:SetPoint("LEFT", b, "RIGHT", 3, 0)
    elseif side == "RIGHT" then
        b.rank:SetPoint("RIGHT", b, "LEFT", -3, 0)
    else
        b.rank:SetPoint("TOP", b, "BOTTOM", 0, -2)
    end
    b.picks = picks
    b.more:SetText(#picks > 1 and "+" .. (#picks - 1) or "")
    b.rank:SetShown(id ~= nil)
    if id then
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ShowPick(b)
        marks[#marks + 1] = b
    else
        b.itemID = nil
        local _, empty = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)
        b.icon:SetTexture(empty)
        b.icon:SetTexCoord(0, 1, 0, 1)
        b.border:SetColorTexture(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], 1)
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
    -- A model frame drops its model while hidden. A new frame starts shown, so OnShow only
    -- covers later shows and the first unit is set here.
    model:SetScript("OnShow", function(self) self:SetUnit("player") end)
    model:SetUnit("player")
    model:SetScript("OnEvent", function(self)
        if self:IsVisible() then self:RefreshUnit() end
    end)
    model:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    model:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    return f
end

-- lines are the panel's slot lines, lit while their slot is hovered.
local function Paperdoll(parent, x, y, marks, lines)
    local doll = ns.UI.Keep(parent, "bisDoll", NewDoll)
    doll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    doll.lines = lines
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

-- Where a wowsrc source says the item comes from, and the boss or detail before that.
local function Place(source)
    local detail, place = source:match("^(.*)" .. SOURCE_SEP .. "(.+)$")
    return place or source, detail
end

local function Owned(slot, id)
    return Wearing(slot, id) or C_Item.GetItemCount(id, true) > 0
end

-- Sources that are not somewhere to go.
local NOT_A_PLACE = { Crafted = true, Quest = true, ["Quest (Horde)"] = true, ["Quest (Alliance)"] = true,
    ["Quest Reward"] = true, ["World drop"] = true, Reputation = true }

-- The places with the most BiS picks you do not have yet, most first, at most three.
local function RunNext(list)
    local places, byName = {}, {}
    local idle = OffHandIdle(list)
    for slot in pairs(SLOT_NAME) do
        local id = not (slot == 17 and idle) and list.slots[slot]
        local source = id and ns.BiSSource(id)
        local name = source and Place(source)
        if name and not NOT_A_PLACE[name] and not Owned(slot, id) then
            local p = byName[name]
            if not p then
                p = { name = name, bis = 0 }
                byName[name] = p
                places[#places + 1] = p
            end
            p.bis = p.bis + 1
        end
    end
    table.sort(places, function(a, b)
        if a.bis ~= b.bis then return a.bis > b.bis end
        return a.name < b.name
    end)
    for i = #places, 4, -1 do places[i] = nil end
    return places
end

-- The #1 pick in every empty slot from the spec's ranking, skipping items already picked
-- elsewhere, so the second ring or trinket gets the next one down. Returns how many.
function ns.FillBisFromRanking()
    local list = List()
    local spec = CurrentSpec()
    local used, filled = {}, 0
    for slot in pairs(SLOT_NAME) do
        if list.slots[slot] then used[list.slots[slot]] = true end
    end
    for _, s in ipairs(SLOTS) do
        local slot = s[1]
        if not list.slots[slot] and not (slot == 17 and OffHandIdle(list)) then
            for _, id in ipairs(Candidates(slot, spec)) do
                if not used[id] then
                    list.slots[slot], used[id], filled = id, true, filled + 1
                    break
                end
            end
        end
    end
    if filled > 0 then Changed() end
    return filled
end

local SLOT_ROW, PICK_LINE = 20, 18
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

local function NewSourcePanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    local title = ns.Font(f, 12, nil, T.accent)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -8)
    title:SetText("WHERE YOUR ITEMS DROP")
    local sep = ns.Solid(f, "ARTWORK", T.line, 1)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -26)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -26)
    sep:SetHeight(1)
    f.lines = {}
    return f
end

local function NewRunLine(parent)
    local fs = ns.Font(parent, 12, nil)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A slot's #1 pick and where it drops; clicking lists every pick under it.
local function NewSlotLine(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(SLOT_ROW)
    b.hover = ns.Solid(b, "BACKGROUND", T.accent, 0.12)
    b.hover:SetAllPoints()
    b.hover:Hide()
    -- Only the +/- opens a slot; the rest of the line is for its tooltip.
    b.toggle = CreateFrame("Button", nil, b)
    b.toggle:SetSize(14, 14)
    b.toggle:SetPoint("LEFT", 2, 0)
    b.toggle:SetScript("OnClick", function(self)
        local line = self:GetParent()
        openSlots[line.slot] = not openSlots[line.slot] or nil
        ns.UI:RefreshPage(true)
    end)
    b.label = ns.Font(b, 12, nil, T.muted)
    b.label:SetPoint("LEFT", 22, 0)
    b.more = ns.Font(b, 12, nil, T.muted)
    b.more:SetPoint("RIGHT", -4, 0)
    b.place = ns.Font(b, 12, nil, T.muted)
    b.place:SetPoint("RIGHT", -36, 0)
    b.place:SetWidth(140)
    b.place:SetJustifyH("RIGHT")
    b.place:SetWordWrap(false)
    b.item = ns.Font(b, 12, nil)
    b.item:SetPoint("LEFT", 100, 0)
    b.item:SetPoint("RIGHT", b.place, "LEFT", -8, 0)
    b.item:SetJustifyH("LEFT")
    b.item:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.id then ItemTooltip(self, self.id) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    return b
end

local function NewPickLine(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PICK_LINE)
    row:EnableMouse(true)
    row.num = ns.Font(row, 12, nil, T.muted)
    row.num:SetPoint("RIGHT", row, "LEFT", 40, 0)
    row.item = ns.Font(row, 12, nil)
    row.item:SetPoint("LEFT", 46, 0)
    row.item:SetWidth(180)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    row.source = ns.Font(row, 12, nil, T.muted)
    row.source:SetPoint("LEFT", row.item, "RIGHT", 8, 0)
    row.source:SetPoint("RIGHT", -4, 0)
    row.source:SetJustifyH("LEFT")
    row.source:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) ItemTooltip(self, self.id) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- The places to run next, then a line per slot in paperdoll order, open ones listing every
-- pick. Returns the panel's height and its slot lines.
local function SourcePanel(parent, x, y, width)
    local UI = ns.UI
    local f = UI.Keep(parent, "bisSources", NewSourcePanel)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetWidth(width)
    wipe(f.lines)
    local list = List()
    local top = -36

    local places = RunNext(list)
    if places[1] then
        local head = UI.KeepFont(f, "runHead", 12, nil, T.accent)
        head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, top)
        head:SetText("RUN NEXT")
        top = top - 20
        for _, p in ipairs(places) do
            local line = UI.Keep(f, "run", NewRunLine)
            line:SetPoint("TOPLEFT", f, "TOPLEFT", 22, top)
            line:SetPoint("RIGHT", f, "RIGHT")
            line:SetText(("%s: |cff1ad933%d BiS|r"):format(p.name, p.bis))
            top = top - PICK_LINE
        end
        top = top - 12
    end

    local named, ids = {}, {}
    for _, side in ipairs({ LEFT_SLOTS, RIGHT_SLOTS, BOTTOM_SLOTS }) do
        for _, slot in ipairs(side) do
            local picks = Picks(list, slot)
            local b = UI.Keep(f, "slotLine", NewSlotLine)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, top)
            b:SetPoint("RIGHT", f, "RIGHT")
            local rank = ShownRank(slot, picks)
            b.slot, b.id = slot, picks[rank]
            b.tag = picks[1] and ("  |cff%s%s|r"):format(Wearing(slot, b.id) and "1ad933" or "808080",
                RankLabel(rank)) or ""
            f.lines[slot] = b
            b.label:SetText(ns.L(SLOT_NAME[slot]) .. ":")
            b.more:SetText(#picks > 1 and "+" .. (#picks - 1) or "")
            b.toggle:SetShown(picks[1] ~= nil)
            top = top - SLOT_ROW
            if not picks[1] then
                b.item:SetText("|cff808080not picked|r")
                b.place:SetText("")
            else
                b.toggle:SetNormalTexture(openSlots[slot] and MINUS or PLUS)
                b.place:SetText(slot == 17 and OffHandIdle(list) and "unused, two-hander in main hand"
                    or (Place(ns.BiSSource(b.id) or "Source not listed")))
                named[#named + 1] = b
                ids[#ids + 1] = b.id
            end
            if picks[1] and openSlots[slot] then
                for i, id in ipairs(picks) do
                    local row = UI.Keep(f, "pickLine", NewPickLine)
                    row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, top)
                    row:SetPoint("RIGHT", f, "RIGHT")
                    row.id = id
                    row.tag = Wearing(slot, id) and "  |cff1ad933Worn|r" or ""
                    row.num:SetText(i .. ".")
                    local place, detail = Place(ns.BiSSource(id) or "Source not listed")
                    row.source:SetText(detail and detail .. ", " .. place or place)
                    named[#named + 1] = row
                    ids[#ids + 1] = id
                    top = top - PICK_LINE
                end
                top = top - 4
            end
        end
    end
    -- A later build can hand these lines another item, or none, before the names load.
    local function SetNames()
        for _, line in ipairs(named) do
            if line.id then line.item:SetText(QualityHex(line.id) .. Name(line.id) .. "|r" .. line.tag) end
        end
    end
    SetNames()
    OnLoaded(ids, SetNames)
    f:SetHeight(-top)
    return -top, f.lines
end

local function ListChoice()
    local values, order = ns.BisListChoices()
    return { type = "dropdown", text = "BiS List", values = values, order = order,
        tooltip = "Lists are shared by every character of your class. Each character keeps "
            .. "using the one picked here.",
        getValue = function() return select(3, ns.BisListChoices()) end,
        setValue = function(v) ns.SelectBisList(v) end }
end

local function NameListPrompt(title, text, save)
    ns.PromptText(title, text, 40, function(name)
        local ok, err = save(name)
        if not ok then ns.Print("BiS list not saved: " .. err .. ".") end
    end)
end

function ns.BuildQoLBiSSettingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Click a slot to pick its items from the ranking for your spec, or "
        .. "from every dungeon drop your class can use, best first: your BiS, then your 2nd, 3rd "
        .. "and so on. A slot shows a pick in a border of its quality colour and +N for the rest; the button beside it steps through your picks and is green for the one you wear. Alt+Shift-click any item (bags, links, loot) to "
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
            setValue = function(v) ns.SetBisSpec(v) end }
        or { type = "label", text = "" }
    ); y = y - h
    _, h = W:SectionHeader(parent, "LISTS", y); y = y - h
    _, h = W:DualRow(parent, y, ListChoice(),
        { type = "button", text = "New List", buttonText = "New", onClick = function()
            NameListPrompt("Name the new BiS list", "", ns.NewBisList)
        end }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = "Rename This List", buttonText = "Rename", onClick = function()
            NameListPrompt("Rename this BiS list", (List().name:gsub("||", "|")), ns.RenameBisList)
        end },
        { type = "button", text = "Delete This List", buttonText = "Delete", onClick = function()
            ns.Confirm(("Delete the BiS list %s? Every character of your class using it moves "
                .. "to another list."):format(List().name), ns.DeleteBisList)
        end }
    ); y = y - h
    _, h = W:Button(parent, "Import a BiS List", y, function()
        ns.PromptText("Paste a Naowh BiS list", "", 0, function(text) ns.ImportBisList(text) end)
    end); y = y - h
    _, h = W:Button(parent, "Export This List", y, function()
        ns.PromptText("Copy this to share your list", ns.ExportBisList(), 0, function() end)
    end); y = y - h
    return y
end

function ns.BuildQoLBiSPage(parent, y)
    -- The main window and the BiS window can each have the page built. A build the window
    -- has since thrown away is unparented, and its marks go with it.
    for page in pairs(wornMarks) do
        if not page:GetParent() then wornMarks[page] = nil end
    end
    wornMarks[parent] = {}
    y = y - select(2, ns.UI.Widgets:DualRow(parent, y, ListChoice(),
        { type = "button", text = "Fill Empty Slots", buttonText = "Fill", onClick = function()
            local spec = CurrentSpec()
            local n = ns.FillBisFromRanking()
            ns.Print(n > 0 and ("Filled %d empty slots from the %s ranking."):format(n, spec.name)
                or "The ranking has nothing new for your empty slots.")
        end }))
    local pad = ns.UI.CONTENT_PAD
    local width = parent:GetWidth() - pad * 2
    if width <= 0 then width = 910 end
    local gap = 48
    local panelH, lines = SourcePanel(parent, pad + DOLL_W + gap, y, width - DOLL_W - gap)
    Paperdoll(parent, pad, y - 8, wornMarks[parent], lines)
    return y - math.max(DOLL_H + 8, panelH)
end
