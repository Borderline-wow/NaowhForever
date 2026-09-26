-------------------------------------------------------------------------------
--  NaowhForever_Window.lua -- the standalone options window.
--
--  Owns the window lifecycle half of ns.UI: RefreshPage, ClearContentHeader and the
--  OnShow/OnHide callback lists the runtime uses to drive the preview. The page builders
--  themselves live in the later files and are resolved at open time, since this file
--  loads before them.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local SIDEBAR_W, CONTENT_W, WINDOW_H = 230, 1000, 700
local HEADER_H, TAB_H, FOOTER_H, NAV_H = 76, 32, 46, 32
local LOGO = "Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga"

-- The window's own pages sit in the header; the sidebar has one entry per module. A module opens
-- on its first tab. `build` names the ns builder resolved at open time; `arg` is passed
-- after the starting y. A page with `soon` is built but not ready: its tab stays in the
-- strip, dimmed, and opens a note instead of half-finished work.
-- A module with `command` also opens in a window of its own, from /nf<command> and a micro
-- menu button labelled `short`; `micro` puts that button on the bar by default.
local SYSTEM_PAGES = {
    { name = "Settings", build = "BuildSettingsPage",
      subtitle = "Options for the whole addon, saved for this computer." },
    { name = "Patch Notes", build = "BuildPatchNotesPage",
      subtitle = "What changed in recent builds." },
    { name = "Profiles", build = "BuildProfileSettings",
      subtitle = "Switch, copy and share everything these pages save." },
}

-- Custom Reminders has no runtime yet; its switch only needs somewhere to live.
ns.CustomReminderSettings = UI.ModuleSettings("customReminders", { enabled = false })

