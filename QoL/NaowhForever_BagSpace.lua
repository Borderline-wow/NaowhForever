-------------------------------------------------------------------------------
--  NaowhForever_BagSpace.lua -- the QoL Bag Space row: the cheapest things in your bags as
--  icons on a small card, under your free slots, to delete, sell or ignore. Its Background is the
--  card, a soft fade or none (Parts.HudBackdrop); the icons keep their own edges in each. Its
--  Font Size is the header's; the bag, the header line and the prices scale with it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local S = ns.QoLSettings
local Parts, St = ns.Shared.Parts, ns.Shared.Style
local Coins = Parts.Coins

-- Called for every bag slot on every scan, so looked up once.
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local SCAN_DELAY = 0.2
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SAMPLE_PRICE = 12   -- Unlock Mode's sample icons: this many copper, times their place
local SAMPLE_FREE, SAMPLE_SLOTS = 28, 96   -- and its free count before the first scan
local FULL_SHOW = 20      -- seconds the row stays up after an "Inventory is full" error
local OUTLEVEL = 10       -- a consumable this many levels below you is flagged as old
local MERGE_STEPS = 60    -- a stack merge gives up after this many moves
local QUEST_CONFIRM = 5   -- seconds a second Ctrl-click has to delete an item a quest needs
local EDGE_COLORED = 2     -- Uncommon: from here up an item's edge shows its quality color
local DIRECT_DELETE = 1   -- highest quality Ctrl-click deletes; better goes on the cursor

-- The card: the house panel (the theme's background, a 1px black edge) round a slim header
-- (the bag, free slots out of your total, Scrap Marker's "+N", the Stack button) over a cell
-- per item (its icon, its marks, its price under it).
local BORDER_RGB = St.BORDER_RGB
local CARD_ALPHA = 0.85   -- the panel's fill, as the Flight Timer's card
local PAD = 6             -- the card's edge to what is in it
local GAP = 6             -- between cells
local HEAD_H = 16         -- the header line, and the Stack button's height
local HEAD_GAP = 5        -- under the header
local HEAD_SPACE = 12     -- at least this between the free count and the Stack button
local HEAD_SIZE = 12      -- the header's text at the default Font Size, which the sizes here are for
local HEAD_ICON = 12      -- the bag before it
local ICON_DROP = Parts.CARD_DROP   -- the bag lowered to the letters, as on a card
local TEXT_GAP = 4        -- between the header's words
local STACK_PAD = 8       -- the Stack button's label to its edges
local PRICE_SIZE = 10     -- the price under each icon: small and muted
local PRICE_H = 12
local PRICE_GAP = 3       -- an icon to its price
local PRICE_W = 32
local LOW_SHARE = 0.1     -- under this share of your slots free, the count turns orange
local QUEST_RGB = St.CARRIED_RGB    -- the game's quest gold
local FREE_TEXT = "free"
local OLD_TIP = ("Outlevelled: %d or more levels below you"):format(OUTLEVEL)
local TIP_ICON, TIP_ICON_TINTED = "|A:%s:0:0:0:%d|a ", "|A:%s:0:0:0:%d:%d:%d:%d|a "
local STACK_TEXT = "Stack +%d"

-- Never offered whatever they are worth: you need them, or they free no bag space.
local PROTECTED_CLASS = {
    [5] = true,     -- Reagent: class reagents such as Flash Powder and candles
    [6] = true,     -- Projectile: arrows and shot
    [11] = true,    -- Quiver
    [12] = true,    -- Quest
    [13] = true,    -- Key
}

local frame, unlocked, atMerchant, inCombat, pendingScan, missingInfo, junkFirst, oldFirst
local pool, picks = {}, {}  -- scan entries are reused; picks is the sorted view
local free, total, fullUntil = 0, 0, 0
local scrapSlots = 0   -- slots holding Scrap Marker's scrap, free after the next vendor
local setItems, setsDirty = {}, true
local partial, stackSaves = {}, 0   -- itemID -> part-filled stacks in plain bags; slots merging frees
local merging, mergeSteps, mergeStartFree

local function On()
    return S.Get("enabled") and S.Get("bagSpace")
end

-- Stored in the profile, created on first write so the defaults table is never written into.
local function Ignored()
    local db = S.DB()
    db.bagSpaceIgnore = db.bagSpaceIgnore or {}
    return db.bagSpaceIgnore
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
local scanIgnored, scanProtect, scanAuction, scanMaxQuality, scanScrap

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
    free, total, missingInfo, anyLocked, scrapSlots = 0, 0, false, false, 0
    if setsDirty then RebuildSets() end
    if questDirty then RebuildQuestNeeds() end
    scanIgnored, scanProtect = Ignored(), S.Get("bagSpaceProtect")
    scanAuction, scanMaxQuality = S.Get("bagSpaceAuction"), S.Get("bagSpaceMaxQuality")
    local scrapper = ns.ScrapMarker
    scanScrap = scrapper and scrapper.On() and scrapper.IsScrap or nil
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
                        local scrap = scanScrap ~= nil and vendor > 0 and scanScrap(info.itemID)
                        if scrap then scrapSlots = scrapSlots + 1 end
                        if vendor > 0 and quality <= scanMaxQuality
                            and not Protected(info.itemID, classID) then
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
        .. "put it back."):format(Label(p), Coins(p.value)))
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
    ns.Print(("deleted %s (%s)."):format(Label(p), Coins(p.value)))
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
--  The card
-------------------------------------------------------------------------------
local function OnClick(self, button)
    local e = self.pick
    if not e or unlocked then return end
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
    if count <= 1 then return Coins(each) end
    return Coins(each * count) .. ("  " .. ns.Color("muted", "(%s each x%d)")):format(Coins(each), count)
