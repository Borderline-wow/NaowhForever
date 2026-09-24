-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_LootFeed.lua -- the QoL loot feed: a line per loot with its icon,
--  amount, bag total and value, stacking upward from the anchor and fading out, plus an
--  optional gold per hour counter.
--
--  Forever has no GetItemInfo/GetItemCount/GetCoinTextureString globals (Blizzard_Deprecated*
--  never loads there), so everything goes through C_Item and C_CurrencyInfo.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local S = ns.QoLSettings

local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local XP_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local QUEST_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local REP_ICON = "Interface\\Icons\\INV_BannerPVP_02"
local XP_COLOR, REP_COLOR = "|cffb48ef9", "|cff4fc3f7"
local STYLES = {
    dark  = { bg = { 0.05, 0.05, 0.06, 0.8 }, edge = { 0, 0, 0, 1 } },
    light = { bg = { 0.32, 0.23, 0.14, 0.7 }, edge = { 0.12, 0.08, 0.04, 1 } },
}

local feed, gph, unlocked
local rows, pool = {}, {}
local sessionStart, sessionValue = nil, 0

local function On()
    return S.Get("enabled") and S.Get("lootFeed")
end

-- "You receive loot: %sx%d." and friends, turned into patterns once. Pushed covers quest
-- rewards and anything handed straight to the bags.
local PATTERNS = {}
for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF,
                       LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    PATTERNS[#PATTERNS + 1] = "^" .. p .. "$"
end

-- "%d Gold" and so on, for reading the amount out of a money message.
local GOLD = GOLD_AMOUNT:gsub("%%d", "(%%d+)")
local SILVER = SILVER_AMOUNT:gsub("%%d", "(%%d+)")
local COPPER = COPPER_AMOUNT:gsub("%%d", "(%%d+)")

-- "Reputation with %s increased by %d."
local REP_PATTERN = "^" .. FACTION_STANDING_INCREASED:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"

local function Coins(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper, 12)
end

local function FormatGPH()
    local hours = (GetTime() - sessionStart) / 3600
    local per = math.floor(sessionValue / math.max(hours, 1 / 60))
    return ("%dg %ds %dc/Hr"):format(math.floor(per / 10000), math.floor(per / 100) % 100, per % 100)
end

local function AddSessionValue(copper)
    if not sessionStart then sessionStart = GetTime() end
    sessionValue = sessionValue + copper
end

function ns.ResetLootFeedSession()
    sessionStart, sessionValue = nil, 0
    if gph then gph:Hide() end
end

-- TradeSkillMaster is optional and its price call errors on a source it cannot resolve,
-- which is the one reason this is protected.
local function UnitPrice(link, vendor)
    if S.Get("lootFeedPrice") == "tsm" and TSM_API and TSM_API.GetCustomPriceValue then
        local ok, value = pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", TSM_API.ToItemString(link))
        if ok and value then return value end
    end
    return vendor or 0
end

local function Layout()
    local step = S.Get("lootFeedHeight") + S.Get("lootFeedSpacing")
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("BOTTOM", feed, "BOTTOM", 0, (i - 1) * step)
    end
    local newest = rows[1]
    if gph and newest and S.Get("lootFeedGPH") and sessionStart then
        gph:SetText(FormatGPH())
        gph:ClearAllPoints()
        gph:SetPoint("LEFT", newest, "RIGHT", 10, 0)
        gph:Show()
    elseif gph then
        gph:Hide()
    end
end

local function Release(row)
    row.anim:Stop()
    row:Hide()
    row.link = nil
    for i = #rows, 1, -1 do
        if rows[i] == row then table.remove(rows, i) end
    end
    pool[#pool + 1] = row
    Layout()
end

local function StyleRow(row)
    local st = STYLES[S.Get("lootFeedStyle")] or STYLES.dark
    row.bg:SetColorTexture(unpack(st.bg))
    row.border:SetColor(unpack(st.edge))
    row.glow:SetShown(S.Get("lootFeedGlow"))
    local h, size = S.Get("lootFeedHeight"), S.Get("lootFeedFontSize")
    local font = ns.UI.FontPath(S.Get("lootFeedFont"))
    row:SetSize(S.Get("lootFeedWidth"), h)
    row.icon:SetSize(h - 2, h - 2)
    row.name:SetFont(font, size, "OUTLINE")
    row.value:SetFont(font, size - 1, "OUTLINE")
    row.bags:SetFont(font, math.max(8, size - 2), "OUTLINE")
end

local function NewRow()
    local row = CreateFrame("Frame", nil, feed)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.border = ns.Border(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 1, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.glow = row:CreateTexture(nil, "ARTWORK")
    row.glow:SetColorTexture(1, 1, 1, 1)
    row.glow:SetGradient("HORIZONTAL", CreateColor(1, 0.8, 0.3, 0.7), CreateColor(1, 0.8, 0.3, 0))
    row.glow:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 0, 0)
    row.glow:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 0, 0)
    row.glow:SetWidth(12)

    row.bags = ns.Font(row, 11, "OUTLINE")
    row.bags:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 2, 2)

    row.value = ns.Font(row, 12, "OUTLINE")
    row.value:SetPoint("RIGHT", -8, 0)
    row.name = ns.Font(row, 13, "OUTLINE")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Fades in, holds for the display time, then fades out and frees the slot.
    row.anim = row:CreateAnimationGroup()
    local appear = row.anim:CreateAnimation("Alpha")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    appear:SetDuration(0.15)
    row.fade = row.anim:CreateAnimation("Alpha")
    row.fade:SetFromAlpha(1)
    row.fade:SetToAlpha(0)
    row.fade:SetDuration(0.4)
    row.fade:SetOrder(2)
    row.anim:SetScript("OnFinished", function() Release(row) end)

    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Push(icon, name, value, bags, link)
    local row = table.remove(pool) or NewRow()
    StyleRow(row)
    row.icon:SetTexture(icon)
    row.name:SetText(name)
    row.value:SetText(value or "")
    row.bags:SetText(bags or "")
    row.link = link
    row:EnableMouse(link ~= nil)
    row:SetAlpha(1)
    row:Show()
    table.insert(rows, 1, row)
    while #rows > S.Get("lootFeedCount") do Release(rows[#rows]) end
    row.fade:SetStartDelay(S.Get("lootFeedFade"))
    row.anim:Restart()
    Layout()
