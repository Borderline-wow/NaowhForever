-------------------------------------------------------------------------------
--  NaowhForever_Window.lua -- the standalone options window and the lifecycle half of ns.UI.
--  The page builders live in later files and are resolved at open time.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local SIDEBAR_W, CONTENT_W, WINDOW_W, WINDOW_H = 240, 1000, 1440, 790
local TOP_H, PAGE_HEADER_H = 64, 128
local HEADER_H, TAB_H, FOOTER_H, NAV_H = 76, 32, 46, 32
local SEARCH_W = 120
local SCROLL_BAR_GAP = 12 -- the page scrollbar sits this far right of the page, in its margin
local LINK_ICONS = "Interface\\AddOns\\NaowhForever\\Media\\Links\\"
local LINKS = {
    { "Discord", "discord", function() return ns.NAOWH_DISCORD or "https://discord.com/invite/naowh" end },
    { "Website", "website", function() return "https://naowh.gg" end },
    { "GitHub", "github", function() return "https://github.com/nwh-gaming-ab/NaowhForever" end },
}
local SYSTEM_NAV = { { "Settings", "settings" }, { "Profiles", "person" }, { "Patch Notes", "notes" }, { "Credits", "heart" } }
local NAV_STEP, LINK_SIZE, LINK_GAP = 30, 16, 10
local NAV_DOT, NAV_OPEN, NAV_OPEN_ICON = 6, 22, 14
local MEDIA = "Interface\\AddOns\\NaowhForever\\Media\\"
local FOOTER_H_SIDEBAR = 28
local LOGO = "Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga"
local BRAND_LOGO = "Interface\\AddOns\\NaowhForever\\Media\\BrandLogo.tga"
-- The art fills the top left 448x139 of its 512x256 canvas (the size mipmaps need) and is drawn
-- cropped to it, 56 tall, 8 in from the panel's top left.
local BRAND = { artW = 448, artH = 139, texW = 512, texH = 256, height = 56, inset = 8 }

-- System pages sit below the module navigation. `build` names the ns builder (resolved at
-- open time); `arg` is passed after the starting y.
--   soon      tab stays, dimmed, and opens a note instead of the page
--   reuse     rows kept across rebuilds; only pages drawn entirely with row widgets and UI.Keep
--   collapse  features (W:Feature) start closed; row-widget pages only
--   command   module also opens in its own window from /nf<command> and broker NaowhForever<short>
--             with `open`, ns[open] toggles the module's own window instead
--   addon     module shipped as its own addon, left out of the window while it is not loaded
--   needs     module addons it cannot work without; turning one off turns this one off too
local SYSTEM_PAGES = {
    { name = "Settings", build = "BuildSettingsPage", reuse = true,
      subtitle = "Options for the whole addon, saved for this computer." },
    { name = "Patch Notes", reuse = true, subtitle = "What changed in recent builds." },
    { name = "Credits", build = "BuildCreditsPage", reuse = true, subtitle = "The people and projects behind Naowh Forever." },
    { name = "Profiles", build = "BuildProfileSettings", reuse = true,
      subtitle = "Switch, copy and share everything these pages save." },
}

-- Custom Reminders has no runtime yet; its switch only needs somewhere to live.
ns.CustomReminderSettings = UI.ModuleSettings("customReminders", { enabled = false })

