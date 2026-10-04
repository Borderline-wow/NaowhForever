-------------------------------------------------------------------------------
--  UI/Window.lua -- the Dungeon Journal's own window (/nfjournal or /nfdj, its minimap and
--  top bar button, its key binding, and Open Dungeon Journal on its settings page), built
--  from the shared window parts. Down the left a switch between Dungeons & Raids,
--  Reputation and PvP, a search over every dungeon and faction, and the list the switch
--  shows (UI/DungeonList.lua, or UI/FactionList.lua); on the right the page you pick, drawn
--  by the Journal's view; in the title bar the list's button, Filters and the opacity. The
--  list can be hidden for the cards across the whole window. Made the first time it opens;
--  it remembers where you put it, the tab and whether the list shows. Opening it turns the
--  module on; turning the module off closes it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local S = J.Settings
local Loot = J.Loot
local List = J.DungeonList
local Factions = J.FactionList
local Parts = J.View.Parts

local St = J.Style
local WIDTH, HEIGHT, HEADER, PAD = St.WINDOW_W, St.WINDOW_H, St.WINDOW_HEADER, St.WINDOW_PAD
local FOOTER = St.WINDOW_FOOTER
local LIST_W, SEARCH_H, SCROLLBAR, CONTENT_INSET = St.LIST_W, St.SEARCH_H, St.SCROLLBAR, St.CONTENT_INSET
local BORDER_RGB, PLACE_DOT = St.BORDER_RGB, St.PLACE_DOT
local BAR_ICON, FUNNEL, TICK = St.BAR_ICON, St.FUNNEL, St.TICK
local LIST_SHOWN, LIST_HIDDEN = St.LIST_SHOWN, St.LIST_HIDDEN
local FACTION_W, FACTION_ICON, FACTION_OFF, FACTION_GAP = St.FACTION_W, St.FACTION_ICON, St.FACTION_OFF, St.FACTION_GAP
local FACTION_ATLAS, TERRITORY_CODE = St.FACTION_ATLAS, St.TERRITORY_CODE
local TAB_H, TAB_GAP = St.TAB_H, St.TAB_GAP

local PAGE = "Dungeon Journal"
local SEARCH_DELAY = 0.15   -- seconds after the last key before the search runs
local MIN_QUERY = 2         -- letters

local window, view, scroll, search, listFrame, factionFrame
local listCard, contentCard   -- the window's two cards: behind the list, and behind the page
local selected                -- the page shown: a dungeon, a faction or J.RANK
local awayForMap = false      -- put away by the world map opening (J.WindowAwayForMap)
local onClose                 -- opened from another window: brings it back when this one closes
local shownTab                -- "dungeons", "reputation" or "pvp"
local picked = {}             -- tab -> the page last shown on it, for this session

-------------------------------------------------------------------------------
--  The switch over the list. Each part shows its own list, and opens on the page last
--  shown on it.
-------------------------------------------------------------------------------
local TABS = {
    { key = "dungeons", label = "Dungeons & Raids" },
    { key = "reputation", label = "Reputation" },
    { key = "pvp", label = "PvP" },
}

local function TabOf(page)
    return page.tab or "dungeons"
end

local function SavedTab()
    local tab = ns.AccountSettings().journalTab
    return (tab == "reputation" or tab == "pvp") and tab or "dungeons"
end

