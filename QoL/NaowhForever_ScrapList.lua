-------------------------------------------------------------------------------
--  NaowhForever_ScrapList.lua -- the Scrap Marker's own window, the Scrap List (Open Scrap
--  List on QoL > Loot & Items, and /nf scrap): every marked item and every rule match in your
--  bags, with what you carry and what it sells for, a search, an X to unmark, a tag to switch
--  a mark between the account and this character, drop an item to mark it, Clear All, and
--  Export and Import as a plain string. Built the first time it opens.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Shared = ns.Shared
local Parts, St, View, Items = Shared.Parts, Shared.Style, Shared.View, Shared.Items
local Scrap = ns.ScrapMarker

local GetItemInfo = C_Item.GetItemInfo
local GetItemCount = C_Item.GetItemCount
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemQualityByID = C_Item.GetItemQualityByID
local GetContainerItemID = C_Container.GetContainerItemID
local GetContainerNumSlots = C_Container.GetContainerNumSlots

local PAGE = "QoL/Loot & Items"
local WIDTH, HEIGHT = 500, 560
local HEADER, PAD, FOOTER, SCROLLBAR = St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER, St.SCROLLBAR
local SEARCH_H, BAR_GAP, INSET = St.SEARCH_H, St.BAR_GAP, St.CONTENT_INSET
local BOTTOM_H = 34
local CLEAR_W, CLEAR_H = 100, 24
local EXPORT_PREFIX = "NFSCRAP:1:"
local IMPORT_MAX = 500
local IMPORT_LETTERS = 4000
local SHOWN_NAMES = 3
local UNCOMMON, RARE = 2, 3
local HIGH_VALUE, HIGH_VALUE_TEXT = 10000, "1g"
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "EQUIPMENT_SETS_CHANGED" }
local EMPTY_NOTE = "Nothing marked. Alt-click an item in your bags to mark it."
local NO_MATCH = "No scrap item matches your search."
local TAGS = { account = "Account", char = "Character" }
local TAG_TIPS = { account = "Marked on every character; click for this character only.",
    char = "Marked on this character only; click for every character." }
local RULE_TAG, RULE_TIP = "Rule", "Picked by a rule; the X keeps it."

local window, view, scroll, search, summary
local filter = ""
local ids, marked, have, price, rule, seen = {}, {}, {}, {}, {}, {}
local lowered = {}
local metaTexts = {}
local lastCount, lastTotal

local function MetaText(reason, count)
    local byReason = metaTexts[reason]
    if not byReason then
        byReason = {}
        metaTexts[reason] = byReason
    end
    local text = byReason[count]
    if not text then
        local carried = count > 0 and (count .. " in your bags") or "Not in your bags"
        text = reason ~= "" and (reason .. "  " .. carried) or carried
        byReason[count] = text
    end
    return text
end

local function Lower(id)
    local text = lowered[id]
    if not text then
        local name = GetItemInfo(id)
        if not name then return nil end
        text = name:lower()
        lowered[id] = text
    end
    return text
end

local function Carried(a, b)
    local ha, hb = have[a] > 0, have[b] > 0
    if ha ~= hb then return ha end
    local na, nb = GetItemInfo(a), GetItemInfo(b)
    if na ~= nb then
        if not na then return false end
        if not nb then return true end
        return na < nb
    end
    return a < b
end

local function Note(id)
    if seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
    have[id] = GetItemCount(id)
    local _, _, _, _, _, _, _, _, _, _, sell = GetItemInfo(id)
    price[id] = sell or 0
end

local function Collect()
    wipe(ids)
    wipe(seen)
    wipe(rule)
    Scrap.MarkedIDs(marked)
    for i = 1, #marked do Note(marked[i]) end
    for bag = BACKPACK_CONTAINER, LAST_BAG do
        for slot = 1, GetContainerNumSlots(bag) do
            local id = GetContainerItemID(bag, slot)
            if id and not seen[id] then
                local why = Scrap.RuleMatch(id)
                if why then
                    rule[id] = why
                    Note(id)
                end
            end
        end
    end
    table.sort(ids, Carried)
