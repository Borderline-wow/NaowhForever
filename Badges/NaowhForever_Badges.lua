-------------------------------------------------------------------------------
--  NaowhForever_Badges.lua -- supporter badges: the Naowh Forever N next to the name of
--  Naowh, a Developer, a Moderator or a Legendary Patron in chat, a card when you hover it,
--  a plate over their player tooltip, and a banner when one joins your group. Each part has its
--  own setting in QoL > Character: badges, card and tooltip start on so everyone sees them,
--  the banner starts off (Naowh's call). /nf badges preview puts one on your own name
--  (staff only).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\Badges\\"
local CACHE_SIZE = 200    -- chat lines remembered for the hover card
local TOAST_HOLD = 4      -- seconds a group toast stays up
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" }

local TIERS = {
    -- Naowh himself: Artifact gold, the one quality above Legendary, and the biggest sound.
    naowh = {
        title = "Founder",
        about = "The Man. The King.",
        label = "Naowh, the Founder",
        color = { r = 0xe6 / 255, g = 0xcc / 255, b = 0x80 / 255 },
        chat = MEDIA .. "BadgeNaowhChat.tga",
        large = MEDIA .. "BadgeNaowhLarge.tga",
        sound = "UI_72_ARTIFACT_FORGE_FINAL_TRAIT_UNLOCKED",
    },
    developer = {
        title = "Developer",
        about = "Builds Naowh Forever.",
        color = { r = 0x00 / 255, g = 0x91 / 255, b = 0xed / 255 },
        chat = MEDIA .. "BadgeDeveloperChat.tga",
        large = MEDIA .. "BadgeDeveloperLarge.tga",
        sound = "UI_72_ARTIFACT_FORGE_ACTIVATE_FINAL_TIER",
    },
    -- Epic purple: the next quality down, for the people who keep the community running.
    moderator = {
        title = "Moderator",
        about = "Keeps the community running.",
        color = { r = 0xa3 / 255, g = 0x35 / 255, b = 0xee / 255 },
        chat = MEDIA .. "BadgeModeratorChat.tga",
        large = MEDIA .. "BadgeModeratorLarge.tga",
        sound = "UI_PVP_HONOR_PRESTIGE_RANK_UP",
    },
    legendary = {
        title = "Legendary Patron",
        about = "Supports Naowh at the Legendary tier on Patreon.",
        color = { r = 0xff / 255, g = 0x80 / 255, b = 0x00 / 255 },
        chat = MEDIA .. "BadgeLegendaryChat.tga",
        large = MEDIA .. "BadgeLegendaryLarge.tga",
        sound = "UI_LEGENDARY_LOOT_TOAST",
        showsSince = true,  -- "Supporter since" is a patron's line, not a developer's
    },
}
-- The chat badge is as tall as the chat's text, so a line is no taller for it, and goes
-- this much lower: the Naowh and game fonts leave room above their capitals, so letters sit
-- under the middle of the line an icon is centred on.
local BADGE_DROP = 1

for _, tier in pairs(TIERS) do
    local c = tier.color
    tier.hex = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    tier.markup = ("|T%s:0:0:0:%d|t"):format(tier.chat, -BADGE_DROP)
    tier.tooltipLine = "|T" .. tier.chat .. ":16:16|t |c" .. tier.hex
        .. (tier.label or ("Naowh Forever " .. tier.title)) .. "|r"
end

local issecretvalue = issecretvalue
local function Secret(value) return issecretvalue and issecretvalue(value) end

-- A roster entry is a tier name ("developer"), or a table with a personal title and the
-- month the support started: { tier = "legendary", since = "2026-09", title = "..." }.
local previewGUID, previewEntry  -- /nf badges preview, this session only

-- This region's badges, from the staff list and the generated patron list. Another
-- region's characters are never looked at, so a GUID that happens to exist in two regions
-- can't borrow a badge.
local roster = {}

local function BuildRoster()
    wipe(roster)
    local region = GetCurrentRegion and GetCurrentRegion()
    local patrons = region and ns.BADGE_PATRONS and ns.BADGE_PATRONS[region]
    if patrons then
        for guid, entry in pairs(patrons) do
            entry.tier = "legendary"
            roster[guid] = entry
        end
    end
    local staff = region and ns.BADGE_STAFF and ns.BADGE_STAFF[region]
    if staff then
        for guid, entry in pairs(staff) do roster[guid] = entry end  -- staff wins
    end
end
BuildRoster()

local function EntryOf(guid)
    if not guid or Secret(guid) then return nil end
    if guid == previewGUID then return previewEntry end
    return roster[guid]
end

-- Preview and test toasts are for the team only, so nobody can screenshot a badge they
-- don't have. Any region counts: a preview only ever shows on your own screen.
local function IsStaff(guid)
    for _, list in pairs(ns.BADGE_STAFF or {}) do
        if list[guid] then return true end
    end
    return false
end

local function TierOf(entry)
    if type(entry) == "table" then return TIERS[entry.tier] end
    return entry and TIERS[entry]
end

local function TitleOf(entry, tier)
    return type(entry) == "table" and entry.title or tier.title
end

local function SinceOf(entry)
    local tier = TierOf(entry)
    local since = tier and tier.showsSince and entry.since
    if type(since) ~= "string" then return nil end
    local year, month = since:match("^(%d%d%d%d)%-(%d%d)$")
    month = year and MONTHS[tonumber(month)]
    if not month then return nil end
    return "Supporter since " .. month .. " " .. year
end

-------------------------------------------------------------------------------
--  Chat: the icon goes after the sender's name.
--  Blizzard skips this filter when the name is secret, so restricted chat stays untouched.
-------------------------------------------------------------------------------
-- Chat line -> sender GUID, so hovering a name finds its badge. A ring of reused slots: no
-- table per message, and the oldest line is forgotten first.
local guidByLine, lineAt, nextSlot = {}, {}, 1

local function Remember(lineID, guid)
    local old = lineAt[nextSlot]
    if old then guidByLine[old] = nil end
    lineAt[nextSlot], guidByLine[lineID] = lineID, guid
    nextSlot = nextSlot % CACHE_SIZE + 1
end

-- The badge goes after the name, so every name in chat starts where it would without one.
local function DecorateName(_, name, _, _, _, _, _, _, _, _, _, _, lineID, guid)
    local tier = TierOf(EntryOf(guid))
    if not tier then return name end
    if lineID and not Secret(lineID) then Remember(lineID, guid) end
    return name .. " " .. tier.markup
end

-------------------------------------------------------------------------------
--  Shared chrome for the card and the toast: panel, tier border and top bar, and the big
--  logo with its glow.
-------------------------------------------------------------------------------
local function Chrome(frame, iconSize)
    local bg = ns.Solid(frame, "BACKGROUND", T.bg, 0.97)
    bg:SetAllPoints()
    frame.border = ns.Border(frame)

    frame.bar = frame:CreateTexture(nil, "ARTWORK")
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("TOPRIGHT", -1, -1)
    frame.bar:SetHeight(2)
    frame.bar:SetColorTexture(1, 1, 1, 1)

    frame.glow = frame:CreateTexture(nil, "ARTWORK")
    frame.glow:SetSize(iconSize * 1.3, iconSize * 1.3)
    frame.glow:SetBlendMode("ADD")

    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(iconSize, iconSize)
    frame.icon:SetPoint("CENTER", frame.glow)
end

local function Paint(frame, tier)
    local c = tier.color
    frame.border:SetColor(c.r, c.g, c.b, 0.9)
    frame.bar:SetGradient("HORIZONTAL", CreateColor(c.r, c.g, c.b, 1), CreateColor(c.r, c.g, c.b, 0))
    frame.glow:SetTexture(tier.large)
    frame.icon:SetTexture(tier.large)
end

-------------------------------------------------------------------------------
--  The card shown while you hover a badged name
-------------------------------------------------------------------------------
local card

-- A soft band of light that crosses the logo every few seconds, clipped to its shape.
local function AddShine(frame)
    frame.mask = frame:CreateMaskTexture()
    frame.mask:SetAllPoints(frame.icon)
    frame.shines = {}
    for i = 1, 2 do
        local band = frame:CreateTexture(nil, "OVERLAY", nil, 2)
        band:SetSize(12, 90)
        band:SetColorTexture(1, 1, 1, 1)
        band:SetBlendMode("ADD")
        band:AddMaskTexture(frame.mask)
        if i == 1 then
            band:SetPoint("RIGHT", frame.icon, "LEFT", 0, 0)
            band:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.45))
        else
            band:SetPoint("LEFT", frame.shines[1], "RIGHT", 0, 0)
            band:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.45), CreateColor(1, 1, 1, 0))
        end
        local sweep = band:CreateAnimationGroup()
        sweep:SetLooping("REPEAT")
        local move = sweep:CreateAnimation("Translation")
        move:SetOffset(110, 0)
        move:SetDuration(0.9)
        move:SetStartDelay(0.3)
        move:SetEndDelay(2.4)
        move:SetSmoothing("IN_OUT")
        band.sweep = sweep
        frame.shines[i] = band
    end
