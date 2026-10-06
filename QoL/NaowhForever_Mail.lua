-------------------------------------------------------------------------------
--  NaowhForever_Mail.lua -- additions to Blizzard's mailbox: an alts list for the To box, quick
--  attach, and a login warning for expiring mail.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local function Tag() return ns.Color("accent", "Naowh Mail") end
local SEND_SLOTS = 12
local EXPIRY_WARN = 3 * 86400
local TRADE_GOODS = Enum.ItemClass.Tradegoods
local GEAR = { [Enum.ItemClass.Weapon] = true, [Enum.ItemClass.Armor] = true }

local altsButton, attachButton
local qBag, qSlot, qItem = {}, {}, {}
local qHead, qCount = 1, 0
local pendingSlot, pendingItem, pendingBag, pendingBagSlot
local clicking = false
local counts, labels, order = {}, {}, {}

local function On(key)
    return S.Get("enabled") and S.Get(key)
end

local function Coins(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper, 12)
end

local function OpenAltsMenu(owner)
    local list = ns.AltList()
    local total = GetMoney()
    for _, alt in ipairs(list) do total = total + alt.money end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Gold on this realm: " .. Coins(total))
        if #list == 0 then
            root:CreateTitle("Log in on your other characters once and they appear here.", WHITE_FONT_COLOR)
            return
        end
        for _, alt in ipairs(list) do
            local text = ("%s  |cff808080%d|r  %s"):format(ns.ClassColoredName(alt.name, alt.class),
                alt.level, Coins(alt.money))
            root:CreateButton(text, function()
                SendMailNameEditBox:SetText(alt.name)
                SendMailSubjectEditBox:SetFocus()
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Quick attach: one stack at a time from a scan made at the click, each checked in its bag
--  slot and on the cursor before it goes in, and the next only once it has landed.
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function FreeSlot()
    for i = 1, SEND_SLOTS do
        if not HasSendMailItem(i) then return i end
    end
end

local function StopAttaching()
    qHead, qCount = 1, 0
    pendingSlot, pendingItem, pendingBag, pendingBagSlot = nil, nil, nil, nil
    clicking = false
    events:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
    events:UnregisterEvent("MAIL_SEND_SUCCESS")
end

local function Mailable(bag, slot)
    local itemID = C_Container.GetContainerItemID(bag, slot)
    if not itemID then return end
    local _, _, subType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= TRADE_GOODS and not GEAR[classID] then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isBound or info.isLocked or info.itemID ~= itemID then return end
    if GEAR[classID] and (info.quality or 0) < Enum.ItemQuality.Uncommon then return end
    return itemID, classID, subClassID or -1, subType
end

local function Matches(key, classID, subClassID)
    if key == "gear" then return GEAR[classID] end
    return classID == TRADE_GOODS and (key == "all" or key == subClassID)
end

local function Landed()
    if not HasSendMailItem(pendingSlot) then return false end
    local _, itemID = GetSendMailItem(pendingSlot)
    return itemID == pendingItem
end

local function AttachNext()
    if clicking then return end
    while true do
        if pendingSlot then
            if not Landed() then
                local info = C_Container.GetContainerItemInfo(pendingBag, pendingBagSlot)
                if not GetCursorInfo() and not (info and info.isLocked) then StopAttaching() end
                return
            end
            pendingSlot = nil
        end
        if qHead > qCount or GetCursorInfo() then
            StopAttaching()
            return
        end
        local slot = FreeSlot()
        if not slot then
            local left = qCount - qHead + 1
            ns.Print(("%s: %d %s didn't fit, all %d attachment slots are full. Send this one and attach again.")
                :format(Tag(), left, left == 1 and "stack" or "stacks", SEND_SLOTS))
            StopAttaching()
            return
        end
        local bag, bagSlot, itemID = qBag[qHead], qSlot[qHead], qItem[qHead]
        qHead = qHead + 1
        local info = C_Container.GetContainerItemInfo(bag, bagSlot)
        if info and info.itemID == itemID and not info.isLocked and not info.isBound then
            C_Container.PickupContainerItem(bag, bagSlot)
            local kind, cursorID = GetCursorInfo()
            if kind ~= "item" or cursorID ~= itemID then
                if kind then ClearCursor() end
                StopAttaching()
                return
            end
            pendingSlot, pendingItem, pendingBag, pendingBagSlot = slot, itemID, bag, bagSlot
            clicking = true
            ClickSendMailItemButton(slot)
            clicking = false
            kind, cursorID = GetCursorInfo()
            if kind == "item" and cursorID == itemID then
                ClearCursor()
                StopAttaching()
                return
            end
        end
    end
end

local function Attach(key)
    StopAttaching()
    local n = 0
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID, classID, subClassID = Mailable(bag, slot)
            if itemID and Matches(key, classID, subClassID) then
                n = n + 1
                qBag[n], qSlot[n], qItem[n] = bag, slot, itemID
            end
        end
    end
    if n == 0 then return end
    qHead, qCount = 1, n
    events:RegisterEvent("MAIL_SEND_INFO_UPDATE")
    events:RegisterEvent("MAIL_SEND_SUCCESS")
    AttachNext()
end

local function Tally(key, label)
    if not counts[key] then
        counts[key] = 0
        labels[key] = label
        order[#order + 1] = key
    end
    counts[key] = counts[key] + 1
end

local function Count()
    wipe(counts)
    wipe(labels)
    wipe(order)
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID, classID, subClassID, subType = Mailable(bag, slot)
            if itemID then
                if classID == TRADE_GOODS then
                    Tally("all", "All trade goods")
                    Tally(subClassID, subType or "Other trade goods")
                else
                    Tally("gear", "Unbound gear")
                end
            end
        end
    end
end

local function OpenAttachMenu(owner)
    Count()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Attach from your bags")
        if #order == 0 then
            root:CreateTitle("No trade goods or unbound gear in your bags.", WHITE_FONT_COLOR)
            return
        end
        for _, key in ipairs(order) do
            local n = counts[key]
            root:CreateButton(("%s (%d %s)"):format(labels[key], n, n == 1 and "stack" or "stacks"), function()
                Attach(key)
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Expiry warning
-------------------------------------------------------------------------------
local function WarnExpiring()
    local now, soon = time(), {}
    for _, realm in pairs(ns.AccountSettings().alts or {}) do
        for name, c in pairs(realm) do
            if c.mailExpires and (c.mailCount or 0) > 0 and c.mailExpires - now < EXPIRY_WARN then
                local left = c.mailExpires - now
                local when = left <= 0 and "may have expired" or left < 86400 and "less than a day"
                    or math.floor(left / 86400) .. "d"
                soon[#soon + 1] = ns.ClassColoredName(name, c.class) .. " (" .. when .. ")"
            end
        end
    end
    if #soon > 0 then
        ns.Print(Tag() .. ": mail expiring soon on " .. table.concat(soon, ", ")
            .. ". Open the mailbox on those characters to keep it.")
    end
end

-------------------------------------------------------------------------------
--  Buttons on the send tab, in a column beside the mail frame.
-------------------------------------------------------------------------------
local function Build()
    if altsButton or not (SendMailFrame and MailFrame) then return end
    altsButton = ns.Button(SendMailFrame, "Alts", 64, 22, function() OpenAltsMenu(altsButton) end)
    altsButton:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    ns.Tooltip(altsButton, "Your Characters", "Pick one of your characters on this realm and "
        .. "faction to fill the To box. Shows each one's level and gold.")
    attachButton = ns.Button(SendMailFrame, "Attach", 64, 22, function() OpenAttachMenu(attachButton) end)
    ns.Tooltip(attachButton, "Quick Attach", "Attach every trade good, one type of trade good, or "
        .. "your unbound gear from your bags, up to the 12 attachment slots.")
end

local function Place()
    if not altsButton then return end
    altsButton:SetShown(On("mailAlts"))
    attachButton:ClearAllPoints()
    if altsButton:IsShown() then
        attachButton:SetPoint("TOPLEFT", altsButton, "BOTTOMLEFT", 0, -4)
    else
        attachButton:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    end
    attachButton:SetShown(On("mailQuickAttach"))
end

events:SetScript("OnEvent", function(_, event, isLogin)
    if event == "MAIL_SEND_INFO_UPDATE" then
        AttachNext()
    elseif event == "MAIL_SHOW" then
        Build()
        Place()
    elseif event == "MAIL_CLOSED" or event == "MAIL_SEND_SUCCESS" then
        StopAttaching()
    elseif event == "PLAYER_ENTERING_WORLD" then
        events:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if isLogin then C_Timer.After(5, WarnExpiring) end
    end
end)

local function Apply()
    if On("mailAlts") or On("mailQuickAttach") then
        Build()
        events:RegisterEvent("MAIL_SHOW")
        events:RegisterEvent("MAIL_CLOSED")
    else
        StopAttaching()
        events:UnregisterEvent("MAIL_SHOW")
        events:UnregisterEvent("MAIL_CLOSED")
    end
    Place()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "mailAlts" or key == "mailQuickAttach" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    Apply()
    if On("mailExpiry") then events:RegisterEvent("PLAYER_ENTERING_WORLD") end
end)

local function ForgetCharacter()
    ns.OpenForgetAltMenu(UIParent)
end

ns.Shared.Settings.Page("QoL/Loot & Items", S):Card({
    id = "mailAlts", name = "Mail & Alts", order = 40,
    help = "Your characters on this realm and faction, remembered across your account: what they "
        .. "hold on item tooltips, and help at the mailbox.",
    rows = {
        { key = "altCounts", label = "Alt Item Counts", toggle = true,
          help = "Item tooltips show how many your characters on this realm and faction hold in "
              .. "their bags, bank and mailbox. Each character is counted once you log in on it, "
              .. "and its bank once you open it." },
        { key = "mailAlts", label = "Alts Button on Mail", toggle = true,
          help = "An Alts button beside the mailbox's Send tab lists your characters on this realm "
              .. "and faction with their level and gold. Pick one to fill the To box." },
        { key = "mailQuickAttach", label = "Quick Attach", toggle = true,
          help = "An Attach button beside the mailbox's Send tab: attach every trade good, one type "
              .. "of trade good, or your unbound gear in one click." },
        { key = "mailExpiry", label = "Mail Expiry Warning", toggle = true,
          help = "At login, names any of your characters with mail that expires within three days. "
              .. "It knows each character's mail from the last time it opened a mailbox." },
        { label = "Forget a Character", button = ForgetCharacter, buttonText = "Forget",
          help = "Removes a deleted or transferred character from the counts and the Alts list." },
    },
})