-- The search sits beside the faction switch; alone at the list's width where the switch has
-- nothing to list or hide (Reputation: no faction there is one side's).
local SEARCH_W = LIST_W - 8 - FACTION_W * 2 - FACTION_GAP
local SEARCH_FULL_W = LIST_W - 8

local function ShowLists()
    if not shownTab then return end
    local hidden = S.Get("listHidden")
    local dungeons = shownTab == "dungeons"
    local sides = shownTab ~= "reputation"
    listFrame:SetShown(dungeons and not hidden)
    factionFrame:SetShown(not dungeons and not hidden)
    window.factionSwitch:SetShown(sides and not hidden)
    search:SetWidth(sides and SEARCH_W or SEARCH_FULL_W)
    if not dungeons then Factions.Layout(shownTab) end
end

local function ShowTab(tab)
    shownTab = tab
    ns.AccountSettings().journalTab = tab
    -- The faction list shows your standing: the view redraws, and the list with it, when it moves.
    view.watchFactions = tab ~= "dungeons"
    ShowLists()
    Parts.PaintTabs(window.tabBar, tab)
end

local function FirstPage(tab)
    if tab == "dungeons" then return J.Suggested() end
    if tab == "pvp" then return J.RANK end
    return Factions.First(tab) or J.Suggested()
end

-------------------------------------------------------------------------------
--  Showing a page, and searching
-------------------------------------------------------------------------------
local shownQuery = ""         -- the search on the page ("" for a dungeon)
local searchQueued = false
local clearing = false        -- the window is emptying the search box itself

local function ClearSearch()
    if search:GetText() ~= "" then
        clearing = true
        search:SetText("")
        clearing = false
    end
    shownQuery = ""
end

local function DrawPage(page)
    if page.rank then
        view:DrawRank()
    elseif page.tab then
        view:DrawFaction(page)
    else
        view:Draw(page)
    end
end

-- The list is painted when the view has drawn (Drawn).
local function Select(page)
    local tab = TabOf(page)
    if tab ~= shownTab then ShowTab(tab) end
    selected = page
    picked[tab] = page
    ClearSearch()
    DrawPage(page)
    scroll:SetVerticalScroll(0)
end

local function TabPicked(tab)
    Select(picked[tab] or FirstPage(tab))
end

-- Two letters or more search every dungeon's bosses and loot; fewer go back to the page.
-- Runs once typing pauses, and only when the search changed.
local function RunSearch()
    searchQueued = false
    if not window:IsShown() then return end
    local query = strtrim(search:GetText()):lower()
    if #query < MIN_QUERY then query = "" end
    if query == shownQuery then return end
    shownQuery = query
    if query == "" then DrawPage(selected) else view:DrawSearch(query, Select) end
    scroll:SetVerticalScroll(0)
end

local function OnSearch()
    if clearing or searchQueued then return end
    searchQueued = true
    C_Timer.After(SEARCH_DELAY, RunSearch)
end

-- Up and Down step through the list, and Ctrl+F goes to the search box, while the mouse is
-- on the window and you are not typing. Out of combat only, where the window may keep a key
-- from the game; everything else goes to Esc's handler.
local function PassKeysOn()
    if not InCombatLockdown() then window:SetPropagateKeyboardInput(true) end
end

local function OnKeyDown(self, key)
    if not InCombatLockdown() and self:IsMouseOver() and not search:HasFocus() then
        if key == "UP" or key == "DOWN" then
            self:SetPropagateKeyboardInput(false)
            local by = key == "UP" and -1 or 1
            Select(shownTab == "dungeons" and List.Next(selected, by) or Factions.Next(selected, by))
            C_Timer.After(0, PassKeysOn)
            return
        elseif key == "F" and IsControlKeyDown() then
            self:SetPropagateKeyboardInput(false)
            search:SetFocus()
            C_Timer.After(0, PassKeysOn)
            return
        end
    end
    ns.UI.CloseOnEscape(self, key)
end

-------------------------------------------------------------------------------
--  Filters: the Journal's switches (J.OPTION_GROUPS), ticked while on, under what they do
-------------------------------------------------------------------------------
local GROUPS = J.OPTION_GROUPS

-- One that needs the BiS List does nothing without it.
local function Available(option)
    return not option.needsBis or Loot.BisOn()
end

local function FiltersOn()
    local on = 0
    for _, group in ipairs(GROUPS) do
        for _, option in ipairs(group.options) do
            if option.hides ~= nil and S.Get(option.key) == option.hides and Available(option) then
                on = on + 1
            end
        end
    end
    return on
end

-- The addon's own panel under the funnel: each group's title in small capitals, then a row
-- per switch, its box ticked in the accent while on; one that needs the BiS List is dimmed
-- and says why. A click anywhere else, or on the funnel again, closes it. It listens for
-- clicks only while open.
local MENU_W, MENU_PAD = 220, 12
local MENU_TITLE_H, MENU_GROUP_GAP = 16, 10
local MENU_ROW_H = 26
local MENU_BOX, MENU_BOX_GAP = 14, 10
local MENU_DIMMED = 0.5
local menu

local function PaintMenu()
    local y = MENU_PAD
    for _, part in ipairs(menu.parts) do
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", MENU_PAD, -y)
        part:SetPoint("RIGHT", -MENU_PAD, 0)
        local option = part.option
        if not option then
            y = y + (part.gap or 0)
            part:SetPoint("TOPLEFT", MENU_PAD, -y)
            y = y + MENU_TITLE_H
        else
            local on, available = S.Get(option.key), Available(option)
            part.tick:SetShown(on and true or false)
            local edge = on and available and T.accent or BORDER_RGB
            part.edge:SetColor(edge.r, edge.g, edge.b, 1)
            part:SetAlpha(available and 1 or MENU_DIMMED)
            part:SetHeight(MENU_ROW_H)
            y = y + MENU_ROW_H
        end
    end
    menu:SetHeight(y + MENU_PAD)
end

local function RowClicked(row)
    if Available(row.option) then S.Set(row.option.key, not S.Get(row.option.key)) end
end

local function RowEnter(row)
    row.band:Show()
    local option = row.option
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT", MENU_PAD, 0)
    GameTooltip:SetText(option.label, 1, 1, 1)
    GameTooltip:AddLine(option.tooltip, T.muted.r, T.muted.g, T.muted.b, true)
    if not Available(option) then GameTooltip:AddLine(J.NEEDS_BIS, T.accentSoft.r, T.accentSoft.g, T.accentSoft.b, true) end
    GameTooltip:Show()
end

local function RowLeave(row)
    row.band:Hide()
    GameTooltip:Hide()
end

local function MenuRow(option)
    local row = CreateFrame("Button", nil, menu)
    row.option = option
    row.band = ns.Solid(row, "BACKGROUND", T.accent, 0.08)
    row.band:SetPoint("TOPLEFT", -MENU_PAD / 2, 0)
    row.band:SetPoint("BOTTOMRIGHT", MENU_PAD / 2, 0)
    row.band:Hide()
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(MENU_BOX, MENU_BOX)
    box:SetPoint("LEFT", 0, 0)
    ns.Solid(box, "BACKGROUND", T.bg, 1):SetAllPoints()
    row.edge = ns.Border(box, BORDER_RGB)
    row.tick = box:CreateTexture(nil, "ARTWORK")
    row.tick:SetTexture(TICK)
    ns.PixelInset(row.tick, 1)
    row.tick:SetVertexColor(T.accent.r, T.accent.g, T.accent.b, 1)
    row.label = ns.Font(row, 13, nil, T.fg)
    row.label:SetPoint("LEFT", MENU_BOX + MENU_BOX_GAP, 0)
    row.label:SetPoint("RIGHT")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(option.label)
    row:SetScript("OnClick", RowClicked)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

local function MenuMouseDown()
    if not (menu:IsMouseOver() or window.filters:IsMouseOver()) then menu:Hide() end
end

local function BuildMenu()
    menu = CreateFrame("Frame", nil, window)
    menu:SetWidth(MENU_W)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:SetPoint("TOPRIGHT", window.filters, "BOTTOMRIGHT", 0, -6)
    ns.Solid(menu, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(menu, BORDER_RGB)
    menu.parts = {}
    for g, group in ipairs(GROUPS) do
        local title = ns.Font(menu, 11, nil, T.muted)
        title:SetText(group.title:upper())
        title:SetJustifyH("LEFT")
        title.gap = g > 1 and MENU_GROUP_GAP or 0
        menu.parts[#menu.parts + 1] = title
        for _, option in ipairs(group.options) do menu.parts[#menu.parts + 1] = MenuRow(option) end
    end
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    menu:SetScript("OnEvent", MenuMouseDown)
    menu:Hide()
end

local function OpenFilters()
    if not menu then BuildMenu() end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    GameTooltip:Hide()
    menu:Show()
    PaintMenu()
end

-------------------------------------------------------------------------------
--  The faction switch beside the search: the Alliance crest on the left, the Horde's on the
--  right, each half listing or hiding the dungeons on its side's ground (contested ones
--  always show). One half stays on: switching off the last one turns the other back on.
-------------------------------------------------------------------------------
local SIDES = { { faction = "Alliance", key = "showAlliance" }, { faction = "Horde", key = "showHorde" } }

-- "|cff4a9eff" -> r, g, b
local function CodeRGB(code)
    return tonumber(code:sub(5, 6), 16) / 255, tonumber(code:sub(7, 8), 16) / 255, tonumber(code:sub(9, 10), 16) / 255
end

local function PaintSide(half)
    local on = S.Get(half.side.key)
    half.icon:SetDesaturated(not on)
    half.icon:SetAlpha(on and 1 or FACTION_OFF)
    half.fill:SetShown(on)
end

local function PaintFactions()
    for _, half in ipairs(window.factions) do PaintSide(half) end
end

local function SideEnter(half)
    local side = half.side
    local on = S.Get(side.key)
    GameTooltip:SetOwner(half, "ANCHOR_BOTTOM")
    GameTooltip:SetText(TERRITORY_CODE[side.faction] .. side.faction .. "|r", 1, 1, 1)
    GameTooltip:AddLine(on and "Listed: the dungeons on " .. side.faction .. " ground, and its battleground "
        .. "factions. Click to hide them." or "Hidden. Click to list them again.", 1, 1, 1, true)
    GameTooltip:AddLine("Contested dungeons are always listed.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function SideClicked(half)
    local key = half.side.key
    local turningOff = S.Get(key)
    if turningOff then
        for _, side in ipairs(SIDES) do
            if side.key ~= key and not S.Get(side.key) then S.Set(side.key, true) end
        end
    end
    S.Set(key, not turningOff)
    SideEnter(half)
end

local function FactionSwitch(parent)
    local switch = CreateFrame("Frame", nil, parent)
    switch:SetSize(FACTION_W * 2, SEARCH_H)
    ns.Solid(switch, "BACKGROUND", T.panel, 1):SetAllPoints()
    ns.Border(switch, BORDER_RGB)
    local halves = {}
    for i, side in ipairs(SIDES) do
        local half = CreateFrame("Button", nil, switch)
        half:SetSize(FACTION_W, SEARCH_H)
        half:SetPoint("LEFT", (i - 1) * FACTION_W, 0)
        half.side = side
        half.fill = half:CreateTexture(nil, "BACKGROUND", nil, 1)
        half.fill:SetAllPoints()
        local r, g, b = CodeRGB(TERRITORY_CODE[side.faction])
        half.fill:SetColorTexture(r, g, b, 0.15)
        half.icon = half:CreateTexture(nil, "ARTWORK")
        half.icon:SetAtlas(FACTION_ATLAS[side.faction])
        half.icon:SetSize(FACTION_ICON, FACTION_ICON)
        half.icon:SetPoint("CENTER")
        half:SetScript("OnClick", SideClicked)
        half:SetScript("OnEnter", SideEnter)
        half:SetScript("OnLeave", GameTooltip_Hide)
        halves[i] = half
    end
    local split = ns.Solid(switch, "BORDER", BORDER_RGB, 1)
    split:SetPoint("TOP", 0, 0)
    split:SetPoint("BOTTOM", 0, 0)
    ns.Hairline(split, "v")
    return switch, halves
end

-------------------------------------------------------------------------------
--  The title bar's icons and the opacity
-------------------------------------------------------------------------------
local function Opacity()
    return math.floor((S.Get("windowAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("windowAlpha", value / 100)
end

local function FiltersEnter(button)
    Parts.LightBarIcon(button, true)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    local on = FiltersOn()
    GameTooltip:SetText(on == 1 and "Filters: 1 hiding loot or bosses"
        or ("Filters: %d hiding loot or bosses"):format(on), 1, 1, 1)
    GameTooltip:AddLine("Click to choose what is listed and shown.", T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

local function PaintFilters()
    local on = FiltersOn()
    local button = window.filters
    button.count:SetText(on > 0 and on or "")
    button:SetWidth(BAR_ICON + 4 + (on > 0 and math.ceil(button.count:GetStringWidth()) + 2 or 0))
end

local function FiltersButton(parent)
    local button = Parts.BarIcon(parent, FUNNEL, true)
    button.count = ns.Font(button, 12, nil, T.accentSoft)
    button.count:SetPoint("LEFT", button.icon, "RIGHT", 2, 0)
    button:SetScript("OnClick", OpenFilters)
    button:SetScript("OnEnter", FiltersEnter)
    return button
end

local function ToggleEnter(button)
    Parts.LightBarIcon(button, true)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(S.Get("listHidden") and "Show the dungeon list" or "Hide the dungeon list", 1, 1, 1)
    GameTooltip:Show()
end

local function ToggleClicked(button)
    S.Set("listHidden", not S.Get("listHidden"))
    ToggleEnter(button)
end

-------------------------------------------------------------------------------
--  Hiding the list: the switch, the search, the list and their card fold away and the page
--  takes the window's whole width. Up and Down still step through it.
-------------------------------------------------------------------------------
local function Arrange()
    local hidden = S.Get("listHidden")
    if hidden then ClearSearch() end
    search:SetShown(not hidden)
    window.factionSwitch:SetShown(not hidden)
    window.tabBar:SetShown(not hidden)
    ShowLists()
    for _, part in ipairs(listCard) do part:SetShown(not hidden) end
    local cardLeft = hidden and 6 or LIST_W + PAD + 14
    local fill = contentCard[1]
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", cardLeft, -(HEADER + 6))
    fill:SetPoint("BOTTOMRIGHT", -4, FOOTER + 6)
    local left = cardLeft + CONTENT_INSET
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", left, -(HEADER + PAD + 4))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, FOOTER + PAD)
    view:SetWidth(WIDTH - left - SCROLLBAR - PAD - 8)
    window.listToggle.icon:SetTexture(hidden and LIST_HIDDEN or LIST_SHOWN)
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local function DataEnter(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText("Game data: WoW Forever " .. J.DATA_BUILD, 1, 1, 1)
    if J.DATA_DATE ~= "" then
        GameTooltip:AddLine("That build came out on " .. J.DATA_DATE .. ".", T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:AddLine("Faction rewards, their standings and prices, and the boss fights the kill counts follow, "
        .. "are read from it. A daily check moves them on to each new build.", T.muted.r, T.muted.g, T.muted.b, true)
    GameTooltip:Show()
end

-- Closing it, but not putting it away for the world map, hands back to the window it was
-- opened from.
local function Hidden()
    if awayForMap then return end
    local back = onClose
    onClose = nil
    window.back:Hide()
    if back then back() end
end

local function BackClicked()
    window:Hide()
end

-- Every draw repaints the list too: a BiS change from an item's menu moves its counts.
local function Drawn()
    if shownTab == "dungeons" then List.Paint(selected) else Factions.Paint(selected) end
end

local function Build()
    window = Parts.Window(WIDTH, HEIGHT, "journalWindow")
    local backdrop = window.backdrop
    listCard = backdrop:Card(6, HEADER + 6, WIDTH - LIST_W - PAD - 6, FOOTER + 6)
    contentCard = backdrop:Card(LIST_W + PAD + 14, HEADER + 6, 4, FOOTER + 6)
    window:SetScript("OnKeyDown", OnKeyDown)

    -- Right to left: close, opacity, Filters and the list's button.
    local close = Parts.TitleBar(window, "Dungeon Journal",
        "Dungeons and raids, reputation and PvP: what drops, your quests, and more.", PAGE)
    local opacityIcon
    opacityIcon, window.opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    window.filters = FiltersButton(window)
    window.filters:SetPoint("RIGHT", opacityIcon, "LEFT", -18, 0)
    window.listToggle = Parts.BarIcon(window, LIST_SHOWN, true)
    window.listToggle:SetScript("OnClick", ToggleClicked)
    window.listToggle:SetScript("OnEnter", ToggleEnter)
    window.listToggle:SetPoint("RIGHT", window.filters, "LEFT", -12, 0)
    window.back = Parts.Link(window, BackClicked, true)
    window.back:SetPoint("LEFT", window.title, "RIGHT", 16, -1)
    window.back:Hide()
    window:HookScript("OnHide", Hidden)

    Parts.FooterBrand(window, PAGE)
    if J.DATA_BUILD then
        Parts.FooterNote(window, "Game data: build " .. J.DATA_BUILD
            .. (J.DATA_DATE ~= "" and PLACE_DOT .. J.DATA_DATE or ""), DataEnter)
    end

    -- The switch, then the search beside the faction switch, then the list, down the left.
    window.tabBar = Parts.Tabs(window, SEARCH_FULL_W, TABS, TabPicked)
    window.tabBar:SetPoint("TOPLEFT", PAD, -(HEADER + PAD))
    local below = HEADER + PAD + TAB_H + TAB_GAP
    search = Parts.SearchBox(window, "Search items, bosses or factions", OnSearch)
    search:SetSize(SEARCH_W, SEARCH_H)
    search:SetPoint("TOPLEFT", PAD, -below)
    window.factionSwitch, window.factions = FactionSwitch(window)
    window.factionSwitch:SetPoint("LEFT", search, "RIGHT", FACTION_GAP, 0)
    listFrame = CreateFrame("Frame", nil, window)
    listFrame:SetPoint("TOPLEFT", PAD, -(below + SEARCH_H + 4))
    listFrame:SetPoint("BOTTOMLEFT", PAD, FOOTER + PAD)
    listFrame:SetWidth(LIST_W)
    List.Build(listFrame, Select)
    factionFrame = CreateFrame("Frame", nil, window)
    factionFrame:SetPoint("TOPLEFT", listFrame)
    factionFrame:SetPoint("BOTTOMLEFT", listFrame)
    factionFrame:SetWidth(LIST_W)
    factionFrame:Hide()
    Factions.Build(factionFrame, Select)

    -- The page, scrolling under the title bar; Arrange places it, with the list or without.
    scroll = ns.UI.SlimScroll(window)
    view = J.View.New(scroll)
    scroll:SetScrollChild(view)
    view.onResize = Drawn
    view.navigate = Select
end

-- What the profile holds: opacity, the list shown or not, the filters. On every open and on
-- a profile switch, so a switch while it is closed shows when it opens.
local function ApplyProfile()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
    PaintFactions()
    Arrange()
    PaintFilters()
    List.Layout()
end

-- A setting it shows changed (the Filters menu here, or the settings page).
local function SettingChanged(key)
    if not (window and window:IsShown()) then return end
    if key == "enabled" then
        if not S.Get("enabled") then window:Hide() end
    elseif key == "windowAlpha" then
        window.backdrop:Paint(Opacity() / 100)
        window.opacity._refreshValue()
    elseif key:find("^closedGroup") then
        List.Layout()
    elseif key == "openUnreleased" then
        if shownTab ~= "dungeons" then
            Factions.Layout(shownTab)
            Factions.Paint(selected)
        end
    elseif key == "showAlliance" or key == "showHorde" then
        PaintFactions()
        List.Layout()
        if shownTab ~= "dungeons" then
            Factions.Layout(shownTab)
            Factions.Paint(selected)
        end
        if shownQuery ~= "" then view:Redraw() end
    else
        if key == "listHidden" then Arrange() end
        PaintFilters()
        if menu and menu:IsShown() then PaintMenu() end
        view:Redraw()
    end
end

S.OnChange(SettingChanged)
hooksecurefunc(ns, "Apply", function()
    if window and window:IsShown() then
        ApplyProfile()
        view:Redraw()
    end
end)

-- Draws the page shown again, when the window is open: for data that changed under it
-- (kills or loot forgotten from the settings page).
function ns.RedrawJournalWindow()
    if window and window:IsShown() then view:Redraw() end
    J.View.BossPanel.Refresh()
end

local function IsItem(row, itemID) return row.itemID == itemID end

-- Opens the window on the dungeon (or faction) given, else the one you are in, else the page
-- you last looked at, else the first of the tab you left it on. Opened from another window,
-- back() brings that one back when this closes, and backText is the link that says so. With
-- an item, the page scrolls to it and lights its boss, as a click on the boss's name does.
---@param dungeon? JournalDungeon|JournalFaction
---@param back? fun()
---@param backText? string
---@param itemID? number
function ns.OpenJournalWindow(dungeon, back, backText, itemID)
    awayForMap = false   -- opened by hand: the map closing has nothing to bring back
    J.TurnOn()
    if not window then Build() end
    onClose = back
    window.back:SetShown(back ~= nil)
    if back then Parts.SetLink(window.back, backText or "Back") end
    window:SetScale(ns.UIScale())
    window:Show()
    ApplyProfile()
    local here = J.Current()
    Select(dungeon or here and here[1] or selected or FirstPage(SavedTab()))
    local row = itemID and view:Find("item", IsItem, itemID)
    if row then
        view:ScrollToRow(scroll, row)
        if row.boss and view.pinned ~= row.boss then view:Pin(row.boss) end
    end
end

function ns.ToggleJournalWindow()
    if window and window:IsShown() then window:Hide() else ns.OpenJournalWindow() end
end

-- The world map opening (M) puts the window away while it is open, and the map closing (M
-- again) brings it back as it was; the map panel (UI/MapPanel.lua) says when.
---@param mapShown boolean
function J.WindowAwayForMap(mapShown)
    if mapShown then
        if window and window:IsShown() then
            awayForMap = true
            window:Hide()
        end
    elseif awayForMap then
        awayForMap = false
        if window and S.Get("enabled") then window:Show() end
    end
end

BINDING_NAME_NAOWHFOREVER_JOURNAL = "Open Dungeon Journal"

function NaowhForever_ToggleJournal()
    ns.ToggleJournalWindow()
end
