-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Window.lua -- the standalone options window.
--
--  Owns the window lifecycle half of ns.UI: RefreshPage, ClearContentHeader and the
--  OnShow/OnHide callback lists the runtime uses to drive the preview. The page builders
--  themselves live in the main and Bosses files and are resolved at open time, since this
--  file loads before them.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local T = ns.THEME
local UI = ns.UI

local WINDOW_W, WINDOW_H = 1000, 640
local TITLE_H, TAB_H = 28, 30

local PAGES = { "Smart Reminders Setup", "Cooldown Presets", "Dungeon Bosses",
    "Raid Bosses", "Ability Reminders", "Profiles" }

-- Pages that are built but not ready to be used. The tab stays in the strip, dimmed, and
-- opens a note instead of the page: removing it would leave a gap people ask about, and
-- letting it open half-finished work is worse than saying so.
local COMING_SOON = {
    ["Ability Reminders"] = "Every reminder for one boss in a single list, instead of one "
        .. "boss page at a time. Not finished yet.\n\nNothing is missing in the meantime: "
        .. "the same reminders are authored per boss from the Dungeon Bosses and Raid "
        .. "Bosses tabs, which is where this page reads them from.",
}

local window, scrollFrame, scrollChild
local tabButtons = {}
local wrappers = {}          -- pageName -> built wrapper frame
local currentPage = PAGES[1]
local pendingRefresh
local onShowCallbacks, onHideCallbacks = {}, {}

function UI:RegisterOnShow(fn) onShowCallbacks[#onShowCallbacks + 1] = fn end
function UI:RegisterOnHide(fn) onHideCallbacks[#onHideCallbacks + 1] = fn end
function UI:ClearContentHeader() end

-- The dispatch the pages were registered with when EllesmereUI hosted them; the builders
-- return their raw running y (negative), and the wrapper takes math.abs of it.
local function BuildPageInto(pageName, parent)
    local soon = COMING_SOON[pageName]
    if soon then
        local head = ns.Font(parent, 16, "OUTLINE", T.muted)
        head:SetPoint("TOP", parent, "TOP", 0, -60)
        head:SetText("Coming soon")

        local body = ns.Font(parent, 12, nil, T.muted)
        body:SetPoint("TOP", head, "BOTTOM", 0, -12)
        body:SetPoint("LEFT", parent, "LEFT", 60, 0)
        body:SetPoint("RIGHT", parent, "RIGHT", -60, 0)
        body:SetJustifyH("CENTER")
        body:SetWordWrap(true)
        body:SetText(soon)
        return -180
    end
    if pageName == "Profiles" then
        return ns.BuildProfileSettings and ns.BuildProfileSettings(parent, -6) or -6
    elseif pageName == "Cooldown Presets" then
        return ns.BuildPresetsPage and ns.BuildPresetsPage(parent, -6) or -6
    elseif pageName == "Dungeon Bosses" then
        return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, -6, false) or -6
    elseif pageName == "Raid Bosses" then
        return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, -6, true) or -6
    elseif pageName == "Ability Reminders" then
        return ns.BuildCustomRemindersPage and ns.BuildCustomRemindersPage(parent, -6) or -6
    else
        return ns.BuildSetupPage and ns.BuildSetupPage(parent, -6) or -6
    end
end

local function PaintTabs()
    for name, btn in pairs(tabButtons) do
        local active = (name == currentPage)
        -- A page that cannot be used reads as dimmer than an inactive one, and keeps that
        -- look even while it is the page you are on, since selecting it changes nothing
        -- about whether it works.
        if COMING_SOON[name] then
            btn.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 0.45)
        else
            btn.label:SetTextColor(active and T.fg.r or T.muted.r,
                active and T.fg.g or T.muted.g,
                active and T.fg.b or T.muted.b, 1)
        end
        btn.marker:SetShown(active)
    end
end

local function ShowPage(pageName)
    currentPage = pageName
    for name, w in pairs(wrappers) do
        w:SetShown(name == pageName)
    end
    if not wrappers[pageName] then
        local wrapper = CreateFrame("Frame", nil, scrollChild)
        wrapper:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        wrapper:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
        wrapper:SetHeight(1)
        wrappers[pageName] = wrapper
        wrapper._dirty = true
    end
    local wrapper = wrappers[pageName]
    if wrapper._dirty then
        wrapper._dirty = nil
        if pageName == PAGES[1] then UI.BeginReusableRows(wrapper) end
        local usedY = BuildPageInto(pageName, wrapper)
        wrapper:SetHeight(math.abs(usedY) + 30)
    end
    scrollChild:SetHeight(wrappers[pageName]:GetHeight())
    scrollFrame:SetVerticalScroll(0)
    PaintTabs()
