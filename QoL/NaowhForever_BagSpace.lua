-------------------------------------------------------------------------------
--  NaowhForever_BagSpace.lua -- the QoL Bag Space row: the cheapest things in your bags as
--  icons, to delete, sell or ignore.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local S = ns.QoLSettings

-- Called for every bag slot on every scan, so looked up once.
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local GAP = 6
local SCAN_DELAY = 0.2
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local STACK_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local FULL_COLOR = { r = 1, g = 0.25, b = 0.25 }
local LOW_COLOR = { r = 1, g = 0.6, b = 0.2 }
local FULL_SHOW = 20      -- seconds the row stays up after an "Inventory is full" error
local OUTLEVEL = 10       -- a consumable this many levels below you is flagged as old
local MERGE_STEPS = 60    -- a stack merge gives up after this many moves
local QUEST_CONFIRM = 5   -- seconds a second Ctrl-click has to delete an item a quest needs
local DIRECT_DELETE = 1   -- highest quality Ctrl-click deletes; better goes on the cursor

-- Never offered whatever they are worth: you need them, or they free no bag space.
local PROTECTED_CLASS = {
    [5] = true,     -- Reagent: class reagents such as Flash Powder and candles
    [6] = true,     -- Projectile: arrows and shot
    [11] = true,    -- Quiver
    [12] = true,    -- Quest
    [13] = true,    -- Key
}

local frame, unlocked, atMerchant, inCombat, pendingScan, missingInfo, junkFirst, oldFirst
local buttons = {}
local pool, picks = {}, {}  -- scan entries are reused; picks is the sorted view
local free, total, fullUntil = 0, 0, 0
local setItems, setsDirty = {}, true
local partial, stackSaves = {}, 0   -- itemID -> part-filled stacks in plain bags; slots merging frees
local merging, mergeSteps, mergeStartFree
local stackEntry = { stack = true }

local function On()
    return S.Get("enabled") and S.Get("bagSpace")
end

-- Stored in the profile, created on first write so the defaults table is never written into.
local function Ignored()
    local db = S.DB()
    db.bagSpaceIgnore = db.bagSpaceIgnore or {}
    return db.bagSpaceIgnore
end

local GOLD, SILVER, COPPER = "|cffffd700%dg|r", "|cffc7c7cf%ds|r", "|cffeda55f%dc|r"
local BLACK = { r = 0, g = 0, b = 0 }