local MODULES = {
    { name = "QoL", navIcon = "checklist", settings = "QoLSettings",
      subtitle = "Naowh's quality of life tweaks, trimmed to what Forever has.",
      tabs = {
          { name = "Interface", reuse = true },
          { name = "Character", reuse = true },
          { name = "Cursor", reuse = true },
          { name = "Combat", reuse = true },
          { name = "Questing & Group", reuse = true },
          { name = "XP", reuse = true },
          { name = "Loot & Items", reuse = true },
          { name = "Travel", reuse = true },
          { name = "System", reuse = true },
      } },
    -- The journal itself is a window of its own (open); only its settings live here.
    { name = "Dungeon Journal", group = "ADVENTURE", navIcon = "map", settings = "JournalSettings",
      addon = "NaowhForever_DungeonJournal", needs = { "NaowhForever_BiS" },
      open = "ToggleJournalWindow",
      command = "journal", alias = "dj", short = "Journal", icon = "Interface\\Icons\\INV_Misc_Book_09",
      subtitle = "Every dungeon and raid: what drops, your quests, and more.",
      tabs = {
          { name = "Journal", reuse = true },
          { name = "Quest Tracker", reuse = true },
          { name = "Map", reuse = true },
      } },
    -- The list itself is a window of its own (open); only its settings live here.
    { name = "BiS List", group = "ADVENTURE", navIcon = "trophy", settings = "QoLSettings", enabledKey = "bis",
      addon = "NaowhForever_BiS", needs = { "NaowhForever_DungeonJournal" },
      open = "ToggleBisWindow",
      command = "bis", short = "BiS", icon = "Interface\\Icons\\INV_Sword_39",
      subtitle = "Your best-in-slot list, marked on tooltips and called out when it drops.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    -- The planner itself is a window of its own (open); only its settings live here.
    { name = "Training Planner", group = "ADVENTURE", navIcon = "notes", settings = "TrainingSettings",
      addon = "NaowhForever_Training", needs = { "NaowhForever_Professions" },
      open = "ToggleTrainingWindow",
      command = "training", short = "Training", icon = "Interface\\Icons\\INV_Misc_Book_11",
      subtitle = "What you can train now, what each level brings and what it costs.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    -- The books are a window of their own (open); only their settings live here.
    { name = "Discovery", group = "ADVENTURE", navIcon = "compass", settings = "DiscoverySettings",
      addon = "NaowhForever_Discovery",
      open = "ToggleDiscoveryWindow",
      command = "discovery", short = "Discovery", icon = "Interface\\Icons\\INV_Misc_Book_07",
      subtitle = "Library books to find around Azeroth, and who to hand them to.",
      tabs = {
          { name = "Library Books", reuse = true },
          { name = "Sleeping Bag", reuse = true },
      } },
    -- The sets are a window of their own (open); only their settings live here.
    { name = "Gear & Trinkets", group = "COMBAT", navIcon = "shield", settings = "QoLSettings", enabledKey = "gearSets",
      addon = "NaowhForever_GearSets",
      open = "ToggleGearSetsWindow",
      command = "gear", short = "Gear", icon = "Interface\\Icons\\INV_Chest_Plate04",
      subtitle = "Swap equipment sets from a bar, or on their own while you ride or rest.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Blessings", group = "COMBAT", navIcon = "spark", settings = "QoLSettings", enabledKey = "blessings",
      addon = "NaowhForever_Blessings",
      open = "ToggleBlessingsWindow",
      command = "bless", short = "Bless", icon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
      subtitle = "Paladin blessings by class and player, shared with the group's paladins.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Professions", group = "ADVENTURE", navIcon = "hammer", settings = "ProfessionSettings",
      addon = "NaowhForever_Professions",
      subtitle = "Recipes, reagents and crafting in one window, with the recipes you have not learned yet.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Macros", group = "UTILITIES", navIcon = "pen", settings = "MacroSettings",
      addon = "NaowhForever_Macros",
      open = "ToggleMacroWindow",
      command = "macros", short = "Macros", icon = "Interface\\Icons\\INV_Misc_Note_01",
      subtitle = "Naowh's Forge: your macros, checked and explained, and macros kept current for you.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Action Bars", group = "UTILITIES", navIcon = "grid", settings = "ActionBarSettings",
      addon = "NaowhForever_ActionBars",
      open = "ToggleActionBarsWindow",
      command = "bars", short = "Bars", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      subtitle = "Your action bars saved by name and put back whenever you want them.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "AuraBuffs", group = "COMBAT", navIcon = "aura", settings = "AuraBuffSettings",
      addon = "NaowhForever_AuraBuffs",
      open = "ToggleAuraBuffsWindow",
      command = "buffs", short = "Buffs", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
      subtitle = "Buff, consumable and campfire reminders, low health and debuff sounds.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Threat Meter", group = "COMBAT", navIcon = "bars", settings = "ThreatMeterSettings",
      addon = "NaowhForever_ThreatMeter",
      command = "threat", short = "Threat", icon = "Interface\\Icons\\Ability_Warrior_Sunder",
      subtitle = "Threat on your target for the whole group, and a warning before you pull.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Swing Timer", group = "COMBAT", navIcon = "infinity", settings = "SwingTimerSettings",
      addon = "NaowhForever_SwingTimer",
      subtitle = "Your swings from the game's own swing timer, with marks for timing around them.",
      tabs = {
          { name = "Settings", reuse = true },
      } },
    { name = "Custom Reminders", settings = "CustomReminderSettings",
      subtitle = "Your own reminders, driven by the same triggers Smart Reminders uses.",
      tabs = {
          { name = "Custom Notes", soon = "Your own note lines, driven by the same triggers "
              .. "the reminders use. Not finished yet.\n\nNothing is missing in the meantime: "
              .. "reminders still carry their own text, set per reminder from the boss "
              .. "pages." },
      } },
    { name = "Smart Reminders", group = "COMBAT", navIcon = "bell",
      open = "ToggleSmartRemindersWindow",
      command = "reminders", short = "Reminders", icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
      subtitle = "Calls out what to press when a boss ability is about to land.",
      tabs = {
          { name = "Settings", reuse = true },
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

local window, scrollFrame, scrollChild, tabLine, headerTitle, headerSub
local contentHeader, contentFooter, searchBar, breadcrumb, moduleSwitch, moduleLabel
local lastPages = {}
local navButtons, tabStrips, navBlocks = {}, {}, {}
local wrappers = {}          -- page key -> built wrapper frame
-- The first page of a session; after that the window reopens where it was left.
local currentPage = "QoL/Interface"
local pendingRefresh
local onShowCallbacks, onHideCallbacks = {}, {}
local moduleWindows = {}     -- module name -> its standalone window

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
    local Settings = ns.Shared and ns.Shared.Settings
    if Settings and Settings.pages[page.key] then
        return -Settings.Render(parent, page.key, function(height)
            parent:SetHeight(height + 30)
            local child = parent:GetParent()
            if child and parent:IsShown() then child:SetHeight(parent:GetHeight()) end
        end)
    end
    local fn = ns[page.build]
    if not fn then return -6 end
    return fn(parent, -6, page.arg)
end

local function DisplayName(mod)
    return ns.L(mod.name == "QoL" and "Quality of Life" or mod.name)
end

local function Loaded(mod)
    return not mod.addon or C_AddOns.IsAddOnLoaded(mod.addon)
end

local function Has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- The module addons that switch along with mod: turning it off takes every module that
-- needs it, turning it on brings every module it needs.
local function Linked(mod, on)
    local mods, seen = { mod }, { [mod.addon] = true }
    local i = 1
    while mods[i] do
        local cur = mods[i]
        for _, other in ipairs(MODULES) do
            if other.addon and not seen[other.addon]
                and (on and Has(cur.needs, other.addon) or not on and Has(other.needs, cur.addon)) then
                seen[other.addon] = true
                mods[#mods + 1] = other
            end
        end
        i = i + 1
    end
    return mods
end

local function NameList(mods)
    local names = {}
    for i, m in ipairs(mods) do names[i] = DisplayName(m) end
    if #names == 1 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Enables or disables a module addon, with the ones linked to it, for every character. The
-- game applies it at the next reload, so the reload prompt follows.
local function SwitchModuleAddon(mod, on)
    local mods = Linked(mod, on)
    local verb = on and "enable" or "disable"
    local text = ("%s %s?"):format(on and "Enable" or "Disable", DisplayName(mod))
    if #mods > 1 then
        local others = { unpack(mods, 2) }
        text = text .. (on and " It needs %s, so %s will be %sd." or " %s needs it, so %s will be %sd.")
            :format(NameList(others), #mods == 2 and "both" or "all of them", verb)
    end
    local yes = (on and "Enable" or "Disable") .. (#mods == 2 and " Both" or #mods > 2 and " All" or "")
    ns.Confirm(text, function()
        for _, m in ipairs(mods) do
            if on then C_AddOns.EnableAddOn(m.addon) else C_AddOns.DisableAddOn(m.addon) end
        end
        UI:RefreshPage(true)
        ns.ConfirmReload(("%s will be %sd when you reload. Reload now?"):format(NameList(mods), verb))
    end, function() UI:RefreshPage(true) end, yes, "Cancel")
end

-- A module's on/off switch. Smart Reminders keeps its own master switch; the newer modules
-- store `enabled` (or their `enabledKey`) in their settings table. Switching off a module
-- shipped as its own addon disables the addon, so it is gone after a reload; until then it
-- reads as off, and switching it back on cancels that.
local function ModuleOn(mod)
    if mod.addon and C_AddOns.GetAddOnEnableState(mod.addon) == 0 then return false end
    if mod.settings then return ns[mod.settings].Get(mod.enabledKey or "enabled") end
    return ns.DB().enabled == true
end

local function SetModuleOn(mod, on)
    if mod.addon and not on then return SwitchModuleAddon(mod, false) end
    if mod.addon then
        for _, m in ipairs(Linked(mod, true)) do C_AddOns.EnableAddOn(m.addon) end
    end
    if mod.settings then ns[mod.settings].Set(mod.enabledKey or "enabled", on) else ns.SetEnabled(on) end
    UI:RefreshPage(true)
end

-- The sidebar entry a page lights: its module, or the page itself.
local function ActiveNav()
    local page = PAGES[currentPage]
    return page.module and page.module.name or page.key
end

-- A page that cannot be used stays dimmer than an inactive one, even while selected.
local function PaintTabs(bar, shown)
    ns.Shared.Parts.PaintTabs(bar, shown)
    for _, button in ipairs(bar.buttons) do
        if PAGES[button.key] and PAGES[button.key].soon then button.text:SetAlpha(0.45) end
    end
end

local NAV_ROW, NAV_OFF_ALPHA = 32, 0.45

-- Within each group the modules that are on come first, then the ones you have off.
local function LayoutNav()
    for _, block in ipairs(navBlocks) do
        local y = block.top
        for pass = 1, 2 do
            for _, mod in ipairs(block.mods) do
                if (not ModuleOn(mod)) == (pass == 2) then
                    local btn = navButtons[mod.name]
                    btn:SetPoint("TOPLEFT", 8, y)
                    btn:SetPoint("TOPRIGHT", -8, y)
                    y = y - NAV_ROW
                end
            end
        end
    end
end

local function PaintNavButton(btn, hover)
    local active = btn.fill:IsShown()
    local off = btn.mod ~= nil and not ModuleOn(btn.mod)
    local c = (active or hover) and T.fg or T.muted
    local a = (off and not active and not hover) and NAV_OFF_ALPHA or 1
    btn.label:SetTextColor(c.r, c.g, c.b, a)
    if btn.icon then btn.icon:SetVertexColor(c.r, c.g, c.b, a) end
    if btn.open then btn.open:SetShown(active or hover) end
    if btn.dot then btn.dot:SetShown(off and not (btn.open and btn.open:IsShown())) end
end

local function PaintNav()
    local nav = ActiveNav()
    LayoutNav()
    for name, btn in pairs(navButtons) do
        local active = name == nav
        btn.fill:SetShown(active)
        btn.marker:SetShown(active)
        PaintNavButton(btn, btn:IsMouseOver())
    end
    for _, bar in pairs(tabStrips) do PaintTabs(bar, currentPage) end
end

local function LayoutContent()
    local page = PAGES[currentPage]
    local mod = page.module
    local nested = mod and #mod.tabs > 1
    local left = SIDEBAR_W
    -- The tab row sits under the subtitle and pushes the page down by its own height.
    local headerH = PAGE_HEADER_H + (nested and TAB_H - 12 or 0)
    -- The search bar sits under the window's header and pushes the page down while it is up.
    local top = TOP_H + (searchBar:IsShown() and searchBar:GetHeight() or 0)
    searchBar:ClearAllPoints()
    searchBar:SetPoint("TOPLEFT", window, "TOPLEFT", left, -TOP_H)
    searchBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -TOP_H)
    headerTitle:SetText(mod and DisplayName(mod) or ns.L(page.title))
    breadcrumb:SetText(mod and (DisplayName(mod) .. " / " .. ns.L(page.name)) or "Naowh Forever")
    headerSub:SetText(mod and mod.subtitle or page.subtitle)
    contentHeader:ClearAllPoints()
    contentHeader:SetPoint("TOPLEFT", window, "TOPLEFT", left, -top)
    contentHeader:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -top)
    contentHeader:SetHeight(headerH)
    moduleSwitch:SetShown(mod ~= nil and not page.soon)
    moduleLabel:SetShown(mod ~= nil and not page.soon)
    if mod and not page.soon then
        moduleLabel:SetText(ns.L("Enable") .. " " .. ns.L(mod.name))
        moduleSwitch._refreshValue()
    end
    for name, strip in pairs(tabStrips) do strip:SetShown(nested and name == mod.name or false) end
    tabLine:ClearAllPoints()
    tabLine:SetPoint("TOPLEFT", window, "TOPLEFT", left + 26, -(top + headerH))
    tabLine:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -(top + headerH))
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", window, "TOPLEFT", left + 6, -(top + headerH + 8))
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, FOOTER_H + 4)
    scrollChild:SetWidth(window:GetWidth() - left - 36)
    contentFooter:ClearAllPoints()
    contentFooter:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", left, 0)
    contentFooter:SetPoint("BOTTOMRIGHT")
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
    if wrapper._builtWidth ~= child:GetWidth() then wrapper._dirty = true end
    if wrapper._dirty then
        wrapper._builtWidth = child:GetWidth()
        wrapper._dirty = nil
        wrapper._pageKey, wrapper._collapsible, wrapper._nsuiCollapsed = key, PAGES[key].collapse, nil
        wrapper._nsuiFeatureId = nil
        if PAGES[key].reuse then UI.BeginReusableRows(wrapper) end
        local usedY = BuildPageInto(PAGES[key], wrapper)
        wrapper:SetHeight(math.abs(usedY) + 30)
    end
    child:SetHeight(wrapper:GetHeight())
end

local function ShowPage(key)
    -- A link to a module that is switched off lands where it can be turned back on.
    if PAGES[key].module and not Loaded(PAGES[key].module) then key = "Settings" end
    currentPage = key
    if PAGES[key].module then lastPages[PAGES[key].module.name] = key end
    LayoutContent()
    ShowWrapper(wrappers, scrollChild, key)
    scrollFrame:SetVerticalScroll(0)
    PaintNav()
end

-- The pages the search bar looks through, the window's own and every module's tabs.
function UI.SearchPages()
    local pages = {}
    for _, page in ipairs(SYSTEM_PAGES) do pages[#pages + 1] = page end
    for _, mod in ipairs(MODULES) do
        for _, tab in ipairs(mod.tabs) do
            if not tab.soon and Loaded(mod) then pages[#pages + 1] = tab end
        end
    end
    return pages
end

-- Opens the page (building it if this is the first visit) and, given a card, opens the card
-- and brings its head, or its setting named `label`, a third of the way down the page. A
-- card the search bar holds open (UI.searchOpen) is left to it.
local SETTING_AT = 1 / 3

function UI.GoToSetting(key, label, card)
    if not (window and PAGES[key]) then return end
    local Settings = ns.Shared.Settings
    if card and not (UI.searchOpen and UI.searchOpen[card]) then Settings.Reveal(card) end
    -- Drawn again, so the place measured below is the layout that stays.
    if wrappers[key] then wrappers[key]._dirty = true end
    ShowPage(key)
    if not (card and Settings.pages[key]) then return end
    local _, top = Settings.FindRow(wrappers[key], label, card)
    if not top then return end
    scrollFrame:UpdateScrollChildRect()
    local y = top - scrollFrame:GetHeight() * SETTING_AT
    scrollFrame:SetVerticalScroll(math.min(scrollFrame:GetVerticalScrollRange(), math.max(0, y)))
end

local function ShowModulePage(win, key)
    win.page = key
    ShowWrapper(win.wrappers, win.scrollChild, key)
    win.scrollFrame:SetVerticalScroll(0)
    win.switch._refreshValue()
    PaintTabs(win.tabs, key)
end

local function InvalidatePages(pageWrappers)
    for name, w in pairs(pageWrappers) do
        if PAGES[name].reuse then
            w._dirty = true
        else
            w:Hide()
            w:SetParent(nil)
            pageWrappers[name] = nil
        end
    end
end

-- Invalidates every cached tab, not only the active one: a pack import can add Cooldown
-- Presets while Raid Bosses is on show. While hidden, the rebuild waits for the next open so
-- page-build side effects (preview, lazy journal reads) never run off-screen. One rebuild per
-- frame however often it is asked for.
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

-- Cached pages only rebuild on RefreshPage, so a trinket swap under a shown Cooldown Presets
-- page went unnoticed. The event fires per changed slot; a set swap arrives as a burst.
local equipWatcher = CreateFrame("Frame")
equipWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
equipWatcher:SetScript("OnEvent", function(_, _, slot)
    if slot == INVSLOT_TRINKET1 or slot == INVSLOT_TRINKET2 then UI:RefreshPage(true) end
end)

-- Set from a dropdown, not a slider: the control sits inside the frame it resizes, so
-- rescaling mid-drag moved the track out from under the cursor.
local function FitMainWindow()
    if not window then return end
    local fit = math.min((UIParent:GetWidth() - 32) / window:GetWidth(),
        (UIParent:GetHeight() - 32) / window:GetHeight())
    window:SetScale(math.min(ns.UIScale(), math.max(0.25, fit)))
    ns.RefitPixels()
end

function ns.SetWindowScale(pct)
    ns.AccountSettings().windowScale = tonumber(pct) or 100
    FitMainWindow()
    for _, win in pairs(moduleWindows) do win:SetScale(ns.UIScale()) end
    ns.RefitPixels()
end

-- Saved for this computer, like the window scale, under the key of the micro menu these
-- switches came from. Off until switched on: the top bar carries the modules.
local function MinimapButtonOn(mod)
    local account = ns.AccountSettings()
    return account.microMenu and account.microMenu.buttons[mod.name] == true
end

-- Set by any change in COLORS or RESTEDXP; only a reload clears it.
local colorsPending = false
local rxpPending = false

function ns.BuildMinimapIcons(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "MINIMAP ICONS", y); y = y - h
    _, h = W:DualRow(parent, y,
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
          end },
        { type = "toggle", text = "Game Menu Button",
          tooltip = "Naowh Forever in the game menu (Esc), by the other addons' buttons. "
          .. "Saved for this computer.",
          getValue = function() return ns.AccountSettings().gameMenuButton ~= false end,
          setValue = function(v) ns.AccountSettings().gameMenuButton = v and true or false end }
    ); y = y - h
    local rows = {}
    for _, mod in ipairs(MODULES) do
        if mod.command and Loaded(mod) then
            rows[#rows + 1] = { type = "toggle", text = mod.name,
                tooltip = ("A minimap button that opens %s on its own. /nf%s does the same, "
                    .. "and the Top Bar can carry it too. Saved for this computer.")
                    :format(mod.name, mod.command),
                getValue = function() return MinimapButtonOn(mod) end,
                setValue = function(v)
                    local account = ns.AccountSettings()
                    account.microMenu = account.microMenu or { buttons = {} }
                    account.microMenu.buttons[mod.name] = v
                    account.moduleButtons[mod.name].hide = not v
                    local icon = LibStub("LibDBIcon-1.0")
                    if v then icon:Show("NaowhForever" .. mod.short) else icon:Hide("NaowhForever" .. mod.short) end
                end }
        end
    end
    for i = 1, #rows, 2 do
        _, h = W:DualRow(parent, y, rows[i], rows[i + 1] or { type = "label", text = "" }); y = y - h
    end
    return y
end

function ns.BuildSettingsPage(parent, y)
    local W = UI.Widgets
    local _, h

    -- Every module shipped as its own addon, switched on or off for the next reload. A module
    -- that is off is only here, so this is where it comes back.
    _, h = W:SectionHeader(parent, "MODULES", y); y = y - h
    local rows = {}
    for _, mod in ipairs(MODULES) do
        if mod.addon then
            local tip = mod.subtitle
            if mod.needs then
                local needs = {}
                for i, addon in ipairs(mod.needs) do
                    for _, other in ipairs(MODULES) do
                        if other.addon == addon then needs[i] = other end
                    end
                end
                tip = tip .. "|n|nSwitches with " .. NameList(needs) .. "."
            end
            rows[#rows + 1] = { type = "toggle", text = mod.name,
                tooltip = tip,
                getValue = function() return C_AddOns.GetAddOnEnableState(mod.addon) > 0 end,
                setValue = function(v) SwitchModuleAddon(mod, v) end }
        end
    end
    for i = 1, #rows, 2 do
        _, h = W:DualRow(parent, y, rows[i], rows[i + 1] or { type = "label", text = "" }); y = y - h
    end

    y = ns.BuildMinimapIcons(parent, y)

    _, h = W:SectionHeader(parent, "OPTIONS WINDOW", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Window Scale",
          values = { [200] = "200%", [190] = "190%", [180] = "180%", [170] = "170%",
                     [160] = "160%", [150] = "150%", [140] = "140%", [130] = "130%",
                     [120] = "120%", [110] = "110%", [100] = "100%  (default)", [90] = "90%",
                     [80] = "80%", [70] = "70%", [60] = "60%", [50] = "50%" },
          order = { 200, 190, 180, 170, 160, 150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50 },
          tooltip = "Size of this options window and the editors it opens, as a percentage. "
          .. "This window never grows past your screen, so above that size a higher setting "
          .. "only enlarges the editors.|n|nSaved for this computer instead of in the profile, so switching "
          .. "profile leaves it alone and an exported pack never carries it to someone on a "
          .. "different monitor.",
          getValue = function() return tonumber(ns.AccountSettings().windowScale) or 100 end,
          setValue = function(v) ns.SetWindowScale(v) end }
    ); y = y - h

    _, h = W:SectionHeader(parent, "FONT", y); y = y - h
    local uiFonts, uiFontOrder = UI.FontChoices(ns.AccountSettings().uiFont)
    uiFonts[""] = "Naowh (default)"
    uiFonts[ns.BLIZZARD_FONT] = "Blizzard Default"
    table.insert(uiFontOrder, 2, ns.BLIZZARD_FONT)
    -- Off is saved as nil; an old Global Font of Blizzard Default reads as Off too.
    local function GameFontDropdown(text, key, tooltip)
        local saved = ns.AccountSettings()[key]
        if saved == ns.BLIZZARD_FONT then saved = nil end
        local fonts, order = UI.FontChoices(saved)
        fonts[""] = "Off (Blizzard Default)"
        return { type = "dropdown", text = text, values = fonts, order = order,
            tooltip = tooltip .. " Saved for this computer.|n|nTakes effect after a /reload.",
            getValue = function()
                local v = ns.AccountSettings()[key]
                return (v == nil or v == ns.BLIZZARD_FONT) and "" or v
            end,
            setValue = function(v)
                ns.AccountSettings()[key] = v ~= "" and v or nil
            end }
    end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Addon Font", values = uiFonts, order = uiFontOrder,
          tooltip = "The font for this addon's windows and HUD. Font settings on a feature "
          .. "use it unless they pick their own. Saved for this computer.|n|nTakes effect "
          .. "after a /reload.",
          getValue = function() return ns.AccountSettings().uiFont or "" end,
          setValue = function(v)
              ns.AccountSettings().uiFont = v ~= "" and v or nil
          end },
        GameFontDropdown("Game Font", "gameFont", "The font for the rest of the game: menus, "
            .. "chat, tooltips and names. Off leaves the game's own fonts alone.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        GameFontDropdown("Combat Text Font", "combatFont", "The font for damage and healing "
            .. "numbers, over enemies and over your character. Off leaves the game's own "
            .. "font alone."),
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:SectionHeader(parent, "COLORS", y); y = y - h
    local function CustomSelected() return ns.ThemePresetKey() == "custom" end
    -- A swatch drag calls setValue on every tick and has no OK callback, so the page is
    -- rebuilt once, on the first change, to bring the hint up.
    local function MarkColorsPending()
        if colorsPending then return end
        colorsPending = true
        UI:RefreshPage(true)
    end
    local themes, themeOrder = { [""] = "Naowh (default)" }, { "" }
    for _, key in ipairs(ns.THEME_PRESET_ORDER) do
        themes[key] = ns.THEME_PRESETS[key].name
        themeOrder[#themeOrder + 1] = key
    end
    themes.custom = "Custom"
    themeOrder[#themeOrder + 1] = "custom"
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Theme", values = themes, order = themeOrder,
          tooltip = "Theme presets for the addon's windows and HUD frames, plus a Custom "
          .. "option for your own colors. If text gets hard to read, pick Naowh (default). "
          .. "Saved for this computer.|n|nTakes effect after a /reload.",
          getValue = ns.ThemePresetKey,
          setValue = function(v)
              ns.SetThemePreset(v)
              colorsPending = true
              UI:RefreshPage(true)
          end },
        -- What the selection looks like, before a reload.
        { type = "palette", text = "", colors = function() return ns.ThemePalette(ns.ThemePresetKey()) end }
    ); y = y - h
    if CustomSelected() then
        -- An action, not a setting: it always reads "Choose a theme...", and picking one
        -- asks before it replaces the swatches below with that theme's colors.
        local starts, startOrder = { [""] = "Choose a theme...", default = "Naowh (default)" }, { "", "default" }
        for _, key in ipairs(ns.THEME_PRESET_ORDER) do
            starts[key] = ns.THEME_PRESETS[key].name
            startOrder[#startOrder + 1] = key
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Start From", values = starts, order = startOrder,
              tooltip = "Replace your custom colors with the colors of a theme, then adjust "
              .. "them below. Picking Naowh (default) is a reset.",
              getValue = function() return "" end,
              setValue = function(v)
                  if v == "" then return end
                  ns.Confirm("Replace your custom colors with " .. starts[v] .. "?", function()
                      ns.CopyThemeToCustom(v ~= "default" and v or "")
                      colorsPending = true
                      UI:RefreshPage(true)
                  end)
              end },
            { type = "label", text = "" }
        ); y = y - h
        local function Swatch(key, text)
            return { type = "colorpicker", text = text, hasAlpha = false,
                getValue = function() return ns.ThemeSwatchColor(key) end,
                setValue = function(r, g, b)
                    local account = ns.AccountSettings()
                    if type(account.themeColors) ~= "table" then account.themeColors = {} end
                    account.themeColors[key] = { r = r, g = g, b = b }
                    MarkColorsPending()
                end }
        end
        _, h = W:DualRow(parent, y, Swatch("bg", "Background"), Swatch("panel", "Panels")); y = y - h
        _, h = W:DualRow(parent, y, Swatch("line", "Borders & Lines"), Swatch("fg", "Text")); y = y - h
        _, h = W:DualRow(parent, y, Swatch("muted", "Secondary Text"), Swatch("accent", "Accent")); y = y - h
    end
    if colorsPending then
        _, h = W:Note(parent, "Reload UI to apply your color changes.", y); y = y - h
    end

    -- Only with RestedXP Guides installed.
    if ns.RXPThemesAvailable and ns.RXPThemesAvailable() then
        _, h = W:SectionHeader(parent, "RESTEDXP", y); y = y - h
        -- RestedXP reads these as it starts, so each one asks for a reload.
        local function Switch(text, tooltip, get, set)
            return { type = "toggle", text = text, tooltip = tooltip,
                getValue = get,
                setValue = function(v)
                    set(v)
                    rxpPending = true
                    UI:RefreshPage(true)
                end }
        end
        local themesSwitch = Switch("Add Themes to RestedXP", "Adds the Naowh themes to RestedXP's theme list.",
            ns.RXPThemesEnabled, ns.SetRXPThemes)
        local themeChoice = { type = "label", text = "" }
        if ns.RXPThemesEnabled() then
            local choices, choiceOrder = ns.RXPThemeChoices()
            themeChoice = ns.RXPThemesReady() and { type = "dropdown", text = "RestedXP Theme", values = choices,
                order = choiceOrder, tooltip = "The theme RestedXP uses: its own, or one of the Naowh themes.",
                getValue = ns.RXPThemeChoice,
                setValue = function(v)
                    if ns.SetRXPThemeChoice(v) == "reload" then
                        rxpPending = true
                        UI:RefreshPage(true)
                    end
                end } or { type = "label", text = "Reload UI to pick a theme." }
        end
        _, h = W:DualRow(parent, y, themesSwitch, themeChoice); y = y - h
        if ns.RXPThemesEnabled() then
            local image = ns.RXPArrowStyle() == "image"
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "RestedXP Arrow",
                  values = { layer = "Colored layer", image = "Naowh arrow", off = "RestedXP's own" },
                  order = { "layer", "image", "off" },
                  tooltip = "How RestedXP's waypoint arrow is drawn with a Naowh theme.",
                  getValue = ns.RXPArrowStyle,
                  setValue = function(v)
                      ns.SetRXPArrowStyle(v)
                      UI:RefreshPage(true)
                  end },
                image and { type = "dropdown", text = "Naowh Arrow Shape",
                  values = { kite = "Kite", wide = "Wide kite" },
                  order = { "kite", "wide" },
                  tooltip = "The shape of Naowh's arrow.",
                  getValue = ns.RXPArrowShape,
                  setValue = function(v) ns.SetRXPArrowShape(v) end } or { type = "label", text = "" }
            ); y = y - h
            if image then
                local sizeMin, sizeMax, sizeStep = ns.RXPArrowSizeRange()
                _, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Naowh Arrow Glow",
                      tooltip = "A soft glow around Naowh's arrow.",
                      getValue = ns.RXPArrowGlow,
                      setValue = function(v) ns.SetRXPArrowGlow(v) end },
                    { type = "slider", text = "Naowh Arrow Size", min = sizeMin, max = sizeMax, step = sizeStep,
                      tooltip = "How big Naowh's arrow is.",
                      getValue = ns.RXPArrowSize,
                      setValue = function(v) ns.SetRXPArrowSize(v) end }
                ); y = y - h
            end
            local gapMin, gapMax = ns.RXPArrowGapRange()
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Show Arrow Text",
                  tooltip = "The step and distance text under RestedXP's waypoint arrow.",
                  getValue = ns.RXPArrowTextEnabled,
                  setValue = function(v) ns.SetRXPArrowText(v) end },
                image and { type = "slider", text = "Naowh Arrow Text Gap", min = gapMin, max = gapMax, step = 1,
                  tooltip = "The space between Naowh's arrow and the text under it.",
                  getValue = ns.RXPArrowGap,
                  setValue = function(v) ns.SetRXPArrowGap(v) end } or { type = "label", text = "" }
            ); y = y - h
            _, h = W:DualRow(parent, y,
                Switch("Use Addon Font", "RestedXP's text uses your Addon Font.", ns.RXPFontEnabled, ns.SetRXPFont),
                Switch("Use Theme Text Color", "RestedXP's text uses the theme's Text color.",
                    ns.RXPTextColorEnabled, ns.SetRXPTextColor)
            ); y = y - h
        end
        if rxpPending then
            _, h = W:Note(parent, "Reload UI to apply your RestedXP changes.", y); y = y - h
        end
    end
    _, h = W:ReloadButton(parent, y); y = y - h

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
    ns.AllowOffscreen(target)