end

-- Where the card's lines start: right of the logo, under the top bar.
local CARD_TEXT_LEFT, CARD_TEXT_TOP = 110, 16

local function BuildCard()
    card = CreateFrame("Frame", "NaowhForeverBadgeCard", UIParent)
    card:SetFrameStrata("TOOLTIP")
    card:SetWidth(360)
    card:SetClampedToScreen(true)
    card:Hide()
    Chrome(card, 80)
    card.glow:SetPoint("LEFT", 2, 0)
    AddShine(card)

    card.pulse = card.glow:CreateAnimationGroup()
    card.pulse:SetLooping("BOUNCE")
    local fade = card.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.2)
    fade:SetToAlpha(0.75)
    fade:SetDuration(1.1)
    fade:SetSmoothing("IN_OUT")
    local grow = card.pulse:CreateAnimation("Scale")
    grow:SetScaleFrom(0.94, 0.94)
    grow:SetScaleTo(1.06, 1.06)
    grow:SetDuration(1.1)
    grow:SetSmoothing("IN_OUT")
    card:SetScript("OnShow", function(self)
        self.pulse:Play()
        for i = 1, #self.shines do self.shines[i].sweep:Play() end
    end)
    card:SetScript("OnHide", function(self)
        self.pulse:Stop()
        for i = 1, #self.shines do self.shines[i].sweep:Stop() end
    end)

    -- The lines, each under the last, their letters on one left edge (ns.FontInset): each
    -- is moved by the difference between its size's inset and the one above it.
    local function Line(size, color, above, aboveSize, gap)
        local line = ns.Font(card, size, nil, color)
        if above then
            line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", ns.FontInset(aboveSize) - ns.FontInset(size), -gap)
        else
            line:SetPoint("TOPLEFT", CARD_TEXT_LEFT - ns.FontInset(size), -CARD_TEXT_TOP)
        end
        return line
    end
    card.brand = Line(10, T.muted)
    card.brand:SetText("NAOWH FOREVER")
    card.title = Line(19, nil, card.brand, 10, 4)
    card.player = Line(13, nil, card.title, 19, 4)
    card.about = Line(11, T.muted, card.player, 13, 6)
    card.about:SetWidth(238)
    card.about:SetJustifyH("LEFT")
    card.since = Line(10, nil, card.about, 11, 6)

    card.site = ns.Font(card, 10, nil, T.accentSoft)
    card.site:SetPoint("BOTTOMRIGHT", -10, 8)
    card.site:SetText("naowh.gg")
