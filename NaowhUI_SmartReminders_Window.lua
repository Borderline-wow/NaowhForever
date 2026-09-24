-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Window.lua -- the standalone options window.
--
--  Owns the window lifecycle half of ns.UI: RefreshPage, ClearContentHeader and the
--  OnShow/OnHide callback lists the runtime uses to drive the preview. The page builders
--  themselves live in the later files and are resolved at open time, since this file
--  loads before them.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local T = ns.THEME
local UI = ns.UI

local SIDEBAR_W, CONTENT_W, WINDOW_H = 230, 1000, 700
local HEADER_H, TAB_H, FOOTER_H, NAV_H = 76, 32, 46, 32
local LOGO = "Interface\\AddOns\\NaowhSmartReminders\\Media\\LogoAddon.tga"

-- The sidebar is the window's own pages first, then one entry per module. A module opens
-- on its first tab. `build` names the ns builder resolved at open time; `arg` is passed
-- after the starting y. A page with `soon` is built but not ready: its tab stays in the
-- strip, dimmed, and opens a note instead of half-finished work.
local SYSTEM_PAGES = {
    { name = "Settings", build = "BuildSettingsPage",
      subtitle = "Options for the whole addon, saved for this computer." },
    { name = "Patch Notes", build = "BuildPatchNotesPage",
      subtitle = "What changed in recent builds." },
    { name = "Profiles", build = "BuildProfileSettings",
      subtitle = "Switch, copy and share everything these pages save." },
}

local MODULES = {
    { name = "Smart Reminders",
      subtitle = "Calls out what to press when a boss ability is about to land.",
      tabs = {
          { name = "Setup", build = "BuildSetupPage" },
          { name = "Cooldown Presets", build = "BuildPresetsPage" },
          { name = "Dungeon Bosses", build = "BuildBossTabPage", arg = false },
          { name = "Raid Bosses", build = "BuildBossTabPage", arg = true },
          { name = "Trash", build = "BuildIntegrationsPage" },
          { name = "Custom Notes", soon = "Your own note lines, driven by the same triggers "
              .. "the reminders use. Not finished yet.\n\nNothing is missing in the meantime: "
              .. "reminders still carry their own text, set per reminder from the boss and "
              .. "trash pages." },
      } },
    { name = "QoL", settings = "QoLSettings",
      subtitle = "Naowh's quality of life tweaks, trimmed to what Forever has.",
      tabs = {
          { name = "General", build = "BuildQoLGeneralPage" },
          { name = "Loot & Items", build = "BuildQoLLootPage" },
          { name = "Alerts", build = "BuildQoLAlertsPage" },
          { name = "Interface", build = "BuildQoLInterfacePage" },
          { name = "Trainer", build = "BuildQoLTrainerPage" },
          { name = "Flight & Camp", build = "BuildQoLFlightPage" },
          { name = "Dungeon Quests", build = "BuildQoLDungeonQuestsPage" },
      } },
    { name = "Macros", settings = "MacroSettings",
      subtitle = "Macros written and kept current for you, out of combat.",
      tabs = {
          { name = "Consumables", build = "BuildMacroConsumablesPage" },
          { name = "Focus & Cursor", build = "BuildMacroFocusPage" },
      } },
    { name = "AuraBuffs", settings = "AuraBuffSettings",
      subtitle = "Buff, consumable and campfire reminders, low health and debuff sounds.",
      tabs = {
          { name = "Buffs & Consumables", build = "BuildAuraBuffsPage" },
          { name = "Campfire", build = "BuildCampfirePage" },
          { name = "Low Health", build = "BuildLowHealthPage" },
          { name = "Poison & Dispel", build = "BuildPoisonDispelPage" },
      } },
}

-- Page key -> page. Module tabs are keyed "Module/Tab", since two modules may share a tab
-- name; the window's own pages are their own key.
local PAGES = {}
for _, page in ipairs(SYSTEM_PAGES) do
    page.key, page.title = page.name, page.name
    PAGES[page.key] = page