end

-- A grip in the bottom-right corner, with the size kept per window in the account store.
-- Pages lay out at the scroll child's width when they build, so a new width rebuilds them
-- once the drag ends.
local function Resizable(frame, key, child, inset, minW, minH)
    local function Fit()
        child:SetWidth(frame:GetWidth() - (type(inset) == "function" and inset() or inset))
    end
    local sizes = ns.AccountSettings().windowSizes
    local saved = sizes and sizes[key]
    if saved then frame:SetSize(math.max(saved[1], minW), math.max(saved[2], minH)) end
    Fit()
    frame:SetResizable(true)
    frame:SetResizeBounds(minW, minH)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local account = ns.AccountSettings()
        account.windowSizes = account.windowSizes or {}
        account.windowSizes[key] = { frame:GetWidth(), frame:GetHeight() }
        local width = child:GetWidth()
        Fit()
        if frame == window then FitMainWindow() end
        if child:GetWidth() ~= width then UI:RefreshPage(true) end
    end)
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
UI.CloseOnEscape = CloseOnEscape

local TAB_MARGIN = 28

local function TabStrip(parent, mod, onPick, maxW)
    local items = {}
    for i, tab in ipairs(mod.tabs) do items[i] = { key = tab.key, label = ns.L(tab.name) } end
    local Parts = ns.Shared.Parts
    local bar = Parts.Tabs(parent, 1, items, onPick)
    Parts.FitTabs(bar, items, TAB_MARGIN, maxW)
    return bar