end

local oldLine, questMark

local function TipMarks()
    local c = St.WARN_RGB
    oldLine = TIP_ICON_TINTED:format(St.CLOCK_ATLAS, -Parts.TOOLTIP_DROP, c.r * 255, c.g * 255, c.b * 255) .. OLD_TIP
    questMark = TIP_ICON:format(St.QUEST_ATLAS, -Parts.TOOLTIP_DROP)
end

-- The lines Bag Space adds under an item's own tooltip; ah is its auction price each, if known.
-- Each can be turned off; the quest warning always shows, since it is what stops a needed item
-- going by mistake.
local function AddTipLines(e, ah)
    if not oldLine then TipMarks() end
    local vendor, auction = S.Get("bagSpaceTipVendor"), S.Get("bagSpaceTipAuction")
    local deleteHint, ignoreHint = S.Get("bagSpaceTipDelete"), S.Get("bagSpaceTipIgnore")
    if vendor or auction or deleteHint or ignoreHint or e.quest or e.old then GameTooltip:AddLine(" ") end
    if vendor then GameTooltip:AddDoubleLine("Vendor", Worth(e.vendor, e.count), 1, 1, 1, 1, 1, 1) end
    if auction then
        GameTooltip:AddDoubleLine("Auction", ah and Worth(ah, e.count) or ns.Color("muted", "unknown"), 1, 1, 1, 1, 1, 1)
    end
    if e.old then GameTooltip:AddLine(oldLine, St.WARN_RGB.r, St.WARN_RGB.g, St.WARN_RGB.b) end
    if e.quest then
        GameTooltip:AddLine(questMark .. "Needed for " .. QuestText(e.quest), QUEST_RGB.r, QUEST_RGB.g, QUEST_RGB.b)
    end
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
end

local function OnEnter(self)
    local e = self.pick
    if not e or unlocked then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetBagItem(e.bag, e.slot)
    AddTipLines(e, S.Get("bagSpaceTipAuction") and AuctionEach(e.itemID, e.link) or nil)
    GameTooltip:Show()