end

-- The card for a roster entry (or a preview's), at the cursor.
local function ShowEntryCard(entry, playerName)
    local tier = TierOf(entry)
    if not tier then return end
    if not card then BuildCard() end
    Paint(card, tier)
    card.mask:SetTexture(tier.large, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local c = tier.color
    card.title:SetText(TitleOf(entry, tier))
    card.title:SetTextColor(c.r, c.g, c.b, 1)
    card.player:SetText(playerName or "")
    card.about:SetText(tier.about)
    local since = SinceOf(entry)
    card.since:SetText(since or "")
    card.since:SetTextColor(c.r, c.g, c.b, 0.85)
    card:SetHeight(since and 136 or 112)

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    card:ClearAllPoints()
    card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale + 12)
    card:Show()
end

local function ShowCard(guid, playerName)
    ShowEntryCard(EntryOf(guid), playerName)
end

-- Chat frames report hovered links through EventRegistry; a player link reads
-- "player:Name-Realm:lineID:chatType...".
local function OnLinkEnter(_, _, link)
    if not link or Secret(link) then return end
    local kind, name, lineID = strsplit(":", link)
    if kind ~= "player" then return end
    local guid = guidByLine[tonumber(lineID)]
    if guid then ShowCard(guid, Ambiguate and Ambiguate(name, "none") or name) end
end

local function OnLinkLeave()
    if card then card:Hide() end
end

-------------------------------------------------------------------------------
--  Player tooltips: on the game's tooltip a plate of its own over its top, as wide as it, the
--  badge and the title in the tier's colour, as the hover card has them; on any other, a line.
--  The plate is ours, anchored to the tooltip (never the other way round), and goes when the
--  tooltip hides or moves on to someone else. The tooltip sizes itself after we add to it, so
--  the title is fitted each time the plate's width changes: in full where it fits, else the
--  title alone (the badge says it is Naowh Forever's), never cut off.
-------------------------------------------------------------------------------
local PLATE_H, PLATE_ICON, PLATE_GAP, PLATE_PAD = 26, 18, 2, 6
local plate

local function HidePlate()
    if plate then plate:Hide() end
end

-- Watched from the plate, not by hooking GameTooltip's scripts: OnTooltipCleared runs in the
-- middle of the game's own tooltip building, and with our hook on it the game's unit colouring
-- was reported failing on secret values as tainted by Naowh Forever.
local function PlateUpdate()
    local data = GameTooltip:IsShown() and GameTooltip:GetPrimaryTooltipData()
    local guid = data and data.guid
    if not guid or Secret(guid) or guid ~= plate.guid then plate:Hide() end
end

local function FitTitle()
    local title = plate.title
    title:SetText(plate.full)
    if plate.short and title:GetStringWidth() > title:GetWidth() then title:SetText(plate.short) end
end

local function BuildPlate()
    plate = CreateFrame("Frame", nil, UIParent)
    plate:SetFrameStrata("TOOLTIP")
    plate:SetHeight(PLATE_H)
    plate:Hide()
    Chrome(plate, PLATE_ICON)
    plate.glow:SetPoint("LEFT", PLATE_PAD - 2, 0)
    plate.title = ns.Font(plate, 12)
    plate.title:SetPoint("LEFT", plate.icon, "RIGHT", PLATE_PAD, 0)
    plate.title:SetPoint("RIGHT", -PLATE_PAD, 0)
    plate.title:SetJustifyH("LEFT")
    plate.title:SetWordWrap(false)
    plate:SetScript("OnSizeChanged", FitTitle)
    plate:SetScript("OnUpdate", PlateUpdate)
end

local function ShowPlate(tooltip, guid, entry, tier)
    if not plate then BuildPlate() end
    plate.guid = guid
    Paint(plate, tier)
    local c = tier.color
    local title = TitleOf(entry, tier)
    plate.full = tier.label or ("Naowh Forever " .. title)
    plate.short = not tier.label and title or nil
    FitTitle()
    plate.title:SetTextColor(c.r, c.g, c.b, 1)
    plate:ClearAllPoints()
    plate:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 0, PLATE_GAP)
    plate:SetPoint("BOTTOMRIGHT", tooltip, "TOPRIGHT", 0, PLATE_GAP)
    plate:Show()
end

local function AddTooltipLine(tooltip, data)
    if not S.Get("badgeTooltip") then return end
    local entry = EntryOf(data and data.guid)
    local tier = TierOf(entry)
    if not tier then
        if tooltip == GameTooltip then HidePlate() end
        return
    end
    if tooltip == GameTooltip then
        ShowPlate(tooltip, data.guid, entry, tier)
    else
        tooltip:AddLine(tier.tooltipLine)
    end
end

-------------------------------------------------------------------------------
--  Group toast: a supporter joining your group gets a short banner, once per group.
-------------------------------------------------------------------------------
local toast
local queueEntry, queueName, queueRaid, queueHead, queueTail = {}, {}, {}, 1, 0

local function BuildToast()
    toast = CreateFrame("Frame", "NaowhForeverBadgeToast", UIParent)
    toast:SetFrameStrata("HIGH")
    toast:SetSize(360, 66)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
    toast:Hide()
    Chrome(toast, 50)
    toast.glow:SetPoint("LEFT", 2, 0)

    toast.brand = ns.Font(toast, 9, nil, T.muted)
    toast.brand:SetPoint("TOPLEFT", 74, -12)
    toast.brand:SetText("NAOWH FOREVER")
    toast.text = ns.Font(toast, 14)
    toast.text:SetPoint("TOPLEFT", toast.brand, "BOTTOMLEFT", 0, -3)
    toast.title = ns.Font(toast, 12)
    toast.title:SetPoint("TOPLEFT", toast.text, "BOTTOMLEFT", 0, -3)

    toast.life = toast:CreateAnimationGroup()
    toast.life:SetToFinalAlpha(true)
    local inFade = toast.life:CreateAnimation("Alpha")
    inFade:SetFromAlpha(0)
    inFade:SetToAlpha(1)
    inFade:SetDuration(0.3)
    inFade:SetOrder(1)
    local inGrow = toast.life:CreateAnimation("Scale")
    inGrow:SetScaleFrom(0.92, 0.92)
    inGrow:SetScaleTo(1, 1)
    inGrow:SetDuration(0.3)
    inGrow:SetOrder(1)
    local hold = toast.life:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(TOAST_HOLD)
    hold:SetOrder(2)
    local outFade = toast.life:CreateAnimation("Alpha")
    outFade:SetFromAlpha(1)
    outFade:SetToAlpha(0)
    outFade:SetDuration(0.6)
    outFade:SetOrder(3)
end

local ShowNextToast

local function OnToastDone()
    toast:Hide()
    ShowNextToast()
end

function ShowNextToast()
    if queueHead > queueTail or (toast and toast:IsShown()) then return end
    local entry, name, raid = queueEntry[queueHead], queueName[queueHead], queueRaid[queueHead]
    queueEntry[queueHead], queueName[queueHead], queueRaid[queueHead] = nil, nil, nil
    queueHead = queueHead + 1
    local tier = TierOf(entry)
    if not tier then return ShowNextToast() end
    if not toast then
        BuildToast()
        toast.life:SetScript("OnFinished", OnToastDone)
    end
    Paint(toast, tier)
    local c = tier.color
    toast.text:SetText((name or "A supporter") .. " joined your " .. (raid and "raid" or "party"))
    toast.title:SetText(TitleOf(entry, tier))
    toast.title:SetTextColor(c.r, c.g, c.b, 1)
    toast:Show()
    toast.life:Play()
    local kit = SOUNDKIT and SOUNDKIT[tier.sound]
    if kit then PlaySound(kit) end
end

-- Forever names are a first name and a surname; UnitName only gives the first.
local function FullName(unit)
    local first, surname = UnitFullName(unit)
    if not first or Secret(first) or Secret(surname) then return nil end
    if surname and surname ~= "" then return first .. " " .. surname end
    return first
end

local function QueueToast(entry, name, raid)
    queueTail = queueTail + 1
    queueEntry[queueTail], queueName[queueTail], queueRaid[queueTail] = entry, name, raid
    ShowNextToast()
end

-- Unit tokens built once, so a scan makes no strings.
local PARTY_UNITS, RAID_UNITS = {}, {}
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

-- Supporters already announced in this group; forgotten when you leave it.
local announced = {}
local playerGUID, bannerOn
local groupEvents = CreateFrame("Frame")

-- Every character you log into, account-wide and by region, so /nf badges id can give one
-- code for your main and all your alts. One write per login.
local function RememberCharacter()
    local region = GetCurrentRegion and GetCurrentRegion()
    local guid = UnitGUID("player")
    if not region or not guid or Secret(guid) then return end
    local account = ns.AccountSettings()
    account.badgeCharacters = account.badgeCharacters or {}
    local characters = account.badgeCharacters
    characters[region] = characters[region] or {}
    characters[region][guid] = true
end

-- quiet: note who is there without a toast (logging in or reloading inside a group).
-- Guild members see each other every day, so their banner is optional.
local function InMyGuild(unit)
    local result = UnitIsInMyGuild and UnitIsInMyGuild(unit)
    return result == true and not Secret(result)
end

-- A scan put off until combat ends keeps its quiet, unless a normal one was put off in the
-- same fight: someone who joined mid-fight still gets their banner.
local deferQuiet

local function ScanGroup(quiet)
    if not IsInGroup() then
        wipe(announced)
        return
    end
    if InCombatLockdown() then
        deferQuiet = quiet and deferQuiet ~= false
        groupEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local raid = IsInRaid()
    local units = raid and RAID_UNITS or PARTY_UNITS
    local count = math.min(GetNumGroupMembers() - (raid and 0 or 1), #units)
    for i = 1, count do
        local unit = units[i]
        local guid = UnitGUID(unit)
        if guid and not Secret(guid) and guid ~= playerGUID and not announced[guid] then
            local entry = roster[guid]
            if TierOf(entry) then
                announced[guid] = true
                if not quiet and not (S.Get("badgeBannerSkipGuild") and InMyGuild(unit)) then
                    QueueToast(entry, FullName(unit), raid)
                end
            end
        end
    end
end

groupEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        playerGUID = UnitGUID("player")
        RememberCharacter()
        if bannerOn then ScanGroup(true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local quiet = deferQuiet
        deferQuiet = nil
        ScanGroup(quiet)
    else
        ScanGroup(false)
    end
end)
-- Always on: one event at login, to remember the character for /nf badges id.
groupEvents:RegisterEvent("PLAYER_ENTERING_WORLD")

-------------------------------------------------------------------------------
--  The guild and community member list (Guild & Communities): the badge after each badged
--  member's name, as in chat. The list is Blizzard's, loaded when the window first opens;
--  the badge is the addon's own texture on a row, kept in a side table, set each time the
--  list fills a row (it reuses rows as it scrolls) and hidden when the row is someone else.
-------------------------------------------------------------------------------
local LIST_BADGE = 14       -- as tall as the list's names
local LIST_BADGE_GAP = 3    -- the name's end to the badge

local listBadges = setmetatable({}, { __mode = "k" })   -- row -> its badge texture
local listOn, listWaiting

local function MemberScroll()
    local frame = CommunitiesFrame
    return frame and frame.MemberList and frame.MemberList.ScrollBox
end

-- The row's member, read from Blizzard's own field (never written).
local function PaintRow(row)
    local info = listOn and row.memberInfo
    local guid = info and info.guid
    local tier = guid and not Secret(guid) and TierOf(EntryOf(guid))
    local badge = listBadges[row]
    if not tier then
        if badge then badge:Hide() end
        return
    end
    local name = row.NameFrame and row.NameFrame.Name
    if not name then return end
    if not badge then
        badge = row.NameFrame:CreateTexture(nil, "OVERLAY")
        badge:SetSize(LIST_BADGE, LIST_BADGE)
        listBadges[row] = badge
    end
    badge:SetTexture(tier.chat)
    badge:ClearAllPoints()
    -- After the name's text, or at its edge when the list cuts a long name short.
    local width = math.min(name:GetStringWidth(), name:GetWidth())
    badge:SetPoint("LEFT", name, "LEFT", width + LIST_BADGE_GAP, -BADGE_DROP)
    badge:Show()
end

local function RowInitialized(_, row)
    PaintRow(row)
end

local function HookList()
    listWaiting = false
    local scroll = MemberScroll()
    if not (scroll and listOn) then return end
    scroll:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, RowInitialized, listBadges)
    scroll:ForEachFrame(PaintRow)
end

-- On with the chat badges. The list's code loads with the window, so the first time this
-- may wait for it; off, the callback goes and every badge on the list is hidden.
local function SyncList(on)
    if on == (listOn or false) then return end
    listOn = on
    local scroll = MemberScroll()
    if on then
        if scroll then
            HookList()
        elseif not listWaiting then
            listWaiting = true
            EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", HookList)
        end
    else
        if scroll then scroll:UnregisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, listBadges) end
        for _, badge in pairs(listBadges) do badge:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Settings. Each part is registered only while it's on. The name filter needs