end

-- Only navigation scrolls here; the footer and global controls stay in reach.
local function NavigationScroll(parent, top, bottom, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 0, -top)
    scroll:SetPoint("BOTTOMRIGHT", -12, bottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 12, 1)
    scroll:SetScrollChild(child)
    local bar = CreateFrame("Slider", nil, scroll)
    scroll.ScrollBar = bar
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 1, -2)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 1, 2)
    bar:SetWidth(10)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    local track = ns.Solid(bar, "BACKGROUND", T.line, 1)
    track:SetPoint("TOP"); track:SetPoint("BOTTOM"); track:SetWidth(2)
    local thumb = ns.Solid(bar, "ARTWORK", T.muted, 0.85)
    thumb:SetSize(6, 40)
    bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(_, value)
        if value ~= scroll:GetVerticalScroll() then scroll:SetVerticalScroll(value) end
    end)
    scroll:SetScript("OnVerticalScroll", function(_, value) bar:SetValue(value) end)
    local function UpdateRange()
        local range = scroll:GetVerticalScrollRange()
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScroll(), range)))
        bar:SetValue(scroll:GetVerticalScroll())
    end
    bar:Hide()
    scroll:SetScript("OnScrollRangeChanged", UpdateRange)
    scroll:SetScript("OnShow", UpdateRange)
    UI.SmoothWheel(scroll, NAV_H)
    scroll:SetScript("OnSizeChanged", function(self)
        self:UpdateScrollChildRect()
        UpdateRange()
    end)
    return child
