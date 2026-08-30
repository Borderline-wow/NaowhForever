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

local PAGES = { "Setup", "Dungeon Bosses", "Raid Bosses" }

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
    if pageName == "Dungeon Bosses" then
        return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, -6, false) or -6
    elseif pageName == "Raid Bosses" then
        return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, -6, true) or -6
    else
        return ns.BuildSetupPage and ns.BuildSetupPage(parent, -6) or -6
    end
end

local function PaintTabs()
    for name, btn in pairs(tabButtons) do
        local active = (name == currentPage)
        btn.label:SetTextColor(active and T.fg.r or T.muted.r,
            active and T.fg.g or T.muted.g,
            active and T.fg.b or T.muted.b, 1)
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
        local usedY = BuildPageInto(pageName, wrapper)
        wrapper:SetHeight(math.abs(usedY) + 30)
    end
    scrollChild:SetHeight(wrappers[pageName]:GetHeight())
    scrollFrame:SetVerticalScroll(0)
    PaintTabs()
end

-- The universal "this setting changed the page's shape, redraw it" call, with the same
-- semantics the pages were written against: full rebuild of the active tab, scroll
-- preserved. When the window is hidden the rebuild waits for the next open, so page-build
-- side effects (preview, lazy journal reads) never run off-screen.
function UI:RefreshPage(force)
    if not (window and window:IsShown()) then
        pendingRefresh = true
        return
    end
    local scroll = scrollFrame:GetVerticalScroll()
    local old = wrappers[currentPage]
    if old then
        old:Hide()
        old:SetParent(nil)
        wrappers[currentPage] = nil
    end
    ShowPage(currentPage)
    scrollFrame:UpdateScrollChildRect()
    scrollFrame:SetVerticalScroll(scroll)
end

local function CreateWindow()
    window = CreateFrame("Frame", "NaowhUISmartRemindersOptions", UIParent)
    window:SetSize(WINDOW_W, WINDOW_H)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    ns.Solid(window, "BACKGROUND", T.bg, 1):SetAllPoints()
    ns.Border(window)

    -- ESC closes via Blizzard's own special-frames path: combat-safe, no keyboard grab.
    tinsert(UISpecialFrames, "NaowhUISmartRemindersOptions")

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

    -- Tab strip, in the same visual language as the modal editors' own tabs: a button
    -- with an accent underline marking the active page.
    local tx = 10
    for _, name in ipairs(PAGES) do
        local btn = CreateFrame("Button", nil, window)
        btn:SetSize(130, TAB_H)
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
        tx = tx + 134
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

    window:SetScript("OnShow", function()
        if pendingRefresh then
            pendingRefresh = nil
            local old = wrappers[currentPage]
            if old then
                old:Hide()
                old:SetParent(nil)
                wrappers[currentPage] = nil
            end
        end
        ShowPage(currentPage)
        for i = 1, #onShowCallbacks do onShowCallbacks[i]() end
    end)
    window:SetScript("OnHide", function()
        for i = 1, #onHideCallbacks do onHideCallbacks[i]() end
    end)
end

function ns.OpenOptionsWindow()
    if not window then CreateWindow() end
    window:Show()
end

function ns.ToggleOptionsWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        ns.OpenOptionsWindow()
    end
end

-- Addon compartment entry (the puzzle-piece menu by the minimap); wired in the .toc.
function _G.NaowhUI_SmartReminders_OnCompartmentClick()
    ns.ToggleOptionsWindow()
end

SLASH_NAOWHUISMARTREM1 = "/smartreminders"
SlashCmdList["NAOWHUISMARTREM"] = function() ns.ToggleOptionsWindow() end