-- The two largest coins that are not zero, coloured: "1g 20s", "35s", "12c".
local function Money(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return s > 0 and (GOLD .. " " .. SILVER):format(g, s) or GOLD:format(g) end
    if s > 0 then return c > 0 and (SILVER .. " " .. COPPER):format(s, c) or SILVER:format(s) end
    return COPPER:format(c)
end

-------------------------------------------------------------------------------
--  Picking
-------------------------------------------------------------------------------
local function RebuildSets()
    setsDirty = false
    wipe(setItems)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local ids = C_EquipmentSet.GetItemIDs(setID)
        if ids then
            for _, itemID in pairs(ids) do
                if type(itemID) == "number" and itemID > 0 then setItems[itemID] = true end
            end
        end
    end
end

-- Settings a scan reads for every slot, read once at its start.
local scanIgnored, scanProtect, scanAuction, scanMaxQuality

local function Protected(itemID, classID)
    if scanIgnored[itemID] then return true end
    if not scanProtect then return false end
    if PROTECTED_CLASS[classID] or setItems[itemID] then return true end
    return ns.IsBisItem and ns.IsBisItem(itemID) and true or false
end

-- One of the item at the auction house: the last Scan Prices, else TradeSkillMaster, else nil.
local function AuctionEach(itemID, link)
    local ah = ns.AuctionPrice and ns.AuctionPrice(itemID)
    if not ah and TSM_API and TSM_API.GetCustomPriceValue then
        local ok, value = pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", TSM_API.ToItemString(link))
        if ok then ah = value end
    end
    return ah
end

-- What the stack would fetch: its vendor price, or its auction price when that is higher, so
-- an item worth listing sorts behind ones only a vendor wants.
local function StackValue(itemID, link, vendor, count)
    local each = vendor
    if scanAuction then
        local ah = AuctionEach(itemID, link)
        if ah and ah > each then each = ah end
    end
    return each * count
end

-- Items an unfinished quest in your log still asks for, by item name: "Okra" -> the quest and
-- how many you have of how many. Rebuilt only when the quest log changes, and pooled.
local questNeeds, questDirty = {}, true
local needPool, needsUsed = {}, 0

local function NoteNeed(name, title, have, need)
    needsUsed = needsUsed + 1
    local n = needPool[needsUsed] or {}
    needPool[needsUsed] = n
    n.title, n.have, n.need = title, have, need
    questNeeds[name] = n
end

local function RebuildQuestNeeds()
    questDirty = false
    wipe(questNeeds)
    needsUsed = 0
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for _, o in ipairs(objectives) do
                    if o.type == "item" and not o.finished and o.text then
                        -- "Okra: 1/3", or "1/3 Okra" in clients that put the count first.
                        local name = o.text:match("^(.-):%s*%d+%s*/%s*%d+")
                            or o.text:match("^%d+%s*/%s*%d+%s+(.+)$")
                        if name then NoteNeed(name, info.title, o.numFulfilled or 0, o.numRequired or 0) end
                    end
                end
            end
        end
    end
end

local function Cheaper(a, b)
    -- Anything a quest still needs goes last, whatever it is worth.
    if (a.quest ~= nil) ~= (b.quest ~= nil) then return b.quest ~= nil end
    if junkFirst and (a.quality == 0) ~= (b.quality == 0) then return a.quality == 0 end
    if oldFirst and a.old ~= b.old then return a.old end
    if a.value ~= b.value then return a.value < b.value end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Part-filled stacks of one item, by slot. Merging them frees every slot beyond what the
-- total needs; protected items count too, since stacking loses nothing. The lists and slot
-- records are pooled: a scan runs after every loot, and must not leave tables behind.
local listPool, listsUsed = {}, 0
local slotPool, slotsUsed = {}, 0

local function NotePartial(bag, slot, itemID, count, maxStack)
    if not maxStack or maxStack <= 1 or count >= maxStack then return end
    local list = partial[itemID]
    if not list then
        listsUsed = listsUsed + 1
        list = listPool[listsUsed] or {}
        listPool[listsUsed] = list
        wipe(list)
        list.total, list.max = 0, maxStack
        partial[itemID] = list
    end
    slotsUsed = slotsUsed + 1
    local rec = slotPool[slotsUsed] or {}
    slotPool[slotsUsed] = rec
    rec.bag, rec.slot, rec.count = bag, slot, count
    list[#list + 1] = rec
    list.total = list.total + count
end

local function CountStackSaves()
    stackSaves = 0
    for _, list in pairs(partial) do
        if #list > 1 then
            stackSaves = stackSaves + #list - math.ceil(list.total / list.max)
        end
    end
end

local anyLocked

-- Plain bags only: a quiver, soul bag or profession bag holds its own kind of item, and
-- emptying one frees nothing for the rest of your loot.
local function Scan()
    for i = #picks, 1, -1 do picks[i] = nil end
    wipe(partial)
    listsUsed, slotsUsed = 0, 0
    free, total, missingInfo, anyLocked = 0, 0, false, false
    if setsDirty then RebuildSets() end
    if questDirty then RebuildQuestNeeds() end
    scanIgnored, scanProtect = Ignored(), S.Get("bagSpaceProtect")
    scanAuction, scanMaxQuality = S.Get("bagSpaceAuction"), S.Get("bagSpaceMaxQuality")
    local level = UnitLevel("player")
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local n = 0
    for bag = BACKPACK_CONTAINER, lastBag do
        local freeSlots, family = GetContainerNumFreeSlots(bag)
        if family == 0 then
            local slots = GetContainerNumSlots(bag)
            free, total = free + (freeSlots or 0), total + slots
            for slot = 1, slots do
                local info = GetContainerItemInfo(bag, slot)
                if info and info.isLocked then anyLocked = true end
                if info and info.itemID and not info.isLocked then
                    local _, _, _, _, _, classID = GetItemInfoInstant(info.itemID)
                    local quality = info.quality or 1
                    local name, _, _, _, minLevel, _, _, maxStack, _, _, vendor = GetItemInfo(info.itemID)
                    if vendor == nil then
                        missingInfo = true
                    else
                        NotePartial(bag, slot, info.itemID, info.stackCount or 1, maxStack)
                        if vendor > 0 and quality <= scanMaxQuality and not Protected(info.itemID, classID) then
                            n = n + 1
                            local e = pool[n] or {}
                            pool[n] = e
                            e.bag, e.slot, e.itemID, e.link = bag, slot, info.itemID, info.hyperlink
                            e.icon, e.count, e.quality = info.iconFileID, info.stackCount or 1, quality
                            e.vendor = vendor
                            e.value = StackValue(info.itemID, info.hyperlink, vendor, e.count)
                            -- Food, drink and potions long outlevelled: classic junk that is not grey.
                            e.old = classID == 0 and (minLevel or 0) > 0 and level - minLevel >= OUTLEVEL
                            e.quest = questNeeds[name]
                            picks[n] = e
                        end
                    end
                end
            end
        end
    end
    CountStackSaves()
    junkFirst, oldFirst = S.Get("bagSpaceJunkFirst"), S.Get("bagSpaceOldFirst")
    table.sort(picks, Cheaper)
end

-------------------------------------------------------------------------------
--  Deleting, selling, ignoring
-------------------------------------------------------------------------------
local RequestScan, Update

-- The slot is read again right before acting: bags shift under a row that was drawn a
-- moment ago, and the item there now is the one that would go.
local function StillThere(p)
    local info = C_Container.GetContainerItemInfo(p.bag, p.slot)
    return info and info.itemID == p.itemID and (info.stackCount or 1) == p.count and not info.isLocked
end

local function Snapshot(e)
    return { bag = e.bag, slot = e.slot, itemID = e.itemID, link = e.link, count = e.count, value = e.value,
        quest = e.quest, quality = e.quality }
end

local function Label(p)
    return p.link .. (p.count > 1 and (" x" .. p.count) or "")
end

-- DeleteCursorItem is protected on Forever, so the delete itself is the game's: the item goes
-- on the cursor, and dropping it on the ground brings up Blizzard's own delete confirmation.
local function PickUp(p)
    if GetCursorInfo() then
        ns.Print("put down what you are holding first.")
        return
    end
    if not StillThere(p) then
        ns.Print("that item moved in your bags; the row has been refreshed.")
        RequestScan()
        return
    end
    C_Container.PickupContainerItem(p.bag, p.slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= p.itemID then
        ClearCursor()
        return
    end
    return true
end

local function QuestText(q)
    return ("%s (%d/%d)"):format(q.title or "a quest", q.have, q.need)
end

local function GroundHint(p)
    if p.quest then ns.Print(("careful: %s is needed for %s."):format(p.link, QuestText(p.quest))) end
    ns.Print(("%s (%s) is on your cursor: click the ground to delete it, or a bag slot to "
        .. "put it back."):format(Label(p), Money(p.value)))
end

-- A quest item takes a second Ctrl-click within a few seconds: a warning, not a popup, since
-- the game only lets the delete through straight from a click on the icon.
local armedItem, armedUntil = nil, 0

local function ConfirmQuestDelete(p)
    if not p.quest or (armedItem == p.itemID and GetTime() < armedUntil) then
        armedItem = nil
        return true
    end
    armedItem, armedUntil = p.itemID, GetTime() + QUEST_CONFIRM
    ns.Print(("%s is needed for %s. Ctrl-click it again within %d seconds to delete it anyway.")
        :format(p.link, QuestText(p.quest), QUEST_CONFIRM))
    return false
end

-- Straight from a click on the icon the game lets the delete through; from anywhere else
-- (a confirmation button, a key binding) it is blocked, so those only pick the item up.
-- DeleteCursorItem skips the game's confirmation, so Uncommon and better only go on the
-- cursor, where dropping them brings up the game's prompt (type DELETE for Rare and up).
local function Delete(p)
    if not PickUp(p) then return end
    if p.quality > DIRECT_DELETE then
        GroundHint(p)
        return
    end
    DeleteCursorItem()
    if GetCursorInfo() then
        GroundHint(p)
        return
    end
    ns.Print(("deleted %s (%s)."):format(Label(p), Money(p.value)))
end

local function Sell(p)
    if InCombatLockdown() or not StillThere(p) then return end
    C_Container.UseContainerItem(p.bag, p.slot)
end

-- Stored with the time it was ignored, so the list can show the newest first.
local function Ignore(p)
    Ignored()[p.itemID] = time()
    ns.Print(("%s is ignored and will not be offered again. Manage it under QoL > Loot > "
        .. "Bag Space > Ignore List."):format(p.link))
    RequestScan()
end

-------------------------------------------------------------------------------
--  Ignore list
-------------------------------------------------------------------------------
local LIST_W, LIST_H, LIST_ROW = 440, 500, 30
local listDimmer, listPanel
local FillList

-- Newest first. An entry without a time sorts last.
local function NewestFirst(a, b)
    if a.when ~= b.when then return a.when > b.when end
    return a.id < b.id
end

local function IgnoredByDate()
    local out = {}
    for itemID, when in pairs(Ignored()) do
        out[#out + 1] = { id = itemID, when = type(when) == "number" and when or 0 }
    end
    table.sort(out, NewestFirst)
    return out
end

local function Refill()
    if listDimmer and listDimmer:IsShown() then FillList() end
end

local function Unignore(id)
    Ignored()[id] = nil
    Refill()
    RequestScan()
end

-- An item dropped (or clicked) onto the drop zone is ignored and goes straight back to its bag.
local function IgnoreFromCursor()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    Ignored()[id] = time()
    Refill()
    RequestScan()
end

-- The X shows while the row is hovered. Moving onto the X still counts as the row.
local function RowLeave(row)
    if row:IsMouseOver() then return end
    row.hover:Hide()
    row.remove:Hide()
    GameTooltip:Hide()
end

local function NewListRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LIST_ROW)
    row:EnableMouse(true)
    row.hover = ns.Solid(row, "BACKGROUND", T.accent, 0.12)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.remove = ns.Button(row, "X", 22, 22, function() Unignore(row.id) end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.remove:HookScript("OnLeave", function() RowLeave(row) end)
    row.remove:Hide()
    row.when = ns.Font(row, 11, nil, T.muted)
    row.when:SetPoint("RIGHT", row, "RIGHT", -32, 0)
    row.count = ns.Font(row, 11, nil, T.muted)
    row.count:SetPoint("RIGHT", row.when, "LEFT", -12, 0)
    row.text = ns.Font(row, 12, nil)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        self.remove:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", RowLeave)
    return row
end

local function Note(content, text)
    local note = UI.KeepFont(content, "note", 12, nil, T.muted)
    note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
    note:SetWidth(LIST_W - 62)
    note:SetJustifyH("LEFT")
    note:SetText(text)
end

function FillList()
    local content = listPanel.scroll.content
    UI.BeginReusableRows(content)
    local items = IgnoredByDate()
    local filter = strtrim(listPanel.search:GetText()):lower()
    listPanel.head:SetText(("Bag Space: Ignored Items (%d)"):format(#items))
    local y, shown = 0, 0
    for _, entry in ipairs(items) do
        local id = entry.id
        local name, _, quality = C_Item.GetItemInfo(id)
        if filter == "" or (name and name:lower():find(filter, 1, true)) then
            local row = UI.Keep(content, "ignoreRow", NewListRow)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            row.id = id
            row.hover:Hide()
            row.remove:Hide()
            row.icon:SetTexture(C_Item.GetItemIconByID(id))
            if name then
                local c = ITEM_QUALITY_COLORS[quality]
                row.text:SetText((c and c.hex or "|cffffffff") .. name .. "|r")
            else
                -- Not cached yet: named once the item data arrives.
                row.text:SetText("Item " .. id)
                Item:CreateFromItemID(id):ContinueOnItemLoad(Refill)
            end
            local carried = C_Item.GetItemCount(id)
            row.count:SetText(carried > 0 and ("x" .. carried) or "")
            row.when:SetText(entry.when > 0 and date("%d %b", entry.when) or "")
            y = y - LIST_ROW
            shown = shown + 1
        end
    end
    if #items == 0 then
        Note(content, "Nothing ignored yet. Middle-click an icon on the Bag Space row, or drop "
            .. "an item below.")
        y = y - LIST_ROW
    elseif shown == 0 then
        Note(content, "No ignored item matches your search.")
        y = y - LIST_ROW
    end
    content:SetHeight(-y)
end

local function NewSearchBox(parent)
    local box = ns.NewEditBox(parent)
    box.hint = ns.Font(box, 12, nil, T.muted)
    box.hint:SetPoint("LEFT", box, "LEFT", 8, 0)
    box.hint:SetText("Search")
    box:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        if listPanel then FillList() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function NewDropZone(parent)
    local zone = CreateFrame("Button", nil, parent)
    zone:SetHeight(34)
    ns.Solid(zone, "BACKGROUND", T.bg, 1):SetAllPoints()
    zone.border = ns.Border(zone)
    zone.text = ns.Font(zone, 12, nil, T.muted)
    zone.text:SetPoint("CENTER")
    zone.text:SetText("Drop an item here to ignore it")
    zone:SetScript("OnReceiveDrag", IgnoreFromCursor)
    zone:SetScript("OnClick", IgnoreFromCursor)
    -- Lights up while an item is held over it, so the drop target is obvious.
    zone:SetScript("OnEnter", function(self)
        if GetCursorInfo() == "item" then self.border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1) end
    end)
    zone:SetScript("OnLeave", function(self) self.border:SetColor(T.line.r, T.line.g, T.line.b, 1) end)
    return zone
end

function ns.ShowBagSpaceIgnoreList()
    local dimmer, panel = ns.MakeModal(LIST_W, LIST_H, "bagSpaceIgnore")
    listDimmer, listPanel = dimmer, panel
    panel.head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    panel.head:SetPoint("TOP", 0, -16)
    panel.scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        sf.content = CreateFrame("Frame", nil, sf)
        -- Sized off the panel: the scroll frame reads 0 wide until a layout pass has run.
        sf.content:SetSize(LIST_W - 62, 1)
        sf:SetScrollChild(sf.content)
        return sf
    end)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -80)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 100)
    panel.scroll:SetVerticalScroll(0)
    panel.search = UI.Keep(panel, "search", NewSearchBox)
    panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -44)
    panel.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -44)
    panel.search:SetHeight(24)
    panel.search:SetText("")
    panel.drop = UI.Keep(panel, "drop", NewDropZone)
    panel.drop:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 54)
    panel.drop:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 54)
    UI.KeepButton(panel, "clear", "Clear All", 100, 26, function()
        ns.Confirm("Offer every item you ignored again?", function()
            wipe(Ignored())
            Refill()
            RequestScan()
        end)
    end):SetPoint("BOTTOM", panel, "BOTTOM", -56, 16)
    UI.KeepButton(panel, "done", "Done", 100, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 56, 16)
    FillList()
    dimmer:Show()