end

local function NavEnter(btn)
    PaintNavButton(btn, true)
end

local function NavLeave(btn)
    if btn:IsMouseOver() then return end
    PaintNavButton(btn, false)
end

local function NavigationButton(parent, label, y, onClick, icon)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", 8, y)
    btn:SetPoint("TOPRIGHT", -8, y)
    btn:SetHeight(38)
    btn.fill = ns.Solid(btn, "BACKGROUND", T.accent, 0.16)
    btn.fill:SetAllPoints()
    btn.fill:Hide()
    btn.marker = ns.Solid(btn, "ARTWORK", T.accent, 1)
    btn.marker:SetPoint("TOPLEFT"); btn.marker:SetPoint("BOTTOMLEFT"); btn.marker:SetWidth(3)
    btn.marker:Hide()
    btn.label = ns.Font(btn, 14, nil, T.muted)
    btn.label:SetPoint("LEFT", icon and 42 or 18, 0)
    btn.label:SetPoint("RIGHT", -10, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)
    btn.label:SetText(label)
    if icon then
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\Navigation\\" .. icon .. ".tga")
        btn.icon:SetSize(20, 20)
        btn.icon:SetPoint("LEFT", 14, 0)
        btn.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    end
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", NavEnter)
    btn:SetScript("OnLeave", NavLeave)
    return btn