local MODULES = {
    { name = "QoL", settings = "QoLSettings",
      subtitle = "Naowh's quality of life tweaks, trimmed to what Forever has.",
      tabs = {
          { name = "General", build = "BuildQoLGeneralPage" },
          { name = "Loot & Items", build = "BuildQoLLootPage" },
          { name = "Alerts", build = "BuildQoLAlertsPage" },
          { name = "Interface", build = "BuildQoLInterfacePage" },
          { name = "Trainer", build = "BuildQoLTrainerPage" },
          { name = "Flight & Camp", build = "BuildQoLFlightPage" },
      } },
    -- Settings still live in the QoL table so existing profiles carry over; each module's
    -- switch is the feature's own key rather than QoL's.
    { name = "Dungeon Quests", settings = "QoLSettings", enabledKey = "dqTracker",
      command = "dq", short = "DQ", micro = true,
      subtitle = "Every dungeon quest on Forever, and a tracker for the dungeon you are in.",
      tabs = {
          { name = "Tracker", build = "BuildQoLDungeonQuestsPage" },
      } },
    { name = "Gear Sets", settings = "QoLSettings", enabledKey = "gearSets",
      command = "gear", short = "Gear",
      subtitle = "Swap equipment sets from a bar, or on their own while you ride or rest.",
      tabs = {
          { name = "Sets", build = "BuildQoLGearSetsPage" },
      } },
    { name = "Blessings", settings = "QoLSettings", enabledKey = "blessings",
      command = "bless", short = "Bless",
      subtitle = "Paladin blessings by class and player, shared with the group's paladins.",
      tabs = {
          { name = "Bar", build = "BuildQoLBlessingsPage" },
          { name = "Assignments", build = "BuildBlessingAssignmentsPage" },
      } },
    { name = "BiS List", settings = "QoLSettings", enabledKey = "bis",
      command = "bis", short = "BiS", micro = true,
      subtitle = "Your best-in-slot list, marked on tooltips and called out when it drops.",
      tabs = {
          { name = "List", build = "BuildQoLBiSPage" },
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
    { name = "Threat Meter", settings = "ThreatMeterSettings",
      command = "threat", short = "Threat",
      subtitle = "Threat on your target for the whole group, and a warning before you pull.",
      tabs = {
          { name = "Meter", build = "BuildThreatMeterPage" },
      } },
    -- The reminder modules sit below a divider in the sidebar.
    { name = "Custom Reminders", settings = "CustomReminderSettings", divider = true,
      subtitle = "Your own reminders, driven by the same triggers Smart Reminders uses.",
      tabs = {
          { name = "Custom Notes", soon = "Your own note lines, driven by the same triggers "
              .. "the reminders use. Not finished yet.\n\nNothing is missing in the meantime: "
              .. "reminders still carry their own text, set per reminder from the boss "
              .. "pages." },
      } },
    { name = "Smart Reminders",
      subtitle = "Calls out what to press when a boss ability is about to land.",
      tabs = {
          { name = "Setup", build = "BuildSetupPage" },
          { name = "Cooldown Presets", build = "BuildPresetsPage" },
          { name = "Dungeon Bosses", build = "BuildBossTabPage", arg = false },
          { name = "Raid Bosses", build = "BuildBossTabPage", arg = true },
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
local currentPage = "Settings"
local pendingRefresh
local onShowCallbacks, onHideCallbacks = {}, {}
local moduleWindows = {}     -- module name -> its standalone window
local microButtons = {}      -- module name -> its micro menu button
local ApplyMicroMenu

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
-- store `enabled` (or their `enabledKey`) in their settings table.
local function ModuleOn(mod)
    if mod.settings then return ns[mod.settings].Get(mod.enabledKey or "enabled") end
    return ns.DB().enabled == true
end

local function SetModuleOn(mod, on)
    if mod.settings then ns[mod.settings].Set(mod.enabledKey or "enabled", on) else ns.SetEnabled(on) end
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

-- Each window keeps its own wrappers, so a page open in the main window and in a module's
-- own window at once is two separate builds.
local function ShowWrapper(pageWrappers, child, key)
    for name, w in pairs(pageWrappers) do
        w:SetShown(name == key)
    end
    if not pageWrappers[key] then
        local wrapper = CreateFrame("Frame", nil, child)
        wrapper:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        wrapper:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)
        wrapper:SetHeight(1)
        pageWrappers[key] = wrapper
        wrapper._dirty = true
    end
    local wrapper = pageWrappers[key]
    if wrapper._dirty then
        wrapper._dirty = nil
        if key == SETUP_PAGE then UI.BeginReusableRows(wrapper) end
        local usedY = BuildPageInto(PAGES[key], wrapper)
        wrapper:SetHeight(math.abs(usedY) + 30)
    end
    child:SetHeight(wrapper:GetHeight())
end

local function ShowPage(key)
    currentPage = key
    LayoutContent()
    ShowWrapper(wrappers, scrollChild, key)
    scrollFrame:SetVerticalScroll(0)
    PaintNav()
end

local function ShowModulePage(win, key)
    win.page = key
    ShowWrapper(win.wrappers, win.scrollChild, key)
    win.scrollFrame:SetVerticalScroll(0)
    win.switch._refreshValue()
    for k, btn in pairs(win.tabButtons) do PaintTab(btn, PAGES[k], k == key) end
end

local function InvalidatePages(pageWrappers)
    for name, w in pairs(pageWrappers) do
        if name == SETUP_PAGE then
            w._dirty = true
        else
            w:Hide()
            w:SetParent(nil)
            pageWrappers[name] = nil
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
-- never run off-screen. The module windows follow the same rules.
-- One rebuild per frame however many times it is asked for: one action (a pack import,
-- a chain of setters) can ask repeatedly.
local refreshQueued

local function RebuildPages()
    refreshQueued = false
    -- A tooltip anchored to a row we are about to destroy would hang on screen with its
    -- anchor orphaned; changing a setting while hovering its label is the ordinary way in.
    if UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
    if window and window:IsShown() then
        local scroll = scrollFrame:GetVerticalScroll()
        InvalidatePages(wrappers)
        ShowPage(currentPage)
        scrollFrame:UpdateScrollChildRect()
        scrollFrame:SetVerticalScroll(scroll)
    else
        pendingRefresh = true
    end
    for _, win in pairs(moduleWindows) do
        if win:IsShown() then
            local scroll = win.scrollFrame:GetVerticalScroll()
            InvalidatePages(win.wrappers)
            ShowModulePage(win, win.page)
            win.scrollFrame:UpdateScrollChildRect()
            win.scrollFrame:SetVerticalScroll(scroll)
        else
            win.pendingRefresh = true
        end
    end
end

local function AnyWindowShown()
    if window and window:IsShown() then return true end
    for _, win in pairs(moduleWindows) do
        if win:IsShown() then return true end
    end
    return false
end

function UI:RefreshPage(force)
    if not AnyWindowShown() then
        pendingRefresh = true
        for _, win in pairs(moduleWindows) do win.pendingRefresh = true end
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
    for _, win in pairs(moduleWindows) do win:SetScale(ns.UIScale()) end
end

-- Saved for this computer, like the window scale. A button never set follows its module's
-- `micro` default.
local function MicroDB()
    local account = ns.AccountSettings()
    account.microMenu = account.microMenu or { buttons = {} }
    return account.microMenu
end

local function MicroButtonOn(mod)
    local on = MicroDB().buttons[mod.name]
    if on == nil then return mod.micro == true end
    return on
end

function ns.BuildSettingsPage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "OPTIONS WINDOW", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Window Scale",
          values = { [200] = "200%", [190] = "190%", [180] = "180%", [170] = "170%",
                     [160] = "160%", [150] = "150%", [140] = "140%", [130] = "130%",
                     [120] = "120%", [110] = "110%", [100] = "100%  (default)", [90] = "90%",
                     [80] = "80%", [70] = "70%", [60] = "60%", [50] = "50%" },
          order = { 200, 190, 180, 170, 160, 150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50 },
          tooltip = "Size of this options window and the editors it opens, as a percentage. "
          .. "Turn it down if the window is too big for your screen; 1080p usually wants 80 "
          .. "or below. Turn it up on a large or high-resolution monitor.|n|nSaved for this computer instead of in the profile, so switching "
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
              if v then icon:Show("NaowhForever") else icon:Hide("NaowhForever") end
          end }
    ); y = y - h

    _, h = W:SectionHeader(parent, "MICRO MENU", y); y = y - h
    local rows = {
        { type = "toggle", text = "Micro Menu",
          tooltip = "A bar at the top of the screen with a button per module that opens on its "
          .. "own. Move it in Unlock Mode. Saved for this computer.",
          getValue = function() return not MicroDB().hide end,
          setValue = function(v)
              MicroDB().hide = not v
              ApplyMicroMenu()
              UI:RefreshPage(true)
          end },
    }
    for _, mod in ipairs(MODULES) do
        if mod.command then
            rows[#rows + 1] = { type = "toggle", text = mod.name,
                tooltip = ("A button that opens %s on its own. /nf%s does the same.")
                    :format(mod.name, mod.command),
                disabled = function() return MicroDB().hide end,
                getValue = function() return MicroButtonOn(mod) end,
                setValue = function(v)
                    MicroDB().buttons[mod.name] = v
                    ApplyMicroMenu()
                end }
        end
    end
    for i = 1, #rows, 2 do
        _, h = W:DualRow(parent, y, rows[i], rows[i + 1] or { type = "label", text = "" }); y = y - h
    end

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

local function DragRegion(frame, target)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() target:StartMoving() end)
    frame:SetScript("OnDragStop", function() target:StopMovingOrSizing() end)
end

-- ESC via our own keyboard handler, NOT UISpecialFrames: a named addon frame in that
-- table is a convicted taint injector (Blizzard's CloseAllWindows enumerates it inside
-- secure execution). Same combat-guarded pattern MakeModal uses; opened in combat the
-- window keeps its close button and ESC binds from its next out-of-combat open (OnShow).
local function CloseOnEscape(self, key)
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
end

-- Tab strip, in the same visual language as the modal editors' own tabs: a button
-- with an accent underline marking the active page. Widths are measured off the label
-- rather than fixed, since tab names vary a lot in length and a fixed width leaves the
-- short ones swimming.
local function TabStrip(parent, left, mod, onClick, buttons)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -HEADER_H)
    strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -HEADER_H)
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
        btn:SetScript("OnClick", function() onClick(tab.key) end)
        btn:SetPoint("TOPLEFT", strip, "TOPLEFT", tx, 0)
        buttons[tab.key] = btn
        tx = tx + btn:GetWidth() + 2
    end
    return strip
