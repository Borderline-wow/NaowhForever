-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_BiS.lua -- the QoL BiS list: a best-in-slot list per character,
--  built by Alt+Shift-clicking items or by item ID, shared as an import string, and shown
--  on item tooltips, in the loot feed and as an alert when a listed item drops.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings

local PREFIX = "!NBIS1!"
local MAX_ITEMS = 300
local TAG = "|cff0091edNaowh BiS|r"

local lookup   -- itemID -> true, rebuilt when the list changes

local function On()
    return S.Get("enabled") and S.Get("bis")
end

-- One list per character, kept in the account store: personal, so it never travels in an
-- exported profile.
local function List()
    local account = ns.AccountSettings()
    account.bis = account.bis or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    account.bis[key] = account.bis[key] or { name = "My BiS", items = {} }
    return account.bis[key]
end

local function Rebuild()
    lookup = {}
    for _, id in ipairs(List().items) do lookup[id] = true end
end

function ns.IsBisItem(itemID)
    if not (On() and itemID) then return false end
    if not lookup then Rebuild() end
    return lookup[itemID] == true
end

local function IDFrom(value)
    if type(value) == "number" then return value end
    return tonumber(tostring(value):match("item:(%d+)") or tostring(value):match("^%s*(%d+)%s*$"))
end

local function Equippable(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

local function Name(itemID)
    return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

local function Changed()
    Rebuild()
    if ns.UI.RefreshPage then ns.UI:RefreshPage(true) end
end

function ns.AddBisItem(value)
    local id = IDFrom(value)
    if not (id and Equippable(id)) then
        ns.Print("That is not an item you can equip.")
        return
    end
    if ns.IsBisItem(id) then return end
    local items = List().items
    if #items >= MAX_ITEMS then return end
    items[#items + 1] = id
    Changed()
    ns.Print("Added " .. Name(id) .. " to your BiS list.")
end

function ns.RemoveBisItem(itemID)
    local items = List().items
    for i = #items, 1, -1 do
        if items[i] == itemID then table.remove(items, i) end
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
    return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({ v = 1, name = list.name, items = list.items })))
end

-- Parsed as data, never run: only a name and a bounded list of item numbers are kept.
local function Decode(text)
    local LS, LD = Codec()
    local body = type(text) == "string" and text:match("^%s*" .. PREFIX:gsub("!", "%%!") .. "(%S+)%s*$")
    local packed = body and LD:DecodeForPrint(body)
    local raw = packed and LD:DecompressDeflate(packed)
    if not raw then return end
    local ok, data = LS:Deserialize(raw)
    if not (ok and type(data) == "table" and data.v == 1 and type(data.items) == "table") then return end
    local items, seen = {}, {}
    for _, id in ipairs(data.items) do
        if type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] and #items < MAX_ITEMS then
            items[#items + 1] = id
            seen[id] = true
        end
    end
    local name = type(data.name) == "string" and data.name:sub(1, 40) or "Imported BiS"
    return name, items
end

-- Also the entry point for a curated list delivered in a profile pack.
function ns.ImportBisList(text, quiet)
    local name, items = Decode(text)
    if not name then
        ns.Print("That is not a Naowh BiS list.")
        return false
    end
    local function Apply()
        local list = List()
        list.name, list.items = name, items
        Changed()
        ns.Print(("Imported %s: %d items."):format(name, #items))
    end
    if quiet then Apply() else
        ns.Confirm(("Replace your BiS list with %s (%d items)?"):format(name, #items), Apply)
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

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if not (On() and S.Get("bisLootAlert")) then return end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and not (issecretvalue and issecretvalue(link)) and ns.IsBisItem(IDFrom(link)) then
            ns.Print(TAG .. " drop: " .. link)
            PlaySound(SOUNDKIT.RAID_WARNING)
        end
    end
end)
events:RegisterEvent("LOOT_READY")

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
function ns.BuildQoLBiSPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    local list = List()
    _, h = W:Note(parent, "Alt+Shift-click any item (bags, links, the Dungeon Journal, loot) to "
        .. "add it to your BiS list, or again to take it off. Listed items say so on their "
        .. "tooltip, are tagged in the loot feed, and ring an alert when they drop.", y); y = y - h

    _, h = W:SectionHeader(parent, "BIS LIST" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bis", "BiS List", "Tracks your list and marks the items on it."),
        S.Toggle("bisTooltip", "Show on Tooltips", "A Naowh BiS line on listed items.", "bis")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("bisLootAlert", "Drop Alert",
            "A chat line and a sound when a listed item is in the loot window.", "bis"),
        { type = "label", text = "" }
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

    -- Grouped by the slot each item goes in.
    local bySlot, slots = {}, {}
    for _, id in ipairs(list.items) do
        C_Item.RequestLoadItemDataByID(id)
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
        local slot = _G[equipLoc] or equipLoc or "?"
        if not bySlot[slot] then
            bySlot[slot] = {}
            slots[#slots + 1] = slot
        end
        table.insert(bySlot[slot], id)
    end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        _, h = W:SectionHeader(parent, slot:upper(), y); y = y - h
        for _, id in ipairs(bySlot[slot]) do
            _, h = W:Button(parent, "Remove " .. Name(id), y, function() ns.RemoveBisItem(id) end); y = y - h
        end
    end
    return y
end
