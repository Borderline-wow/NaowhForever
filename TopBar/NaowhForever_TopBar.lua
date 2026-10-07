-------------------------------------------------------------------------------
--  NaowhForever_TopBar.lua -- [buttons] [clock] [buttons] across the top of the screen, FPS / MS
--  under it. One saved layout orders the buttons on each side: friends, guild and Hearthstone
--  (secure buttons) and any addon's LibDataBroker source. The settings card's preview edits it:
--  drag a button to move it, its x removes it, a side's + adds one.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME
local Parts = ns.Shared.Parts

local S = UI.ModuleSettings("topBar", {
    enabled = true,
    -- The clock font is EllesmereUI's, found through SharedMedia; without it the Addon Font.
    iconSize = 22, clockSize = 27, clockFont = "Gotham Narrow Ultra", clockOutline = "NONE", use24h = true,
    font = "", outline = "OUTLINE",
    bgAlpha = 85, iconColor = { r = 1, g = 1, b = 1 },
    hideInCombat = false, mouseover = false, mouseoverAlpha = 0,
    showSystem = true, systemTooltip = true, sysSize = 13, tooltipScale = 120,
    layout = { left = { "friends", "guild" }, right = { "ldb:NaowhForeverJournal", "ldb:NaowhForeverBiS" } },
})
ns.TopBarSettings = S

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\TopBar\\"
local HEARTHSTONE = 6948
local BTN_PAD, GAP, EDGE, CLOCK_GAP, CLOCK_PAD, SEG_PAD = 8, 4, 14, 22, 6, 6
local ROSTER_CAP = 40   -- keeps a big guild's tooltip on the screen
local BADGE_SIZE = 10   -- the online count on Friends and Guild

-- Our own glyphs for our modules; any other source's icon is desaturated and tinted to match.
local GLYPH = {
    NaowhForeverJournal = MEDIA .. "icon-journal.png",
    NaowhForeverBiS = MEDIA .. "icon-bis.png",
    NaowhForeverGroup = MEDIA .. "icon-group.png",
}

-- Clicks pass through to Blizzard's own button, the first of these that exists.
local CLICK_THROUGH = {
    friends = { "QuickJoinToastButton", "FriendsMicroButton", "SocialsMicroButton" },
    guild = { "GuildMicroButton" },
}

local bar, clockText, leftGroup, rightGroup, ticker, unlocked, fitPending
local buttons = {}
local lastRoster, lastTipRoster, lastMemScan = 0, 0, 0
local memList = {}
-- The dark pills behind the buttons; ns.ThemeTint swaps in the player's Background color.
local PILL_BG = { r = 0.03, g = 0.03, b = 0.04 }

local function On() return S.Get("enabled") end
local function LDB() return LibStub("LibDataBroker-1.1", true) end
local function Accent() return T.accent.r, T.accent.g, T.accent.b end
-- A grey or white of the tooltips and the clock: the shade it always was, or the player's
-- Text ("fg") / Secondary Text ("muted") when the theme changed that color. Returns r, g, b,
-- so where it is not the last argument its values are put in locals first.
local shades = {}
local function Tone(key, v)
    local shade = shades[v]
    if not shade then
        shade = { r = v, g = v, b = v }
        shades[v] = shade
    end
    local c = ns.ThemeTint(key, shade)
    return c.r, c.g, c.b
end
local function IconColor()
    local c = S.Get("iconColor")
    return c.r, c.g, c.b
end
local function BtnSize() return S.Get("iconSize") + BTN_PAD end
local function BarHeight() return math.max(S.Get("clockSize") + CLOCK_PAD, BtnSize() + 2) end

-- Show On Mouseover fades rather than hides: the bar holds secure buttons. Every enter and
-- leave on the bar or its buttons calls this, since a leave into a gap fires nothing else.
local function UpdateHover()
    local faded = S.Get("mouseover") and not unlocked and not (bar:IsMouseOver() or bar.sys:IsMouseOver())
    local alpha = faded and S.Get("mouseoverAlpha") / 100 or 1
    bar:SetAlpha(alpha)
    bar.sys:SetAlpha(alpha)
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local SIDES = { "left", "right" }
local LDB_PREFIX = "ldb:"
local BUILTIN = { friends = "Friends", guild = "Guild", hearth = "Hearthstone" }
local BUILTIN_ORDER = { "friends", "guild", "hearth" }
local ICON = {
    friends = MEDIA .. "icon-friends.png",
    guild = MEDIA .. "icon-guild.png",
    hearth = MEDIA .. "icon-hearth.png",
}
local OLD_BUTTONS = { showFriends = true, showGuild = true, showHearth = false }
local OLD_BROKERS = { "NaowhForeverJournal", "NaowhForeverBiS" }
local OLD_DQ, JOURNAL = "NaowhForeverDQ", "NaowhForeverJournal"

local function IndexOf(list, key)
    for i = 1, #list do
        if list[i] == key then return i end
    end
end

local function InLayoutOf(layout, key)
    return IndexOf(layout.left, key) ~= nil or IndexOf(layout.right, key) ~= nil
end

local function MigrateBrokers(db)
    local saved = db.brokers
    if not (saved and IndexOf(saved, OLD_DQ)) then return end
    local keep = IndexOf(saved, JOURNAL) ~= nil
    for i = #saved, 1, -1 do
        if saved[i] == OLD_DQ then
            if keep then table.remove(saved, i) else saved[i], keep = JOURNAL, true end
        end
    end
    local sides = db.brokerSide
    if sides and sides[OLD_DQ] then
        sides[JOURNAL] = sides[JOURNAL] or sides[OLD_DQ]
        sides[OLD_DQ] = nil
    end
end

local function OldButton(db, key)
    local v = db[key]
    if v == nil then return OLD_BUTTONS[key] end
    return v
end