end

-- Stacking: one move per bag update. The server locks both slots until a move lands, so the
-- next move waits for BAG_UPDATE_DELAYED rather than racing the lock.
local function StopMerge(message)
    merging = false
    if message then ns.Print(message) end
    RequestScan()
end

local function Smaller(a, b)
    return a.count < b.count
end

local function NextMove()
    for _, list in pairs(partial) do
        if #list > 1 then
            table.sort(list, Smaller)
            -- Smallest into the fullest one that still has room.
            local src = list[1]
            for i = #list, 2, -1 do
                local dst = list[i]
                local room = list.max - dst.count
                if room > 0 then return src, dst, math.min(room, src.count) end
            end
        end
    end
end

local function MergeStep()
    if not merging then return end
    if InCombatLockdown() or GetCursorInfo() then
        return StopMerge("stacking stopped: put down what you are holding, and wait for combat to end.")
    end
    mergeSteps = mergeSteps + 1
    if mergeSteps == 1 then mergeStartFree = free end
    local src, dst, amount = NextMove()
    -- A move still landing hides its slots from the scan; wait for them rather than stop.
    if not src and anyLocked and mergeSteps <= MERGE_STEPS then return end
    if not src or mergeSteps > MERGE_STEPS then
        local freed = free - mergeStartFree
        if freed <= 0 then return StopMerge() end
        return StopMerge(("stacked your bags: %d slot%s freed."):format(freed, freed == 1 and "" or "s"))
    end
    if amount < src.count then
        C_Container.SplitContainerItem(src.bag, src.slot, amount)
    else
        C_Container.PickupContainerItem(src.bag, src.slot)
    end
    C_Container.PickupContainerItem(dst.bag, dst.slot)
    -- Anything left on the cursor goes back where it came from.
    if GetCursorInfo() then C_Container.PickupContainerItem(src.bag, src.slot) end