end

local function InvalidatePages()
    for name, w in pairs(wrappers) do
        if name == PAGES[1] then
            w._dirty = true
        else
            w:Hide()
            w:SetParent(nil)
            wrappers[name] = nil
        end
    end
end

-- The universal "this setting changed, redraw it" call. Every caller passes force=true --
-- there has never been a caller that wants anything less -- and force never meant more than
-- "rebuild the active tab": every OTHER cached tab kept whatever it looked like when it was
-- last built, which is wrong for anything that isn't scoped to the tab you happened to be
-- looking at (a pack import landing new Cooldown Presets while you're sitting on Raid
-- Bosses, say). Invalidate every cached tab: Setup reuses its rows, while dynamic editor
-- pages rebuild their wrappers on the next ShowPage. When the window is hidden the
-- rebuild waits for the next open, so page-build side effects (preview, lazy journal reads)
-- never run off-screen.
-- One rebuild per frame however many times it is asked for: one action (a pack import,
-- a chain of setters) can ask repeatedly.
local refreshQueued

local function RebuildPages()
    refreshQueued = false
    if not (window and window:IsShown()) then
        pendingRefresh = true
        return
    end
    -- A tooltip anchored to a row we are about to destroy would hang on screen with its
    -- anchor orphaned; changing a setting while hovering its label is the ordinary way in.
    if UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
    local scroll = scrollFrame:GetVerticalScroll()
    InvalidatePages()
    ShowPage(currentPage)
    scrollFrame:UpdateScrollChildRect()
    scrollFrame:SetVerticalScroll(scroll)
end

function UI:RefreshPage(force)
    if not (window and window:IsShown()) then
        pendingRefresh = true
        return
    end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, RebuildPages)
end

-- ShowPage only rebuilds a page's cached wrapper on an explicit RefreshPage call, so a
-- trinket swap while the Cooldown Presets page is already built and just sitting shown would
-- otherwise never be noticed short of a full /reload. Only the trinket slots feed that page,
-- and the event fires once per changed slot, so an equipment-set swap arrives as a burst.
local equipWatcher = CreateFrame("Frame")
equipWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
equipWatcher:SetScript("OnEvent", function(_, _, slot)
    if slot == INVSLOT_TRINKET1 or slot == INVSLOT_TRINKET2 then UI:RefreshPage(true) end
end)

-- Set from the dropdown on the setup page. A dropdown rather than a slider on purpose:
-- the control sits inside the frame it resizes, and the slider maps the cursor against the
-- track's live position, so rescaling mid-drag walks the track out from under the pointer
-- and the value chases it.
function ns.SetWindowScale(pct)
    ns.AccountSettings().windowScale = tonumber(pct) or 100
    if window then window:SetScale(ns.UIScale()) end
end