end

local function CreateWindow()
    window = CreateFrame("Frame", "NaowhForeverOptions", UIParent)
    window:SetSize(SIDEBAR_W + CONTENT_W, WINDOW_H)
    window:SetScale(ns.UIScale())
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    ns.Solid(window, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(window)
    window:SetScript("OnKeyDown", CloseOnEscape)

    -- Sidebar: logo and name, then the modules.
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
    DragRegion(brand, window)
    local logo = brand:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO, nil, nil, "TRILINEAR")
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

    local group = ns.Font(sidebar, 13, nil, T.accent)
    group:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 18, ny)
    group:SetText(ns.L("Modules"))
    ny = ny - 24
    -- Indented under the group label, each with a small switch that turns the whole
    -- module off without leaving the page you are on.
    for _, mod in ipairs(MODULES) do
        if mod.divider then
            ny = ny - 8
            local line = ns.Solid(sidebar, "ARTWORK", T.line, 1)
            line:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 18, ny)
            line:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -18, ny)
            line:SetHeight(1)
            ny = ny - 9
        end
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
    DragRegion(header, window)
    headerTitle = ns.Font(header, 24, "OUTLINE")
    headerTitle:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -18)
    headerSub = ns.Font(header, 12, nil, T.muted)
    headerSub:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 1, -6)

    local close = ns.Button(header, "X", 26, 26, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -12)

    -- The window's own pages sit left of the close button, laid out right to left.
    local anchor = close
    local function HeaderButton(label, onClick)
        local btn = CreateFrame("Button", nil, header)
        btn.label = ns.Font(btn, 13, nil, T.muted)
        btn.label:SetPoint("CENTER")
        btn.label:SetText(ns.L(label))
        btn:SetSize(math.ceil(btn.label:GetStringWidth()) + 24, 26)
        btn:SetPoint("RIGHT", anchor, "LEFT", anchor == close and -10 or -2, 0)
        btn.fill = ns.Solid(btn, "BACKGROUND", T.grey, 0.5)
        btn.fill:SetAllPoints()
        btn.fill:Hide()
        btn.marker = ns.Solid(btn, "ARTWORK", T.accent, 1)
        btn.marker:SetPoint("BOTTOMLEFT")
        btn.marker:SetPoint("BOTTOMRIGHT")
        btn.marker:SetHeight(2)
        btn.marker:Hide()
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self) self.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b, 1) end)
        btn:SetScript("OnLeave", function(self)
            local c = self.fill:IsShown() and T.fg or T.muted
            self.label:SetTextColor(c.r, c.g, c.b, 1)
        end)
        anchor = btn
        return btn
    end

    for i = #SYSTEM_PAGES, 1, -1 do
        local page = SYSTEM_PAGES[i]
        navButtons[page.key] = HeaderButton(page.name, function() ShowPage(page.key) end)
    end
    local unlock = HeaderButton("Unlock Mode", EnterUnlockMode)
    ns.Tooltip(unlock, "Unlock Mode",
        "Place and size each reminder display. An alignment grid appears while you are in "
        .. "there. This window steps aside and comes back when you press Exit Config.")

    for _, mod in ipairs(MODULES) do
        local strip = TabStrip(window, SIDEBAR_W, mod, ShowPage, tabButtons)
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
            InvalidatePages(wrappers)
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