end

-- The first move runs off a fresh scan: bags may have changed since the row was drawn.
local function StartMerge()
    if merging or InCombatLockdown() then return end
    if GetCursorInfo() then
        ns.Print("put down what you are holding first.")
        return
    end
    merging, mergeSteps = true, 0
    Update()
end

-- Pick up the cheapest item, for the key binding (Bindings.xml).
BINDING_NAME_NAOWHFOREVER_BAGSPACE_PICKUP = "Pick Up Cheapest Item"

function NaowhForever_BagSpacePickUp()
    if not On() then return end
    -- The row's buttons point into the scan's pooled entries, so a scan redraws the row too.
    Update()
    if not picks[1] then return end
    local p = Snapshot(picks[1])
    if PickUp(p) then GroundHint(p) end
end

-------------------------------------------------------------------------------
--  Row
-------------------------------------------------------------------------------
local function OnClick(self, button)
    local e = self.pick
    if not e or unlocked then return end
    if e.stack then
        if button == "LeftButton" then StartMerge() end
        return
    end
    local p = Snapshot(e)
    -- ChatFrameUtil, not ChatEdit_InsertLink: that is a deprecated shim Forever does not load.
    if IsModifiedClick("CHATLINK") then
        ChatFrameUtil.InsertLink(p.link)
    elseif button == "MiddleButton" then
        Ignore(p)
    elseif IsControlKeyDown() then
        if ConfirmQuestDelete(p) then Delete(p) end
    elseif atMerchant then
        Sell(p)
    end