end

local function Unscrap(id)
    Scrap.Unscrap(id)
end

local function PaintSummary(count, total)
    if count == lastCount and total == lastTotal then return end
    lastCount, lastTotal = count, total
    local text = ("%d item%s"):format(count, count == 1 and "" or "s")
    if total > 0 then text = text .. ", " .. Parts.Coins(total) .. " in your bags" end
    summary:SetText(text)
end

local Draw = {}

function Draw:Redraw()
    self:Clear()
    Collect()
    local total, shown = 0, 0
    for i = 1, #ids do
        local id = ids[i]
        local value = have[id] * price[id]
        total = total + value
        local name = filter ~= "" and Lower(id)
        if filter == "" or (name and name:find(filter, 1, true)) then
            shown = shown + 1
            local why = rule[id]
            local scope = not why and Scrap.Scope(id)
            self:Add("item", id, MetaText(why or "", have[id]), value > 0 and Parts.Coins(value) or "",
                Unscrap, why and "Keep it" or "Unmark", why and RULE_TAG or TAGS[scope],
                not why and Scrap.SwitchScope or nil, why and RULE_TIP or TAG_TIPS[scope])
        end
    end
    if #ids == 0 then
        self:Note(EMPTY_NOTE)
    elseif shown == 0 then
        self:Note(NO_MATCH)
    end
    self:Fit(EVENTS)
    PaintSummary(#ids, total)
end

local function Drop()
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    if Scrap.Scope(id) then return end
    Scrap.Mark(id, link)
end

local function ClearAll()
    ns.Confirm("Unmark every item marked as scrap?", Scrap.Clear)
end

local exportIDs = {}

local function Export()
    Scrap.MarkedIDs(exportIDs)
    if #exportIDs == 0 then
        ns.Print("Nothing marked to export.")
        return
    end
    table.sort(exportIDs)
    ns.ShowCopyLine("Scrap List", EXPORT_PREFIX .. table.concat(exportIDs, ","), St.LOGO)
end

local function Parse(text)
    local body = text:match("^%s*NFSCRAP:1:([%d,%s]*)$")
    if not body then return nil end
    local out, got = {}, {}
    for digits in body:gmatch("%d+") do
        local id = tonumber(digits)
        if id and id > 0 and id < 2147483648 and not got[id] then
            got[id] = true
            out[#out + 1] = id
            if #out >= IMPORT_MAX then break end
        end
    end
    return out
end
Scrap.Parse = Parse

local function QualityFirst(a, b)
    local qa, qb = GetItemQualityByID(a) or 0, GetItemQualityByID(b) or 0
    if qa ~= qb then return qa > qb end
    return a < b
end

local function ImportQuestion(add)
    table.sort(add, QualityFirst)
    local names = {}
    for i = 1, math.min(#add, SHOWN_NAMES) do
        names[i] = Items.QualityHex(add[i]) .. Items.Name(add[i]) .. "|r"
    end
    local more = #add - #names
    local text = ("Add %d item%s to your scrap list: %s%s?"):format(#add, #add == 1 and "" or "s",
        table.concat(names, ", "), more > 0 and (" and %d more"):format(more) or "")
    local rare, uncommon, valuable = 0, 0, 0
    for _, id in ipairs(add) do
        local quality = GetItemQualityByID(id) or 0
        if quality >= RARE then
            rare = rare + 1
        elseif quality >= UNCOMMON then
            uncommon = uncommon + 1
        end
        local sell = select(11, GetItemInfo(id)) or 0
        local auction = ns.AuctionPrice and ns.AuctionPrice(id) or 0
        if math.max(sell, auction) >= HIGH_VALUE then valuable = valuable + 1 end
    end
    local warn
    if rare > 0 then
        warn = ("%d of these %s Rare or better"):format(rare, rare == 1 and "is" or "are")
    elseif uncommon > 0 then
        warn = ("%d of these %s Uncommon"):format(uncommon, uncommon == 1 and "is" or "are")
    end
    if valuable > 0 then
        local worth = ("%d sell%s for %s or more"):format(valuable, valuable == 1 and "s" or "", HIGH_VALUE_TEXT)
        warn = warn and (warn .. ", and " .. worth) or ("%d of these sell%s for %s or more")
            :format(valuable, valuable == 1 and "s" or "", HIGH_VALUE_TEXT)
    end
    if not warn then return text end
    return text .. "|n" .. St.WARN_CODE .. warn .. ".|r"
end

local function Import(text)
    local parsed = Parse(text)
    if not parsed then
        ns.Print("That isn't a Scrap List string.")
        return
    end
    local add = {}
    for _, id in ipairs(parsed) do
        if GetItemInfoInstant(id) and not Scrap.Scope(id) and not Scrap.Refusal(id) then add[#add + 1] = id end
    end
    if #add == 0 then
        ns.Print("Nothing new to add from that list.")
        return
    end
    ns.Confirm(ImportQuestion(add), function()
        Scrap.AddAll(add)
    end)
end

local function ImportPrompt()
    ns.PromptText("Paste a Scrap List", "", IMPORT_LETTERS, Import)
end

local function OnSearch(text)
    filter = (text or ""):lower()
    if view then view:Redraw() end
end

local function DropClick()
    if GetCursorInfo() then Drop() end
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "scrapListWindow")
    window.backdrop:Card(6, HEADER + 6, 6, FOOTER + 6)
    local close = Parts.TitleBar(window, "Scrap List",
        "Sold at the next vendor. Drop an item here to mark it.", PAGE)
    local import = Parts.BarButton(window, St.IMPORT, "Import a list", "Paste a shared list to add its items.",
        ImportPrompt)
    import:SetPoint("RIGHT", close, "LEFT", -BAR_GAP * 2, 0)
    local export = Parts.BarButton(window, St.EXPORT, "Export this list", "A string to share it with.", Export)
    export:SetPoint("RIGHT", import, "LEFT", -BAR_GAP, 0)
    Parts.FooterBrand(window, PAGE)
    window:SetScript("OnReceiveDrag", Drop)
    window:SetScript("OnMouseUp", DropClick)

    local top = HEADER + PAD + 4
    search = Parts.SearchBox(window, "Search", OnSearch)
    search:SetPoint("TOPLEFT", INSET, -top)
    search:SetPoint("TOPRIGHT", -INSET, -top)
    search:SetHeight(SEARCH_H)

    local clear = ns.Button(window, "Clear All", CLEAR_W, CLEAR_H, ClearAll)
    clear:SetPoint("BOTTOMRIGHT", -INSET, FOOTER + PAD)
    summary = ns.Font(window, 12, nil, T.muted)
    summary:SetPoint("LEFT", window, "BOTTOMLEFT", INSET, FOOTER + PAD + CLEAR_H / 2)
    summary:SetPoint("RIGHT", clear, "LEFT", -PAD, 0)
    summary:SetJustifyH("LEFT")

    scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", INSET, -(top + SEARCH_H + PAD))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, FOOTER + PAD + BOTTOM_H)
    view = View.New(scroll, View.NewKinds(), Draw)
    view:SetWidth(WIDTH - INSET - SCROLLBAR - PAD - 8)
    view.onDrop = Drop
    scroll:SetScrollChild(view)
    Scrap.OnChange(function()
        if window:IsShown() then view:QueueRedraw() end
    end)
end

function ns.OpenScrapList()
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    window.backdrop:Paint(1)
    lastCount = nil
    view:Redraw()
end

function ns.ToggleScrapList()
    if window and window:IsShown() then window:Hide() else ns.OpenScrapList() end
end

local function OpenFromCard()
    ns.OpenScrapList()
end

Shared.Settings.Page(PAGE, ns.QoLSettings):Window({
    order = 26,
    text = "Open Scrap List",
    open = OpenFromCard,
    headline = "Scrap List",
    detail = "Every item marked as scrap, to search, unmark, share or add to.",
})