end
for _, mod in ipairs(MODULES) do
    for _, tab in ipairs(mod.tabs) do
        tab.key, tab.module = mod.name .. "/" .. tab.name, mod
        PAGES[tab.key] = tab
    end
end

-- The page whose rows are reused rather than rebuilt.
local SETUP_PAGE = "Smart Reminders/Setup"

local window, scrollFrame, scrollChild, tabLine, headerTitle, headerSub
local navButtons, tabButtons, tabStrips = {}, {}, {}
local wrappers = {}          -- page key -> built wrapper frame
local currentPage = SETUP_PAGE
local pendingRefresh
local onShowCallbacks, onHideCallbacks = {}, {}

function UI:RegisterOnShow(fn) onShowCallbacks[#onShowCallbacks + 1] = fn end
function UI:RegisterOnHide(fn) onHideCallbacks[#onHideCallbacks + 1] = fn end
function UI:ClearContentHeader() end

-- The builders return their raw running y (negative), and the wrapper takes math.abs of it.
local function BuildPageInto(page, parent)
    if page.soon then
        local head = ns.Font(parent, 16, "OUTLINE", T.muted)
        head:SetPoint("TOP", parent, "TOP", 0, -60)
        head:SetText(ns.L("Coming soon"))

        local body = ns.Font(parent, 12, nil, T.muted)
        body:SetPoint("TOP", head, "BOTTOM", 0, -12)
        body:SetPoint("LEFT", parent, "LEFT", 60, 0)
        body:SetPoint("RIGHT", parent, "RIGHT", -60, 0)
        body:SetJustifyH("CENTER")
        body:SetWordWrap(true)
        body:SetText(page.soon)
        return -180
    end
    local fn = ns[page.build]
    if not fn then return -6 end
    return fn(parent, -6, page.arg)
end

-- A module's on/off switch. Smart Reminders keeps its own master switch; the newer modules
-- store `enabled` in their settings table.
local function ModuleOn(mod)
    if mod.settings then return ns[mod.settings].Get("enabled") end
    return ns.DB().enabled == true
end

local function SetModuleOn(mod, on)
    if mod.settings then ns[mod.settings].Set("enabled", on) else ns.SetEnabled(on) end
    UI:RefreshPage(true)
end

-- The sidebar entry a page lights: its module, or the page itself.
local function ActiveNav()
    local page = PAGES[currentPage]
    return page.module and page.module.name or page.key
end

-- A page that cannot be used reads as dimmer than an inactive one, and keeps that look
-- even while it is the page you are on, since selecting it changes nothing about whether
-- it works.
local function PaintTab(btn, page, active)
    if page.soon then
        btn.label:SetTextColor(T.muted.r, T.muted.g, T.muted.b, 0.45)
    else
        local c = active and T.fg or T.muted
        btn.label:SetTextColor(c.r, c.g, c.b, 1)
    end
    btn.marker:SetShown(active)
end

local function PaintNav()
    local nav = ActiveNav()
    for name, btn in pairs(navButtons) do
        local active = name == nav
        local c = active and T.fg or T.muted
        btn.label:SetTextColor(c.r, c.g, c.b, 1)
        btn.fill:SetShown(active)
        btn.marker:SetShown(active)
        if btn.switch then
            btn.switch._refreshValue()
            btn.label:SetAlpha(ModuleOn(btn.module) and 1 or 0.5)
        end
    end
    for key, btn in pairs(tabButtons) do PaintTab(btn, PAGES[key], key == currentPage) end
end

-- Only a module has a tab strip, so the content starts higher on the window's own pages
-- rather than leaving an empty band where the strip would be.
local function LayoutContent()
    local page = PAGES[currentPage]
    local mod = page.module
    headerTitle:SetText(ns.L(mod and mod.name or page.title))
    headerSub:SetText(mod and mod.subtitle or page.subtitle)
    for name, strip in pairs(tabStrips) do strip:SetShown(mod ~= nil and name == mod.name) end
    local offset = HEADER_H + (mod and TAB_H or 0)
    tabLine:ClearAllPoints()
    tabLine:SetPoint("TOPLEFT", window, "TOPLEFT", SIDEBAR_W, -offset)
    tabLine:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -offset)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", window, "TOPLEFT", SIDEBAR_W + 10, -(offset + 5))
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, FOOTER_H + 4)
end