end

-- The whole stack goes, so the total is what is lost; the split says how it adds up.
local function Worth(each, count)
    if count <= 1 then return Money(each) end
    return Money(each * count) .. ("  " .. ns.Color("muted", "(%s each x%d)")):format(Money(each), count)
end

local function OnEnter(self)
    local e = self.pick
    if not e or unlocked then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if e.stack then
        GameTooltip:SetText("Stack Your Bags")
        GameTooltip:AddLine(("Combines part-filled stacks of the same item, freeing %d slot%s. "
            .. "Nothing is deleted."):format(stackSaves, stackSaves == 1 and "" or "s"), 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.Color("accent", "Click") .. "  stack now", 1, 1, 1)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetBagItem(e.bag, e.slot)
    -- Each added line can be turned off; the quest warning always shows, since it is what
    -- stops a needed item going by mistake.
    local vendor, auction = S.Get("bagSpaceTipVendor"), S.Get("bagSpaceTipAuction")
    local deleteHint, ignoreHint = S.Get("bagSpaceTipDelete"), S.Get("bagSpaceTipIgnore")
    if vendor or auction or deleteHint or ignoreHint or e.quest then GameTooltip:AddLine(" ") end
    if vendor then GameTooltip:AddDoubleLine("Vendor", Worth(e.vendor, e.count), 1, 1, 1, 1, 1, 1) end
    if auction then
        local ah = AuctionEach(e.itemID, e.link)
        GameTooltip:AddDoubleLine("Auction", ah and Worth(ah, e.count) or ns.Color("muted", "unknown"), 1, 1, 1, 1, 1, 1)
    end
    if e.quest then GameTooltip:AddLine("Needed for " .. QuestText(e.quest), 1, 0.82, 0) end
    if deleteHint then
        if e.quest then
            GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  twice to delete", 1, 1, 1)
        elseif e.quality > DIRECT_DELETE then
            GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  pick up to delete", 1, 1, 1)
        else
            GameTooltip:AddLine(ns.Color("accent", "Ctrl-click") .. "  delete now", 1, 1, 1)
        end
        if atMerchant then GameTooltip:AddLine(ns.Color("accent", "Click") .. "  sell", 1, 1, 1) end
    end
    if ignoreHint then GameTooltip:AddLine(ns.Color("accent", "Middle-click") .. "  ignore this item", 1, 1, 1) end
    GameTooltip:Show()
