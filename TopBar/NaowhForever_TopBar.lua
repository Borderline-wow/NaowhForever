-------------------------------------------------------------------------------
--  NaowhForever_TopBar.lua -- [friends guild] [clock] across the top of the screen, addon
--  buttons on either side and an optional Hearthstone, FPS / MS under it. Friends, guild and
--  hearth are secure buttons; the rest are any addon's LibDataBroker source, the Dungeon
--  Journal and BiS List by default.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local T = ns.THEME

local S = UI.ModuleSettings("topBar", {
    enabled = true,
    -- The clock font is EllesmereUI's, found through SharedMedia; without it the Addon Font.
    iconSize = 22, clockSize = 27, clockFont = "Gotham Narrow Ultra", use24h = true,
    bgAlpha = 85, iconColor = { r = 1, g = 1, b = 1 },
    hideInCombat = false, mouseover = false, mouseoverAlpha = 0, showFriends = true, showGuild = true, showHearth = false,
    showSystem = true, systemTooltip = true, sysSize = 13, tooltipScale = 120,
    brokers = { "NaowhForeverJournal", "NaowhForeverBiS" },
    brokerSide = {},   -- [name] = "left"; anything else goes on the right
})
ns.TopBarSettings = S

local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\TopBar\\"
local HEARTHSTONE = 6948
local BTN_PAD, GAP, EDGE, CLOCK_GAP, CLOCK_PAD, SEG_PAD = 8, 4, 14, 22, 6, 6
local ROSTER_CAP = 40   -- keeps a big guild's tooltip on the screen