local function ShowPage(key)
    currentPage = key
    LayoutContent()
    for name, w in pairs(wrappers) do
        w:SetShown(name == key)
    end
    if not wrappers[key] then
        local wrapper = CreateFrame("Frame", nil, scrollChild)
        wrapper:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        wrapper:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
        wrapper:SetHeight(1)
        wrappers[key] = wrapper
        wrapper._dirty = true
    end
    local wrapper = wrappers[key]
    if wrapper._dirty then
        wrapper._dirty = nil
        if key == SETUP_PAGE then UI.BeginReusableRows(wrapper) end
        local usedY = BuildPageInto(PAGES[key], wrapper)
        wrapper:SetHeight(math.abs(usedY) + 30)
    end
    scrollChild:SetHeight(wrappers[key]:GetHeight())
    scrollFrame:SetVerticalScroll(0)
    PaintNav()
end

local function InvalidatePages()
    for name, w in pairs(wrappers) do
        if name == SETUP_PAGE then
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

-- Set from the dropdown on the Settings page. A dropdown rather than a slider on purpose:
-- the control sits inside the frame it resizes, and the slider maps the cursor against the
-- track's live position, so rescaling mid-drag walks the track out from under the pointer
-- and the value chases it.
function ns.SetWindowScale(pct)
    ns.AccountSettings().windowScale = tonumber(pct) or 100
    if window then window:SetScale(ns.UIScale()) end
end

function ns.BuildSettingsPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "OPTIONS WINDOW", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Window Scale",
          values = { [100] = "100%  (default)", [90] = "90%", [80] = "80%",
                     [70] = "70%", [60] = "60%", [50] = "50%" },
          order = { 100, 90, 80, 70, 60, 50 },
          tooltip = "Size of this options window and the editors it opens, as a percentage. "
          .. "Turn it down if the window is too big for your screen; 1080p usually wants 80 "
          .. "or below.|n|nSaved for this computer instead of in the profile, so switching "
          .. "profile leaves it alone and an exported pack never carries it to someone on a "
          .. "different monitor.",
          getValue = function() return tonumber(ns.AccountSettings().windowScale) or 100 end,
          setValue = function(v) ns.SetWindowScale(v) end },
        { type = "toggle", text = "Minimap Button",
          tooltip = "The Naowh Forever button on the minimap. The addon compartment entry "
          .. "and /naowh open this window either way.",
          getValue = function()
              local mm = ns.AccountSettings().minimap
              return not (type(mm) == "table" and mm.hide)
          end,
          setValue = function(v)
              ns.AccountSettings().minimap.hide = not v
              local icon = LibStub("LibDBIcon-1.0")
              if v then icon:Show("NaowhSmartReminders") else icon:Hide("NaowhSmartReminders") end
          end }
    ); y = y - h

    _, h = W:SectionHeader(parent, "FONT", y); y = y - h
    local fonts, fontOrder = UI.FontChoices(ns.AccountSettings().gameFont)
    fonts[""] = "Naowh (default)"
    fonts[ns.BLIZZARD_FONT] = "Blizzard Default"
    table.insert(fontOrder, 2, ns.BLIZZARD_FONT)
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Global Font", values = fonts, order = fontOrder,
          tooltip = "The font for all of the game's text: this addon, menus, chat, tooltips, "
          .. "names and damage numbers. Blizzard Default leaves the game's own fonts alone. "
          .. "Saved for this computer.|n|nTakes effect after a /reload.",
          getValue = function() return ns.AccountSettings().gameFont or "" end,
          setValue = function(v)
              if v == "" then v = nil end
              ns.AccountSettings().gameFont = v
          end },
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Reload UI", y, ReloadUI); y = y - h

    return y
end

local function EnterUnlockMode()
    if ns.ShowRaidReminderAnchorConfig then ns.ShowRaidReminderAnchorConfig() end
end