local function MigrateLayout(db)
    db.layoutMigrated = true
    if db.layout ~= nil then return end
    if db.showFriends == nil and db.showGuild == nil and db.showHearth == nil and db.brokers == nil
        and db.brokerSide == nil then return end
    MigrateBrokers(db)
    local left, right = {}, {}
    if OldButton(db, "showHearth") then right[1] = "hearth" end
    local sides = type(db.brokerSide) == "table" and db.brokerSide or {}
    for _, name in ipairs(type(db.brokers) == "table" and db.brokers or OLD_BROKERS) do
        local list = sides[name] == "left" and left or right
        list[#list + 1] = LDB_PREFIX .. name
    end
    if OldButton(db, "showFriends") then left[#left + 1] = "friends" end
    if OldButton(db, "showGuild") then left[#left + 1] = "guild" end
    db.layout = { left = left, right = right }
end

local function SavedLayout()
    local db = S.DB()
    if not db.layoutMigrated then MigrateLayout(db) end
    local layout = S.Get("layout")
    if type(layout) ~= "table" or type(layout.left) ~= "table" or type(layout.right) ~= "table" then
        return S.Default("layout")
    end
    return layout
end

-------------------------------------------------------------------------------
--  Live info
-------------------------------------------------------------------------------
local function FriendsOnline()
    local _, bn = BNGetNumFriends()
    return (bn or 0) + (C_FriendList.GetNumOnlineFriends() or 0)
end

local function GuildOnline()
    if not IsInGuild() then return end
    local _, online = GetNumGuildMembers()
    return online or 0
end

local function HearthCooldown()
    local start, dur = C_Container.GetItemCooldown(HEARTHSTONE)
    if dur and dur > 0 then
        local left = start + dur - GetTime()
        if left > 0 then return left end
    end
end

local function FmtCD(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then return ("%d:%02d:%02d"):format(sec / 3600, (sec % 3600) / 60, sec % 60) end
    return ("%d:%02d"):format(sec / 60, sec % 60)
end

-- GetSavedInstanceInfo's reset counts down from the last UPDATE_INSTANCE_INFO, not from now.
local lockoutsAt = 0

-- Saved instances, soonest reset first, each with its line for a tooltip or chat.
local function Lockouts()
    local out, elapsed = {}, GetTime() - lockoutsAt
    for i = 1, GetNumSavedInstances() do
        local name, _, reset, _, locked, extended, _, _, _, _, total, done = GetSavedInstanceInfo(i)
        local left = (reset or 0) - elapsed
        if (locked or extended) and left > 0 then
            local d, h, m = math.floor(left / 86400), math.floor(left / 3600) % 24, math.floor(left / 60) % 60
            out[#out + 1] = {
                left = left,
                name = (total and total > 0) and ("%s %d/%d"):format(name, done or 0, total) or name,
                reset = d > 0 and ("%dd %dh"):format(d, h) or h > 0 and ("%dh %dm"):format(h, m) or ("%dm"):format(m),
            }
        end
    end
    table.sort(out, function(a, b) return a.left < b.left end)
    return out
end

function ns.LockoutsCommand()
    local list = Lockouts()
    if #list == 0 then ns.Print("You are not saved to any instance.") return end
    ns.Print("Saved instances:")
    for _, l in ipairs(list) do print(("   %s: resets in %s"):format(l.name, l.reset)) end
end

local function Hex(r, g, b)
    return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

local function Band(r, g, b) return { r = r, g = g, b = b, hex = Hex(r, g, b) } end
local FPS_GREAT, FPS_GOOD, FPS_OK, FPS_LOW = Band(0.25, 1, 0.25), Band(0.55, 1, 0.25), Band(1, 1, 0.25),
    Band(1, 0.35, 0.25)
local MS_GOOD, MS_OK, MS_HIGH = Band(0.25, 1, 0.25), Band(1, 1, 0.25), Band(1, 0.35, 0.25)

local function FpsBand(fps)
    if fps >= 100 then return FPS_GREAT end
    if fps >= 60 then return FPS_GOOD end
    if fps >= 30 then return FPS_OK end
    return FPS_LOW
end

local function MsBand(ms)
    if ms < 75 then return MS_GOOD end
    if ms < 150 then return MS_OK end
    return MS_HIGH
end

local function FpsRGB(fps)
    local c = FpsBand(fps)
    return c.r, c.g, c.b
end

local function MsRGB(ms)
    local c = MsBand(ms)
    return c.r, c.g, c.b
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
-- The bar's own tooltips at Tooltip Size; GameTooltip's own scale comes back when it hides.
local tipBase, tipHooked

local function TipHidden(self)
    if tipBase then
        self:SetScale(tipBase)
        tipBase = nil
    end
end

local function OwnTooltip(owner)
    if not tipHooked then
        tipHooked = true
        GameTooltip:HookScript("OnHide", TipHidden)
    end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    tipBase = tipBase or GameTooltip:GetScale()
    GameTooltip:SetScale(tipBase * S.Get("tooltipScale") / 100)
end

-- Online Battle.net friends in WoW, then character friends.
local function AddFriendsRoster()
    local shown = 0
    local lr, lg, lb = Tone("muted", 0.7)
    local function Row(left, right, r, g, b)
        shown = shown + 1
        if shown <= ROSTER_CAP then GameTooltip:AddDoubleLine(left, right or "", r, g, b, lr, lg, lb) end
    end
    for i = 1, (BNGetNumFriends() or 0) do
        local acc = C_BattleNet.GetFriendAccountInfo(i)
        local ga = acc and acc.gameAccountInfo
        if ga and ga.isOnline and ga.clientProgram == BNET_CLIENT_WOW then
            local right = ga.characterName or ""
            if ga.areaName and ga.areaName ~= "" then
                right = (right ~= "" and right .. " - " or "") .. ga.areaName
            end
            Row(acc.accountName or "?", right, 0.51, 0.77, 1)
        end
    end
    for i = 1, C_FriendList.GetNumFriends() do
        local fi = C_FriendList.GetFriendInfoByIndex(i)
        if fi and fi.connected then
            Row(fi.name .. (fi.level and fi.level > 0 and "  " .. fi.level or ""), fi.area, Tone("fg", 1))
        end
    end
    if shown > ROSTER_CAP then
        GameTooltip:AddLine(("... and %d more"):format(shown - ROSTER_CAP), Tone("muted", 0.5))
    end
    return shown
end

-- GuildRoster() answers later and is rate limited, so the list may be a request behind.
local function AddGuildRoster()
    if GetTime() - lastTipRoster >= 10 then
        lastTipRoster = GetTime()
        C_GuildInfo.GuildRoster()
    end
    local gname = GetGuildInfo("player")
    if gname then GameTooltip:AddLine(gname, 0.1, 1, 0.1) end
    local shown = 0
    local lr, lg, lb = Tone("muted", 0.7)
    -- The away tags keep their grey unless the theme changed Secondary Text.
    local grey = ns.ThemeTint("muted", nil) and ns.Color("muted") or "|cff808080"
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, online, status, class = GetGuildRosterInfo(i)
        if online then
            shown = shown + 1
            if shown <= ROSTER_CAP then
                local cc = RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
                local away = (status == 1 and "  " .. grey .. "<AFK>|r") or (status == 2 and "  " .. grey .. "<DND>|r") or ""
                GameTooltip:AddDoubleLine(level .. "  " .. (name:match("[^%-]+") or name) .. away, zone or "",
                    cc.r, cc.g, cc.b, lr, lg, lb)
            end
        end
    end
    if shown > ROSTER_CAP then
        GameTooltip:AddLine(("... and %d more"):format(shown - ROSTER_CAP), Tone("muted", 0.5))
    end
end

-- Roster names and zones can come back secret in combat, so the lists wait for it to end.
local TOOLTIP = {
    friends = function()
        local mr, mg, mb = Tone("muted", 0.7)
        GameTooltip:AddLine("Friends", Tone("fg", 1))
        GameTooltip:AddDoubleLine("Online", tostring(FriendsOnline()), mr, mg, mb, 0.3, 1, 0.3)
        if not InCombatLockdown() then
            GameTooltip:AddLine(" ")
            local ok, count = pcall(AddFriendsRoster)
            if ok and count == 0 then GameTooltip:AddLine("No friends online", Tone("muted", 0.6)) end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open Friends", Accent())
    end,
    guild = function()
        local mr, mg, mb = Tone("muted", 0.7)
        GameTooltip:AddLine("Guild", Tone("fg", 1))
        local n = GuildOnline()
        if n then
            GameTooltip:AddDoubleLine("Online", tostring(n), mr, mg, mb, 1, 0.6, 0.1)
            if not InCombatLockdown() then
                GameTooltip:AddLine(" ")
                pcall(AddGuildRoster)
            end
        else
            GameTooltip:AddLine("Not in a guild", mr, mg, mb)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open Guild", Accent())
    end,
    hearth = function()
        local mr, mg, mb = Tone("muted", 0.7)
        GameTooltip:AddLine(C_Item.GetItemNameByID(HEARTHSTONE) or "Hearthstone", Tone("fg", 1))
        GameTooltip:AddDoubleLine("Bind", GetBindLocation() or "", mr, mg, mb, Tone("fg", 1))
        local cd = HearthCooldown()
        if cd then
            GameTooltip:AddDoubleLine("Cooldown", FmtCD(cd), mr, mg, mb, 1, 0.3, 0.3)
        else
            GameTooltip:AddDoubleLine("Cooldown", "Ready", mr, mg, mb, 0.3, 1, 0.3)
        end
    end,
}

local function ShowTooltip(b)
    OwnTooltip(b)
    TOOLTIP[b.key]()
    GameTooltip:Show()
end

local function ByMem(a, b) return a.mem > b.mem end

local function ShowSystemTooltip(owner)
    OwnTooltip(owner)
    local fps = math.floor(GetFramerate() + 0.5)
    local _, _, home, world = GetNetStats()
    local mr, mg, mb = Tone("muted", 0.7)
    GameTooltip:AddDoubleLine("FPS", fps .. " fps", mr, mg, mb, FpsRGB(fps))
    GameTooltip:AddDoubleLine("Home Latency", math.floor(home) .. " ms", mr, mg, mb, MsRGB(home))
    GameTooltip:AddDoubleLine("World Latency", math.floor(world) .. " ms", mr, mg, mb, MsRGB(world))
    -- The memory scan is a frame spike, so it runs at most every 30 seconds.
    if GetTime() - lastMemScan >= 30 then
        lastMemScan = GetTime()
        UpdateAddOnMemoryUsage()
        local n = 0
        for i = 1, C_AddOns.GetNumAddOns() do
            local mem = GetAddOnMemoryUsage(i)
            if mem > 0 then
                n = n + 1
                memList[n] = memList[n] or {}
                memList[n].name, memList[n].mem = select(2, C_AddOns.GetAddOnInfo(i)), mem
            end
        end
        for i = n + 1, #memList do memList[i] = nil end
        table.sort(memList, ByMem)
    end
    if #memList > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Addon Memory", Accent())
        local fr, fg, fb = Tone("fg", 1)
        for i = 1, math.min(10, #memList) do
            local e = memList[i]
            GameTooltip:AddDoubleLine(e.name, e.mem > 1024 and ("%.2f MB"):format(e.mem / 1024)
                or ("%.0f KB"):format(e.mem), fr, fg, fb, Accent())
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: refresh    Shift-click: collect garbage", Accent())
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  Buttons
-------------------------------------------------------------------------------
local function ShowClockTooltip(owner)
    OwnTooltip(owner)
    GameTooltip:SetText(date("%A, %B %d"), Tone("fg", 1))
    local list = Lockouts()
    if #list > 0 then
        local mr, mg, mb = Tone("muted", 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Saved Instances", Tone("fg", 1))
        for _, l in ipairs(list) do
            GameTooltip:AddDoubleLine(l.name, "resets in " .. l.reset, mr, mg, mb, Tone("fg", 1))
        end
    end
    GameTooltip:Show()
end

local function ShowBrokerTooltip(owner, name)
    local obj = LDB():GetDataObjectByName(name)
    if not obj then return end
    if obj.OnEnter then
        obj.OnEnter(owner)
    elseif obj.OnTooltipShow then
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        obj.OnTooltipShow(GameTooltip)
        GameTooltip:Show()
    end
end

local function LeaveBroker(owner, name)
    local obj = LDB():GetDataObjectByName(name)
    if obj and obj.OnLeave then obj.OnLeave(owner) end
end

local function NewButton(key, parent, template)
    local b = CreateFrame("Button", template and ("NaowhForeverTopBar_" .. key) or nil, parent, template)
    b:RegisterForClicks("AnyUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.key = key
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(IconColor())
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
        UpdateHover()
    end)
    buttons[key] = b
    return b
end

local function Badge(b, r, g, bl)
    b.badge = b:CreateFontString(nil, "OVERLAY")
    b.badge:SetFont(ns.UIFontPath(), BADGE_SIZE, "OUTLINE")
    b.badge:SetPoint("CENTER", b.icon, "BOTTOM", 0, 1)
    b.badge:SetTextColor(r, g, bl)
end

-- Secure, so a click reaches Blizzard's panel even in combat. Built out of combat only.
local function SecureButton(key, parent)
    local b = NewButton(key, parent, "SecureActionButtonTemplate")
    b.icon:SetTexture(MEDIA .. "icon-" .. key .. ".png")
    b:SetAttribute("useOnKeyDown", false)
    if key == "hearth" then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. HEARTHSTONE)
    else
        local target
        for _, name in ipairs(CLICK_THROUGH[key]) do target = target or _G[name] end
        if target then
            b:SetAttribute("*type1", "click")
            b:SetAttribute("*clickbutton1", target)
        else
            b:SetAlpha(0.35)
        end
    end
    b:SetScript("OnEnter", function(self)
        UpdateHover()
        self.icon:SetVertexColor(Accent())
        ShowTooltip(self)
        if key == "hearth" then
            local t = 0
            self:SetScript("OnUpdate", function(s, e)
                t = t + e
                if t >= 0.5 then t = 0; ShowTooltip(s) end
            end)
        end
    end)
    return b
end

-- A plain button handing clicks and the tooltip to the broker object.
local function BrokerButton(name)
    local b = buttons["ldb:" .. name]
    if b then return b end
    b = NewButton("ldb:" .. name, rightGroup)
    b:SetScript("OnClick", function(self, button)
        local obj = LDB():GetDataObjectByName(name)
        if obj and obj.OnClick then obj.OnClick(self, button) end
    end)
    b:SetScript("OnEnter", function(self)
        UpdateHover()
        self.icon:SetVertexColor(Accent())
        ShowBrokerTooltip(self, name)
    end)
    b:HookScript("OnLeave", function(self) LeaveBroker(self, name) end)
    return b
end

local function SetBadge(b, n)
    if b.count == n then return end
    b.count = n
    b.badge:SetText(n and n > 0 and n or "")
end

local function UpdateBadges()
    if not bar then return end
    SetBadge(buttons.friends, FriendsOnline())
    SetBadge(buttons.guild, GuildOnline())
    if InLayoutOf(SavedLayout(), "guild") and IsInGuild() and not InCombatLockdown() and GetTime() - lastRoster >= 15 then
        lastRoster = GetTime()
        C_GuildInfo.GuildRoster()
    end
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
local Look = {}

function Look.NewPills(frame)
    local segs = {}
    for i = 1, 3 do
        local seg = frame:CreateTexture(nil, "BACKGROUND")
        local line = frame:CreateTexture(nil, "BORDER")
        ns.Hairline(line, "h")
        line:SetPoint("BOTTOMLEFT", seg, "BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT")
        line:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.55)
        seg.line = line
        segs[i] = seg
    end
    return segs
end

function Look.PaintPills(frame, segs, left, right, clock, nLeft, nRight)
    local pill = ns.ThemeTint("bg", PILL_BG)
    for _, seg in ipairs(segs) do seg:SetColorTexture(pill.r, pill.g, pill.b, S.Get("bgAlpha") / 100) end
    local segL, segC, segR = segs[1], segs[2], segs[3]
    segL:ClearAllPoints()
    segL:SetPoint("TOPLEFT", left, "TOPLEFT", -SEG_PAD, 0)
    segL:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", SEG_PAD, 0)
    segL:SetShown(nLeft > 0)
    segL.line:SetShown(nLeft > 0)
    segR:ClearAllPoints()
    segR:SetPoint("TOPLEFT", right, "TOPLEFT", -SEG_PAD, 0)
    segR:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", SEG_PAD, 0)
    segR:SetShown(nRight > 0)
    segR.line:SetShown(nRight > 0)
    segC:ClearAllPoints()
    segC:SetPoint("LEFT", clock, "LEFT", -(SEG_PAD + 4), 0)
    segC:SetPoint("RIGHT", clock, "RIGHT", SEG_PAD + 4, 0)
    segC:SetPoint("TOP", frame, "TOP")
    segC:SetPoint("BOTTOM", frame, "BOTTOM")
end

function Look.ClockFont(clock)
    local size, outline = S.Get("clockSize"), S.Get("clockOutline")
    local flags = outline == "NONE" and "" or outline
    if not clock:SetFont(UI.FontPath(S.Get("clockFont")), size, flags) then
        clock:SetFont(ns.UIFontPath(), size, flags)
    end
    Parts.HudText(clock, outline == "" and "card" or false)
    clock:SetTextColor(Tone("fg", 1))
end

function Look.ClockText()
    local use24h = S.Get("use24h")
    local text = date(use24h and "%H:%M" or "%I:%M %p")
    if not use24h then text = text:gsub("^0", "") end
    return text
end

function Look.Row(group, list, n)
    local size, icon, x = BtnSize(), S.Get("iconSize"), 0
    local font, outline = S.Get("font"), S.Get("outline")
    for i = 1, n do
        local b = list[i]
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", group, "LEFT", x, 0)
        b.icon:SetSize(icon, icon)
        b.icon:SetVertexColor(IconColor())
        if b.badge then Parts.HudFont(b.badge, font, BADGE_SIZE, outline) end
        b:Show()
        x = x + size + GAP
    end
    group:SetSize(math.max(1, x - GAP), size)
end

function Look.Fit(frame, left, right, clock)
    local side = math.max(left:GetWidth(), right:GetWidth())
    local clockW = math.max(24, clock:GetStringWidth() + 8)
    frame:SetWidth(2 * (EDGE + side + CLOCK_GAP) + clockW)
    left:ClearAllPoints()
    left:SetPoint("LEFT", frame, "LEFT", EDGE + side - left:GetWidth(), 0)
    right:ClearAllPoints()
    right:SetPoint("RIGHT", frame, "RIGHT", -(EDGE + side - right:GetWidth()), 0)
end

function Look.SystemFont(text)
    Parts.HudFont(text, S.Get("font"), S.Get("sysSize"), S.Get("outline"))
    text:SetTextColor(Tone("fg", 1))
end

local SYSTEM_TEXT = "FPS: |c%s%d|r  MS: |c%s%d|r"

function Look.SystemText(text, fps, ms)
    text:SetText(SYSTEM_TEXT:format(FpsBand(fps).hex, fps, MsBand(ms).hex, ms))
end

local NO_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local GLYPH_COORDS = { 0, 1, 0, 1 }

function Look.Buttons(place)
    local layout, ldb = SavedLayout(), LDB()
    for s = 1, #SIDES do
        local side = SIDES[s]
        local keys = layout[side]
        for i = 1, #keys do
            local key = keys[i]
            if ICON[key] then
                place(side, key, ICON[key], true, GLYPH_COORDS)
            elseif ldb and type(key) == "string" and key:sub(1, #LDB_PREFIX) == LDB_PREFIX then
                local name = key:sub(#LDB_PREFIX + 1)
                local obj = ldb:GetDataObjectByName(name)
                if obj and obj.icon then
                    local glyph = GLYPH[name]
                    place(side, key, glyph or obj.icon, glyph ~= nil,
                        glyph and GLYPH_COORDS or obj.iconCoords or NO_COORDS, name)
                end
            end
        end
    end
end

local function PaintClock()
    local text = Look.ClockText()
    if text == clockText.last then return false end
    clockText.last = text
    clockText:SetText(text)
    return true
end

local function FitWidth()
    if InCombatLockdown() then fitPending = true; return end
    fitPending = false
    Look.Fit(bar, leftGroup, rightGroup, clockText)
end

local function UpdateSystem()
    local sys = bar.sys
    if not (On() and S.Get("showSystem")) then
        sys:Hide()
        sys.fps = nil
        return
    end
    local fps, ms = math.floor(GetFramerate() + 0.5), math.floor(select(3, GetNetStats()))
    if fps ~= sys.fps or ms ~= sys.ms then
        sys.fps, sys.ms = fps, ms
        Look.SystemText(sys.text, fps, ms)
        sys:SetWidth(math.max(40, sys.text:GetStringWidth() + 10))
    end
    sys:Show()
end

local function UpdateResting()
    if bar then bar.rest:SetShown(IsResting()) end
end

-- Below the bar while it shows; where the clock was once Hide In Combat hides it.
local function AnchorSystem()
    bar.sys:ClearAllPoints()
    if bar:IsShown() then
        bar.sys:SetPoint("TOP", bar, "BOTTOM", 0, -2)
    else
        bar.sys:SetPoint("CENTER", bar, "CENTER")
    end
end

local function Build()
    bar = CreateFrame("Frame", "NaowhForeverTopBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)

    bar.segs = Look.NewPills(bar)

    clockText = bar:CreateFontString(nil, "OVERLAY")
    clockText:SetPoint("CENTER")
    clockText:SetFont(ns.UIFontPath(), 20, "")
    local clockBtn = CreateFrame("Button", nil, bar)
    clockBtn:SetPoint("CENTER", clockText, "CENTER")
    clockBtn:SetScript("OnEnter", function(self)
        UpdateHover()
        clockText:SetTextColor(Accent())
        ShowClockTooltip(self)
    end)
    clockBtn:SetScript("OnLeave", function()
        clockText:SetTextColor(Tone("fg", 1))
        GameTooltip:Hide()
        UpdateHover()
    end)
    clockBtn:SetScript("OnClick", function() if ToggleCalendar then ToggleCalendar() end end)
    bar.clockBtn = clockBtn

    -- Resting "zzz": an 8-frame flipbook over the clock's corner.
    local rest = CreateFrame("Frame", nil, bar)
    rest:SetPoint("CENTER", clockText, "TOPRIGHT", 5, 2)
    rest:Hide()
    local restIcon = rest:CreateTexture(nil, "OVERLAY")
    restIcon:SetAllPoints()
    restIcon:SetTexture(MEDIA .. "resting.blp")
    restIcon:SetTexCoord(0, 1 / 16, 0, 0.5)
    local frameT, frameN = 0, 1
    local function Flip(_, e)
        frameT = frameT + e
        if frameT >= 0.25 then
            frameT = frameT - 0.25
            frameN = frameN % 8 + 1
            restIcon:SetTexCoord((frameN - 1) / 16, frameN / 16, 0, 0.5)
        end
    end
    rest:SetScript("OnShow", function(self)
        frameT, frameN = 0, 1
        self:SetScript("OnUpdate", Flip)
    end)
    rest:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    bar.rest = rest

    -- A sibling on UIParent, so Hide In Combat leaves the readout up.
    local sys = CreateFrame("Button", nil, UIParent)
    sys:RegisterForClicks("AnyUp")
    sys.text = sys:CreateFontString(nil, "OVERLAY")
    sys.text:SetPoint("CENTER")
    sys:SetScript("OnEnter", function(self)
        UpdateHover()
        if not S.Get("systemTooltip") then return end
        ShowSystemTooltip(self)
        local t = 0
        self:SetScript("OnUpdate", function(s, e)
            t = t + e
            if t >= 1 then t = 0; ShowSystemTooltip(s) end
        end)
    end)
    sys:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
        UpdateHover()
    end)
    sys:SetScript("OnClick", function(self)
        if IsShiftKeyDown() then collectgarbage("collect") end
        lastMemScan = 0
        if S.Get("systemTooltip") then ShowSystemTooltip(self) end
    end)
    bar.sys = sys
    bar:HookScript("OnShow", AnchorSystem)
    bar:HookScript("OnHide", AnchorSystem)
    -- Motion only, so the gaps between buttons still click through.
    bar:SetMouseClickEnabled(false)
    bar:SetScript("OnEnter", UpdateHover)
    bar:SetScript("OnLeave", UpdateHover)

    leftGroup = CreateFrame("Frame", nil, bar)
    rightGroup = CreateFrame("Frame", nil, bar)
    Badge(SecureButton("friends", leftGroup), 0.3, 1, 0.3)
    Badge(SecureButton("guild", leftGroup), 1, 0.62, 0.1)
    SecureButton("hearth", rightGroup)

    bar.mover = UI.AttachMover(bar, "Top Bar", function(pos) S.Set("pos", pos) end, "QoL/Interface", "QoL/Interface:topBar")
end

local function Layout(group, keys)
    local list = {}
    for i, key in ipairs(keys) do list[i] = buttons[key] end
    Look.Row(group, list, #list)
end

local function GroupKeys()
    local left, right = {}, {}
    for _, b in pairs(buttons) do b:Hide() end
    Look.Buttons(function(side, key, texture, glyph, coords, name)
        local b = name and BrokerButton(name) or buttons[key]
        if name then
            b.icon:SetTexture(texture)
            b.icon:SetDesaturated(not glyph)
            b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
        b:SetParent(side == "left" and leftGroup or rightGroup)
        local keys = side == "left" and left or right
        keys[#keys + 1] = key
    end)
    return left, right
end

local BAR_EVENTS = { "PLAYER_UPDATE_RESTING", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GUILD_ROSTER_UPDATE" }
local events = CreateFrame("Frame")

local function StartTicker()
    if ticker then return end
    for i = 1, #BAR_EVENTS do events:RegisterEvent(BAR_EVENTS[i]) end
    local n = 0
    ticker = C_Timer.NewTicker(1, function()
        UpdateSystem()
        if not bar:IsShown() then return end
        if PaintClock() or fitPending then FitWidth() end
        n = n + 1
        if n >= 10 then n = 0; UpdateBadges() end
    end)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    for i = 1, #BAR_EVENTS do events:UnregisterEvent(BAR_EVENTS[i]) end
end

local pending = CreateFrame("Frame")

-- Everything here moves or shows secure buttons, so combat defers it to the end of the fight.
local function Apply()
    if InCombatLockdown() then
        pending:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if not (On() or unlocked) then
        StopTicker()
        if bar then
            UnregisterStateDriver(bar, "visibility")
            bar:Hide()
            bar.sys:Hide()
        end
        return
    end
    if not bar then Build() end

    local pos = S.Get("pos")
    bar:ClearAllPoints()
    if pos then
        bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
    end
    local h = BarHeight()
    bar:SetHeight(h)
    bar.clockBtn:SetSize(80, h)
    local rest = math.max(12, math.floor(h * 0.55 + 0.5))
    bar.rest:SetSize(rest, rest)
    Look.ClockFont(clockText)
    clockText.last = nil
    PaintClock()
    Look.SystemFont(bar.sys.text)
    bar.sys.fps = nil
    bar.sys:SetHeight(S.Get("sysSize") + 3)

    local left, right = GroupKeys()
    Layout(leftGroup, left)
    Layout(rightGroup, right)
    FitWidth()
    Look.PaintPills(bar, bar.segs, leftGroup, rightGroup, clockText, #left, #right)

    -- A state driver, since hiding a frame that holds secure buttons is protected in combat.
    if S.Get("hideInCombat") and not unlocked then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end
    bar.mover:SetShown(unlocked == true)
    bar:SetMouseMotionEnabled(S.Get("mouseover"))
    UpdateHover()
    AnchorSystem()
    UpdateSystem()
    UpdateBadges()
    UpdateResting()
    StartTicker()
end

pending:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Apply()
end)

-------------------------------------------------------------------------------
--  Options
-------------------------------------------------------------------------------
local Group = ns.Shared.Settings.Group
local St = ns.Shared.Style

local SAMPLE_FRIENDS, SAMPLE_GUILD, SAMPLE_FPS, SAMPLE_MS = 12, 31, 144, 38
local PREVIEW_TOP = 26
local NOTE_BOTTOM, NOTE_SIZE = 10, 11
local HINT = "Drag to move, x to remove, + to add."
local TIP_HINT = "Drag to move. Click x to remove."
local HOVER_ALPHA = 0.18
local DRAGGED_ALPHA = 0.3
local GHOST_ALPHA = 0.85
local MARKER_W = 2
local REMOVE_SIZE, REMOVE_ICON = 12, 8
local REMOVE_INSET = 3
local PLUS_GAP = 6
local PLUS_ICON = 12
local PLUS_BG_ALPHA = 0.6
local DROP_SLOP = 12
local EDIT_LEVEL = 10
local BLACK = { r = 0, g = 0, b = 0 }
local STATES = {
    { key = "normal", label = "Normal", tip = "The bar as it sits on your screen." },
    { key = "faded", label = "Faded", tip = "While the mouse is away, with Show On Mouseover on.",
      needs = "mouseover" },
    { key = "combat", label = "In Combat", tip = "In a fight, with Hide In Combat on: FPS / MS stays up.",
      needs = "hideInCombat" },
}

local function CopyList(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function EditableLayout(key)
    local layout = SavedLayout()
    local out = { left = CopyList(layout.left), right = CopyList(layout.right) }
    for s = 1, #SIDES do
        local list = out[SIDES[s]]
        for i = #list, 1, -1 do
            if list[i] == key then table.remove(list, i) end
        end
    end
    return out
end

local function RemoveKey(key)
    S.Set("layout", EditableLayout(key))
end

local function MoveKey(key, side, before)
    local layout = EditableLayout(key)
    local list = layout[side]
    table.insert(list, before and IndexOf(list, before) or #list + 1, key)
    S.Set("layout", layout)
end

local function AddKey(side, key)
    local layout = EditableLayout(key)
    local list = layout[side]
    table.insert(list, side == "left" and 1 or #list + 1, key)
    S.Set("layout", layout)
end

local function ResetLayout()
    S.Set("layout", nil)
end

local function ButtonName(key)
    if BUILTIN[key] then return BUILTIN[key] end
    local name = key:sub(#LDB_PREFIX + 1)
    local ldb = LDB()
    local obj = ldb and ldb:GetDataObjectByName(name)
    return obj and obj.label or name
end

local function Unhover(preview)
    local b = preview.hover
    if not b then return end
    preview.hover = nil
    b.icon:SetVertexColor(IconColor())
    b.wash:Hide()
    preview.remove:Hide()
    GameTooltip:Hide()
end

local function Hover(preview, b)
    if preview.hover ~= b then Unhover(preview) end
    preview.hover = b
    b.icon:SetVertexColor(Accent())
    b.wash:Show()
    local x = preview.remove
    x.owner = b
    x:ClearAllPoints()
    x:SetPoint("CENTER", b, "TOPRIGHT", -REMOVE_INSET, -REMOVE_INSET)
    x:Show()
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:AddLine(ButtonName(b.key), Tone("fg", 1))
    GameTooltip:AddLine(TIP_HINT, Tone("muted", 0.7))
    GameTooltip:Show()
end

local function PreviewEnter(b)
    if not b.preview.drag then Hover(b.preview, b) end
end

local function PreviewLeave(b)
    local preview = b.preview
    if preview.hover == b and not preview.remove:IsMouseOver() then Unhover(preview) end
end

local function RemoveEnter(x)
    x.icon:SetVertexColor(Accent())
end

local function RemoveLeave(x)
    x.icon:SetVertexColor(Tone("fg", 1))
    if not (x.owner and x.owner:IsMouseOver()) then Unhover(x.preview) end
end

local function RemoveClick(x)
    local key = x.owner and x.owner.key
    Unhover(x.preview)
    if key then RemoveKey(key) end
end

local function DropTarget(preview, x)
    local side = x < preview.clock:GetCenter() and "left" or "right"
    local list = preview.lists[side]
    for i = 1, #list do
        local b = list[i]
        if b ~= preview.drag and x < b:GetCenter() then return side, b end
    end
    return side, nil
end

local function PlaceMarker(preview, side, before)
    local marker = preview.marker
    marker:ClearAllPoints()
    if before then
        marker:SetPoint("CENTER", before, "LEFT", -GAP / 2, 0)
    else
        local list, last = preview.lists[side], nil
        for i = #list, 1, -1 do
            if list[i] ~= preview.drag then
                last = list[i]
                break
            end
        end
        if last then
            marker:SetPoint("CENTER", last, "RIGHT", GAP / 2, 0)
        else
            marker:SetPoint("CENTER", side == "left" and preview.left or preview.right, "CENTER")
        end
    end
    marker:Show()
end

local function DragUpdate(edit)
    local preview = edit.preview
    local scale = preview:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local ghost = preview.ghost
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", preview, "BOTTOMLEFT", x - preview:GetLeft(), y - preview:GetBottom())
    if preview:IsMouseOver(DROP_SLOP, -DROP_SLOP, -DROP_SLOP, DROP_SLOP) then
        local side, before = DropTarget(preview, x)
        if side ~= preview.dropSide or before ~= preview.dropBefore then
            preview.dropSide, preview.dropBefore = side, before
            PlaceMarker(preview, side, before)
        end
    elseif preview.dropSide then
        preview.dropSide, preview.dropBefore = nil, nil
        preview.marker:Hide()
    end
end

local function DragStart(b)
    local preview = b.preview
    if preview.drag then return end
    Unhover(preview)
    preview.drag, preview.dropSide, preview.dropBefore = b, nil, nil
    b:SetAlpha(DRAGGED_ALPHA)
    local size, icon = BtnSize(), S.Get("iconSize")
    local ghost = preview.ghost
    local c = b.coords
    ghost:SetSize(size, size)
    ghost.icon:SetSize(icon, icon)
    ghost.icon:SetTexture(b.texture)
    ghost.icon:SetDesaturated(not b.glyph)
    ghost.icon:SetTexCoord(c[1], c[2], c[3], c[4])
    ghost.icon:SetVertexColor(Accent())
    ghost:Show()
    preview.marker:SetHeight(size)
    local edit = preview.edit
    if not InCombatLockdown() then
        edit:EnableKeyboard(true)
        edit:SetPropagateKeyboardInput(true)
    end
    edit:SetScript("OnUpdate", DragUpdate)
    DragUpdate(edit)
end

local function EndDrag(preview, commit)
    local b = preview.drag
    if not b then return end
    local edit = preview.edit
    edit:SetScript("OnUpdate", nil)
    C_Timer.After(0, edit.release)
    preview.drag = nil
    b:SetAlpha(1)
    preview.ghost:Hide()
    preview.marker:Hide()
    local side, before = preview.dropSide, preview.dropBefore
    preview.dropSide, preview.dropBefore = nil, nil
    if commit and side then MoveKey(b.key, side, before and before.key) end
end

local function DragStop(b)
    EndDrag(b.preview, true)
end

local function DragKey(edit, key)
    if InCombatLockdown() then return end
    -- A drag that ends in combat cannot turn the keyboard off; with no drag, Escape still
    -- reaches the options window.
    if key == "ESCAPE" and edit.preview.drag then
        edit:SetPropagateKeyboardInput(false)
        EndDrag(edit.preview, false)
    else
        edit:SetPropagateKeyboardInput(true)
    end
end

local function PreviewHidden(preview)
    EndDrag(preview, false)
    Unhover(preview)
end

local addKeys, addBrokers, addLabels, onBar = {}, {}, {}, {}

local function ByAddLabel(a, b)
    return addLabels[a]:lower() < addLabels[b]:lower()
end

local function AddMenu(plus)
    local side, layout, ldb = plus.side, SavedLayout(), LDB()
    wipe(addKeys)
    wipe(addBrokers)
    wipe(addLabels)
    for _, key in ipairs(BUILTIN_ORDER) do
        if not InLayoutOf(layout, key) then addKeys[#addKeys + 1] = key end
    end
    local fixed = #addKeys
    if ldb then
        for name, obj in ldb:DataObjectIterator() do
            local key = LDB_PREFIX .. name
            if obj.icon and not InLayoutOf(layout, key) then
                addBrokers[#addBrokers + 1] = key
                addLabels[key] = obj.label or name
            end
        end
    end
    table.sort(addBrokers, ByAddLabel)
    for i = 1, #addBrokers do addKeys[fixed + i] = addBrokers[i] end
    wipe(onBar)
    for _, list in ipairs({ layout.left, layout.right }) do
        for _, key in ipairs(list) do
            local obj = not BUILTIN[key] and ldb and ldb:GetDataObjectByName(key:sub(#LDB_PREFIX + 1))
            local label = BUILTIN[key] or (obj and (obj.label or key:sub(#LDB_PREFIX + 1)))
            if label then onBar[#onBar + 1] = label end
        end
    end
    table.sort(onBar)
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(plus, function(_, root)
        root:CreateTitle(side == "left" and "Add to the Left Side" or "Add to the Right Side")
        if #addKeys == 0 then root:CreateTitle("Everything is on the bar already.") end
        for i = 1, #addKeys do
            local key = addKeys[i]
            if i == fixed + 1 and fixed > 0 then root:CreateDivider() end
            root:CreateButton(BUILTIN[key] or addLabels[key], function() AddKey(side, key) end)
        end
        if #onBar == 0 then return end
        root:CreateDivider()
        root:CreateTitle("Already on the bar")
        for i = 1, #onBar do root:CreateButton(onBar[i]):SetEnabled(false) end
    end)
end

local function PlusEnter(plus)
    plus.icon:SetVertexColor(Accent())
    GameTooltip:SetOwner(plus, "ANCHOR_TOP")
    GameTooltip:AddLine("Add a Button", Tone("fg", 1))
    GameTooltip:AddLine(plus.side == "left" and "On the left side." or "On the right side.", Tone("muted", 0.7))
    GameTooltip:Show()
end

local function PlusLeave(plus)
    plus.icon:SetVertexColor(Tone("muted", 0.7))
    GameTooltip:Hide()
end

local function HideTooltip() GameTooltip:Hide() end

local function SystemEnter(hit)
    if S.Get("systemTooltip") then ShowSystemTooltip(hit) end
end

local function NewPreviewButton(preview)
    local b = CreateFrame("Frame", nil, preview)
    b.preview = preview
    b.wash = ns.Solid(b, "BACKGROUND", T.accent, HOVER_ALPHA)
    b.wash:SetAllPoints()
    b.wash:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnEnter", PreviewEnter)
    b:SetScript("OnLeave", PreviewLeave)
    b:SetScript("OnDragStart", DragStart)
    b:SetScript("OnDragStop", DragStop)
    preview.pool[#preview.pool + 1] = b
    return b
end

local function NewPlus(preview, side)
    local plus = CreateFrame("Button", nil, preview)
    plus.preview, plus.side = preview, side
    ns.Solid(plus, "BACKGROUND", T.bg, PLUS_BG_ALPHA):SetAllPoints()
    ns.Border(plus, BLACK)
    plus.icon = plus:CreateTexture(nil, "ARTWORK")
    plus.icon:SetTexture(St.PLUS)
    plus.icon:SetSize(PLUS_ICON, PLUS_ICON)
    plus.icon:SetPoint("CENTER")
    plus.icon:SetVertexColor(Tone("muted", 0.7))
    plus:SetScript("OnEnter", PlusEnter)
    plus:SetScript("OnLeave", PlusLeave)
    plus:SetScript("OnClick", AddMenu)
    local group = side == "left" and preview.left or preview.right
    if side == "left" then
        plus:SetPoint("RIGHT", group, "LEFT", -(SEG_PAD + PLUS_GAP), 0)
    else
        plus:SetPoint("LEFT", group, "RIGHT", SEG_PAD + PLUS_GAP, 0)
    end
    return plus
end

local function NewEditLayer(preview)
    local edit = CreateFrame("Frame", nil, preview)
    edit.preview = preview
    edit:SetAllPoints()
    edit:SetFrameLevel(preview:GetFrameLevel() + EDIT_LEVEL)
    edit:SetScript("OnKeyDown", DragKey)
    -- Setting an OnKeyDown script turns keyboard input on; it stays off until a drag starts.
    edit:EnableKeyboard(false)
    edit.release = function()
        if not preview.drag and not InCombatLockdown() then edit:EnableKeyboard(false) end
    end
    preview.edit = edit

    preview.marker = ns.Solid(edit, "OVERLAY", T.accent, 1)
    preview.marker:SetWidth(MARKER_W)
    preview.marker:Hide()

    local ghost = CreateFrame("Frame", nil, edit)
    ghost:SetAlpha(GHOST_ALPHA)
    ns.Solid(ghost, "BACKGROUND", T.accent, HOVER_ALPHA):SetAllPoints()
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("CENTER")
    ghost:Hide()
    preview.ghost = ghost

    local x = CreateFrame("Button", nil, edit)
    x.preview = preview
    x:SetSize(REMOVE_SIZE, REMOVE_SIZE)
    ns.Solid(x, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(x, BLACK)
    x.icon = x:CreateTexture(nil, "ARTWORK")
    x.icon:SetTexture(St.CROSS)
    x.icon:SetSize(REMOVE_ICON, REMOVE_ICON)
    x.icon:SetPoint("CENTER")
    x.icon:SetVertexColor(Tone("fg", 1))
    x:SetScript("OnEnter", RemoveEnter)
    x:SetScript("OnLeave", RemoveLeave)
    x:SetScript("OnClick", RemoveClick)
    x:Hide()
    preview.remove = x
end

local function NewPreview(stage)
    local preview = CreateFrame("Frame", nil, stage)
    preview:SetPoint("TOP", 0, -PREVIEW_TOP)
    preview.segs = Look.NewPills(preview)
    preview.clock = preview:CreateFontString(nil, "OVERLAY")
    preview.clock:SetPoint("CENTER")
    preview.left = CreateFrame("Frame", nil, preview)
    preview.right = CreateFrame("Frame", nil, preview)
    preview.pool, preview.lists = {}, { left = {}, right = {} }
    preview.sys = preview:CreateFontString(nil, "OVERLAY")
    preview.clockHit = CreateFrame("Frame", nil, preview)
    preview.clockHit:SetAllPoints(preview.clock)
    preview.clockHit:EnableMouse(true)
    preview.clockHit:SetScript("OnEnter", ShowClockTooltip)
    preview.clockHit:SetScript("OnLeave", HideTooltip)
    preview.sysHit = CreateFrame("Frame", nil, preview)
    preview.sysHit:SetAllPoints(preview.sys)
    preview.sysHit:EnableMouse(true)
    preview.sysHit:SetScript("OnEnter", SystemEnter)
    preview.sysHit:SetScript("OnLeave", HideTooltip)
    preview.plusLeft = NewPlus(preview, "left")
    preview.plusRight = NewPlus(preview, "right")
    NewEditLayer(preview)
    preview:SetScript("OnHide", PreviewHidden)
    preview.note = preview:CreateFontString(nil, "OVERLAY")
    preview.note:SetPoint("BOTTOM", stage, "BOTTOM", 0, NOTE_BOTTOM)
    preview.note:SetFont(ns.UIFontPath(), NOTE_SIZE, "")
    preview.note:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 1)
    return preview
end

local used

local function PlaceSample(preview, side, key, texture, glyph, coords)
    used = used + 1
    local b = preview.pool[used] or NewPreviewButton(preview)
    b.key = key
    b.texture, b.glyph, b.coords = texture, glyph, coords or GLYPH_COORDS
    b:SetParent(side == "left" and preview.left or preview.right)
    b:SetAlpha(1)
    b.icon:SetTexture(texture)
    b.icon:SetDesaturated(not glyph)
    b.icon:SetTexCoord(b.coords[1], b.coords[2], b.coords[3], b.coords[4])
    if not b.badge then
        Badge(b, 0.3, 1, 0.3)
    end
    local count = key == "friends" and SAMPLE_FRIENDS or key == "guild" and SAMPLE_GUILD
    b.badge:SetText(count or "")
    if key == "guild" then b.badge:SetTextColor(1, 0.62, 0.1) else b.badge:SetTextColor(0.3, 1, 0.3) end
    local list = preview.lists[side]
    list[#list + 1] = b
end

local function PaintPreview(preview, state)
    EndDrag(preview, false)
    Unhover(preview)
    local lists = preview.lists
    wipe(lists.left)
    wipe(lists.right)
    used = 0
    Look.Buttons(function(side, key, texture, glyph, coords)
        PlaceSample(preview, side, key, texture, glyph, coords)
    end)
    for i = used + 1, #preview.pool do preview.pool[i]:Hide() end
    preview:SetHeight(BarHeight())
    Look.ClockFont(preview.clock)
    preview.clock:SetText(Look.ClockText())
    Look.Row(preview.left, lists.left, #lists.left)
    Look.Row(preview.right, lists.right, #lists.right)
    Look.Fit(preview, preview.left, preview.right, preview.clock)
    Look.PaintPills(preview, preview.segs, preview.left, preview.right, preview.clock, #lists.left, #lists.right)
    local sys = preview.sys
    Look.SystemFont(sys)
    Look.SystemText(sys, SAMPLE_FPS, SAMPLE_MS)
    sys:ClearAllPoints()
    sys:SetPoint("TOP", preview, "BOTTOM", 0, -2)
    sys:SetShown(S.Get("showSystem"))
    preview.sysHit:SetShown(S.Get("showSystem"))
    local alpha = 1
    if state == "faded" and S.Get("mouseover") then
        alpha = S.Get("mouseoverAlpha") / 100
    elseif state == "combat" and S.Get("hideInCombat") then
        alpha = 0
        sys:ClearAllPoints()
        sys:SetPoint("CENTER", preview, "CENTER")
    end
    local editable = alpha > 0
    preview:SetAlpha(alpha)
    for i = 1, #preview.pool do preview.pool[i]:EnableMouse(editable) end
    preview.clockHit:EnableMouse(editable)
    local size = BtnSize()
    preview.plusLeft:SetSize(size, size)
    preview.plusRight:SetSize(size, size)
    preview.plusLeft:SetShown(editable)
    preview.plusRight:SetShown(editable)
    sys:SetAlpha(state == "faded" and alpha or 1)
    preview.note:SetText(HINT)
    if not editable then return end
    for s = 1, #SIDES do
        local list = lists[SIDES[s]]
        for i = 1, #list do
            if list[i]:IsMouseOver() then Hover(preview, list[i]) return end
        end
    end
end

local function Summary(store)
    local layout = SavedLayout()
    return ("%s clock, %d buttons%s"):format(store.Get("use24h") and "24-hour" or "12-hour",
        #layout.left + #layout.right, store.Get("mouseover") and ", fades until hovered" or "")
end

local ROWS = {
    Group("Clock"),
    { key = "use24h", label = "24-Hour Clock", toggle = true },
    Group("Buttons"),
    { key = "layout", label = "Reset Layout", button = ResetLayout, buttonText = "Reset",
      help = "Puts the bar's buttons back as they came: Friends and Guild on the left, the Dungeon "
          .. "Journal and BiS List on the right." },
    Group("FPS / MS"),
    { key = "showSystem", label = "Show FPS / MS", toggle = true },
    { key = "systemTooltip", label = "Tooltip", toggle = true, needs = "showSystem",
      help = "Latency and addon memory when you hover the readout." },
    Group("Size"),
    { key = "iconSize", label = "Icon Size", slider = { 12, 32, 1 } },
    { key = "tooltipScale", label = "Tooltip Size", slider = { 80, 160, 5 }, unit = "%",
      help = "Size of the friends, guild, Hearthstone, clock and FPS tooltips." },
    Group("Text"),
    { key = "font", label = "Font", font = true, help = "The FPS / MS readout and the online counts on the buttons." },
    { key = "outline", label = "Outline", choice = Parts.HUD_OUTLINES,
      help = "A black outline round the FPS / MS readout and the counts, in place of the soft shadow." },
    { key = "sysSize", label = "FPS / MS Size", slider = { 6, 24, 1 }, needs = "showSystem" },
    { key = "clockFont", label = "Clock Font", font = true },
    { key = "clockSize", label = "Clock Size", slider = { 10, 36, 1 } },
    { key = "clockOutline", label = "Clock Outline", choice = Parts.HUD_OUTLINES,
      help = "A black outline round the clock." },
    Group("Background"),
    { key = "bgAlpha", label = "Bar Opacity", slider = { 0, 100, 5 }, unit = "%" },
    Group("Colours"),
    { key = "iconColor", label = "Icon Colour", colour = true,
      help = "The tint on every button's icon: Naowh's own and any addon's." },
    Group("Visibility"),
    { key = "hideInCombat", label = "Hide In Combat", toggle = true, help = "The FPS / MS readout stays up." },
    { key = "mouseover", label = "Show On Mouseover", toggle = true,
      help = "The bar and the FPS / MS readout fade to Faded Opacity until you hover them. Their "
          .. "buttons still click while faded." },
    { key = "mouseoverAlpha", label = "Faded Opacity", slider = { 0, 100, 5 }, unit = "%", needs = "mouseover",
      help = "How visible the bar and the FPS / MS readout stay while the mouse is away. At 0 they "
          .. "are invisible." },
}

ns.Shared.Settings.Page("QoL/Interface", S):Card({
    id = "topBar", name = "Top Bar", order = 10, switch = "enabled",
    help = "Your buttons on either side of the clock, with FPS and latency underneath. Arrange the "
        .. "buttons in the preview: drag one to move it, its x removes it, a side's + adds one. Move "
        .. "the bar in the HUD Editor.",
    summary = Summary,
    studio = { height = 120, states = STATES, new = NewPreview, paint = PaintPreview },
    rows = ROWS,
})

hooksecurefunc(S, "Set", function(key)
    if key ~= "pos" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    if bar then Apply() end
end)

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_INSTANCE_INFO")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_UPDATE_RESTING" then
        UpdateResting()
    elseif event == "UPDATE_INSTANCE_INFO" then
        lockoutsAt = GetTime()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then RequestRaidInfo() end
        -- PLAYER_ENTERING_WORLD comes after every addon's login, so late brokers exist by then.
        Apply()
    else
        UpdateBadges()
    end
end)