--  ChatFrameUtil (Forever 1.60, retail 12.x); without it there are no chat badges or cards.
-------------------------------------------------------------------------------
local chatOn, cardOn, tooltipHooked

local function Apply()
    local chatAPI = (ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter) ~= nil
    local chat = chatAPI and S.Get("badgeChat") == true
    if chat ~= (chatOn or false) then
        chatOn = chat
        if chat then
            ChatFrameUtil.AddSenderNameFilter(DecorateName)
        else
            ChatFrameUtil.RemoveSenderNameFilter(DecorateName)
        end
    end
    SyncList(chat)

    -- The card needs the chat badges: it finds its player through the line they wrote.
    local cardWanted = chat and S.Get("badgeCard") == true
    if cardWanted ~= (cardOn or false) then
        cardOn = cardWanted
        if cardWanted then
            EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", OnLinkEnter, TIERS)
            EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", OnLinkLeave, TIERS)
        else
            EventRegistry:UnregisterCallback("ChatFrame.OnHyperlinkEnter", TIERS)
            EventRegistry:UnregisterCallback("ChatFrame.OnHyperlinkLeave", TIERS)
            OnLinkLeave()
        end
    end

    -- A tooltip post-call can't be removed, so it's added the first time the line is wanted
    -- and checks the setting itself.
    if S.Get("badgeTooltip") and not tooltipHooked then
        tooltipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLine)
    end

    local banner = S.Get("badgeBanner") == true
    if banner ~= (bannerOn or false) then
        bannerOn = banner
        if banner then
            groupEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
            ScanGroup(true)  -- whoever is already in the group doesn't get a banner
        else
            groupEvents:UnregisterEvent("GROUP_ROSTER_UPDATE")
            groupEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
            wipe(announced)
        end
    end