local function CreateWindow()
    window = CreateFrame("Frame", "NaowhUISmartRemindersOptions", UIParent)
    window:SetSize(WINDOW_W, WINDOW_H)
    window:SetScale(ns.UIScale())
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    ns.Solid(window, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(window)

    -- ESC via our own keyboard handler, NOT UISpecialFrames: a named addon frame in that
    -- table is a convicted taint injector (Blizzard's CloseAllWindows enumerates it inside
    -- secure execution). Same combat-guarded pattern MakeModal uses; opened in combat the
    -- window keeps its close button and ESC binds from its next out-of-combat open (OnShow).
    window:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false)
            -- Restored once this key is consumed: reopened in combat, the window cannot
            -- change it and would swallow every keybind while open.
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local titleBar = CreateFrame("Button", nil, window)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
    ns.Solid(titleBar, "BACKGROUND", T.panel, 1):SetAllPoints()
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    local title = ns.Font(titleBar, 13, "OUTLINE")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("|cff0091edNaowh|r Smart Reminders")

    local close = ns.Button(titleBar, "X", 22, 22, function() window:Hide() end)
    close:SetPoint("RIGHT", -3, 0)

    local version = ns.Font(titleBar, 11, nil, T.muted)
    version:SetPoint("RIGHT", close, "LEFT", -10, 0)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata(ns.MODULE_KEY, "Version") or "unknown"))

    -- Tab strip, in the same visual language as the modal editors' own tabs: a button
    -- with an accent underline marking the active page.
    local tx = 10
    for _, name in ipairs(PAGES) do
        local btn = CreateFrame("Button", nil, window)
        btn:SetSize(150, TAB_H)
        btn:SetPoint("TOPLEFT", window, "TOPLEFT", tx, -TITLE_H)
        btn.label = ns.Font(btn, 12, nil, T.muted)
        btn.label:SetPoint("CENTER")
        btn.label:SetText(name)
        btn.marker = ns.Solid(btn, "OVERLAY", T.accent, 1)
        btn.marker:SetPoint("BOTTOMLEFT", 16, 0)
        btn.marker:SetPoint("BOTTOMRIGHT", -16, 0)
        btn.marker:SetHeight(2)
        btn.marker:Hide()
        btn:SetScript("OnClick", function() ShowPage(name) end)
        tabButtons[name] = btn
        tx = tx + 154
    end
    local tabLine = ns.Solid(window, "ARTWORK", T.line, 1)
    tabLine:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -(TITLE_H + TAB_H))
    tabLine:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -(TITLE_H + TAB_H))
    tabLine:SetHeight(1)

    scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -(TITLE_H + TAB_H + 5))
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 10)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    -- Fixed width so the builders' CONTENT_PAD math lands on the same row widths every
    -- build; the window is deliberately not resizable for the same reason.
    scrollChild:SetSize(WINDOW_W - 40, 1)
    scrollFrame:SetScrollChild(scrollChild)

    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(true)
        end
        -- Same rule as RefreshPage itself: a refresh asked for while the window was
        -- closed (gear changed with it shut, say) is not scoped to whichever tab happens
        -- to be current on reopen, so every cached tab goes, not just that one.
        if pendingRefresh then
            pendingRefresh = nil
            InvalidatePages()
        end
        ShowPage(currentPage)
        for i = 1, #onShowCallbacks do onShowCallbacks[i]() end
    end)
    window:SetScript("OnHide", function()
        if UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
        for i = 1, #onHideCallbacks do onHideCallbacks[i]() end
    end)

    -- CreateFrame hands back a SHOWN frame, so without this the first Show() is a no-op
    -- and OnShow never runs: the page renders (OpenOptionsWindow calls ShowPage itself)
    -- but nothing that rides the open callback -- the preview above all -- ever arms,
    -- until something genuinely hides the window and the next Show() is a real edge.
    window:Hide()
end

-- pageName, when given, is which tab the window opens on; OnShow renders currentPage,
-- so setting it before Show() is the whole mechanism.
function ns.OpenOptionsWindow(pageName)
    if pageName then
        for _, name in ipairs(PAGES) do
            if name == pageName then currentPage = pageName break end
        end
    end
    if not window then CreateWindow() end
    if window:IsShown() and pageName then
        ShowPage(currentPage)
    end
    window:Show()
end

-- Anchor config mode draws its movers and its own toolbar at HIGH, and this window is
-- DIALOG, so the two cannot share the screen. Config mode steps the window out of the
-- way and puts it back on exit.
function ns.StashOptionsWindow()
    if window and window:IsShown() then
        window:Hide()
        return true
    end
    return false
end

function ns.ToggleOptionsWindow(pageName)
    if window and window:IsShown() then
        window:Hide()
    else
        ns.OpenOptionsWindow(pageName)
    end
end

-- Addon compartment entry (the puzzle-piece menu by the minimap); wired in the .toc.
function _G.NaowhUI_SmartReminders_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

SLASH_NAOWHUISMARTREM1 = "/smartreminders"
SLASH_NAOWHUISMARTREM2 = "/naowh"
SLASH_NAOWHUISMARTREM3 = "/nao"
SLASH_NAOWHUISMARTREM4 = "/nsr"
SlashCmdList["NAOWHUISMARTREM"] = function() ns.ToggleOptionsWindow() end

-- The launcher position belongs to the account, not an imported settings profile.
local launcherEvents = CreateFrame("Frame")
launcherEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local account = ns.AccountSettings()
    if type(account.minimap) ~= "table" then
        account.minimap = { minimapPos = 220 }
    end
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject("NaowhSmartReminders", {
        type = "launcher",
        label = "Naowh Smart Reminders",
        icon = "Interface\\AddOns\\NaowhSmartReminders\\Media\\LogoAddon.tga",
        OnClick = function() ns.ToggleOptionsWindow() end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Naowh Smart Reminders")
            tooltip:AddLine("Click to open settings.", 1, 1, 1)
            tooltip:AddLine("Drag to move the minimap button.", 1, 1, 1)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("NaowhSmartReminders", launcher, account.minimap)
end)
launcherEvents:RegisterEvent("PLAYER_LOGIN")