local function StartDrag() window:StartMoving() end
local function StopDrag() window:StopMovingOrSizing() end

local function DragRegion(frame)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
end

local function CreateWindow()
    window = CreateFrame("Frame", "NaowhUISmartRemindersOptions", UIParent)
    window:SetSize(SIDEBAR_W + CONTENT_W, WINDOW_H)
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

    -- Sidebar: logo and name, the window's own pages, then the modules.
    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT")
    sidebar:SetPoint("BOTTOMLEFT")
    sidebar:SetWidth(SIDEBAR_W)
    ns.Solid(sidebar, "BACKGROUND", T.panel, 1):SetAllPoints()
    local edge = ns.Solid(sidebar, "ARTWORK", T.line, 1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)

    local brand = CreateFrame("Frame", nil, sidebar)
    brand:SetPoint("TOPLEFT")
    brand:SetPoint("TOPRIGHT")
    brand:SetHeight(HEADER_H)
    DragRegion(brand)
    local logo = brand:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetSize(44, 44)
    logo:SetPoint("LEFT", brand, "LEFT", 16, 0)
    local name = ns.Font(brand, 19, "OUTLINE")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("|cff0091edNaowh|r Forever")

    local ny = -(HEADER_H + 8)
    local function NavButton(label, onClick, indent)
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, ny)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, ny)
        btn:SetHeight(NAV_H)
        btn.fill = ns.Solid(btn, "BACKGROUND", T.grey, 0.5)
        btn.fill:SetAllPoints()
        btn.fill:Hide()
        btn.marker = ns.Solid(btn, "ARTWORK", T.accent, 1)
        btn.marker:SetPoint("TOPLEFT")
        btn.marker:SetPoint("BOTTOMLEFT")
        btn.marker:SetWidth(3)
        btn.marker:Hide()
        btn.label = ns.Font(btn, 13, nil, T.muted)
        btn.label:SetPoint("LEFT", btn, "LEFT", indent or 22, 0)
        btn.label:SetText(ns.L(label))
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self) self.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1) end)
        btn:SetScript("OnLeave", function(self)
            local c = self.fill:IsShown() and T.fg or T.muted
            self.label:SetTextColor(c.r, c.g, c.b, 1)
        end)
        ny = ny - NAV_H
        return btn
    end

    local unlock = NavButton("Unlock Mode", EnterUnlockMode)
    ns.Tooltip(unlock, "Unlock Mode",
        "Place and size each reminder display. An alignment grid appears while you are in "
        .. "there. This window steps aside and comes back when you press Exit Config.")
    for _, page in ipairs(SYSTEM_PAGES) do
        navButtons[page.key] = NavButton(page.name, function() ShowPage(page.key) end)
    end

    ny = ny - 14
    local group = ns.Font(sidebar, 13, nil, T.accent)
    group:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 18, ny)
    group:SetText(ns.L("Modules"))
    ny = ny - 24
    -- Indented under the group label, each with a small switch that turns the whole
    -- module off without leaving the page you are on.
    for _, mod in ipairs(MODULES) do
        local btn = NavButton(mod.name, function() ShowPage(mod.tabs[1].key) end, 36)
        local switch = UI.BuildToggleControl(btn, btn:GetFrameLevel() + 2,
            function() return ModuleOn(mod) end,
            function(v) SetModuleOn(mod, v) end, 28, 14)
        switch:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
        ns.Tooltip(switch, mod.name, function()
            return ModuleOn(mod) and "On. Click to turn the whole module off."
                or "Off. Click to turn it back on."
        end)
        btn.switch, btn.module = switch, mod
        navButtons[mod.name] = btn
    end

    local version = ns.Font(sidebar, 11, nil, T.muted)
    version:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 18, 14)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata(ns.MODULE_KEY, "Version") or "unknown"))

    -- Content header: the open module's name and what it is for, with its tabs below.
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", window, "TOPLEFT", SIDEBAR_W, 0)
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    DragRegion(header)
    headerTitle = ns.Font(header, 24, "OUTLINE")
    headerTitle:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -18)
    headerSub = ns.Font(header, 12, nil, T.muted)
    headerSub:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 1, -6)

    local close = ns.Button(header, "X", 26, 26, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -12)

    -- Tab strip, in the same visual language as the modal editors' own tabs: a button
    -- with an accent underline marking the active page. Widths are measured off the label
    -- rather than fixed, since tab names vary a lot in length and a fixed width leaves the
    -- short ones swimming.
    for _, mod in ipairs(MODULES) do
        local strip = CreateFrame("Frame", nil, window)
        strip:SetPoint("TOPLEFT", window, "TOPLEFT", SIDEBAR_W, -HEADER_H)
        strip:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -HEADER_H)
        strip:SetHeight(TAB_H)
        local tx = 20
        for _, tab in ipairs(mod.tabs) do
            local btn = CreateFrame("Button", nil, strip)
            btn.label = ns.Font(btn, 14, nil, T.muted)
            btn.label:SetPoint("CENTER")
            btn.label:SetText(ns.L(tab.name))
            btn:SetSize(math.ceil(btn.label:GetStringWidth()) + 30, TAB_H)
            btn.marker = ns.Solid(btn, "OVERLAY", T.accent, 1)
            btn.marker:SetPoint("BOTTOMLEFT", 6, 0)
            btn.marker:SetPoint("BOTTOMRIGHT", -6, 0)
            btn.marker:SetHeight(2)
            btn.marker:Hide()
            btn:SetScript("OnClick", function() ShowPage(tab.key) end)
            btn:SetPoint("TOPLEFT", strip, "TOPLEFT", tx, 0)
            tabButtons[tab.key] = btn
            tx = tx + btn:GetWidth() + 2
        end
        tabStrips[mod.name] = strip
        strip:Hide()
    end

    tabLine = ns.Solid(window, "ARTWORK", T.line, 1)
    tabLine:SetHeight(1)

    local footer = CreateFrame("Frame", nil, window)
    footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", SIDEBAR_W, 0)
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    local footLine = ns.Solid(footer, "ARTWORK", T.line, 1)
    footLine:SetPoint("TOPLEFT")
    footLine:SetPoint("TOPRIGHT")
    footLine:SetHeight(1)
    ns.Button(footer, "Reload UI", 140, 26, ReloadUI):SetPoint("LEFT", footer, "LEFT", 30, 0)
    ns.Button(footer, "Close", 140, 26, function() window:Hide() end)
        :SetPoint("RIGHT", footer, "RIGHT", -30, 0)

    scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    -- Fixed width so the builders' CONTENT_PAD math lands on the same row widths every
    -- build; the window is deliberately not resizable for the same reason.
    scrollChild:SetSize(CONTENT_W - 40, 1)
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