end

hooksecurefunc(S, "Set", function(key)
    if type(key) == "string" and key:find("^badge") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

-------------------------------------------------------------------------------
--  /nf badges
-------------------------------------------------------------------------------
local function PreviewEntry(tierKey)
    if tierKey == "developer" then return { tier = tierKey, title = "Lead Developer" } end
    return { tier = tierKey, since = date("%Y-%m") }
end

-- "90:Player-4613-006EB819,Player-4613-00ABCDEF": the region number (GetCurrentRegion;
-- Forever has its own, not retail's 1 to 5), then this character first. One group per region.
-- Returns the code and how many characters it holds.
local function BadgeCode()
    local characters = ns.AccountSettings().badgeCharacters or {}
    local current = GetCurrentRegion and GetCurrentRegion()
    local me = UnitGUID("player")
    local regions, count = {}, 0
    for region in pairs(characters) do regions[#regions + 1] = region end
    table.sort(regions, function(a, b)
        if a == current or b == current then return a == current and b ~= current end
        return a < b
    end)
    local groups = {}
    for _, region in ipairs(regions) do
        local list = {}
        for guid in pairs(characters[region]) do
            if not (region == current and guid == me) then list[#list + 1] = guid end
        end
        table.sort(list)
        if region == current and me then table.insert(list, 1, me) end
        if #list > 0 then
            count = count + #list
            groups[#groups + 1] = region .. ":" .. table.concat(list, ",")
        end
    end
    return table.concat(groups, ";"), count
end

-- Naowh's Discord: where a badge is asked for (a support request), and more on the badges.
local DISCORD = "https://discord.com/invite/naowh"
ns.NAOWH_DISCORD = DISCORD

local function ShowCode(code, count)
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(440, 150, "badgeCode")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE")
    head:SetPoint("TOP", 0, -14)
    head:SetText("Your badge code")
    local hint = UI.KeepFont(panel, "hint", 11, nil, T.muted)
    hint:SetPoint("TOP", head, "BOTTOM", 0, -6)
    hint:SetWidth(400)   -- two lines at most: the code box sits under it
    hint:SetText(count .. (count == 1 and " character" or " characters")
        .. ". Ctrl+C to copy it, then send it in a support request on Discord to be added.")
    local box = UI.Keep(panel, "box", ns.NewEditBox)
    box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
    box:SetSize(400, 28)
    box:SetMaxLetters(0)
    box:SetText(code)
    -- Read only: typing puts the code back, so a stray key can't break it.
    box:SetScript("OnTextChanged", function(self, byUser)
        if byUser then self:SetText(code); self:HighlightText() end
    end)
    box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    -- Discord's link to copy beside Close (the game opens no browser): the code first, then it.
    UI.KeepButton(panel, "discord", "Discord", 96, 26, function()
        dimmer:Hide()
        ns.ShowCopyLine("Naowh's Discord", DISCORD, TIERS.legendary.large)
    end):SetPoint("BOTTOM", panel, "BOTTOM", -52, 14)
    UI.KeepButton(panel, "close", "Close", 96, 26, function() dimmer:Hide() end)
        :SetPoint("BOTTOM", panel, "BOTTOM", 52, 14)
    dimmer:Show()
    box:SetFocus()
    box:HighlightText()
end

function ns.BadgesCommand(arg)
    local word = strtrim(arg or ""):lower()
    local previewTier = word == "preview" and "legendary" or word:match("^preview (%a+)$")
    local staffOnly = previewTier or word == "toast"
    if staffOnly and not IsStaff(UnitGUID("player")) then
        ns.Print("Badge previews are for the Naowh Forever team.")
    elseif word == "id" then
        RememberCharacter()
        local code, count = BadgeCode()
        ShowCode(code, count)
    elseif previewTier == "none" then
        -- You as a player with no badge, to see what everyone else sees (the character panel's
        -- grey Legendary Patron and its card): until the reload, or preview off.
        previewEntry = false
        previewGUID = UnitGUID("player")
        ns.Print("Preview on: you wear no badge until you reload, as a player without one sees it.")
    elseif previewTier and TIERS[previewTier] then
        previewEntry = PreviewEntry(previewTier)
        previewGUID = UnitGUID("player")
        ns.Print("Preview on: your name wears the " .. TierOf(previewEntry).title
            .. " badge until you reload. Say something to see it.")
    elseif word == "preview off" then
        previewGUID, previewEntry = nil, nil
        ns.Print("Preview off.")
    elseif word == "toast" then
        QueueToast(previewEntry or PreviewEntry("legendary"), FullName("player"), IsInRaid())
    else
        ns.Print("/nf badges id | preview [legendary|moderator|developer|naowh|none] | preview off | toast")
    end
end

-- For the other modules (the character panel's badge): the badge a character wears, as its
-- tier ({ title, label, about, color, large }) and roster entry, nil for none; the tiers; a
-- patron's "Supporter since" line; and the badge code's card.
function ns.BadgeOf(guid)
    local entry = EntryOf(guid)
    local tier = TierOf(entry)
    if not tier then return nil end
    return tier, entry
end
ns.BADGE_TIERS = TIERS
ns.BadgeSince = SinceOf

function ns.ShowBadgeCode()
    RememberCharacter()
    ShowCode(BadgeCode())
end

-- The card people see when they hover a badged name, for a tier's badge on playerName: what
-- the character panel's "Become a Legendary Patron" card shows on its sample chat line.
function ns.ShowBadgeCard(tierKey, playerName)
    ShowEntryCard(PreviewEntry(tierKey), playerName)
end

function ns.HideBadgeCard()
    if card then card:Hide() end
end

-- For the offline test.
ns._BadgesTest = { DecorateName = DecorateName, ListBadges = listBadges, OnLinkEnter = OnLinkEnter, TIERS = TIERS,
    guidByLine = guidByLine, CACHE_SIZE = CACHE_SIZE, SinceOf = SinceOf,
    BuildRoster = BuildRoster, BadgeCode = BadgeCode,
    Card = function() return card end, Toast = function() return toast end,
    QueueSize = function() return queueTail - queueHead + 1 end, GroupEvents = groupEvents }

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local BADGE_KEYS = { "badgeChat", "badgeCard", "badgeTooltip", "badgeBanner", "badgeBannerSkipGuild" }

local function BadgesSummary(store)
    local on = 0
    for i = 1, #BADGE_KEYS do
        if store.Get(BADGE_KEYS[i]) then on = on + 1 end
    end
    return ("%d of %d on"):format(on, #BADGE_KEYS)
end

Settings.Page("QoL/Character", S):Card({
    id = "supporterBadges", name = "Supporter Badges", order = 40,
    help = "Shows who Naowh, the developers, the moderators and our Legendary patrons are: a badge "
        .. "by their name in chat, a line on their tooltip and, if you want it, a banner when one "
        .. "of them joins your group.",
    summary = BadgesSummary,
    rows = {
        { key = "badgeChat", label = "Chat Badges", toggle = true,
          help = "The Naowh Forever N next to the name of Naowh, the developers, the moderators and "
              .. "our Legendary patrons in chat." },
        { key = "badgeCard", label = "Hover Card", toggle = true, needs = "badgeChat",
          help = "Hover a badged name in chat to see their card." },
        { key = "badgeTooltip", label = "Tooltip Line", toggle = true,
          help = "A line in their colour on their player tooltip." },
        { key = "badgeBanner", label = "Group Banner", toggle = true,
          help = "A banner and a sound when one of them joins your group." },
        { key = "badgeBannerSkipGuild", label = "No Banner For Guild Members", toggle = true,
          needs = "badgeBanner", help = "Skips the banner when they're in your guild." },
    },
})