-- A module on its own: its header and tabs over the same page builders, without the sidebar
-- or the window's own pages. The content is as wide as the main window's, so every page lays
-- out the same in both.
local MODULE_WINDOW_H = 560

local function PaintMicroButton(mod)
    local btn = microButtons[mod.name]
    if not btn then return end
    local win = moduleWindows[mod.name]
    local c = win and win:IsShown() and T.accentSoft or T.fg
    btn.label:SetTextColor(c.r, c.g, c.b, 1)
end

local function CreateModuleWindow(mod)
    local win = CreateFrame("Frame", nil, UIParent)
    win:Hide()
    win:SetSize(CONTENT_W, MODULE_WINDOW_H)
    win:SetScale(ns.UIScale())
    win:SetPoint("CENTER")
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    ns.Solid(win, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(win)
    win:SetScript("OnKeyDown", CloseOnEscape)

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    DragRegion(header, win)
    local title = ns.Font(header, 24, "OUTLINE")
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -18)
    title:SetText(ns.L(mod.name))
    local sub = ns.Font(header, 12, nil, T.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
    sub:SetText(mod.subtitle)
    local close = ns.Button(header, "X", 26, 26, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -12)
    -- The sidebar's module switch, since some pages have no switch of their own.
    local switch = UI.BuildToggleControl(header, header:GetFrameLevel() + 2,
        function() return ModuleOn(mod) end,
        function(v) SetModuleOn(mod, v) end, 28, 14)
    switch:SetPoint("RIGHT", close, "LEFT", -14, 0)
    ns.Tooltip(switch, mod.name, function()
        return ModuleOn(mod) and "On. Click to turn the whole module off."
            or "Off. Click to turn it back on."
    end)
    win.switch = switch

    win.tabButtons = {}
    TabStrip(win, 0, mod, function(key) ShowModulePage(win, key) end, win.tabButtons)
    local offset = HEADER_H + TAB_H
    local line = ns.Solid(win, "ARTWORK", T.line, 1)
    line:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -offset)
    line:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -offset)
    line:SetHeight(1)

    win.scrollFrame = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    win.scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -(offset + 5))
    win.scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 10)
    win.scrollChild = CreateFrame("Frame", nil, win.scrollFrame)
    win.scrollChild:SetSize(CONTENT_W - 40, 1)
    win.scrollFrame:SetScrollChild(win.scrollChild)
    win.wrappers = {}
    win.page = mod.tabs[1].key

    win:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(true)
        end
        if self.pendingRefresh then
            self.pendingRefresh = nil
            InvalidatePages(self.wrappers)
        end
        ShowModulePage(self, self.page)
        PaintMicroButton(mod)
    end)
    win:SetScript("OnHide", function()
        if UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
        PaintMicroButton(mod)
    end)
    return win