-- pageName, when given, is which page the window opens on; OnShow renders currentPage,
-- so setting it before Show() is the whole mechanism. A page key, a module name (its
-- first tab) or a bare tab name all work, so older callers naming "Setup" still land.
function ns.OpenOptionsWindow(pageName)
    if pageName then
        if PAGES[pageName] then
            currentPage = pageName
        else
            for _, mod in ipairs(MODULES) do
                if mod.name == pageName then currentPage = mod.tabs[1].key break end
                for _, tab in ipairs(mod.tabs) do
                    if tab.name == pageName then currentPage = tab.key break end
                end
            end
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
SlashCmdList["NAOWHUISMARTREM"] = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "quiz" and ns.ToggleQuiz then
        ns.ToggleQuiz()
    elseif cmd == "xp" and ns.XPTickerCommand then
        ns.XPTickerCommand(arg)
    else
        ns.ToggleOptionsWindow()
    end
end

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
        label = "Naowh Forever",
        icon = LOGO,
        OnClick = function() ns.ToggleOptionsWindow() end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Naowh Forever")
            tooltip:AddLine(ns.L("Click to open settings."), 1, 1, 1)
            tooltip:AddLine(ns.L("Drag to move the minimap button."), 1, 1, 1)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("NaowhSmartReminders", launcher, account.minimap)
end)
launcherEvents:RegisterEvent("PLAYER_LOGIN")