end

local function CreateButton(i)
    local b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    -- A quality-coloured frame, so a grey item reads apart from a white one.
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(b.icon, 1, b)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = ns.Font(b, 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.price = ns.Font(b, 11, "OUTLINE")
    b.price:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b.old = ns.Font(b, 9, "OUTLINE", { r = 0.95, g = 0.6, b = 0.2 })
    b.old:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.old:SetText("OLD")
    b.quest = ns.Font(b, 13, "OUTLINE", { r = 1, g = 0.82, b = 0 })
    b.quest:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -1)
    b.quest:SetText("!")
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    buttons[i] = b
    return b
end

local STEP = { RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

local function Layout(shown)
    local size = S.Get("bagSpaceSize")
    local dir = STEP[S.Get("bagSpaceGrow")] or STEP.RIGHT
    local step = size + GAP
    frame:SetSize(size, size)
    for i = 1, shown do
        local b = buttons[i] or CreateButton(i)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("CENTER", frame, "CENTER", (i - 1) * step * dir[1], (i - 1) * step * dir[2])
        b:Show()
    end
    for i = shown + 1, #buttons do buttons[i]:Hide() end
    -- The counter sits over the row's left end: the first icon, or the last one when the row
    -- grows left or up.
    local back = dir[1] < 0 or dir[2] > 0
    local lead = back and buttons[math.max(shown, 1)] or buttons[1]
    frame.free:ClearAllPoints()
    if lead then frame.free:SetPoint("BOTTOMLEFT", lead, "TOPLEFT", 0, 3) end
    local first, last = buttons[1], buttons[math.max(shown, 1)]
    frame.mover:ClearAllPoints()
    if first and last then
        frame.mover:SetPoint("TOPLEFT", back and last or first, "TOPLEFT")
        frame.mover:SetPoint("BOTTOMRIGHT", back and first or last, "BOTTOMRIGHT")
    else
        frame.mover:SetAllPoints()
    end
end

local function Fill(b, e, icon, price, count, quality, old, quest)
    b.pick = e
    b.icon:SetTexture(icon)
    b.price:SetText(price)
    b.count:SetText(count and count > 1 and count or "")
    b.old:SetShown(old == true)
    b.quest:SetShown(quest ~= nil)
    -- Common items take the house 1px black border; every other quality shows its colour.
    local c = quality ~= 1 and ITEM_QUALITY_COLORS[quality] or BLACK
    b.edge:SetColorTexture(c.r, c.g, c.b, 1)
end

-- Built on first use, once the theme is applied, then reused: a scan fills this every time.
local stackLabel

local function FillStack(b)
    b.pick = stackEntry
    b.icon:SetTexture(STACK_ICON)
    stackLabel = stackLabel or ns.Color("accent", "Stack")
    b.price:SetText(stackLabel)
    b.count:SetText("+" .. stackSaves)
    b.old:Hide()
    b.quest:Hide()
    b.edge:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
end

-- Free out of total over the row, orange under a tenth free and red when full.
local function ShowFree(count, slots)
    local f = frame.free
    f:SetShown(S.Get("bagSpaceShowFree"))
    local c = count == 0 and FULL_COLOR or count < slots * 0.1 and LOW_COLOR or T.fg
    f.text:SetTextColor(c.r, c.g, c.b, 1)
    f.text:SetText(("%d/%d"):format(count, slots))
    f:SetSize(16 + f.text:GetStringWidth(), 14)
end

-- Hovering the counter: each plain bag's free and total slots.
local function FreeTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Bag Space")
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local special = false
    for bag = BACKPACK_CONTAINER, lastBag do
        local slots = GetContainerNumSlots(bag)
        if slots > 0 then
            local freeSlots, family = GetContainerNumFreeSlots(bag)
            if family == 0 then
                local name = C_Container.GetBagName and C_Container.GetBagName(bag) or ("Bag " .. bag)
                GameTooltip:AddDoubleLine(name, ("%d/%d free"):format(freeSlots or 0, slots), 1, 1, 1, 1, 1, 1)
            else
                special = true
            end
        end
    end
    if special then
        GameTooltip:AddLine("Quivers and profession bags are not counted.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function NewFreeCounter(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(60, 14)
    f:EnableMouse(true)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(12, 12)
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.icon:SetTexture(BAG_ICON)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = ns.Font(f, 11, "OUTLINE")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f:SetScript("OnEnter", FreeTooltip)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

local function Render()
    -- Unlock Mode shows your own items, so the row looks as it will where you place it; the
    -- slots with none get a sample, so the whole row can still be placed. Clicks do nothing
    -- while unlocked.
    if unlocked then
        local n = S.Get("bagSpaceCount")
        Layout(n)
        for i = 1, n do
            local e = picks[i]
            if e then
                Fill(buttons[i], nil, e.icon, Money(e.value), e.count, e.quality, e.old, e.quest)
            else
                Fill(buttons[i], nil, SAMPLE_ICON, Money(12 * i), nil, 1, i == 1)
            end
        end
        if total > 0 then ShowFree(free, total) else ShowFree(28, 96) end
        frame:Show()
        return
    end
    -- An "Inventory is full" error brings the row up for a while whatever the threshold says.
    local below = S.Get("bagSpaceFreeBelow")
    local enoughRoom = below > 0 and free >= below and GetTime() >= fullUntil
    local offerStack = S.Get("bagSpaceStack") and stackSaves > 0 and not merging
    local shown = math.min(#picks, S.Get("bagSpaceCount"))
    if (shown == 0 and not offerStack) or (inCombat and S.Get("bagSpaceHideCombat")) or enoughRoom then
        frame:Hide()
        return
    end
    local first = offerStack and 1 or 0
    Layout(shown + first)
    if offerStack then FillStack(buttons[1]) end
    for i = 1, shown do
        local e = picks[i]
        Fill(buttons[i + first], e, e.icon, Money(e.value), e.count, e.quality, e.old, e.quest)
    end
    ShowFree(free, total)
    frame:Show()
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

function Update()
    pendingScan = false
    if not (frame and On()) then return end
    Scan()
    -- Item data arrives in the background on first sight; a rescan waits for it only while
    -- something is still missing.
    if missingInfo then
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    if merging then
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        MergeStep()
    else
        events:UnregisterEvent("ITEM_LOCK_CHANGED")
    end
    Render()
end

function RequestScan()
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(SCAN_DELAY, Update)
end

events:SetScript("OnEvent", function(_, event, _, message)
    if event == "UI_ERROR_MESSAGE" then
        if message ~= ERR_INV_FULL and message ~= ERR_BAG_FULL then return end
        fullUntil = GetTime() + FULL_SHOW
        C_Timer.After(FULL_SHOW + 0.1, RequestScan)
    elseif event == "MERCHANT_SHOW" then
        atMerchant = true
    elseif event == "MERCHANT_CLOSED" then
        atMerchant = false
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        setsDirty = true
    elseif event == "QUEST_LOG_UPDATE" then
        questDirty = true
    end
    RequestScan()
end)

local function Place()
    local pos = S.Get("bagSpacePos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
end

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", "NaowhForeverBagSpace", UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame.mover = UI.AttachMover(frame, "Bag Space", function(pos) S.Set("bagSpacePos", pos) end, "QoL/Loot & Items", "QoL/Loot & Items:bagSpace")
        frame.free = NewFreeCounter(frame)
    end
    Place()
    frame.mover:SetShown(unlocked == true)
    inCombat = UnitAffectingCombat("player")
    atMerchant = MerchantFrame and MerchantFrame:IsShown()
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Only needed while a threshold can hide the row.
    if S.Get("bagSpaceOnFull") and S.Get("bagSpaceFreeBelow") > 0 then
        events:RegisterEvent("UI_ERROR_MESSAGE")
    end
    setsDirty, questDirty = true, true
    Update()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^bagSpace") and key ~= "bagSpacePos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group
local QUALITY = { { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }, { 0, 1, 2, 3, 4 } }
local DIRECTION = { { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }, { "RIGHT", "LEFT", "UP", "DOWN" } }

local function ShowIgnoreList()
    if ns.ShowBagSpaceIgnoreList then ns.ShowBagSpaceIgnoreList() end
end

local function BagSpaceSummary(store)
    return ("%d items, %s and below"):format(store.Get("bagSpaceCount"),
        QUALITY[1][store.Get("bagSpaceMaxQuality")] or "Common")
end

Settings.Page("QoL/Loot & Items", S):Card({
    id = "bagSpace", name = "Bag Space", order = 60, switch = "bagSpace",
    help = "The cheapest items in your bags as a row of icons, cheapest first. Ctrl-click an icon "
        .. "to delete it, or click it to sell it while a vendor is open. Middle-click to ignore "
        .. "an item. "
        .. "Move it in Unlock Mode.",
    summary = BagSpaceSummary,
    rows = {
        Group("Offered"),
        { key = "bagSpaceCount", label = "Items Shown", slider = { 1, 8, 1 } },
        { key = "bagSpaceMaxQuality", label = "Highest Quality Offered", choice = QUALITY,
          help = "Items above this quality are never offered." },
        { key = "bagSpaceJunkFirst", label = "Grey Items First", toggle = true,
          help = "Grey items come before everything else, whatever they sell for." },
        { key = "bagSpaceOldFirst", label = "Outlevelled Food & Potions First", toggle = true,
          help = "Food, drink and potions 10 or more levels below you are marked OLD; this puts them "
              .. "first." },
        { key = "bagSpaceAuction", label = "Count Auction Prices", toggle = true,
          help = "An item worth more at the auction house than at a vendor is valued at its auction "
              .. "price, from your last Scan Prices or TradeSkillMaster." },
        { key = "bagSpaceProtect", label = "Protect Needed Items", toggle = true,
          help = "Never offers reagents, ammo, quest items, keys, items in an equipment set or items "
              .. "on your BiS list." },
        { label = "Ignore List", button = ShowIgnoreList, buttonText = "Ignore List", always = true,
          help = "Items Bag Space never offers. Search for one, drag one in, or middle-click an icon "
              .. "on the row." },
        Group("Showing"),
        { key = "bagSpaceFreeBelow", label = "Only With Free Slots Below", slider = { 0, 30, 1 },
          help = "Shows the row only once your bags are this full. 0 shows it all the time." },
        { key = "bagSpaceOnFull", label = "Show When Bags Are Full", toggle = true,
          help = "An \"Inventory is full\" error brings the row up for 20 seconds, even with more free "
              .. "slots than the threshold above." },
        { key = "bagSpaceHideCombat", label = "Hide in Combat", toggle = true },
        { key = "bagSpaceShowFree", label = "Show Free Slots", toggle = true,
          help = "Free bag slots out of your total, above the row. Hover it for each bag." },
        { key = "bagSpaceStack", label = "Offer to Stack", toggle = true,
          help = "A Stack button at the start of the row when part-filled stacks of the same item can "
              .. "be combined, with how many slots it frees. Nothing is deleted." },
        { label = "Pick Up Cheapest Item", binding = "NAOWHFOREVER_BAGSPACE_PICKUP",
          help = "Puts the cheapest item on your cursor, to drop or sell." },
        Group("Look"),
        { key = "bagSpaceSize", label = "Icon Size", slider = { 24, 56, 1 } },
        { key = "bagSpaceGrow", label = "Direction", choice = DIRECTION },
        Group("Tooltips"),
        { key = "bagSpaceTipVendor", label = "Tooltip: Vendor Price", toggle = true,
          help = "What the whole stack sells for at a vendor, and each item's price." },
        { key = "bagSpaceTipAuction", label = "Tooltip: Auction Price", toggle = true,
          help = "What the stack fetches at the auction house, from your last Scan Prices or "
              .. "TradeSkillMaster." },
        { key = "bagSpaceTipDelete", label = "Tooltip: Delete Hint", toggle = true,
          help = "The Ctrl-click line, and Click to sell while a vendor is open." },
        { key = "bagSpaceTipIgnore", label = "Tooltip: Ignore Hint", toggle = true, help = "The Middle-click line." },
    },
})