end

local function ToggleModuleWindow(mod)
    local win = moduleWindows[mod.name]
    if not win then
        win = CreateModuleWindow(mod)
        moduleWindows[mod.name] = win
    end
    win:SetShown(not win:IsShown())
end

-- Addon compartment entry (the puzzle-piece menu by the minimap); wired in the .toc.
function _G.NaowhForever_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

SLASH_NAOWHFOREVER1 = "/smartreminders"
SLASH_NAOWHFOREVER2 = "/naowh"
SLASH_NAOWHFOREVER3 = "/nao"
SLASH_NAOWHFOREVER4 = "/nsr"
SLASH_NAOWHFOREVER5 = "/nf"
SlashCmdList["NAOWHFOREVER"] = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "quiz" and ns.ToggleQuiz then
        ns.ToggleQuiz()
    elseif cmd == "xp" and ns.XPTickerCommand then
        ns.XPTickerCommand(arg)
    elseif cmd == "ranks" and ns.TrainerRankCheck then
        ns.TrainerRankCheck()
    elseif cmd == "townaudit" and ns.TownAudit then
        ns.TownAudit()
    else
        ns.ToggleOptionsWindow()
    end
end

for _, mod in ipairs(MODULES) do
    if mod.command then
        local key = "NAOWHFOREVER" .. mod.command:upper()
        _G["SLASH_" .. key .. "1"] = "/nf" .. mod.command
        SlashCmdList[key] = function() ToggleModuleWindow(mod) end
    end
end

-- The micro menu: a button per module with a command, placed in Unlock Mode.
local microBar, microUnlocked

local function BuildMicroBar()
    microBar = CreateFrame("Frame", "NaowhForeverMicroMenu", UIParent)
    microBar:SetHeight(22)
    microBar:SetMovable(true)
    microBar:SetClampedToScreen(true)
    for _, mod in ipairs(MODULES) do
        if mod.command then
            local btn = ns.Button(microBar, mod.short, 1, 22, function() ToggleModuleWindow(mod) end)
            btn:SetWidth(math.ceil(btn.label:GetStringWidth()) + 16)
            ns.Tooltip(btn, mod.name, "Opens or closes it on its own, as /nf" .. mod.command .. " does.")
            microButtons[mod.name] = btn
            PaintMicroButton(mod)
        end
    end
    microBar.mover = UI.AttachMover(microBar, "Menu", function(pos) MicroDB().pos = pos end)
    local pos = MicroDB().pos
    if pos then
        microBar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        microBar:SetPoint("TOP", UIParent, "TOP", 0, -4)
    end
end

function ApplyMicroMenu()
    local db = MicroDB()
    if not microBar then
        if db.hide then return end
        BuildMicroBar()
    end
    local x = 0
    for _, mod in ipairs(MODULES) do
        local btn = microButtons[mod.name]
        if btn then
            local on = MicroButtonOn(mod)
            btn:SetShown(on)
            if on then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", microBar, "LEFT", x, 0)
                x = x + btn:GetWidth() + 2
            end
        end
    end
    microBar:SetWidth(math.max(x - 2, 1))
    microBar:SetShown(not db.hide and x > 0)
    microBar.mover:SetShown(microUnlocked == true)
end

-- The launcher position belongs to the account, not an imported settings profile.
local launcherEvents = CreateFrame("Frame")
launcherEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local account = ns.AccountSettings()
    if type(account.minimap) ~= "table" then
        account.minimap = { minimapPos = 220 }
    end
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject("NaowhForever", {
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
    LibStub("LibDBIcon-1.0"):Register("NaowhForever", launcher, account.minimap)

    -- Hooked at login: RaidReminders, which defines these, loads after this file.
    hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
        microUnlocked = true
        if microBar then ApplyMicroMenu() end
    end)
    hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
        microUnlocked = false
        if microBar then ApplyMicroMenu() end
    end)
    ApplyMicroMenu()
end)
launcherEvents:RegisterEvent("PLAYER_LOGIN")