end

local function OpenEnter(open)
    PaintNavButton(open:GetParent(), true)
    open.icon:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1)
    GameTooltip:SetOwner(open, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L("Open") .. " " .. DisplayName(open:GetParent().mod), 1, 1, 1)
    GameTooltip:Show()
end

local function OpenLeave(open)
    open.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    GameTooltip:Hide()
    local btn = open:GetParent()
    PaintNavButton(btn, btn:IsMouseOver())
end

local function OpenClicked(open)
    local fn = ns[open:GetParent().mod.open]
    if fn then ns.OpenFromOptions(fn) end
end

-- A module with a window of its own: an icon on its row that opens the window, and a grey dot
-- while the module is off.
local function NavExtras(btn, mod)
    btn.mod = mod
    btn.dot = btn:CreateTexture(nil, "ARTWORK")
    btn.dot:SetTexture(MEDIA .. "circle_mask.tga", nil, nil, "TRILINEAR")
    btn.dot:SetSize(NAV_DOT, NAV_DOT)
    btn.dot:SetPoint("RIGHT", -14, 0)
    btn.dot:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, NAV_OFF_ALPHA)
    btn.dot:Hide()
    if not mod.open then return end
    local open = CreateFrame("Button", nil, btn)
    open:SetSize(NAV_OPEN, NAV_OPEN)
    open:SetPoint("RIGHT", -6, 0)
    open.icon = open:CreateTexture(nil, "ARTWORK")
    open.icon:SetTexture(MEDIA .. "Navigation\\window.tga", nil, nil, "TRILINEAR")
    open.icon:SetSize(NAV_OPEN_ICON, NAV_OPEN_ICON)
    open.icon:SetPoint("CENTER")
    open.icon:SetVertexColor(T.muted.r, T.muted.g, T.muted.b, 1)
    open:SetScript("OnClick", OpenClicked)
    open:SetScript("OnEnter", OpenEnter)
    open:SetScript("OnLeave", OpenLeave)
    open:Hide()
    btn.open = open
    btn.label:SetPoint("RIGHT", -(NAV_OPEN + 8), 0)
end