end

-- The Stack button: how many slots it frees is kept on it at each draw.
local function StackTip(self)
    local saves = self.saves or 0
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Stack Your Bags")
    GameTooltip:AddLine(("Combines part-filled stacks of the same item, freeing %d slot%s. "
        .. "Nothing is deleted."):format(saves, saves == 1 and "" or "s"), 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.Color("accent", "Click") .. "  stack now", 1, 1, 1)
    GameTooltip:Show()
end

local function StackClicked()
    if not unlocked then StartMerge() end
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
        GameTooltip:AddLine("Quivers and profession bags are not counted.", T.muted.r, T.muted.g, T.muted.b, true)
    end
    if scrapSlots > 0 then
        GameTooltip:AddLine(("%d more free after the next vendor sells your scrap."):format(scrapSlots),
            T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true)
    end
    GameTooltip:Show()
end

-- The header's left: the bag, "28/52" in its state's color, "free", and Scrap Marker's "+2".
-- With live, hovering it lists your bags.
local function NewFreeCounter(parent, live)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(HEAD_H)
    f.icon = Parts.Smooth(f:CreateTexture(nil, "ARTWORK"), St.BAG)
    f.icon:SetSize(HEAD_ICON, HEAD_ICON)
    f.icon:SetPoint("LEFT", 0, -ICON_DROP)
    f.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b)
    f.text = Parts.HudText(ns.Font(f, HEAD_SIZE))
    f.text:SetPoint("LEFT", HEAD_ICON + TEXT_GAP, 0)
    f.word = Parts.HudText(ns.Font(f, HEAD_SIZE, nil, T.muted))
    f.word:SetPoint("LEFT", f.text, "RIGHT", TEXT_GAP, 0)
    f.word:SetText(FREE_TEXT)
    f.scrap = Parts.HudText(ns.Font(f, HEAD_SIZE, nil, T.accentSoft))
    f.scrap:SetPoint("LEFT", f.word, "RIGHT", TEXT_GAP, 0)
    if live then
        f:EnableMouse(true)
        f:SetScript("OnEnter", FreeTooltip)
        f:SetScript("OnLeave", GameTooltip_Hide)
    end
    return f
end

-- view is where the first icon goes: Unlock Mode moves it and saves its place, so a place saved
-- before the card keeps the icons where they were. The card is drawn round the icons from it.
-- onClick (nil on the settings preview) acts on an icon, onEnter shows its tooltip and onStack
-- stacks; live: the real row, whose counter lists your bags on hover.
local function NewView(view, onClick, onEnter, onStack, live)
    local card = CreateFrame("Frame", nil, view)
    view.backdrop = Parts.HudBackdrop(card, { alpha = CARD_ALPHA })
    view.card = card
    view.free = NewFreeCounter(card, live)
    view.free:SetPoint("TOPLEFT", PAD, -PAD)
    view.stack = ns.AccentBorder(ns.Button(card, "Stack", HEAD_H, HEAD_H, onStack))
    view.stack:SetPoint("TOPRIGHT", -PAD, -PAD)
    view.stack:HookScript("OnEnter", StackTip)
    view.stack:HookScript("OnLeave", GameTooltip_Hide)
    view.stack:Hide()
    view.cells, view.onClick, view.onEnter = {}, onClick, onEnter
    return view
end

