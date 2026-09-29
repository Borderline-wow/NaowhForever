-------------------------------------------------------------------------------
--  NaowhForever_Mail.lua -- additions to Blizzard's mailbox: a list of your characters for
--  the To box, attaching trade goods or unbound gear in one click, and a login warning when
--  a character's mail is about to expire. Open All is Blizzard's own.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings

local TAG = "|cff0091edNaowh Mail|r"
local SEND_SLOTS = 12
local EXPIRY_WARN = 3 * 86400
local TRADE_GOODS = Enum.ItemClass.Tradegoods
local GEAR = { [Enum.ItemClass.Weapon] = true, [Enum.ItemClass.Armor] = true }

local altsButton, attachButton
local queue = {}

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
--  Quick attach: one item per MAIL_SEND_INFO_UPDATE, since the next pickup has to wait for
--  the last attachment to land.
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function FreeSlot()
    for i = 1, SEND_SLOTS do
        if not HasSendMailItem(i) then return i end
    end
end

local function StopAttaching()
    wipe(queue)
    events:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
end

local function AttachNext()
    if GetCursorInfo() then
        ClearCursor()
        StopAttaching()
        return
    end
    while #queue > 0 do
        local e = table.remove(queue, 1)
        local slot = FreeSlot()
        if not slot then
            ns.Print(TAG .. ": all " .. SEND_SLOTS .. " attachment slots are full. Send this one and attach again.")
            StopAttaching()
            return
        end
        local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
        if info and info.itemID == e.itemID and not info.isLocked then
            C_Container.PickupContainerItem(e.bag, e.slot)
            ClickSendMailItemButton(slot)
            return
        end
    end
    StopAttaching()
end

-- Mailable stacks in the bags, grouped for the menu: every trade good, each trade goods
-- type, and unbound gear of uncommon quality or better.
local function Groups()
    local groups, order = {}, {}
    local function Add(key, label, entry)
        if not groups[key] then
            groups[key] = { label = label, items = {} }
            order[#order + 1] = key
        end
        local items = groups[key].items
        items[#items + 1] = entry
    end
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not info.isLocked then
                local _, _, subType, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
                local entry = { bag = bag, slot = slot, itemID = info.itemID }
                if classID == TRADE_GOODS then
                    Add("all", "All trade goods", entry)
                    Add("sub:" .. (subType or ""), subType or "Other trade goods", entry)
                elseif GEAR[classID] and (info.quality or 0) >= Enum.ItemQuality.Uncommon then
                    Add("gear", "Unbound gear", entry)
                end
            end
        end
    end
    return groups, order
end

local function OpenAttachMenu(owner)
    local groups, order = Groups()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Attach from your bags")
        if #order == 0 then
            root:CreateTitle("No trade goods or unbound gear in your bags.", WHITE_FONT_COLOR)
            return
        end
        for _, key in ipairs(order) do
            local group = groups[key]
            root:CreateButton(("%s (%d)"):format(group.label, #group.items), function()
                StopAttaching()
                for _, entry in ipairs(group.items) do queue[#queue + 1] = entry end
                events:RegisterEvent("MAIL_SEND_INFO_UPDATE")
                AttachNext()
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
        ns.Print(TAG .. ": mail expiring soon on " .. table.concat(soon, ", ")
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
    elseif event == "MAIL_CLOSED" then
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