-- Our own glyphs for our modules; any other source's icon is desaturated and tinted to match.
local GLYPH = {
    NaowhForeverJournal = MEDIA .. "icon-journal.png",
    NaowhForeverBiS = MEDIA .. "icon-bis.png",
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

local function FpsRGB(fps)
    if fps >= 100 then return 0.25, 1, 0.25 end
    if fps >= 60 then return 0.55, 1, 0.25 end
    if fps >= 30 then return 1, 1, 0.25 end
    return 1, 0.35, 0.25
end

local function MsRGB(ms)
    if ms < 75 then return 0.25, 1, 0.25 end
    if ms < 150 then return 1, 1, 0.25 end
    return 1, 0.35, 0.25
end

local function Hex(r, g, b)
    return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
-- The bar's own tooltips at Tooltip Size; GameTooltip's own scale comes back when it hides.
local tipBase

local function OwnTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    tipBase = tipBase or GameTooltip:GetScale()
    GameTooltip:SetScale(tipBase * S.Get("tooltipScale") / 100)
end

GameTooltip:HookScript("OnHide", function(self)
    if tipBase then
        self:SetScale(tipBase)
        tipBase = nil
    end
end)

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
    b.badge:SetFont(ns.UIFontPath(), 10, "OUTLINE")
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
        local obj = LDB():GetDataObjectByName(name)
        if not obj then return end
        if obj.OnEnter then
            obj.OnEnter(self)
        elseif obj.OnTooltipShow then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            obj.OnTooltipShow(GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function(self)
        local obj = LDB():GetDataObjectByName(name)
        if obj and obj.OnLeave then obj.OnLeave(self) end
    end)
    return b
end

local function UpdateBadges()
    if not bar then return end
    local n = FriendsOnline()
    buttons.friends.badge:SetText(n > 0 and n or "")
    n = GuildOnline()
    buttons.guild.badge:SetText(n and n > 0 and n or "")
    if S.Get("showGuild") and IsInGuild() and not InCombatLockdown() and GetTime() - lastRoster >= 15 then
        lastRoster = GetTime()
        C_GuildInfo.GuildRoster()
    end
end

-------------------------------------------------------------------------------
--  Bar
-------------------------------------------------------------------------------
local function PaintClock()
    local use24h = S.Get("use24h")
    local text = date(use24h and "%H:%M" or "%I:%M %p")
    if not use24h then text = text:gsub("^0", "") end
    if text == clockText.last then return false end
    clockText.last = text
    clockText:SetText(text)
    return true
end

-- Both sides as wide as the wider group, so the clock stays at the bar's centre. Resizing
-- moves the secure buttons, which combat forbids; the ticker retries after.
local function FitWidth()
    if InCombatLockdown() then fitPending = true; return end
    fitPending = false
    local side = math.max(leftGroup:GetWidth(), rightGroup:GetWidth())
    local clockW = math.max(24, clockText:GetStringWidth() + 8)
    bar:SetWidth(2 * (EDGE + side + CLOCK_GAP) + clockW)
    leftGroup:ClearAllPoints()
    leftGroup:SetPoint("LEFT", bar, "LEFT", EDGE + side - leftGroup:GetWidth(), 0)
    rightGroup:ClearAllPoints()
    rightGroup:SetPoint("RIGHT", bar, "RIGHT", -(EDGE + side - rightGroup:GetWidth()), 0)
end

local function UpdateSystem()
    local sys = bar.sys
    if not (On() and S.Get("showSystem")) then sys:Hide(); return end
    local fps = math.floor(GetFramerate() + 0.5)
    local home = math.floor(select(3, GetNetStats()))
    sys.text:SetText(("FPS: |c%s%d|r  MS: |c%s%d|r"):format(Hex(FpsRGB(fps)), fps, Hex(MsRGB(home)), home))
    sys:SetWidth(math.max(40, sys.text:GetStringWidth() + 10))
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

    -- Three dark pills: one per button group and one behind the clock.
    bar.segs = {}
    for i = 1, 3 do
        local seg = bar:CreateTexture(nil, "BACKGROUND")
        local line = bar:CreateTexture(nil, "BORDER")
        ns.Hairline(line, "h")
        line:SetPoint("BOTTOMLEFT", seg, "BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT")
        line:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.55)
        seg.line = line
        bar.segs[i] = seg
    end

    clockText = bar:CreateFontString(nil, "OVERLAY")
    clockText:SetPoint("CENTER")
    clockText:SetFont(ns.UIFontPath(), 20, "")
    local clockBtn = CreateFrame("Button", nil, bar)
    clockBtn:SetPoint("CENTER", clockText, "CENTER")
    clockBtn:SetScript("OnEnter", function(self)
        UpdateHover()
        clockText:SetTextColor(Accent())
        OwnTooltip(self)
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

    bar.mover = UI.AttachMover(bar, "Top Bar", function(pos) S.Set("pos", pos) end)
end

local function Layout(group, keys)
    local size, icon, x = BtnSize(), S.Get("iconSize"), 0
    for _, key in ipairs(keys) do
        local b = buttons[key]
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", group, "LEFT", x, 0)
        b.icon:SetSize(icon, icon)
        b.icon:SetVertexColor(IconColor())
        b:Show()
        x = x + size + GAP
    end
    group:SetSize(math.max(1, x - GAP), size)
end

-- Dungeon Quests became part of the Dungeon Journal: a bar that carried its button carries
-- the Journal's, on the same side. Only a list the player changed is saved; the default
-- already has the Journal.
local OLD_DQ, JOURNAL = "NaowhForeverDQ", "NaowhForeverJournal"

local function MigrateBrokers()
    local db = S.DB()
    local saved = db.brokers
    if not (saved and tContains(saved, OLD_DQ)) then return end
    local keep = tContains(saved, JOURNAL)
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

-- Chosen brokers go on the outer edge of their side: before friends and guild on the left,
-- after the Hearthstone (when shown) on the right, each in the order they were switched on.
local function GroupKeys()
    MigrateBrokers()
    local left, right = {}, {}
    if S.Get("showHearth") then right[1] = "hearth" else buttons.hearth:Hide() end
    for key, b in pairs(buttons) do
        if key:find("^ldb:") then b:Hide() end
    end
    local sides = S.Get("brokerSide")
    local ldb = LDB()
    for _, name in ipairs(ldb and S.Get("brokers") or {}) do
        local obj = ldb:GetDataObjectByName(name)
        if obj and obj.icon then
            local b = BrokerButton(name)
            local glyph = GLYPH[name]
            b.icon:SetTexture(glyph or obj.icon)
            b.icon:SetDesaturated(not glyph)
            local c = glyph and { 0, 1, 0, 1 } or obj.iconCoords or { 0.08, 0.92, 0.08, 0.92 }
            b.icon:SetTexCoord(c[1], c[2], c[3], c[4])
            local keys = sides[name] == "left" and left or right
            b:SetParent(keys == left and leftGroup or rightGroup)
            keys[#keys + 1] = b.key
        end
    end
    for _, key in ipairs({ "friends", "guild" }) do
        if S.Get(key == "friends" and "showFriends" or "showGuild") then
            left[#left + 1] = key
        else
            buttons[key]:Hide()
        end
    end
    return left, right
end

local function StartTicker()
    if ticker then return end
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
    local pill = ns.ThemeTint("bg", PILL_BG)
    for _, seg in ipairs(bar.segs) do seg:SetColorTexture(pill.r, pill.g, pill.b, S.Get("bgAlpha") / 100) end
    if not clockText:SetFont(UI.FontPath(S.Get("clockFont")), S.Get("clockSize"), "") then
        clockText:SetFont(ns.UIFontPath(), S.Get("clockSize"), "")
    end
    clockText:SetTextColor(Tone("fg", 1))
    clockText.last = nil
    PaintClock()
    bar.sys.text:SetFont(ns.UIFontPath(), S.Get("sysSize"), "OUTLINE")
    -- The "FPS:" and "MS:" labels; the numbers keep their own status colors.
    bar.sys.text:SetTextColor(Tone("fg", 1))
    bar.sys:SetHeight(S.Get("sysSize") + 3)

    local left, right = GroupKeys()
    Layout(leftGroup, left)
    Layout(rightGroup, right)
    FitWidth()

    local segL, segC, segR = bar.segs[1], bar.segs[2], bar.segs[3]
    segL:ClearAllPoints()
    segL:SetPoint("TOPLEFT", leftGroup, "TOPLEFT", -SEG_PAD, 0)
    segL:SetPoint("BOTTOMRIGHT", leftGroup, "BOTTOMRIGHT", SEG_PAD, 0)
    segL:SetShown(#left > 0)
    segL.line:SetShown(#left > 0)
    segR:ClearAllPoints()
    segR:SetPoint("TOPLEFT", rightGroup, "TOPLEFT", -SEG_PAD, 0)
    segR:SetPoint("BOTTOMRIGHT", rightGroup, "BOTTOMRIGHT", SEG_PAD, 0)
    segR:SetShown(#right > 0)
    segR.line:SetShown(#right > 0)
    segC:ClearAllPoints()
    segC:SetPoint("LEFT", clockText, "LEFT", -(SEG_PAD + 4), 0)
    segC:SetPoint("RIGHT", clockText, "RIGHT", SEG_PAD + 4, 0)
    segC:SetPoint("TOP", bar, "TOP")
    segC:SetPoint("BOTTOM", bar, "BOTTOM")

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
function ns.BuildTopBarPage(parent, y)
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Friends and guild on the left, the clock in the middle, addon "
        .. "buttons on either side, with FPS and latency underneath. Move it in Unlock Mode.",
        y); y = y - h

    _, h = W:SectionHeader(parent, "TOP BAR", y); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Bar" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("use24h", "24-Hour Clock", nil, "enabled"),
        S.Slider("bgAlpha", "Bar Opacity (%)", 0, 100, 5, nil, "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("iconSize", "Icon Size", 12, 32, 1, nil, "enabled"),
        S.Slider("clockSize", "Clock Size", 10, 36, 1, nil, "enabled")
    ); y = y - h
    local fonts, fontOrder = UI.FontChoices(S.Get("clockFont"))
    _, h = W:DualRow(parent, y,
        S.Dropdown("clockFont", "Clock Font", fonts, fontOrder, nil, "enabled"),
        { type = "colorpicker", text = "Icon Color", hasAlpha = false,
          getValue = IconColor,
          setValue = function(r, g, b) S.Set("iconColor", { r = r, g = g, b = b }) end,
          disabled = function() return not On() end }
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("hideInCombat", "Hide In Combat", "The FPS / MS readout stays up.", "enabled"),
        S.Toggle("mouseover", "Show On Mouseover", "The bar and the FPS / MS readout fade to "
            .. "Faded Opacity until you hover them. Their buttons still click while faded.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("tooltipScale", "Tooltip Size (%)", 80, 160, 5,
            "Size of the friends, guild, Hearthstone, clock and FPS tooltips.", "enabled"),
        S.Slider("mouseoverAlpha", "Faded Opacity (%)", 0, 100, 5,
            "How visible the bar and the FPS / MS readout stay while the mouse is away. "
            .. "At 0 they are invisible.", "mouseover")
    ); y = y - h

    y = ns.BuildMinimapIcons(parent, y)

    _, h = W:SectionHeader(parent, "FPS / MS", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("showSystem", "Show FPS / MS", nil, "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("sysSize", "Text Size", 6, 24, 1, nil, "showSystem"),
        S.Toggle("systemTooltip", "Tooltip", "Latency and addon memory when you hover the readout.",
            "showSystem")
    ); y = y - h

    -- Every broker source with an icon, from any addon, each with the side it goes on.
    _, h = W:SectionHeader(parent, "BUTTONS", y); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Addon Buttons" }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showFriends", "Friends", "Online friends on the button; its tooltip lists them. "
            .. "Click to open Friends.", "enabled"),
        S.Toggle("showGuild", "Guild", "Online guild members on the button; its tooltip lists them. "
            .. "Click to open Guild.", "enabled")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("showHearth", "Hearthstone", "Uses your Hearthstone. Its tooltip shows where "
            .. "it is set and its cooldown.", "enabled"),
        { type = "label", text = "" }
    ); y = y - h
    local ldb = LDB()
    if ldb then
        local names = {}
        for name, obj in ldb:DataObjectIterator() do
            if obj.icon then names[#names + 1] = name end
        end
        local function Label(name) return ldb:GetDataObjectByName(name).label or name end
        table.sort(names, function(a, b) return Label(a):lower() < Label(b):lower() end)
        local function Side(name) return S.Get("brokerSide")[name] == "left" and "left" or "right" end
        local function SetSide(name, side)
            local sides = {}
            for n, v in pairs(S.Get("brokerSide")) do sides[n] = v end
            sides[name] = side == "left" and "left" or nil
            S.Set("brokerSide", sides)
        end
        -- The house cog: dim until hovered, left of the toggle, opening a Left / Right menu.
        local function SideCog(rgn, name)
            local cog = rgn._cog
            if not cog then
                cog = CreateFrame("Button", nil, rgn)
                cog:SetSize(26, 26)
                cog:SetPoint("RIGHT", rgn._control or rgn, "LEFT", -8, 0)
                cog:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cog:SetAlpha(0.4)
                local tex = cog:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetTexture(UI.COGS_ICON)
                cog:SetScript("OnLeave", function(self)
                    self:SetAlpha(0.4)
                    UI.HideWidgetTooltip()
                end)
                rgn._cog = cog
            end
            cog:Show()
            cog:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                UI.ShowWidgetTooltip(self, "Side: which side of the bar it goes on.")
            end)
            cog:SetScript("OnClick", function(self)
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateRadio("Left", function() return Side(name) == "left" end,
                        function() SetSide(name, "left") end)
                    root:CreateRadio("Right", function() return Side(name) == "right" end,
                        function() SetSide(name, "right") end)
                end)
            end)
        end
        local function Row(name)
            return { type = "toggle", text = Label(name),
                tooltip = "A button for it on the bar. It clicks and shows its tooltip the way the "
                    .. "addon's own minimap button does. The cog picks its side.",
                disabled = function() return not On() end,
                getValue = function() return tContains(S.Get("brokers"), name) end,
                setValue = function(v)
                    local list = {}
                    for _, n in ipairs(S.Get("brokers")) do
                        if n ~= name then list[#list + 1] = n end
                    end
                    if v then list[#list + 1] = name end
                    S.Set("brokers", list)
                end }
        end
        for i = 1, #names, 2 do
            local row
            row, h = W:DualRow(parent, y, Row(names[i]), names[i + 1] and Row(names[i + 1])
                or { type = "label", text = "" }); y = y - h
            SideCog(row._leftRegion, names[i])
            -- Rows are reused, so a blank half can still hold a cog from a longer list.
            if names[i + 1] then
                SideCog(row._rightRegion, names[i + 1])
            elseif row._rightRegion._cog then
                row._rightRegion._cog:Hide()
            end
        end
    end
    return y
end

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

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterEvent("FRIENDLIST_UPDATE")
events:RegisterEvent("BN_FRIEND_INFO_CHANGED")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
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