-- An item's cell: the house item icon (1px edge in its quality's color), the shared marks (the
-- stack count in the bottom-right over a shade), the outlevelled clock and the quest bang as corner
-- badges, and the price under it in its largest coin.
local function NewCell(view, i, size)
    local b = CreateFrame("Button", nil, view.card)
    local icon = Parts.ItemIcon(b, size)
    icon:SetAllPoints()
    b.icon, b.edge = icon.texture, icon.edge
    b.marks = Parts.ItemMarks(icon, size)
    b.old = Parts.ItemBadge(b.marks, "TOPLEFT", St.CLOCK_ATLAS, St.WARN_RGB)
    b.quest = Parts.ItemBadge(b.marks, "TOPRIGHT", St.QUEST_ATLAS)
    b.price = Parts.HudFont(ns.Font(b, PRICE_SIZE, nil, T.muted), view.font, view.priceSize, view.outline, view.shadow)
    b.price:SetPoint("TOP", b, "BOTTOM", 0, -PRICE_GAP)
    b.price:SetWordWrap(false)
    if view.onClick then
        b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
        b:SetScript("OnClick", view.onClick)
    end
    b:SetScript("OnEnter", view.onEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    view.cells[i] = b
    return b
end

-- Free out of total, orange under a tenth free and red when full. Returns the counter's width,
-- 0 while it is off.
local function ShowFree(view, count, slots, scrap)
    local f = view.free
    if not S.Get("bagSpaceShowFree") then
        f:Hide()
        return 0
    end
    local c = count == 0 and St.RED_RGB or count < slots * LOW_SHARE and St.WARN_RGB or T.fg
    f.text:SetTextColor(c.r, c.g, c.b, 1)
    f.text:SetText(Parts.Fraction(count, slots))
    local w = view.headIcon + TEXT_GAP + f.text:GetStringWidth() + TEXT_GAP + f.word:GetStringWidth()
    if scrap > 0 then
        f.scrap:SetText("+" .. scrap)
        w = w + TEXT_GAP + f.scrap:GetStringWidth()
    end
    f.scrap:SetShown(scrap > 0)
    w = math.ceil(w)
    f:SetWidth(w)
    f:Show()
    return w
end

-- The Stack button with the slots it frees, or none. Returns its width, 0 while hidden.
local function ShowStack(view, saves)
    local b = view.stack
    if saves <= 0 then
        b:Hide()
        return 0
    end
    ns.SetButtonText(b, STACK_TEXT:format(saves))
    local w = math.ceil(b.label:GetStringWidth()) + STACK_PAD * 2
    b:SetWidth(w)
    b.saves = saves
    b:Show()
    return w
end

local function Scaled(v, scale)
    return math.floor(v * scale + 0.5)
end

-- Background, Font, Font Size and Outline, and the header and price room that follow the size.
-- Before anything is measured, and only redone when one of them changed.
local function Style(view)
    local mode = view.backdrop:SetMode(S.Get("bagSpaceBackground"))
    local font, size, outline = S.Get("bagSpaceFont"), S.Get("bagSpaceFontSize"), S.Get("bagSpaceOutline")
    if view.shadow == mode and view.font == font and view.size == size and view.outline == outline then return end
    view.shadow, view.font, view.size, view.outline = mode, font, size, outline
    local scale = size / HEAD_SIZE
    local price = Scaled(PRICE_SIZE, scale)
    view.priceSize, view.priceH, view.priceW = price, Scaled(PRICE_H, scale), Scaled(PRICE_W, scale)
    view.headH, view.headIcon = Scaled(HEAD_H, scale), Scaled(HEAD_ICON, scale)
    local f, cells = view.free, view.cells
    f:SetHeight(view.headH)
    f.icon:SetSize(view.headIcon, view.headIcon)
    f.text:SetPoint("LEFT", view.headIcon + TEXT_GAP, 0)
    view.stack:SetHeight(view.headH)
    Parts.HudFont(f.text, font, size, outline, mode)
    Parts.HudFont(f.word, font, size, outline, mode)
    Parts.HudFont(f.scrap, font, size, outline, mode)
    for i = 1, #cells do Parts.HudFont(cells[i].price, font, price, outline, mode) end
end

local STEP = { RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

-- shown cells from the first icon in the row's direction, even gaps between them, and the card
-- round them with the header (headW wide, 0 for none) along its top. Keeps the card's centre
-- and size on the view (cardX, cardY from the first icon's centre, cardW, cardH).
local function Layout(view, shown, headW)
    local size = S.Get("bagSpaceSize")
    local prices = S.Get("bagSpacePrices")
    local dir = STEP[S.Get("bagSpaceGrow")] or STEP.RIGHT
    local half = size / 2
    local cellW = prices and math.max(size, view.priceW) or size
    local cellH = prices and size + PRICE_GAP + view.priceH or size
    local stepX, stepY = (cellW + GAP) * dir[1], (cellH + GAP) * dir[2]
    view:SetSize(size, size)
    local cells = view.cells
    for i = 1, shown do
        local b = cells[i] or NewCell(view, i, size)
        b:SetSize(size, size)
        Parts.SizeItemMarks(b.marks, size)
        b:ClearAllPoints()
        b:SetPoint("CENTER", view, "CENTER", (i - 1) * stepX, (i - 1) * stepY)
        b.price:SetShown(prices)
        b:Show()
    end
    for i = shown + 1, #cells do cells[i]:Hide() end
    local spanX, spanY = (shown - 1) * stepX, (shown - 1) * stepY
    local left, right = math.min(0, spanX) - cellW / 2, math.max(0, spanX) + cellW / 2
    local top, bottom = math.max(0, spanY) + half, math.min(0, spanY) + half - cellH
    local head = headW > 0 and view.headH + HEAD_GAP or 0
    if shown == 0 then
        -- The Stack button alone: the header over where the first icon would be.
        left, right, top, bottom, head = -half, -half, half, half, view.headH
    end
    -- A header wider than the icons widens the card away from the first icon.
    if headW > right - left then
        if dir[1] < 0 then left = right - headW else right = left + headW end
    end
    local x, y = left - PAD, top + head + PAD
    local w, h = right - left + PAD * 2, top - bottom + head + PAD * 2
    local card = view.card
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", view, "CENTER", x, y)
    card:SetSize(w, h)
    view.cardX, view.cardY, view.cardW, view.cardH = x + w / 2, y - h / 2, w, h
    -- Kept on screen whole, not just the first icon.
    view:SetClampRectInsets(x + half, x + w - half, y - half, y - h + half)
end

local function Fill(b, e, icon, price, count, quality, old, quest)
    b.pick = e
    b.icon:SetTexture(icon)
    b.price:SetText(price)
    Parts.PaintItemMarks(b.marks, count, nil, false, false)
    b.old:SetShown(old == true)
    b.quest:SetShown(quest ~= nil)
    -- Poor and Common items take the house 1px black border; Uncommon and better show their color.
    local c = quality and quality >= EDGE_COLORED and ITEM_QUALITY_COLORS[quality] or BORDER_RGB
    b.edge:SetColor(c.r, c.g, c.b, 1)
end

-- The card from a list of entries (the scan's, or the settings preview's samples).
local function Draw(view, list, shown, count, slots, scrap, saves)
    Style(view)
    local freeW, stackW = ShowFree(view, count, slots, scrap), ShowStack(view, saves)
    Layout(view, shown, freeW + stackW + (freeW > 0 and stackW > 0 and HEAD_SPACE or 0))
    local cells = view.cells
    for i = 1, shown do
        local e = list[i]
        Fill(cells[i], e, e.icon, Coins(e.value, true), e.count, e.quality, e.old, e.quest)
    end
end

local function Render()
    -- Unlock Mode shows your own items, so the row looks as it will where you place it; the
    -- slots with none get a sample, so the whole row can still be placed. Clicks do nothing
    -- while unlocked.
    if unlocked then
        local n = S.Get("bagSpaceCount")
        Style(frame)
        local freeW
        if total > 0 then
            freeW = ShowFree(frame, free, total, scrapSlots)
        else
            freeW = ShowFree(frame, SAMPLE_FREE, SAMPLE_SLOTS, 0)
        end
        ShowStack(frame, 0)
        Layout(frame, n, freeW)
        local cells = frame.cells
        for i = 1, n do
            local e = picks[i]
            if e then
                Fill(cells[i], nil, e.icon, Coins(e.value, true), e.count, e.quality, e.old, e.quest)
            else
                Fill(cells[i], nil, SAMPLE_ICON, Coins(SAMPLE_PRICE * i, true), nil, 1, i == 1)
            end
        end
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
    Draw(frame, picks, shown, free, total, scrapSlots, offerStack and stackSaves or 0)
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

function ns.BagSpaceRescan()
    if frame and On() then RequestScan() end
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
        NewView(frame, OnClick, OnEnter, StackClicked, true)
        frame.mover = UI.AttachMover(frame, "Bag Space", function(pos) S.Set("bagSpacePos", pos) end, "QoL/Loot & Items", "QoL/Loot & Items:bagSpace")
        -- Over the whole card; dragging it moves the first icon's place, which is what is saved.
        frame.mover:ClearAllPoints()
        frame.mover:SetAllPoints(frame.card)
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

-- The card's preview on its settings page: the same card, drawn by the code above on plain
-- frames, from samples of the addon's own; no bags are read and no click acts. Hovering a
-- sample shows the lines its tooltip would have.
local STAGE_H, STAGE_MARGIN = 150, 14
local PREVIEW_SLOTS, PREVIEW_SCRAP, PREVIEW_STACK = 52, 2, 1
local PREVIEW_FREE = { bags = 28, low = 4, full = 0 }
local STATES = {
    { key = "bags", label = "Bags", tip = "Room to spare: 28 of 52 slots free." },
    { key = "low", label = "Low", tip = "Under a tenth of your slots free.", needs = "bagSpaceShowFree" },
    { key = "full", label = "Full", tip = "Not a slot free.", needs = "bagSpaceShowFree" },
}

-- Made when the card first opens: an item of each quality from Poor to Rare, with a stack, an
-- outlevelled one and one a quest needs.
local function Samples()
    local quest = { title = "Linen for Lakeshire", have = 2, need = 6 }
    local list = {
        { name = "Worn Leather Pants", icon = "Interface\\Icons\\INV_Pants_04", quality = 2, count = 1, vendor = 150 },
        { name = "Ruined Pelt", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", quality = 0, count = 4, vendor = 59 },
        { name = "Tough Jerky", icon = "Interface\\Icons\\INV_Misc_Food_14", quality = 1, count = 20, vendor = 15,
          old = true },
        { name = "Linen Cloth", icon = "Interface\\Icons\\INV_Fabric_Linen_01", quality = 1, count = 7, vendor = 13,
          quest = quest },
        { name = "Jade Ring", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", quality = 3, count = 1, vendor = 920 },
    }
    for i, e in ipairs(list) do
        e.bag, e.slot, e.value = 0, i, e.vendor * e.count
    end
    return list
end

local function PreviewEnter(self)
    local e = self.pick
    if not e then return end
    local c = ITEM_QUALITY_COLORS[e.quality] or ITEM_QUALITY_COLORS[1]
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(e.name, c.r, c.g, c.b)
    AddTipLines(e, nil)
    GameTooltip:Show()
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetAllPoints()
    preview.view = NewView(CreateFrame("Frame", nil, preview), nil, PreviewEnter, nil, false)
    preview.samples, preview.list, preview.n = Samples(), {}, 0
    return preview
end

-- The samples the card's settings offer, in its order, then the card, shrunk to fit the stage.
local function PaintPreview(preview, state)
    local list, samples, maxQuality = preview.list, preview.samples, S.Get("bagSpaceMaxQuality")
    local n = 0
    for i = 1, #samples do
        local e = samples[i]
        if e.quality <= maxQuality then
            n = n + 1
            list[n] = e
        end
    end
    for i = n + 1, preview.n do list[i] = nil end
    preview.n = n
    -- A scan sets these again before it sorts.
    junkFirst, oldFirst = S.Get("bagSpaceJunkFirst"), S.Get("bagSpaceOldFirst")
    table.sort(list, Cheaper)
    local view = preview.view
    Draw(view, list, math.min(n, S.Get("bagSpaceCount")), PREVIEW_FREE[state] or PREVIEW_FREE.bags,
        PREVIEW_SLOTS, PREVIEW_SCRAP, S.Get("bagSpaceStack") and PREVIEW_STACK or 0)
    local scale = 1
    local roomW = preview:GetWidth() - STAGE_MARGIN * 2
    local roomH = preview:GetHeight() - STAGE_MARGIN * 2
    if roomW > 0 and view.cardW > roomW then scale = roomW / view.cardW end
    if roomH > 0 and view.cardH * scale > roomH then scale = roomH / view.cardH end
    view:SetScale(scale)
    view:ClearAllPoints()
    view:SetPoint("CENTER", preview, "CENTER", -view.cardX, -view.cardY)
end

Settings.Page("QoL/Loot & Items", S):Card({
    id = "bagSpace", name = "Bag Space", order = 60, switch = "bagSpace",
    help = "The cheapest items in your bags as a row of icons, cheapest first. Ctrl-click an icon "
        .. "to delete it, or click it to sell it while a vendor is open. Middle-click to ignore "
        .. "an item. "
        .. "Move it with Move Elements.",
    summary = BagSpaceSummary,
    studio = { height = STAGE_H, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = {
        Group("Offered"),
        { key = "bagSpaceCount", label = "Items Shown", slider = { 1, 8, 1 } },
        { key = "bagSpaceMaxQuality", label = "Highest Quality Offered", choice = QUALITY,
          help = "Items above this quality are never offered." },
        { key = "bagSpaceJunkFirst", label = "Grey Items First", toggle = true,
          help = "Grey items come before everything else, whatever they sell for." },
        { key = "bagSpaceOldFirst", label = "Outlevelled Food & Potions First", toggle = true,
          help = "Puts food, drink and potions 10 or more levels below you, marked with a clock, first." },
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
        { key = "bagSpaceShowFree", label = "Show Free Slots", toggle = true,
          help = "Free bag slots out of your total, above the row. Hover it for each bag." },
        { key = "bagSpaceStack", label = "Offer to Stack", toggle = true,
          help = "A Stack button on the card when part-filled stacks of an item can be combined." },
        { key = "bagSpacePrices", label = "Show Prices", toggle = true,
          help = "What each stack is worth, in its largest coin, under its icon." },
        { label = "Pick Up Cheapest Item", binding = "NAOWHFOREVER_BAGSPACE_PICKUP",
          help = "Puts the cheapest item on your cursor, to drop or sell." },
        Group("Tooltips"),
        { key = "bagSpaceTipVendor", label = "Tooltip: Vendor Price", toggle = true,
          help = "What the whole stack sells for at a vendor, and each item's price." },
        { key = "bagSpaceTipAuction", label = "Tooltip: Auction Price", toggle = true,
          help = "What the stack fetches at the auction house, from your last Scan Prices or "
              .. "TradeSkillMaster." },
        { key = "bagSpaceTipDelete", label = "Tooltip: Delete Hint", toggle = true,
          help = "The Ctrl-click line, and Click to sell while a vendor is open." },
        { key = "bagSpaceTipIgnore", label = "Tooltip: Ignore Hint", toggle = true, help = "The Middle-click line." },
        Group("Size"),
        { key = "bagSpaceSize", label = "Icon Size", slider = { 24, 56, 1 } },
        { key = "bagSpaceGrow", label = "Direction", choice = DIRECTION },
        Settings.Look("bagSpace", { text = true, size = { 8, 24, 1 }, background = "card" }),
        Group("Visibility"),
        { key = "bagSpaceHideCombat", label = "Hide in Combat", toggle = true },
    },
})
