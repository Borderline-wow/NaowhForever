-------------------------------------------------------------------------------
--  NaowhForever_Alts.lua -- your characters, kept account-wide per realm and faction: class,
--  level and gold for the mail features, and with Alt Item Counts on, what each one holds in
--  its bags, bank and mailbox, shown on item tooltips.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TAG = "|cff0091edNaowh|r"
local MAIL_ATTACHMENTS = 16
local MAX_TOOLTIP_ROWS = 8

local realmKey, me, bankOpen, mailPending

local function CountsOn()
    return S.Get("enabled") and S.Get("altCounts")
end

local function RosterOn()
    return S.Get("enabled") and (S.Get("altCounts") or S.Get("mailAlts") or S.Get("mailExpiry"))
end

-- Characters on one realm and faction can mail each other, so that is the group kept.
function ns.AltRealm()
    local account = ns.AccountSettings()
    account.alts = account.alts or {}
    realmKey = realmKey or GetRealmName() .. "-" .. (UnitFactionGroup("player") or "")
    account.alts[realmKey] = account.alts[realmKey] or {}
    return account.alts[realmKey]
end

-- Forever has been seen to return "Name-Realm" for the player, and the mail box wants the bare name.
function ns.AltName()
    me = me or (UnitName("player")):match("^[^-]+")
    return me
end

local function Me()
    local realm = ns.AltRealm()
    local name = ns.AltName()
    realm[name] = realm[name] or {}
    return realm[name]
end

function ns.ClassColoredName(name, class)
    local color = class and C_ClassColor.GetClassColor(class)
    return color and color:WrapTextInColorCode(name) or name
end

-- Deleted or transferred characters otherwise stay in the counts and the Alts list for good.
function ns.OpenForgetAltMenu(owner)
    local all = ns.AccountSettings().alts or {}
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Forget a character")
        local any = false
        for realm, chars in pairs(all) do
            for name, c in pairs(chars) do
                any = true
                root:CreateButton(ns.ClassColoredName(name, c.class) .. "  |cff808080" .. realm .. "|r", function()
                    ns.Confirm("Forget " .. name .. " on " .. realm .. "? It comes back the next "
                        .. "time you log in on it with a Mail & Alts option on.", function()
                        chars[name] = nil
                        if not next(chars) then all[realm] = nil end
                    end)
                end)
            end
        end
        if not any then root:CreateTitle("No characters recorded yet.", WHITE_FONT_COLOR) end
    end)
end

local function UpdateRoster()
    local c = Me()
    c.class = select(2, UnitClass("player"))
    c.level = UnitLevel("player")
    c.money = GetMoney()
end

local function Count(into, first, last)
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                into[info.itemID] = (into[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return into
end

local function ScanBags()
    Me().bags = Count({}, BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS)
end

-- The Forever bank is the character bank tabs; a tab not bought has no slots.
local function ScanBank()
    Me().bank = Count({}, Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9)
end

-- Attachments, how many letters wait, and when the soonest one expires. Each MAIL_INBOX_UPDATE
-- would redo this while Open All empties the box, so it waits for the burst to end.
local function ScanMail()
    mailPending = nil
    if not RosterOn() then return end
    local shown, total = GetInboxNumItems()
    local items, soonest, now = {}, nil, time()
    for i = 1, shown do
        local _, _, _, _, _, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if daysLeft then
            local expires = now + math.floor(daysLeft * 86400)
            if not soonest or expires < soonest then soonest = expires end
        end
        if itemCount and itemCount > 0 then
            for a = 1, MAIL_ATTACHMENTS do
                local _, itemID, _, count = GetInboxItem(i, a)
                if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
            end
        end
    end
    local c = Me()
    c.mail, c.mailCount, c.mailExpires = items, total or shown, soonest
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "BAG_UPDATE_DELAYED" then
        ScanBags()
        if bankOpen then ScanBank() end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ScanBank()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = nil
    elseif event == "MAIL_INBOX_UPDATE" then
        if not mailPending then
            mailPending = true
            C_Timer.After(1, ScanMail)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        Me().level = arg
    else
        UpdateRoster()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not RosterOn() then return end
    UpdateRoster()
    events:RegisterEvent("PLAYER_MONEY")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("MAIL_INBOX_UPDATE")
    if CountsOn() then
        ScanBags()
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("BANKFRAME_OPENED")
        events:RegisterEvent("BANKFRAME_CLOSED")
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "altCounts" or key == "mailAlts" or key == "mailExpiry" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-- Your other characters on this realm and faction, highest level first.
function ns.AltList()
    local list, mine = {}, ns.AltName()
    for name, c in pairs(ns.AltRealm()) do
        if name ~= mine then
            list[#list + 1] = { name = name, class = c.class, level = c.level or 0, money = c.money or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return list
end

local rows = {}
local function Where(c, id)
    local bags, bank, mail = c.bags and c.bags[id] or 0, c.bank and c.bank[id] or 0, c.mail and c.mail[id] or 0
    local parts = {}
    if bags > 0 then parts[#parts + 1] = bags .. " bags" end
    if bank > 0 then parts[#parts + 1] = bank .. " bank" end
    if mail > 0 then parts[#parts + 1] = mail .. " mail" end
    return bags + bank + mail, table.concat(parts, ", ")
end

-- Only drawn when some of the item is somewhere other than the bags you are looking at.
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not CountsOn() then return end
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local mine, total, elsewhere = ns.AltName(), 0, false
    wipe(rows)
    for name, c in pairs(ns.AltRealm()) do
        local count, text = Where(c, id)
        if count > 0 then
            total = total + count
            if name ~= mine or text ~= count .. " bags" then elsewhere = true end
            rows[#rows + 1] = { name = name, class = c.class, count = count, text = text }
        end
    end
    if not elsewhere then return end
    table.sort(rows, function(a, b) return a.count > b.count end)
    tooltip:AddDoubleLine(TAG .. " owned", total, 1, 1, 1, 1, 1, 1)
    for i = 1, math.min(#rows, MAX_TOOLTIP_ROWS) do
        local r = rows[i]
        tooltip:AddDoubleLine("  " .. ns.ClassColoredName(r.name, r.class), r.text, 1, 1, 1, 0.8, 0.8, 0.8)
    end
end)