local function CreateWindow()
    window = CreateFrame("Frame", "NaowhForeverOptions", UIParent)
    window:SetSize(WINDOW_W, WINDOW_H)
    window:SetScale(ns.UIScale())
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    ns.Shared.Parts.Backdrop(window):Paint(1)
    local border = ns.Border(window, ns.Shared.Style.BORDER_RGB)
    -- Ctrl+F opens the search bar, and Escape closes the bar before the window.
    window:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local open = key == "F" and IsControlKeyDown()
        if not (open or (key == "ESCAPE" and searchBar:IsShown())) then return CloseOnEscape(self, key) end
        self:SetPropagateKeyboardInput(false)
        if open then UI.OpenSearch() else UI.CloseSearch() end
        C_Timer.After(0, function()
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end)
    end)

    local top = CreateFrame("Frame", nil, window)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(TOP_H)
    DragRegion(top, window)
    local topLine = ns.Solid(top, "ARTWORK", T.line, 1)
    topLine:SetPoint("BOTTOMLEFT"); topLine:SetPoint("BOTTOMRIGHT"); ns.Hairline(topLine, "h")
    local brand = CreateFrame("Frame", nil, top)
    brand:SetPoint("TOPLEFT")
    brand:SetSize(SIDEBAR_W, TOP_H)
    ns.Solid(brand, "BACKGROUND", T.panel, 1):SetAllPoints()
    local brandEdge = ns.Solid(brand, "ARTWORK", T.line, 1)
    brandEdge:SetPoint("TOPRIGHT"); brandEdge:SetPoint("BOTTOMRIGHT"); ns.Hairline(brandEdge, "v")
    local logo = brand:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(BRAND_LOGO, nil, nil, "TRILINEAR")
    logo:SetTexCoord(0, BRAND.artW / BRAND.texW, 0, BRAND.artH / BRAND.texH)
    logo:SetSize(BRAND.height * BRAND.artW / BRAND.artH, BRAND.height)
    logo:SetPoint("TOPLEFT", brand, "TOPLEFT", BRAND.inset, -BRAND.inset)
    -- The logo's panel sits a level above the border's frame, its fill over the window's top
    -- left edges; the border goes over it.
    border._frame:SetFrameLevel(brand:GetFrameLevel() + 1)
    local close = ns.Button(top, "X", 28, 28, function() window:Hide() end)
    close:SetPoint("RIGHT", -18, 0)
    local unlock = ns.Button(top, "Layout Mode", 140, 32, EnterUnlockMode)
    ns.AccentBorder(unlock)
    unlock:SetPoint("RIGHT", close, "LEFT", -18, 0)
    ns.Tooltip(unlock, "Layout Mode", "Place and size each display. Exit Config returns to this window.")
    local search = ns.Button(top, "Search  " .. ns.Color("muted", "Ctrl+F"), SEARCH_W, 32, function() UI.OpenSearch() end)
    search:SetPoint("RIGHT", unlock, "LEFT", -18, 0)
    ns.Tooltip(search, "Search", "Step through every setting that matches what you type.")

    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 0, -TOP_H); sidebar:SetPoint("BOTTOMLEFT"); sidebar:SetWidth(SIDEBAR_W)
    local edge = ns.Solid(sidebar, "ARTWORK", T.line, 1)
    edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT"); ns.Hairline(edge, "v")
    local nav = NavigationScroll(sidebar, 16, FOOTER_H_SIDEBAR + 6 + NAV_STEP * #SYSTEM_NAV, SIDEBAR_W)
    -- Modules list in MODULES order under their group; one with only unfinished tabs, or whose
    -- addon is switched off, is left out.
    local groups, grouped = {}, {}
    for _, mod in ipairs(MODULES) do
        local ready = false
        for _, tab in ipairs(mod.tabs) do ready = ready or not tab.soon end
        if ready and Loaded(mod) then
            local group = mod.group or ""
            if not grouped[group] then
                grouped[group] = {}
                groups[#groups + 1] = group
            end
            table.insert(grouped[group], mod)
        end
    end
    local ny = 0
    for _, group in ipairs(groups) do
        if group ~= "" then
            local label = ns.Font(nav, 11, nil, T.muted)
            label:SetPoint("TOPLEFT", 20, ny - 10); label:SetText(ns.L(group))
            ny = ny - 28
        end
        navBlocks[#navBlocks + 1] = { top = ny, mods = grouped[group] }
        for _, mod in ipairs(grouped[group]) do
            local btn = NavigationButton(nav, DisplayName(mod), ny,
                function() ShowPage(lastPages[mod.name] or mod.tabs[1].key) end, mod.navIcon)
            -- Spaced to fit every module in the default 790-high window (test-navigation.lua).
            btn:SetHeight(30)
            NavExtras(btn, mod)
            navButtons[mod.name] = btn
            ny = ny - NAV_ROW
        end
    end
    nav:SetHeight(-ny)

    local utility = CreateFrame("Frame", nil, sidebar)
    utility:SetPoint("BOTTOMLEFT", 0, FOOTER_H_SIDEBAR); utility:SetPoint("BOTTOMRIGHT", 0, FOOTER_H_SIDEBAR)
    utility:SetHeight(NAV_STEP * #SYSTEM_NAV + 6)
    local utilityLine = ns.Solid(utility, "ARTWORK", T.line, 1)
    utilityLine:SetPoint("TOPLEFT"); utilityLine:SetPoint("TOPRIGHT"); ns.Hairline(utilityLine, "h")
    for i, entry in ipairs(SYSTEM_NAV) do
        local key = entry[1]
        local btn = NavigationButton(utility, ns.L(key), -4 - (i - 1) * NAV_STEP, function() ShowPage(key) end, entry[2])
        btn:SetHeight(28)
        navButtons[key] = btn
    end
    local version = ns.Font(sidebar, 10, nil, T.muted)
    version:SetPoint("BOTTOMLEFT", 20, 10)
    version:SetText("v" .. (ns.CODE_BUILD or C_AddOns.GetAddOnMetadata(ns.MODULE_KEY, "Version") or "unknown"))
    local Parts = ns.Shared.Parts
    local right = -14
    for i = #LINKS, 1, -1 do
        local name, icon, url = LINKS[i][1], LINKS[i][2], LINKS[i][3]
        local link = Parts.IconButton(sidebar, function() ns.ShowCopyLine(name, url()) end, LINK_ICONS .. icon .. ".tga",
            nil, name)
        link:SetSize(LINK_SIZE, LINK_SIZE)
        link.icon:SetSize(LINK_SIZE, LINK_SIZE)
        link:SetPoint("BOTTOMRIGHT", right, 8)
        right = right - LINK_SIZE - LINK_GAP
    end

    contentHeader = CreateFrame("Frame", nil, window)
    contentHeader:SetHeight(PAGE_HEADER_H)
    breadcrumb = ns.Font(contentHeader, 12, nil, T.muted)
    breadcrumb:SetPoint("TOPLEFT", 26, -24)
    headerTitle = ns.Font(contentHeader, 24, nil)
    headerTitle:SetPoint("TOPLEFT", 26, -51)
    headerTitle:SetPoint("TOPRIGHT", contentHeader, "TOPRIGHT", -300, -51)
    headerTitle:SetJustifyH("LEFT"); headerTitle:SetWordWrap(false)
    headerSub = ns.Font(contentHeader, 12, nil, T.muted)
    headerSub:SetPoint("TOPLEFT", 26, -94)
    headerSub:SetPoint("TOPRIGHT", -30, -94); headerSub:SetJustifyH("LEFT"); headerSub:SetWordWrap(false)
    moduleSwitch = UI.BuildToggleControl(contentHeader, nil,
        function() local mod = PAGES[currentPage].module; return mod and ModuleOn(mod) end,
        function(v) local mod = PAGES[currentPage].module; if mod then SetModuleOn(mod, v) end end, 52, 26)
    moduleSwitch:SetPoint("TOPRIGHT", -30, -54)
    moduleLabel = ns.Font(contentHeader, 14, nil)
    moduleLabel:SetPoint("RIGHT", moduleSwitch, "LEFT", -14, 0)
    ns.Tooltip(moduleSwitch, "Module", "Turn this module on or off. Your settings are kept.")
    for _, mod in ipairs(MODULES) do
        if #mod.tabs > 1 then
            local bar = TabStrip(contentHeader, mod, ShowPage, WINDOW_W - SIDEBAR_W - 26 - 30)
            bar:SetPoint("TOPLEFT", contentHeader, "TOPLEFT", 26, -(PAGE_HEADER_H - 14))
            bar:Hide()
            tabStrips[mod.name] = bar
        end
    end
    tabLine = ns.Solid(window, "ARTWORK", T.line, 1); ns.Hairline(tabLine, "h")

    contentFooter = CreateFrame("Frame", nil, window)
    contentFooter:SetHeight(FOOTER_H)
    local footLine = ns.Solid(contentFooter, "ARTWORK", T.line, 1)
    footLine:SetPoint("TOPLEFT"); footLine:SetPoint("TOPRIGHT"); ns.Hairline(footLine, "h")
    ns.AccentBorder(ns.ReloadButton(contentFooter, "Reload UI", 120, 30)):SetPoint("LEFT", 26, 0)
    ns.AccentBorder(ns.Button(contentFooter, "Close", 120, 30, function() window:Hide() end))
        :SetPoint("RIGHT", -30, 0)
    searchBar = UI.AttachSearchBar(window, function() LayoutContent() end)
    scrollFrame = UI.SlimScroll(window, nil, SCROLL_BAR_GAP)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(WINDOW_W - SIDEBAR_W - 36, 1)
    scrollFrame:SetScrollChild(scrollChild)
    Resizable(window, "main", scrollChild, SIDEBAR_W + 36, WINDOW_W, 620)

    window:SetScript("OnShow", function(self)
        FitMainWindow()
        if not InCombatLockdown() then
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(true)
        end
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
    FitMainWindow()
    window:Hide()
end

-- pageName may be a page key, a module name (its first tab) or a bare tab name, so older
-- callers naming "Setup" still land. OnShow renders currentPage.
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
-- A module's own window, opened from here: this window goes, and the module's title links back.
function ns.OpenFromOptions(open)
    if not (window and window:IsShown()) then return open() end
    local page = currentPage
    ns.Shared.Parts.OpenWithBack(open, window, function() ns.OpenOptionsWindow(page) end, "Back to Settings")
end

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
-- or the window's own pages.
local MODULE_WINDOW_H = 560

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
    ns.Shared.Parts.Backdrop(win):Paint(1)
    ns.Border(win, ns.Shared.Style.BORDER_RGB)
    win:SetScript("OnKeyDown", CloseOnEscape)

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    DragRegion(header, win)
    local title = ns.Font(header, 20, nil)
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -18)
    title:SetText(ns.L(mod.name))
    local sub = ns.Font(header, 12, nil, T.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
    sub:SetText(mod.subtitle)
    local close = ns.Button(header, "X", 26, 26, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -12)
    -- The module switch, since some pages have no switch of their own. Full
    -- size, like the switches on the page below it.
    local switch = UI.BuildToggleControl(header, header:GetFrameLevel() + 2,
        function() return ModuleOn(mod) end,
        function(v) SetModuleOn(mod, v) end)
    switch:SetPoint("RIGHT", close, "LEFT", -14, 0)
    ns.Tooltip(switch, mod.name, function()
        return ModuleOn(mod) and "On. Click to turn the whole module off."
            or "Off. Click to turn it back on."
    end)
    win.switch = switch

    win.tabs = TabStrip(win, mod, function(key) ShowModulePage(win, key) end, CONTENT_W - 60)
    win.tabs:SetPoint("TOPLEFT", win, "TOPLEFT", 30, -(HEADER_H + 2))
    local offset = HEADER_H + TAB_H
    local line = ns.Solid(win, "ARTWORK", T.line, 1)
    line:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -offset)
    line:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -offset)
    ns.Hairline(line, "h")

    win.scrollFrame = UI.SlimScroll(win, nil, SCROLL_BAR_GAP)
    win.scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -(offset + 5))
    win.scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 22)
    win.scrollChild = CreateFrame("Frame", nil, win.scrollFrame)
    win.scrollChild:SetSize(CONTENT_W - 40, 1)
    win.scrollFrame:SetScrollChild(win.scrollChild)
    Resizable(win, "module:" .. mod.name, win.scrollChild, 40, CONTENT_W, 360)
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
    end)
    win:SetScript("OnHide", function()
        if UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
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

-- A module's own window: the one it names in `open`, else its tabs on their own.
local function OpenModule(mod)
    if not Loaded(mod) then
        return ns.Print(("%s is switched off. Turn it on under Settings > Modules."):format(DisplayName(mod)))
    end
    if mod.open and ns[mod.open] then ns[mod.open]() else ToggleModuleWindow(mod) end
end

-- Addon compartment entry (the puzzle-piece menu by the minimap); wired in the .toc.
function _G.NaowhForever_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

-- Key Bindings > AddOns (Bindings.xml), named here so the list reads the same whichever modules
-- are on. A module's key calls a function its addon defines over the stub below when it loads.
BINDING_HEADER_NAOWHFOREVER = "Naowh Forever"
BINDING_NAME_NAOWHFOREVER_JOURNAL = "Open Dungeon Journal"
BINDING_NAME_NAOWHFOREVER_BOSSLOOT = "Boss Loot at Cursor"
BINDING_NAME_NAOWHFOREVER_BIS = "Open BiS List"
_G["BINDING_NAME_CLICK NaowhForeverBlessNext:LeftButton"] = "Next Blessing"
_G["BINDING_NAME_CLICK NaowhForeverBlessNextGreater:LeftButton"] = "Next Greater Blessing"

local function SwitchedOff(name)
    return function() ns.Print(("%s is switched off. Turn it on under Settings > Modules."):format(name)) end
end
NaowhForever_ToggleJournal = SwitchedOff("Dungeon Journal")
NaowhForever_BossLoot = SwitchedOff("Dungeon Journal")
NaowhForever_ToggleBis = SwitchedOff("BiS List")

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
    elseif cmd == "dungeon" and ns.ToggleJournalWindow then
        ns.ToggleJournalWindow()
    elseif cmd == "bars" and ns.ActionBarsCommand then
        -- Set names keep the case they were typed in.
        ns.ActionBarsCommand(strtrim(msg):match("^%S+%s*(.-)$"))
    elseif cmd == "lockouts" and ns.LockoutsCommand then
        ns.LockoutsCommand()
    elseif cmd == "ranks" and ns.TrainerRankCheck then
        ns.TrainerRankCheck()
    elseif cmd == "trainer" and ns.Training then
        ns.Training.WaypointToTrainer()
    elseif cmd == "profrank" and ns.ProfessionRankCheck then
        ns.ProfessionRankCheck()
    elseif cmd == "recipes" and ns.RecipeFinderDebug then
        ns.RecipeFinderDebug()
    elseif cmd == "townaudit" and ns.TownAudit then
        ns.TownAudit()
    elseif cmd == "itemprobe" and ns.JournalItemProbe then
        ns.JournalItemProbe()
    elseif (cmd == "mappins" or cmd == "mapcheck") and ns.DungeonMapCommand then
        ns.DungeonMapCommand(cmd)
    elseif cmd == "badges" and ns.BadgesCommand then
        ns.BadgesCommand(arg)
    elseif cmd == "scrap" and ns.ToggleScrapList then
        ns.ToggleScrapList()
    elseif cmd == "welcome" and ns.ShowWelcome then
        ns.ShowWelcome()
    else
        ns.ToggleOptionsWindow()
    end
end

for _, mod in ipairs(MODULES) do
    if mod.command then
        local key = "NAOWHFOREVER" .. mod.command:upper()
        _G["SLASH_" .. key .. "1"] = "/nf" .. mod.command
        -- A short second name: /nfdj for /nfjournal.
        if mod.alias then _G["SLASH_" .. key .. "2"] = "/nf" .. mod.alias end
        SlashCmdList[key] = function() OpenModule(mod) end
    end
end

-- The launcher position belongs to the account, not an imported settings profile.
local launcherEvents = CreateFrame("Frame")
-- The launcher tooltips (minimap, top bar, broker displays): the title is the game's tooltip
-- gold and the lines white, unless the theme changed Accent / Text, which they follow.
local TIP_TITLE = { r = 1, g = 0.82, b = 0 }
local TIP_TEXT = { r = 1, g = 1, b = 1 }
local function TipTitle(tooltip, text)
    local c = ns.ThemeTint("accent", TIP_TITLE)
    tooltip:AddLine(text, c.r, c.g, c.b)
end
local function TipLine(tooltip, text)
    local c = ns.ThemeTint("fg", TIP_TEXT)
    tooltip:AddLine(text, c.r, c.g, c.b)
end
launcherEvents:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ns.SaveModuleDefaults()
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
            TipTitle(tooltip, "Naowh Forever")
            TipLine(tooltip, ns.L("Click to open settings."))
            TipLine(tooltip, ns.L("Drag to move the minimap button."))
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("NaowhForever", launcher, account.minimap)

    -- A launcher per module, for the top bar and any broker display, on the minimap while its
    -- Minimap Buttons switch is on.
    account.moduleButtons = account.moduleButtons or {}
    for _, mod in ipairs(MODULES) do
        if mod.command and Loaded(mod) then
            local db = account.moduleButtons[mod.name] or { minimapPos = 220 }
            account.moduleButtons[mod.name] = db
            db.hide = not MinimapButtonOn(mod)
            local obj = LibStub("LibDataBroker-1.1"):NewDataObject("NaowhForever" .. mod.short, {
                type = "launcher",
                label = mod.name,
                icon = mod.icon,
                OnClick = function() OpenModule(mod) end,
                OnTooltipShow = function(tooltip)
                    TipTitle(tooltip, mod.name)
                    TipLine(tooltip, ns.L("Click to open or close it on its own."))
                end,
            })
            LibStub("LibDBIcon-1.0"):Register("NaowhForever" .. mod.short, obj, db)
        end
    end
end)
launcherEvents:RegisterEvent("PLAYER_LOGIN")