end

local function OnItem(link, count)
    local item = Item:CreateFromItemLink(link)
    if item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
        local _, _, quality, _, _, _, _, _, _, texture, sellPrice = C_Item.GetItemInfo(link)
        if not quality or quality < S.Get("lootFeedQuality") then return end
        local worth = UnitPrice(link, sellPrice) * count
        AddSessionValue(worth)
        local _, _, _, hex = C_Item.GetItemQualityColor(quality)
        local name = ("|c%s%s|r |cff20ff20x%d|r"):format(hex, item:GetItemName(), count)
        local bags = C_Item.GetItemCount(link, S.Get("lootFeedBank"))
        Push(texture, name, S.Get("lootFeedValue") and worth > 0 and Coins(worth) or nil,
            bags > 0 and bags or nil, link)
    end)
end

local function OnMoney(copper)
    AddSessionValue(copper)
    if S.Get("lootFeedMoney") then Push(COIN_ICON, "Coins", Coins(copper)) end
end

-- CHAT_MSG_MONEY carries both your own looted coins and a group share, and only those, so
-- vendor sales and mail never reach the feed.
local function MoneyMessage(text)
    local copper = (tonumber(text:match(GOLD)) or 0) * 10000
        + (tonumber(text:match(SILVER)) or 0) * 100
        + (tonumber(text:match(COPPER)) or 0)
    if copper > 0 then OnMoney(copper) end
end

-- The combat XP message only ever carries kill experience, so quest experience never shows
-- twice. Its first number is the total gained, rested bonus included.
local function KillXP(text)
    local gained = tonumber(text:match("(%d+)"))
    if gained and gained > 0 then
        Push(XP_ICON, XP_COLOR .. "Experience|r", XP_COLOR .. "+" .. BreakUpLargeNumbers(gained) .. "|r")
    end
end

local function QuestTurnedIn(questID, xp, money)
    if money > 0 then AddSessionValue(money) end
    if xp <= 0 and money <= 0 then return end
    local parts = {}
    if xp > 0 then parts[#parts + 1] = XP_COLOR .. "+" .. BreakUpLargeNumbers(xp) .. " XP|r" end
    if money > 0 then parts[#parts + 1] = Coins(money) end
    local title = C_QuestLog.GetTitleForQuestID(questID) or "Quest Complete"
    Push(QUEST_ICON, "|cffffd100" .. title .. "|r", table.concat(parts, "  "))
end

local function Reputation(text)
    local faction, amount = text:match(REP_PATTERN)
    if faction then
        Push(REP_ICON, REP_COLOR .. faction .. "|r", REP_COLOR .. "+" .. amount .. " Rep|r")
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, text, ...)
    if event == "QUEST_TURNED_IN" then
        if S.Get("lootFeedQuest") then QuestTurnedIn(text, ...) end
        return
    end
    -- Chat payloads can be secret; nothing in one is worth recovering.
    if issecretvalue and issecretvalue(text) then return end
    if event == "CHAT_MSG_LOOT" then
        for _, pattern in ipairs(PATTERNS) do
            local link, count = text:match(pattern)
            if link then
                OnItem(link, tonumber(count) or 1)
                return
            end
        end
    elseif event == "CHAT_MSG_MONEY" then
        MoneyMessage(text)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if S.Get("lootFeedXP") then KillXP(text) end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if S.Get("lootFeedRep") then Reputation(text) end
    end
end)

local EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_XP_GAIN",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_TURNED_IN" }

-- Quick loot with Blizzard's loot window kept out of sight. Every slot is taken on
-- LOOT_READY, a slot per 0.05s as EUI's quick loot does on Forever. The window still opens
-- and closes as normal (hiding it would close the loot), shrunk to nothing instead: its open
-- and close animations both drive alpha, so alpha cannot hide it, and it is clamped to the
-- screen, so it cannot be moved off it. It stays full size whenever something would be left
-- behind for the player to deal with.
local lootWatch = CreateFrame("Frame")
local lootHidden, lootScale, lootHooked
local lootGen = 0

local function AllTakeable()
    local threshold = IsInGroup() and GetLootThreshold()
    local items = 0
    for i = 1, GetNumLootItems() do
        local _, _, _, currencyID, quality, locked, _, _, _, isCoin = GetLootSlotInfo(i)
        if locked then return false end
        if not (isCoin or currencyID) then
            items = items + 1
            if threshold and quality and quality >= threshold then return false end
        end
    end
    local free = 0
    for bag = 0, NUM_BAG_SLOTS do free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    return items <= free
end

local function ShrinkLootWindow()
    if not lootScale then
        lootScale = LootFrame:GetScale()
        LootFrame:SetScale(0.001)
    end
end

local function RestoreLootWindow()
    if lootScale then
        LootFrame:SetScale(lootScale)
        lootScale = nil
    end
end

local function ShowLootWindow()
    lootHidden = false
    RestoreLootWindow()
end

lootWatch:SetScript("OnEvent", function(_, event, _, arg2)
    if event == "LOOT_READY" then
        if IsShiftKeyDown() then return end
        lootHidden = AllTakeable()
        local gen = lootGen
        for i = 1, GetNumLootItems() do
            C_Timer.After(0.05 * i, function()
                if gen == lootGen then LootSlot(i) end
            end)
        end
    elseif event == "LOOT_CLOSED" then
        -- The window is still playing its close animation here; it gets its size back once
        -- that finishes, so it never flashes on the way out.
        lootGen = lootGen + 1
        lootHidden = false
    elseif event == "UI_ERROR_MESSAGE" and arg2 == ERR_INV_FULL then
        ShowLootWindow()
    end
end)

local function ApplyLootWindow()
    if S.Get("enabled") and S.Get("hideLootWindow") then
        if not lootHooked then
            lootHooked = true
            hooksecurefunc(LootFrame, "Open", function()
                if lootHidden then ShrinkLootWindow() else RestoreLootWindow() end
            end)
            LootFrame.HideAnim:HookScript("OnFinished", RestoreLootWindow)
        end
        lootWatch:RegisterEvent("LOOT_READY")
        lootWatch:RegisterEvent("LOOT_CLOSED")
        lootWatch:RegisterEvent("UI_ERROR_MESSAGE")
    else
        lootWatch:UnregisterAllEvents()
        ShowLootWindow()
    end
end

local function PlaceFeed()
    local pos = S.Get("lootFeedPos")
    feed:ClearAllPoints()
    if pos then
        feed:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        feed:SetPoint("CENTER", UIParent, "CENTER", -469, -141)
    end
end

local function CreateFeed()
    feed = CreateFrame("Frame", "NaowhForeverLootFeed", UIParent)
    feed:SetMovable(true)
    feed:SetClampedToScreen(true)
    gph = ns.Font(feed, 13, "OUTLINE", { r = 1, g = 0.82, b = 0 })
    gph:Hide()
    feed.mover = ns.UI.AttachMover(feed, "Loot Feed", function(pos) S.Set("lootFeedPos", pos) end)
    PlaceFeed()
end

local function Apply()
    ApplyLootWindow()
    if not On() then
        events:UnregisterAllEvents()
        if feed then
            for i = #rows, 1, -1 do Release(rows[i]) end
            feed.mover:Hide()
        end
        return
    end
    if not feed then CreateFeed() end
    feed:SetSize(S.Get("lootFeedWidth"), S.Get("lootFeedHeight"))
    gph:SetFont(ns.UI.FontPath(S.Get("lootFeedFont")), S.Get("lootFeedFontSize"), "OUTLINE")
    PlaceFeed()
    for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
    for _, row in ipairs(rows) do StyleRow(row) end
    feed.mover:SetShown(unlocked == true)
    Layout()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "hideLootWindow"
        or (key:find("^lootFeed") and key ~= "lootFeedPos") then
        Apply()
    end
end)
-- ns.Apply is what a profile switch re-runs.
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    if On() then
        Apply()
        Push(COIN_ICON, "Coins", Coins(31250))
        Push("Interface\\Icons\\INV_Pants_04","|cff1eff00Journeyman's Pants|r |cff20ff20x1|r",
            Coins(94), 1)
    end
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if feed then feed.mover:Hide() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
